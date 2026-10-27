-- Дополнение SQL из схемы миграций (blink.cmp) — работает без базы и знает ещё не применённые миграции:
--   FROM / JOIN / UPDATE / INTO / REFERENCES / ALTER TABLE …  → таблицы
--   u.  (u — таблица или её псевдоним из FROM u / JOIN users u)  → колонки этой таблицы
--   SELECT …, WHERE …, SET …  → колонки таблиц этого запроса
--   INSERT INTO t (…), REFERENCES t(…), ON t (…)  → колонки t
--   CREATE TABLE (name |, ADD COLUMN name |, TYPE |, ::  → типы Postgres и свои enum
--   после типа в CREATE TABLE  → NOT NULL, DEFAULT, PRIMARY KEY, REFERENCES…
--   status = '|  (колонка с enum-типом)  → значения enum
local schema = require("own.sql.schema")

local M = {}

local TYPES = { -- имя, описание, что вставить (если не само имя)
  { "bigint", "целое 8 байт" }, { "integer", "целое 4 байта" }, { "smallint", "целое 2 байта" },
  { "bigserial", "bigint с автоувеличением (лучше GENERATED ALWAYS AS IDENTITY)" }, { "serial", "integer с автоувеличением" },
  { "text", "строка любой длины" }, { "varchar", "строка с пределом длины", "varchar(${1:255})" },
  { "citext", "строка без учёта регистра (расширение citext)" },
  { "boolean", "true / false" }, { "uuid", "gen_random_uuid()" }, { "timestamptz", "время с часовым поясом — почти всегда нужно оно" },
  { "timestamp", "время без пояса" }, { "date", "дата" }, { "time", "время дня" }, { "interval", "промежуток времени" },
  { "numeric", "точное число — деньги", "numeric(${1:12}, ${2:2})" }, { "double precision", "число с плавающей точкой 8 байт" },
  { "real", "4 байта" }, { "jsonb", "JSON с индексами" }, { "json", "JSON как текст" }, { "bytea", "байты" },
  { "inet", "IP-адрес" }, { "cidr", "сеть" }, { "tsvector", "полнотекстовый поиск" }, { "text[]", "массив строк" },
  { "bigint[]", "массив чисел" },
}

local CONSTRAINTS = {
  { "NOT NULL", "обязательное поле" }, { "DEFAULT", "значение по умолчанию", "DEFAULT $1" }, { "PRIMARY KEY", "первичный ключ" },
  { "UNIQUE", "уникальное" }, { "REFERENCES", "внешний ключ", "REFERENCES ${1:users}(${2:id}) ON DELETE ${3:CASCADE}" },
  { "CHECK", "условие на значение", "CHECK ($1)" }, { "GENERATED ALWAYS AS IDENTITY", "автоувеличение по стандарту SQL" },
  { "DEFAULT now()", "время вставки" }, { "DEFAULT gen_random_uuid()", "новый uuid" },
}

local FROM_END = { "where", "join", "left", "right", "inner", "full", "cross", "group", "order", "limit", "having",
  "returning", "on", "union", "window", "for" }
local TABLE_KW = { from = true, join = true, update = true, into = true, table = true, references = true, truncate = true, exists = true, only = true }
local CLAUSES = { "select", "from", "where", "join", "on", "set", "values", "group", "order", "having", "returning", "using", "into", "update" }

local kinds
local function kind(name)
  kinds = kinds or require("blink.cmp.types").CompletionItemKind
  return kinds[name]
end

--- Схема для буфера: из папки миграций его проекта; текст самого буфера (если он миграция) — несохранённый
function M.schema(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local ok, dir = pcall(require("own.sql.migrations").dir, buf)
  if not ok or not dir then return nil end
  local file = vim.api.nvim_buf_get_name(buf)
  local override
  if vim.fs.dirname(file) == dir and vim.bo[buf].modified then
    override = { [file] = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") }
  end
  return schema.load(dir, override)
end

-- выражение вокруг курсора: текст до курсора и после (до «;»)
local function statement(buf, row, col)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local before = table.concat(vim.list_slice(lines, 1, row - 1), "\n") .. (row > 1 and "\n" or "") .. lines[row]:sub(1, col)
  local after = lines[row]:sub(col + 1) .. "\n" .. table.concat(vim.list_slice(lines, row + 1), "\n")
  before = before:gsub("%-%-[^\n]*\n", "\n")
  before = before:match(".*;(.*)$") or before
  after = after:match("^(.-);") or after
  return before, after
end

-- таблицы запроса: имя/псевдоним → таблица
local function tables_in(text, known)
  local l = " " .. text:lower():gsub("%-%-[^\n]*", ""):gsub("%s+", " ") .. " "
  local map, list = {}, {}
  local function add(name, alias)
    name = schema.ident(name)
    if not name or not known[name] then return end
    if not map[name] then list[#list + 1] = name end
    map[name] = name
    if alias and alias ~= "" and not schema.KEYWORDS[alias] then map[alias] = name end
  end
  for _, kw in ipairs({ "join", "update", "into", "table", "references" }) do
    for name, a1, a2 in l:gmatch("%s" .. kw .. "%s+([%w_\".]+)%s*([%w_]*)%s*([%w_]*)") do add(name, a1 == "as" and a2 or a1) end
  end
  -- FROM a x, b AS y — до следующего слова запроса
  for start in l:gmatch("%sfrom%s+()") do
    local rest = l:sub(start)
    local stop = #rest + 1
    for _, kw in ipairs(FROM_END) do
      local p = rest:find("%s" .. kw .. "%s")
      if p and p < stop then stop = p end
    end
    for item in (rest:sub(1, stop - 1):gsub("[;%)].*$", "") .. ","):gmatch("([^,]+),") do
      local name, a1, a2 = vim.trim(item):match("^([%w_\".]+)%s*([%w_]*)%s*([%w_]*)$")
      if name then add(name, a1 == "as" and a2 or a1) end
    end
  end
  return map, list
end

local function column_doc(t, c)
  local s = ("**%s.%s** `%s`"):format(t.name, c.name, c.type ~= "" and c.type or "?")
  if c.notes and c.notes ~= "" then s = s .. "\n\n" .. c.notes end
  return s .. "\n\n_" .. (c.file or t.file or "") .. "_"
end

local function table_doc(t)
  local rows = {}
  for _, c in ipairs(t.cols) do
    rows[#rows + 1] = ("  %-16s %s%s"):format(c.name, c.type, c.notes ~= "" and ("  -- " .. c.notes) or "")
  end
  return ("**%s**%s\n```sql\n%s\n```\n_%s_"):format(t.name, t.view and " (view)" or "", table.concat(rows, "\n"), t.file or "")
end

local function columns(items, t, score)
  for i, c in ipairs(t.cols) do
    items[#items + 1] = {
      label = c.name,
      kind = kind("Field"),
      labelDetails = { detail = " " .. c.type, description = t.name },
      documentation = { kind = "markdown", value = column_doc(t, c) },
      sortText = ("%d%04d"):format(score or 1, i),
      own_sql = true,
    }
  end
end

local function tables(items, s)
  for name, t in pairs(s.tables) do
    items[#items + 1] = {
      label = name,
      kind = kind("Class"),
      labelDetails = { description = (#t.cols .. " кол.") },
      documentation = { kind = "markdown", value = table_doc(t) },
      own_sql = true,
    }
  end
end

local function keyword_items(items, list, k)
  for i, x in ipairs(list) do
    items[#items + 1] = {
      label = x[1],
      kind = kind(k),
      labelDetails = { description = x[2] },
      insertText = x[3],
      insertTextFormat = x[3] and vim.lsp.protocol.InsertTextFormat.Snippet or nil,
      sortText = ("%04d"):format(i),
    }
  end
end

local function types(items, s)
  keyword_items(items, TYPES, "TypeParameter")
  for name, vals in pairs(s and s.enums or {}) do
    items[#items + 1] = { label = name, kind = kind("Enum"), labelDetails = { description = "enum: " .. table.concat(vals, ", ") }, sortText = "0000" }
  end
end

local function constraints(items) keyword_items(items, CONSTRAINTS, "Keyword") end

--- Что предлагать в этой позиции
function M.complete(buf, row, col)
  local s = M.schema(buf)
  local before, after = statement(buf, row, col)
  local lb = before:lower()
  local prev = lb:gsub("[%w_]*$", "")
  local last = prev:match("([%w_]+)%s*$")
  local items = {}
  local tmap, tlist = tables_in(before .. " " .. after, s and s.tables or {})

  -- значение enum: status = 'w|
  local col_eq = lb:match("([%w_%.]+)%s*=%s*'[^']*$") or lb:match("([%w_%.]+)%s+in%s*%(%s*'[^']*$")
  if col_eq and s then
    local q, cname = col_eq:match("^([%w_]+)%.([%w_]+)$")
    cname = cname or col_eq
    for _, tname in ipairs(q and { tmap[q] } or tlist) do
      for _, c in ipairs((s.tables[tname] or {}).cols or {}) do
        if c.name == cname and s.enums[c.type] then
          for _, v in ipairs(s.enums[c.type]) do items[#items + 1] = { label = v, kind = kind("EnumMember"), labelDetails = { description = c.type } } end
        end
      end
    end
    return items
  end
  if lb:match("'[^']*$") and select(2, lb:gsub("'", "")) % 2 == 1 then return items end -- внутри строки

  -- тип: ::|
  if prev:match("::%s*$") then types(items, s); return items end

  -- u.| — колонки таблицы или псевдонима
  local q = lb:match("([%w_\"]+)%.[%w_]*$")
  if q and s then
    local t = s.tables[tmap[schema.ident(q)] or schema.ident(q)]
    if t then columns(items, t) end
    return items
  end

  -- внутри скобок: CREATE TABLE (…), INSERT INTO t (…), REFERENCES t(…), ON t (…)
  local depth, open_at = 0, nil
  for i = #lb, 1, -1 do
    local c = lb:sub(i, i)
    if c == ")" then depth = depth + 1 elseif c == "(" then
      if depth == 0 then open_at = i; break end
      depth = depth - 1
    end
  end
  if open_at then
    local head = lb:sub(1, open_at - 1)
    local inside = lb:sub(open_at + 1)
    local ref = head:match("references%s+([%w_\".]+)%s*$") or head:match("insert%s+into%s+([%w_\".]+)%s*$")
      or head:match("%son%s+([%w_\".]+)%s*$") or head:match("%son%s+only%s+([%w_\".]+)%s*$")
    if ref then
      local t = s and s.tables[schema.ident(ref)]
      if t then columns(items, t) end
      return items
    end
    if head:match("create%s+[%w%s]-table%s+[%w%s_\".]-$") then
      -- элемент списка колонок: «имя |» — тип, «имя тип … |» — ограничения
      local item = inside:match("[^,]*$")
      local words = select(2, item:gsub("%S+", ""))
      if item:match("%s$") and words == 1 and not item:match("^%s*constraint") then types(items, s); return items end
      if item:match("%s$") and words >= 2 then constraints(items); return items end
      if words == 0 or (words == 1 and not item:match("%s$")) then return items end -- имя новой колонки — придумываешь сам
    end
  end

  -- ALTER TABLE … ADD COLUMN имя |  /  ALTER COLUMN x TYPE |
  if lb:match("add%s+column%s+[%w_\"]+%s+$") or lb:match("add%s+column%s+if%s+not%s+exists%s+[%w_\"]+%s+$")
    or lb:match("%stype%s+$") or lb:match("set%s+data%s+type%s+$") then
    types(items, s)
    return items
  end
  if lb:match("add%s+column%s+[%w_\"]+%s+[%w_%[%]%(%)]+[^,]*%s$") then constraints(items); return items end

  if not s or not last then return items end -- начало выражения — тут слова SQL, не колонки

  -- таблицы: после FROM, JOIN, INTO, UPDATE, TABLE, REFERENCES…; FROM a, |
  local clause
  do
    local best = 0
    for _, kw in ipairs(CLAUSES) do
      local pos = 0
      for p in prev:gmatch("()%f[%w_]" .. kw .. "%f[^%w_]") do pos = p end
      if pos > best then best, clause = pos, kw end
    end
  end
  if (last and TABLE_KW[last]) or (clause == "from" and prev:match(",%s*$")) then
    tables(items, s)
    return items
  end
  if last == "drop" or last == "alter" or last == "create" then return items end

  -- колонки таблиц этого запроса; таблиц нет — все колонки и таблицы
  if #tlist > 0 then
    for _, name in ipairs(tlist) do columns(items, s.tables[name], 1) end
  else
    for _, t in pairs(s.tables) do columns(items, t, 2) end
    tables(items, s)
  end
  return items
end

-- ───── blink.cmp ─────

local Source = {}
Source.__index = Source

function M.new() return setmetatable({}, Source) end

function Source:enabled() return vim.tbl_contains({ "sql", "pgsql", "plsql" }, vim.bo.filetype) end

function Source:get_trigger_characters() return { ".", "(", "'", ":" } end

function Source:get_completions(ctx, callback)
  local ok, items = pcall(M.complete, ctx.bufnr, ctx.cursor[1], ctx.cursor[2])
  callback({ items = ok and items or {}, is_incomplete_forward = false, is_incomplete_backward = false })
end

--- Убрать из ответа сервера SQL то, что уже есть из миграций (у нас — с типом, ограничениями и файлом)
function M.dedupe(ctx, items)
  local ok, s = pcall(M.schema, ctx and ctx.bufnr)
  if not ok or not s then return items end
  return vim.tbl_filter(function(it)
    if it.kind == kind("Class") and s.tables[it.label] then return false end
    if it.kind == kind("Field") then
      local t = ((it.labelDetails or {}).description or ""):match("([%w_]+)$")
      local tbl = t and s.tables[t]
      if tbl then
        for _, c in ipairs(tbl.cols) do if c.name == it.label then return false end end
      end
    end
    return true
  end, items)
end

return M
