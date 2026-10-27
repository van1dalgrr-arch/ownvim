-- Схема базы из файлов миграций — без подключения к базе и с ещё не применёнными миграциями.
-- Читает по порядку имён *.up.sql (golang-migrate) или *.sql (goose — только часть «-- +goose Up») и
-- проигрывает CREATE/ALTER/DROP TABLE, CREATE TYPE … AS ENUM, ALTER TYPE … ADD VALUE.
-- Итог: { tables = { users = { name, cols = { {name, type, notes, file} }, file } }, enums = { role = { "a", "b" } } }
local M = {}

local KEYWORDS = {}
for w in ([[select from where join left right inner outer full cross on using and or not null is in as
  group by order having limit offset union all distinct returning set values into update delete insert
  with case when then else end exists between like ilike asc desc natural lateral window over]]):gmatch("%S+") do
  KEYWORDS[w] = true
end
M.KEYWORDS = KEYWORDS

-- "public"."Users" → users; public.users → users
function M.ident(s)
  if not s then return nil end
  s = s:gsub('"', "")
  s = s:match("^[%w_]+%.([%w_]+)$") or s
  return s:lower()
end

--- Текст без комментариев; кавычки и $$-тела не трогаем
function M.strip_comments(text)
  local out, i, n = {}, 1, #text
  while i <= n do
    local c, two = text:sub(i, i), text:sub(i, i + 1)
    if two == "--" then
      local e = text:find("\n", i, true) or n + 1
      i = e
    elseif two == "/*" then
      local e = text:find("*/", i + 2, true)
      i = e and e + 2 or n + 1
      out[#out + 1] = " "
    elseif c == "'" then
      local e = i + 1
      while e <= n do
        if text:sub(e, e) == "'" then
          if text:sub(e + 1, e + 1) == "'" then e = e + 2 else break end
        else
          e = e + 1
        end
      end
      out[#out + 1] = text:sub(i, e)
      i = e + 1
    elseif c == "$" and text:match("^%$[%w_]*%$", i) then
      local tag = text:match("^%$[%w_]*%$", i)
      local e = text:find(tag, i + #tag, true)
      local stop = e and e + #tag - 1 or n
      out[#out + 1] = text:sub(i, stop)
      i = stop + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Разбить по разделителю sep (по умолчанию «;») вне скобок, кавычек и $$-тел
function M.split(text, sep)
  sep = sep or ";"
  local parts, depth, start, i, n = {}, 0, 1, 1, #text
  while i <= n do
    local c = text:sub(i, i)
    if c == "'" or c == '"' then
      local e = text:find(c, i + 1, true)
      i = (e or n) + 1
    elseif c == "$" and text:match("^%$[%w_]*%$", i) then
      local tag = text:match("^%$[%w_]*%$", i)
      local e = text:find(tag, i + #tag, true)
      i = (e and e + #tag or n + 1)
    else
      if c == "(" then
        depth = depth + 1
      elseif c == ")" then
        depth = math.max(0, depth - 1)
      elseif c == sep and depth == 0 then
        parts[#parts + 1] = text:sub(start, i - 1)
        start = i + 1
      end
      i = i + 1
    end
  end
  parts[#parts + 1] = text:sub(start)
  local out = {}
  for _, p in ipairs(parts) do
    p = vim.trim(p)
    if p ~= "" then out[#out + 1] = p end
  end
  return out
end

--- Содержимое первых скобок после позиции from: "(a, b(1))" → "a, b(1)", конец
local function parens(s, from)
  local open = s:find("(", from or 1, true)
  if not open then return nil end
  local depth = 0
  for i = open, #s do
    local c = s:sub(i, i)
    if c == "(" then depth = depth + 1 elseif c == ")" then
      depth = depth - 1
      if depth == 0 then return s:sub(open + 1, i - 1), i end
    end
  end
  return s:sub(open + 1), #s
end
M.parens = parens

local NAME = '("?[%w_]+"?%.?"?[%w_]*"?)'
local STOP = { ["not"] = true, null = true, default = true, primary = true, references = true, unique = true,
  check = true, generated = true, collate = true, constraint = true }

-- "email TEXT UNIQUE NOT NULL" → { name = "email", type = "text", notes = "unique, not null" }
function M.column(def)
  local name, rest = def:match('^%s*("?[%w_]+"?)%s+(.*)$')
  if not name then return nil end
  local words, typ, notes = {}, {}, {}
  for w in rest:gmatch("%S+") do words[#words + 1] = w end
  local i = 1
  while i <= #words and not STOP[words[i]:lower():gsub("[^%w_].*$", "")] do
    typ[#typ + 1] = words[i]
    i = i + 1
  end
  local tail = table.concat(words, " ", i):lower()
  if tail:find("primary key", 1, true) then notes[#notes + 1] = "первичный ключ" end
  if tail:find("not null", 1, true) then notes[#notes + 1] = "not null" end
  if tail:find("unique", 1, true) then notes[#notes + 1] = "unique" end
  local ref = tail:match("references%s+" .. NAME)
  if ref then notes[#notes + 1] = "→ " .. M.ident(ref) end
  local def_v = rest:match("[Dd][Ee][Ff][Aa][Uu][Ll][Tt]%s+(.-)%s*$")
  if def_v then
    def_v = def_v:gsub("%s+[Nn][Oo][Tt]%s+[Nn][Uu][Ll][Ll].*$", ""):gsub("%s+[Rr][Ee][Ff][Ee][Rr][Ee][Nn][Cc][Ee][Ss].*$", "")
    notes[#notes + 1] = "= " .. def_v
  end
  if tail:find("generated", 1, true) then notes[#notes + 1] = "generated" end
  return { name = M.ident(name), type = table.concat(typ, " "):lower(), notes = table.concat(notes, ", ") }
end

local TABLE_CONSTRAINT = { constraint = true, primary = true, unique = true, check = true, foreign = true, exclude = true, like = true }

--- Разобрать одно выражение. Возвращает описание: { kind = "create_table", table, cols } | { kind = "alter_table", … } | …
function M.statement(st)
  local s = st:gsub("%s+", " ")
  local l = s:lower()
  local name

  -- CREATE TABLE
  name = l:match("^create%s+[%w%s]-table%s+if%s+not%s+exists%s+" .. NAME) or l:match("^create%s+[%w%s]-table%s+" .. NAME)
  if name and not l:match("^create%s+[%w%s]-table%s+[^%(]-%sas%s") then
    local body = parens(s)
    local cols, fks = {}, {}
    for _, item in ipairs(M.split(body or "", ",")) do
      local first = item:match("^(%S+)")
      if first and not TABLE_CONSTRAINT[first:lower()] then
        local c = M.column(item)
        if c then cols[#cols + 1] = c end
      elseif first then
        -- CONSTRAINT fk FOREIGN KEY (user_id) REFERENCES users(id) — пометить колонку
        local list, ref = item:lower():gsub("%s+", " "):match("foreign key ?%(([^)]*)%) ?references " .. NAME)
        if list then
          for col in list:gmatch("[^,%s]+") do fks[M.ident(col)] = M.ident(ref) end
        end
      end
    end
    for _, c in ipairs(cols) do
      if fks[c.name] then c.notes = c.notes .. (c.notes ~= "" and ", " or "") .. "→ " .. fks[c.name] end
    end
    return { kind = "create_table", table = M.ident(name), cols = cols }
  end

  -- CREATE TYPE … AS ENUM
  name = l:match("^create%s+type%s+" .. NAME .. "%s+as%s+enum")
  if name then
    local vals = {}
    for v in (parens(s) or ""):gmatch("'([^']*)'") do vals[#vals + 1] = v end
    return { kind = "create_enum", name = M.ident(name), values = vals }
  end
  name = l:match("^alter%s+type%s+" .. NAME .. "%s+add%s+value")
  if name then return { kind = "enum_add", name = M.ident(name), value = s:match("'([^']*)'") } end

  -- DROP
  local what, list = l:match("^drop%s+(%w+)%s+(.*)$")
  if what == "materialized" then what, list = "view", l:match("^drop%s+materialized%s+view%s+(.*)$") end
  if what == "table" or what == "type" or what == "view" then
    list = list:gsub("^if%s+exists%s+", ""):gsub("%s+cascade%s*$", ""):gsub("%s+restrict%s*$", "")
    local names = {}
    for n in list:gmatch("[^,%s]+") do names[#names + 1] = M.ident(n) end
    return { kind = "drop_" .. what, names = names }
  end

  -- ALTER TABLE
  local head_end
  for _, pat in ipairs({ "^alter%s+table%s+if%s+exists%s+only%s+", "^alter%s+table%s+if%s+exists%s+", "^alter%s+table%s+only%s+", "^alter%s+table%s+" }) do
    _, head_end, name = l:find(pat .. NAME)
    if name then break end
  end
  if name then
    local tbl = M.ident(name)
    local actions = {}
    for _, a in ipairs(M.split(s:sub(head_end + 1), ",")) do
      local al = a:lower()
      local act
      local to = al:match("^rename%s+to%s+" .. NAME)
      if to then
        act = { op = "rename_table", to = M.ident(to) }
      elseif al:match("^add%s+constraint") then
        act = { op = "add_constraint", name = M.ident(al:match("^add%s+constraint%s+" .. NAME)) }
      elseif al:match("^add%s") and not al:match("^add%s+primary") and not al:match("^add%s+unique")
        and not al:match("^add%s+foreign") and not al:match("^add%s+check") then
        local def = a:gsub("^%s*[Aa][Dd][Dd]%s+", ""):gsub("^[Cc][Oo][Ll][Uu][Mm][Nn]%s+", "")
          :gsub("^[Ii][Ff]%s+[Nn][Oo][Tt]%s+[Ee][Xx][Ii][Ss][Tt][Ss]%s+", "")
        act = { op = "add_column", col = M.column(def) }
      elseif al:match("^drop%s+constraint") then
        act = { op = "drop_constraint" }
      elseif al:match("^drop%s") then
        local c = al:gsub("^drop%s+", ""):gsub("^column%s+", ""):gsub("^if%s+exists%s+", ""):match("^" .. NAME)
        act = { op = "drop_column", col = M.ident(c) }
      else
        local from, to2 = al:match("^rename%s+column%s+" .. NAME .. "%s+to%s+" .. NAME)
        if not from then from, to2 = al:match("^rename%s+" .. NAME .. "%s+to%s+" .. NAME) end
        if from then
          act = { op = "rename_column", from = M.ident(from), to = M.ident(to2) }
        else
          local col, typ = al:match("^alter%s+column%s+" .. NAME .. "%s+set%s+data%s+type%s+(.-)%s*$")
          if not col then col, typ = al:match("^alter%s+column%s+" .. NAME .. "%s+type%s+(.-)%s*$") end
          if not col then col, typ = al:match("^alter%s+" .. NAME .. "%s+type%s+(.-)%s*$") end
          if col then act = { op = "alter_type", col = M.ident(col), type = typ:gsub("%s+using%s.*$", "") } end
        end
      end
      if act then act.text = a; actions[#actions + 1] = act end
    end
    return { kind = "alter_table", table = tbl, actions = actions }
  end

  -- то, что нужно только для отката (down)
  name = l:match("^create%s+unique%s+index%s+concurrently%s+if%s+not%s+exists%s+" .. NAME)
    or l:match("^create%s+[%w%s]-index%s+concurrently%s+if%s+not%s+exists%s+" .. NAME)
    or l:match("^create%s+[%w%s]-index%s+if%s+not%s+exists%s+" .. NAME)
    or l:match("^create%s+[%w%s]-index%s+concurrently%s+" .. NAME)
    or l:match("^create%s+[%w%s]-index%s+" .. NAME)
  if name and name ~= "on" then
    return { kind = "create_index", name = M.ident(name), concurrently = l:find(" concurrently ", 1, true) ~= nil }
  end
  name = l:match("^create%s+extension%s+if%s+not%s+exists%s+" .. NAME) or l:match("^create%s+extension%s+" .. NAME)
  if name then return { kind = "create_extension", name = M.ident(name) } end
  name = l:match("^create%s+or%s+replace%s+function%s+" .. NAME) or l:match("^create%s+function%s+" .. NAME)
  if name then return { kind = "create_function", name = M.ident(name) } end
  local trig, on = l:match("^create%s+[%w%s]-trigger%s+" .. NAME .. ".-%son%s+" .. NAME)
  if trig then return { kind = "create_trigger", name = M.ident(trig), table = M.ident(on) } end
  local mat, view = l:match("^create%s+[%w%s]-(materialized)%s+view%s+" .. NAME)
  if not mat then view = l:match("^create%s+or%s+replace%s+view%s+" .. NAME) or l:match("^create%s+view%s+" .. NAME) end
  if view then return { kind = "create_view", name = M.ident(view), materialized = mat ~= nil } end
  return { kind = "other" }
end

--- Часть up из файла миграции: goose — между «-- +goose Up» и «-- +goose Down», иначе весь файл
function M.up_part(text)
  if not text:find("%-%-%s*%+goose%s+[Uu]p") then return text end
  local up = text:match("%-%-%s*%+goose%s+[Uu]p[^\n]*\n(.-)%-%-%s*%+goose%s+[Dd]own") or text:match("%-%-%s*%+goose%s+[Uu]p[^\n]*\n(.*)$")
  return up or ""
end

--- Выражения файла по порядку, уже разобранные
function M.statements(text)
  local out = {}
  for _, st in ipairs(M.split(M.strip_comments(text))) do
    local p = M.statement(st)
    p.source = st
    out[#out + 1] = p
  end
  return out
end

local function apply(schema, p, file)
  local t = schema.tables
  if p.kind == "create_table" then
    for _, c in ipairs(p.cols) do c.file = file end
    t[p.table] = { name = p.table, cols = p.cols, file = file }
  elseif p.kind == "create_view" then
    t[p.name] = t[p.name] or { name = p.name, cols = {}, file = file, view = true }
  elseif p.kind == "drop_table" or p.kind == "drop_view" then
    for _, n in ipairs(p.names) do t[n] = nil end
  elseif p.kind == "drop_type" then
    for _, n in ipairs(p.names) do schema.enums[n] = nil end
  elseif p.kind == "create_enum" then
    schema.enums[p.name] = p.values
  elseif p.kind == "enum_add" and p.value then
    schema.enums[p.name] = schema.enums[p.name] or {}
    table.insert(schema.enums[p.name], p.value)
  elseif p.kind == "alter_table" then
    local tbl = t[p.table]
    if not tbl then return end
    for _, a in ipairs(p.actions) do
      if a.op == "add_column" and a.col then
        a.col.file = file
        tbl.cols[#tbl.cols + 1] = a.col
      elseif a.op == "drop_column" then
        tbl.cols = vim.tbl_filter(function(c) return c.name ~= a.col end, tbl.cols)
      elseif a.op == "rename_column" then
        for _, c in ipairs(tbl.cols) do if c.name == a.from then c.name = a.to end end
      elseif a.op == "alter_type" then
        for _, c in ipairs(tbl.cols) do if c.name == a.col then c.type = a.type end end
      elseif a.op == "rename_table" then
        t[p.table], tbl.name = nil, a.to
        t[a.to] = tbl
        tbl = t[a.to]
      end
    end
  end
end

--- Файлы миграций (up) по порядку
function M.files(dir)
  local out = {}
  for name, typ in vim.fs.dir(dir) do
    if (typ == "file" or typ == "link") and name:match("%.sql$") and not name:match("%.down%.sql$") then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

local cache = {} -- папка → { key = mtime-подпись, schema }

--- Схема по папке миграций; пересчитывается, только если файлы поменялись.
--- override — { [путь] = текст } для открытых несохранённых буферов
function M.load(dir, override)
  local files = M.files(dir)
  local sig = {}
  for _, f in ipairs(files) do
    local st = vim.uv.fs_stat(dir .. "/" .. f)
    sig[#sig + 1] = f .. ":" .. (st and st.mtime.sec .. "." .. st.mtime.nsec or "")
  end
  for path, text in pairs(override or {}) do sig[#sig + 1] = path .. "#" .. vim.fn.sha256(text) end
  local key = table.concat(sig, "|")
  if cache[dir] and cache[dir].key == key then return cache[dir].schema end
  local schema = { tables = {}, enums = {}, dir = dir }
  for _, f in ipairs(files) do
    local path = dir .. "/" .. f
    local text = (override or {})[path]
    if not text then
      local fh = io.open(path)
      text = fh and fh:read("*a") or ""
      if fh then fh:close() end
    end
    for _, p in ipairs(M.statements(M.up_part(text))) do apply(schema, p, f) end
  end
  cache[dir] = { key = key, schema = schema }
  return schema
end

return M
