-- Миграции: golang-migrate (000001_name.up.sql + .down.sql) и goose (один файл с -- +goose Up / Down).
--   new     — пара файлов с номером по порядку (ширина номера — как у уже лежащих), up — заготовка по имени:
--             create_orders → CREATE TABLE orders (…), add_phone_to_users → ALTER TABLE users ADD COLUMN phone
--   down    — заполняется сам при сохранении up, пока его не правили руками (DROP TABLE, DROP COLUMN, RENAME обратно…)
--   статус  — в первой строке миграции: ✓ применена / ○ ждёт / ✗ dirty (migrate version по базе проекта)
--   up / down / redo — migrate или goose с базой проекта (own.sql.db)
local schema = require("own.sql.schema")

local M = {}

local CANDIDATES = { "migrations", "db/migrations", "database/migrations", "sql/migrations", "internal/db/migrations",
  "internal/migrations", "internal/database/migrations", "schema/migrations", "migrate", "db/migrate" }

local function opts() return require("own.settings").module_opts(require("own.settings").current or {}, "sql") or {} end

local function has_sql(dir)
  for name in vim.fs.dir(dir) do
    if name:match("%.sql$") then return true end
  end
  return false
end

--- Папка миграций проекта (или та, где лежит открытый .sql с номером в имени). nil — нет
function M.dir(buf)
  buf = buf or 0
  local file = vim.api.nvim_buf_get_name(buf)
  if file:match("/%d+_[^/]*%.sql$") then return vim.fs.dirname(file) end
  local root = require("own.root").get(buf)
  local o = opts()
  if type(o.migrations) == "string" and o.migrations ~= "" then
    local d = o.migrations:sub(1, 1) == "/" and o.migrations or root .. "/" .. o.migrations
    if vim.uv.fs_stat(d) then return d end
  end
  for _, c in ipairs(CANDIDATES) do
    local d = root .. "/" .. c
    if vim.uv.fs_stat(d) and has_sql(d) then return d end
  end
  for _, d in ipairs(vim.fs.find(function(name, path)
    return name == "migrations" and not path:find("/node_modules", 1, true) and not path:find("/vendor", 1, true)
  end, { path = root, type = "directory", limit = 5 })) do
    if has_sql(d) then return d end
  end
end

--- Чем пользуется проект: "goose" или "migrate"
function M.tool(dir)
  local o = opts()
  if o.tool == "goose" or o.tool == "migrate" then return o.tool end
  for _, f in ipairs(schema.files(dir)) do
    if f:match("%.up%.sql$") then return "migrate" end
    local fh = io.open(dir .. "/" .. f)
    if fh then
      local head = fh:read(400) or ""
      fh:close()
      if head:find("+goose", 1, true) then return "goose" end
    end
  end
  return "migrate"
end

-- номер миграции и имя из файла: 000003_create_x.up.sql → 3, "create_x"
local function parse_name(file)
  local num, name = vim.fs.basename(file):match("^(%d+)_(.-)%.")
  return num and tonumber(num), name
end
M.parse_name = parse_name

--- Путь к паре: up ↔ down (для goose — nil, всё в одном файле)
function M.pair(file)
  if file:match("%.up%.sql$") then return (file:gsub("%.up%.sql$", ".down.sql")) end
  if file:match("%.down%.sql$") then return (file:gsub("%.down%.sql$", ".up.sql")) end
end

-- ───── заготовки ─────

local function id_column(dir)
  -- как у уже существующих таблиц: uuid или bigint
  local uuid, other = 0, 0
  for _, t in pairs(schema.load(dir).tables) do
    local first = t.cols[1]
    if first and first.name == "id" then
      if first.type:find("uuid") then uuid = uuid + 1 else other = other + 1 end
    end
  end
  if uuid > other then return "id uuid PRIMARY KEY DEFAULT gen_random_uuid()" end
  return "id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY"
end

local function template(dir, name)
  local t = name:match("^create_(.-)_table$") or name:match("^create_(.+)$")
  if t then
    return {
      ("CREATE TABLE IF NOT EXISTS %s ("):format(t),
      "    " .. id_column(dir) .. ",",
      "    ",
      "    created_at timestamptz NOT NULL DEFAULT now(),",
      "    updated_at timestamptz NOT NULL DEFAULT now()",
      ");",
    }, 3
  end
  local col, tbl = name:match("^add_(.-)_to_(.+)$")
  if col then return { ("ALTER TABLE %s ADD COLUMN %s ;"):format(tbl, col) }, 1 end
  return { "" }, 1
end

local function next_prefix(dir)
  local files = schema.files(dir)
  for _, f in ipairs(vim.fn.readdir(dir)) do
    if f:match("%.down%.sql$") then files[#files + 1] = f end
  end
  local width, max, stamp = 6, 0, false
  for _, f in ipairs(files) do
    local num = f:match("^(%d+)_")
    if num then
      if #num >= 12 then stamp = true end
      width = #num
      max = math.max(max, tonumber(num))
    end
  end
  if stamp then return os.date("%Y%m%d%H%M%S") end
  return ("%0" .. width .. "d"):format(max + 1)
end

--- Новая миграция: спросить имя, создать файлы, открыть up (и down справа)
function M.new(name)
  local dir = M.dir()
  if not dir then
    local root = require("own.root").get()
    dir = root .. "/migrations"
    vim.fn.mkdir(dir, "p")
  end
  local function create(input)
    if not input or vim.trim(input) == "" then return end
    local n = vim.trim(input):lower():gsub("[%s%-]+", "_"):gsub("[^%w_]", "")
    local prefix = next_prefix(dir)
    local lines, row = template(dir, n)
    local up
    if M.tool(dir) == "goose" then
      up = ("%s/%s_%s.sql"):format(dir, prefix, n)
      local body = { "-- +goose Up" }
      vim.list_extend(body, lines)
      vim.list_extend(body, { "", "-- +goose Down", "" })
      vim.fn.writefile(body, up)
      row = row + 1
    else
      up = ("%s/%s_%s.up.sql"):format(dir, prefix, n)
      vim.fn.writefile(lines, up)
      vim.fn.writefile({}, M.pair(up))
    end
    vim.cmd.edit(vim.fn.fnameescape(up))
    if M.pair(up) then
      M.fill_down(0)
      vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(M.pair(up)))
      vim.cmd.wincmd("p")
    end
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
    pcall(vim.api.nvim_win_set_cursor, 0, { row, math.max(0, #line - (line:match(" ;$") and 1 or 0)) })
    vim.cmd.startinsert()
  end
  if name and name ~= "" then return create(name) end
  vim.ui.input({ prompt = "Новая миграция (create_orders, add_phone_to_users): " }, create)
end

-- ───── down по up ─────

local function down_for(text)
  local out = {}
  local sts = schema.statements(schema.up_part(text))
  for i = #sts, 1, -1 do
    local p = sts[i]
    local k = p.kind
    if k == "create_table" then
      out[#out + 1] = ("DROP TABLE IF EXISTS %s;"):format(p.table)
    elseif k == "create_enum" then
      out[#out + 1] = ("DROP TYPE IF EXISTS %s;"):format(p.name)
    elseif k == "create_index" and p.name then
      out[#out + 1] = ("DROP INDEX %sIF EXISTS %s;"):format(p.concurrently and "CONCURRENTLY " or "", p.name)
    elseif k == "create_extension" then
      out[#out + 1] = ("DROP EXTENSION IF EXISTS %s;"):format(p.name)
    elseif k == "create_function" then
      out[#out + 1] = ("DROP FUNCTION IF EXISTS %s;"):format(p.name)
    elseif k == "create_trigger" then
      out[#out + 1] = ("DROP TRIGGER IF EXISTS %s ON %s;"):format(p.name, p.table)
    elseif k == "create_view" then
      out[#out + 1] = ("DROP %sVIEW IF EXISTS %s;"):format(p.materialized and "MATERIALIZED " or "", p.name)
    elseif k == "alter_table" then
      local tbl = p.table
      for j = #p.actions, 1, -1 do
        local a = p.actions[j]
        if a.op == "add_column" and a.col then
          out[#out + 1] = ("ALTER TABLE %s DROP COLUMN IF EXISTS %s;"):format(tbl, a.col.name)
        elseif a.op == "rename_column" then
          out[#out + 1] = ("ALTER TABLE %s RENAME COLUMN %s TO %s;"):format(tbl, a.to, a.from)
        elseif a.op == "rename_table" then
          out[#out + 1] = ("ALTER TABLE %s RENAME TO %s;"):format(a.to, tbl)
          tbl = a.to
        elseif a.op == "add_constraint" and a.name then
          out[#out + 1] = ("ALTER TABLE %s DROP CONSTRAINT IF EXISTS %s;"):format(tbl, a.name)
        else
          out[#out + 1] = ("-- откатить вручную: ALTER TABLE %s %s"):format(tbl, (a.text:gsub("%s+", " ")))
        end
      end
    elseif k ~= "other" or not p.source:lower():match("^%s*insert") then
      out[#out + 1] = "-- откатить вручную: " .. (p.source:gsub("%s+", " "):sub(1, 80))
    end
  end
  return out
end
M.down_for = down_for

local generated = {} -- путь down → что мы туда написали (правили руками — больше не трогаем)

local function blank(lines)
  for _, l in ipairs(lines) do if vim.trim(l) ~= "" then return false end end
  return true
end

--- После сохранения up: down пуст или ещё наш — переписать по up
function M.fill_down(buf)
  if opts().auto_down == false then return end
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local file = vim.api.nvim_buf_get_name(buf)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")

  -- goose: часть Down внутри того же файла
  if not file:match("%.up%.sql$") then
    if not text:find("+goose", 1, true) then return end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local at
    for i, l in ipairs(lines) do if l:match("^%-%-%s*%+goose%s+[Dd]own") then at = i end end
    if not at then return end
    local rest = vim.list_slice(lines, at + 1)
    local key = file .. "#down"
    if not (blank(rest) or vim.deep_equal(rest, generated[key])) then return end
    local down = down_for(text)
    if #down == 0 or vim.deep_equal(rest, down) then return end
    vim.api.nvim_buf_set_lines(buf, at, -1, false, down)
    generated[key] = down
    return
  end

  local path = M.pair(file)
  local down = down_for(text)
  if #down == 0 then return end
  local dbuf = vim.fn.bufnr(path)
  local cur
  if dbuf ~= -1 and vim.api.nvim_buf_is_loaded(dbuf) then
    cur = vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)
  else
    cur = vim.uv.fs_stat(path) and vim.fn.readfile(path) or {}
  end
  if not (blank(cur) or vim.deep_equal(cur, generated[path])) or vim.deep_equal(cur, down) then return end
  if dbuf ~= -1 and vim.api.nvim_buf_is_loaded(dbuf) then
    vim.api.nvim_buf_set_lines(dbuf, 0, -1, false, down)
    vim.api.nvim_buf_call(dbuf, function() vim.cmd("silent! noautocmd write") end)
  else
    vim.fn.writefile(down, path)
  end
  generated[path] = down
end

-- ───── статус и запуск ─────

local function url() return require("own.sql.db").project_url() end

local function cmd(dir, ...)
  local u = url()
  if not u then return nil, "не нашёл базу проекта: DATABASE_URL в .env или postgres в compose" end
  local tool = M.tool(dir)
  if tool == "goose" then
    if vim.fn.executable("goose") == 0 then return nil, "нет goose: go install github.com/pressly/goose/v3/cmd/goose@latest" end
    return vim.list_extend({ "goose", "-dir", dir, "postgres", u }, { ... })
  end
  if vim.fn.executable("migrate") == 0 then return nil, "нет migrate: brew install golang-migrate" end
  return vim.list_extend({ "migrate", "-path", dir, "-database", u }, { ... })
end

local status = {} -- папка → { version, dirty, at, err }
local ns = vim.api.nvim_create_namespace("own.sql.migrations")

local function mark(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if opts().status == false then return end
  local file = vim.api.nvim_buf_get_name(buf)
  local num = parse_name(file)
  local st = status[vim.fs.dirname(file)]
  if not num or not st or st.err then return end
  local text, hl
  if st.dirty and num == st.version then
    text, hl = "✗ dirty — упала на середине: исправь и migrate force " .. (num - 1 >= 0 and num - 1 or 0), "DiagnosticError"
  elseif st.version and num <= st.version then
    text, hl = "✓ применена", "DiagnosticOk"
  else
    text, hl = "○ ждёт применения", "DiagnosticWarn"
  end
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, 0, 0, { virt_text = { { "  " .. text, hl } }, virt_text_pos = "eol", hl_mode = "combine" })
end

local function mark_all(dir)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.fs.dirname(vim.api.nvim_buf_get_name(b)) == dir then mark(b) end
  end
end

--- Узнать версию базы (не чаще раза в 5 с на папку, force — сразу)
function M.refresh(dir, force, done)
  dir = dir or M.dir()
  if not dir then return end
  local st = status[dir]
  if not force and st and os.time() - st.at < 5 then
    mark_all(dir)
    return done and done(st)
  end
  local c = cmd(dir, "version")
  if not c then return end
  status[dir] = vim.tbl_extend("force", st or {}, { at = os.time() })
  vim.system(c, { text = true, timeout = 8000 }, vim.schedule_wrap(function(r)
    local out = (r.stdout or "") .. (r.stderr or "")
    local s = { at = os.time() }
    if out:find("no migration", 1, true) then
      s.version = 0
    else
      local v = out:match("version:?%s*(%d+)") or out:match("^%s*(%d+)")
      if v then
        s.version, s.dirty = tonumber(v), out:find("dirty", 1, true) ~= nil
      else
        s.err = vim.trim(out)
      end
    end
    status[dir] = s
    mark_all(dir)
    if done then done(s) end
  end))
end

local function run(dir, args, title)
  local c, err = cmd(dir, unpack(args))
  if not c then return vim.notify(err, vim.log.levels.WARN) end
  vim.notify(title .. "…")
  vim.system(c, { text = true }, vim.schedule_wrap(function(r)
    local out = vim.trim((r.stdout or "") .. "\n" .. (r.stderr or ""))
    if out == "" then out = "готово" end
    vim.notify(title .. ":\n" .. out, r.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
    M.refresh(dir, true)
  end))
end

function M.up() local d = M.dir(); if d then run(d, { "up" }, "миграции вверх") end end

function M.down()
  local d = M.dir()
  if not d then return end
  M.refresh(d, true, function(s)
    local v = s.version
    if not v or v == 0 then return vim.notify("откатывать нечего — миграций в базе нет") end
    local name
    for _, f in ipairs(schema.files(d)) do
      local n, nm = parse_name(f)
      if n == v then name = nm end
    end
    vim.ui.select({ "да, откатить", "нет" }, { prompt = ("Откатить %d %s?"):format(v, name or "") }, function(choice)
      if choice ~= "да, откатить" then return end
      run(d, M.tool(d) == "goose" and { "down" } or { "down", "1" }, "откат " .. v)
    end)
  end)
end

function M.redo()
  local d = M.dir()
  if not d then return end
  if M.tool(d) == "goose" then return run(d, { "redo" }, "redo") end
  local c, err = cmd(d, "down", "1")
  if not c then return vim.notify(err, vim.log.levels.WARN) end
  vim.system(c, { text = true }, vim.schedule_wrap(function(r)
    if r.code ~= 0 then return vim.notify("откат упал:\n" .. vim.trim((r.stderr or "") .. (r.stdout or "")), vim.log.levels.ERROR) end
    run(d, { "up", "1" }, "redo — откатить и применить последнюю")
  end))
end

function M.status()
  local d = M.dir()
  if not d then return vim.notify("папки миграций нет — пробел r m → новая миграция создаст migrations/") end
  M.refresh(d, true, function(s)
    if s.err then return vim.notify("migrate version:\n" .. s.err, vim.log.levels.WARN) end
    local lines = {}
    for _, f in ipairs(schema.files(d)) do
      local n, nm = parse_name(f)
      if n then
        local mark_ = (s.dirty and n == s.version) and "✗" or (n <= (s.version or 0)) and "✓" or "○"
        lines[#lines + 1] = ("%s %s %s"):format(mark_, n, nm)
      end
    end
    vim.notify(("база: версия %d%s\n%s"):format(s.version or 0, s.dirty and " (dirty)" or "", table.concat(lines, "\n")))
  end)
end

--- Меню: пробел r m
function M.menu()
  local d = M.dir()
  local items = {
    { "+ новая миграция", M.new },
    { "▲ up — применить все", M.up },
    { "▼ down — откатить последнюю", M.down },
    { "⟳ redo — откатить и применить последнюю", M.redo },
    { "≡ статус", M.status },
  }
  if not d then items = { items[1] } end
  vim.ui.select(items, { prompt = "Миграции" .. (d and (" · " .. vim.fn.fnamemodify(d, ":~:.")) or ""), format_item = function(i) return i[1] end },
    function(choice) if choice then choice[2]() end end)
end

function M.setup(group)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.sql",
    callback = function(ev)
      local file = vim.api.nvim_buf_get_name(ev.buf)
      if file:match("%.down%.sql$") then return end
      if file:match("%.up%.sql$") or (M.dir(ev.buf) == vim.fs.dirname(file)) then M.fill_down(ev.buf) end
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*.sql",
    callback = function(ev)
      local file = vim.api.nvim_buf_get_name(ev.buf)
      if parse_name(file) and opts().status ~= false then
        local dir = vim.fs.dirname(file)
        if status[dir] then mark(ev.buf) end
        M.refresh(dir)
      end
    end,
  })
  vim.api.nvim_create_user_command("Migrate", function(a)
    local f = ({ up = M.up, down = M.down, redo = M.redo, status = M.status, new = function() M.new(a.fargs[2]) end })[a.fargs[1] or ""]
    if f then f() else M.menu() end
  end, { nargs = "*", complete = function() return { "new", "up", "down", "redo", "status" } end, desc = "Миграции" })
end

return M
