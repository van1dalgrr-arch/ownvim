-- Настройки в два слоя, как в Zed: defaults.jsonc — всё по умолчанию с объяснениями (в репозитории),
-- settings.jsonc — только то, что поменял ты. Удалил строку из settings.jsonc — вернулось умолчание.
-- Сохранил settings.jsonc — тема, опции, клавиши и настройки модулей применяются сразу;
-- включить/выключить модуль или плагин — после :restart. Ошибка в файле — подсветка на её строке,
-- редактор продолжает работать на прошлых настройках.
-- Читает, проверяет и сливает слои Go-ядро (core/settings, программа ownvimd); его ответ кэшируется вместе
-- с отпечатком исходных файлов, и на старте читается кэш — программа запускается, только если что-то поменялось.
-- Нет Go — работает прежний Lua-движок ниже (legacy_load).
local jsonc = require("own.jsonc")

local M = {}

local dir = vim.fn.stdpath("config")
M.files = { defaults = dir .. "/defaults.jsonc", user = dir .. "/settings.jsonc" }

local ns = vim.api.nvim_create_namespace("own.settings")
local TOP = { theme = true, options = true, globals = true, modules = true, keys = true, plugins = true,
  lsp = true, diagnostics = true, tools = true, completion = true, format = true, lint = true,
  test = true, debug = true, database = true,
  colors = true, appearance = true, icons = true, statusline = true,
  tabline = true, breadcrumbs = true, dashboard = true, font = true, animations = true, git = true,
  go = true, python = true, tasks = true, ai = true, sessions = true, explorer = true, commands = true, auto = true, extensions = true, checks = true, run = true, project = true }

M.current = nil -- последние применённые настройки
M.problems = {} -- путь → { диагностика }

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

-- пустой {} — тоже объект: vim.islist({}) == true, и "keys": {} иначе стёр бы все клавиши по умолчанию
local function is_dict(t) return type(t) == "table" and (next(t) == nil or not vim.islist(t)) end

-- слияние слоёв: объекты — по ключам, остальное заменяется целиком.
-- true поверх объекта оставляет объект: "modes": true значит «включён, с настройками по умолчанию»
local function merge(base, over)
  if over == nil then return base end
  if over == true and is_dict(base) then return base end
  if not (is_dict(base) and is_dict(over)) then return over end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over) do
    if type(k) ~= "string" or k:sub(-1) ~= "+" then out[k] = merge(base[k], v) end
  end
  -- "ключ+": [ … ] — дописать к списку ключа (как в core/settings/merge.go)
  for k, v in pairs(over) do
    if type(k) == "string" and k:sub(-1) == "+" and vim.islist(v) then
      local name = k:sub(1, -2)
      out[name] = vim.list_extend(vim.deepcopy(type(out[name]) == "table" and out[name] or {}), v)
    end
  end
  return out
end

-- проверить верхний уровень и модули: опечатка в имени не должна молча ничего не делать
local function check(path, text, value, problems)
  for key in pairs(value) do
    if not TOP[key] then
      local lnum, col = jsonc.find_key(text, key)
      problems[#problems + 1] = { lnum = (lnum or 1) - 1, col = col or 0, severity = vim.diagnostic.severity.WARN,
        message = ("неизвестный раздел %q — есть: theme, options, globals, modules, keys, plugins, lsp, diagnostics, tools, completion, format, lint, test, debug, database, colors, appearance, icons, statusline, tabline, breadcrumbs, dashboard, font, animations, git, go, python, tasks, ai, sessions, explorer, commands, auto, extensions, checks, run, project"):format(key) }
    end
  end
  for name in pairs(value.modules or {}) do
    if not vim.uv.fs_stat(dir .. "/lua/own/modules/" .. name .. ".lua") then
      local lnum, col = jsonc.find_key(text, name)
      problems[#problems + 1] = { lnum = (lnum or 1) - 1, col = col or 0, severity = vim.diagnostic.severity.WARN,
        message = ("нет модуля %q (список — в defaults.jsonc, раздел modules)"):format(name) }
    end
  end
  for name in pairs(value.options or {}) do
    if not pcall(vim.api.nvim_get_option_info2, name, {}) then
      local lnum, col = jsonc.find_key(text, name)
      problems[#problems + 1] = { lnum = (lnum or 1) - 1, col = col or 0, severity = vim.diagnostic.severity.WARN,
        message = ("у nvim нет опции %q (:help options)"):format(name) }
    end
  end
  M.problems[path] = problems
end

local function load_file(path)
  local text = read(path)
  if not text then return {} end
  local value, err = jsonc.decode(text)
  if not value then
    M.problems[path] = { { lnum = err.lnum - 1, col = err.col, severity = vim.diagnostic.severity.ERROR, message = err.message } }
    return nil
  end
  check(path, text, value, {})
  return value
end

--- Пожаловаться на ключ "name" в том файле, где он написан (сначала settings.jsonc, потом defaults.jsonc)
function M.warn(name, message)
  for _, which in ipairs({ "user", "defaults" }) do
    local path = M.files[which]
    local lnum, col = jsonc.find_key(read(path) or "", name)
    if lnum then
      M.problems[path] = M.problems[path] or {}
      table.insert(M.problems[path], { lnum = lnum - 1, col = col, severity = vim.diagnostic.severity.WARN, message = message })
      return
    end
  end
  vim.notify(("настройки: %s — %s"):format(name, message), vim.log.levels.WARN)
end

-- показать проблемы в открытых буферах файлов настроек (и снять, когда исправлено)
function M.show_problems()
  local paths = vim.tbl_values(M.files)
  for path in pairs(M.problems) do -- и JSONC-наборы (extensions/*.jsonc)
    if not vim.tbl_contains(paths, path) then paths[#paths + 1] = path end
  end
  for _, path in ipairs(paths) do
    local buf = vim.fn.bufnr(path)
    if buf == -1 then buf = vim.fn.bufnr(vim.fn.resolve(path)) end
    if buf ~= -1 then vim.diagnostic.set(ns, buf, M.problems[path] or {}) end
  end
end

--- Lua-движок: прочитать и слить оба слоя (если Go-ядра нет). skip_user — только умолчания.
local function legacy_load(skip_user)
  if not skip_user then M.problems = {} end
  local defaults = load_file(M.files.defaults)
  local user = skip_user and {} or load_file(M.files.user)
  if not defaults or not user then
    local path = defaults and M.files.user or M.files.defaults
    local p = M.problems[path][1]
    return nil, ("%s:%d — %s"):format(vim.fn.fnamemodify(path, ":t"), p.lnum + 1, p.message)
  end
  local s = merge(defaults, user)
  -- языки, для которых ownvim сам включил инструменты (own.auto), — между умолчаниями и settings.jsonc
  local ok, layer = pcall(function() return require("own.auto").layer(s) end)
  if ok and layer then s = merge(merge(defaults, layer), user) end
  return s
end

-- ── Go-ядро: кэш и вызов ─────────────────────────────────────────────────────

local data = vim.fn.stdpath("data")
local cache_path = data .. "/own-settings.cache.json"
local options_path = data .. "/own-options.json"
local JSON = { luanil = { object = true, array = true } }

local function stamp_of(p)
  local st = vim.uv.fs_stat(p)
  if not st then return "-" end
  return ("%d.%09d:%d"):format(st.mtime.sec, st.mtime.nsec, st.size)
end

-- отпечаток наборов (extensions/*.jsonc) — как core/settings.pluginsStamp: папка и каждый файл
local function plugins_stamp()
  local pdir = dir .. "/extensions"
  local parts = { stamp_of(pdir) }
  local files = vim.fn.glob(pdir .. "/*.jsonc", false, true)
  table.sort(files)
  for _, f in ipairs(files) do parts[#parts + 1] = vim.fs.basename(f) .. "=" .. stamp_of(f) end
  return table.concat(parts, ";")
end

-- отпечаток — тот же, что считает core/settings.Stamp
local function stamp()
  return {
    defaults = stamp_of(M.files.defaults),
    user = stamp_of(M.files.user),
    auto = stamp_of(data .. "/own-auto.json"),
    options = stamp_of(options_path),
    modules = stamp_of(dir .. "/lua/own/modules"),
    plugins = plugins_stamp(),
    engine = stamp_of(require("own.core").bin),
  }
end

local function from_cache()
  local text = read(cache_path)
  if not text then return nil end
  local ok, r = pcall(vim.json.decode, text, JSON)
  if not ok or type(r) ~= "table" or not vim.deep_equal(r.stamp, stamp()) then return nil end
  return r
end

-- имена опций nvim для проверки раздела options (Go их сам не знает); заново — после обновления nvim
local function ensure_options()
  local version = tostring(vim.version())
  local ok, f = pcall(vim.json.decode, read(options_path) or "", JSON)
  if ok and type(f) == "table" and f.version == version then return end
  local names = {}
  for name, info in pairs(vim.api.nvim_get_all_options_info()) do
    names[#names + 1] = name
    if info.shortname and info.shortname ~= "" then names[#names + 1] = info.shortname end
  end
  local out = io.open(options_path, "w")
  if out then out:write(vim.json.encode({ version = version, names = names })); out:close() end
end

local function from_engine()
  ensure_options()
  local r = require("own.core").run({ "settings", "load", "--config", dir, "--data", data })
  if not r or r.code ~= 0 then return nil end
  local ok, res = pcall(vim.json.decode, r.stdout, JSON)
  return ok and type(res) == "table" and res or nil
end

M.legacy_load = legacy_load -- для проверки: Go-движок должен давать то же самое

--- Прочитать и слить слои. Если файл не разобрался — nil и сообщение.
--- skip_user — только умолчания (когда settings.jsonc сломан; его ошибка остаётся в problems)
function M.load(skip_user)
  local r = from_cache() or from_engine()
  if not r then return legacy_load(skip_user) end
  if not skip_user then M.problems = r.problems or {} end
  if skip_user then return r.fallback or r.settings end
  if r.error then return nil, r.error end
  return r.settings
end

--- Модуль включён? (true / объект без enabled=false)
function M.enabled(s, name)
  local v = (s.modules or {})[name]
  return v == true or (is_dict(v) and v.enabled ~= false)
end

--- Настройки модуля (объект из modules.<name> без поля enabled)
function M.module_opts(s, name)
  local v = (s.modules or {})[name]
  if not is_dict(v) then return {} end
  local o = vim.deepcopy(v)
  o.enabled = nil
  return o
end

--- Следить за сохранением settings.jsonc / defaults.jsonc: перечитать и отдать on_change(новые, старые)
--- Перечитать настройки и применить на лету (как при сохранении settings.jsonc)
function M.reapply()
  local new, err = M.load()
  M.show_problems()
  if not new then
    vim.notify("настройки не применены: " .. err, vim.log.levels.ERROR)
    return
  end
  local old = M.current
  M.current = new
  if M.on_change then M.on_change(new, old) end
end

function M.watch(on_change)
  M.on_change = on_change
  local group = vim.api.nvim_create_augroup("own.settings", { clear = true })
  local targets = {}
  for _, p in pairs(M.files) do targets[vim.fn.resolve(p)] = true end
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.jsonc",
    nested = true, -- иначе смена темы не догрузит её плагин (lazy ловит ColorSchemePre) и не сработают ColorScheme-хуки
    callback = function(ev)
      local path = vim.fn.resolve(vim.api.nvim_buf_get_name(ev.buf))
      -- свой файл настроек или JSONC-набор (extensions/*.jsonc)
      if not targets[path] and not path:find(vim.fn.resolve(dir) .. "/extensions/[^/]+%.jsonc$") then return end
      M.reapply()
    end,
  })
  -- открыл файл настроек — сразу видно, что в нём не так
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    pattern = "*.jsonc",
    callback = function(ev)
      local path = vim.fn.resolve(vim.api.nvim_buf_get_name(ev.buf))
      if targets[path] or path:find(vim.fn.resolve(dir) .. "/extensions/[^/]+%.jsonc$") then vim.schedule(M.show_problems) end
    end,
  })
end

-- конец значения JSON, которое начинается в позиции i: объект/массив — до парной скобки, строка — до кавычки
local function value_end(text, i)
  local c = text:sub(i, i)
  if c == '"' then
    local j = i + 1
    while j <= #text do
      local d = text:sub(j, j)
      if d == "\\" then j = j + 1 elseif d == '"' then return j end
      j = j + 1
    end
    return #text
  end
  if c == "{" or c == "[" then
    local depth, j, in_str = 0, i, false
    while j <= #text do
      local d = text:sub(j, j)
      if in_str then
        if d == "\\" then j = j + 1 elseif d == '"' then in_str = false end
      elseif d == '"' then in_str = true
      elseif d == "{" or d == "[" then depth = depth + 1
      elseif d == "}" or d == "]" then
        depth = depth - 1
        if depth == 0 then return j end
      end
      j = j + 1
    end
    return #text
  end
  local j = text:find("[,\n}]", i) or (#text + 1)
  return j - 1
end

--- Записать верхний ключ в settings.jsonc, не трогая комментарии и остальное (как VS Code пишет settings.json).
--- Применяется как при сохранении — через on_change, переданный в watch.
function M.set(key, value)
  local r = require("own.core").run({ "settings", "set", "--config", dir, key, vim.json.encode(value) })
  if r and r.code == 0 then
    local buf = vim.fn.bufnr(M.files.user)
    if buf ~= -1 then vim.api.nvim_buf_call(buf, function() vim.cmd("silent! checktime") end) end
    local new = M.load()
    if new and M.on_change then
      local old = M.current
      M.current = new
      M.on_change(new, old)
    end
    return
  end
  if r then vim.notify("настройки не записаны: " .. vim.trim(r.stderr or ""), vim.log.levels.ERROR) return end
  local path = M.files.user
  local text = read(path) or "{\n}\n"
  local json = vim.json.encode(value)
  -- ищем по тексту без комментариев (позиции совпадают), правим исходный
  local clean = jsonc.strip(text)
  local _, e = clean:match('()"' .. vim.pesc(key) .. '"%s*:%s*()')
  if e then
    text = text:sub(1, e - 1) .. json .. text:sub(value_end(clean, e) + 1)
  else
    local brace = clean:find("{", 1, true)
    if not brace then text, brace = "{\n}\n", 1 end
    text = text:sub(1, brace) .. ("\n  %q: %s,"):format(key, json) .. text:sub(brace + 1)
  end
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 then vim.api.nvim_buf_call(buf, function() vim.cmd("silent! checktime") end) end
  local new = M.load()
  if new and M.on_change then
    local old = M.current
    M.current = new
    M.on_change(new, old)
  end
end

--- :Settings — открыть свой слой; :Settings defaults — посмотреть все умолчания
function M.open(which)
  vim.cmd.edit(vim.fn.fnameescape(which == "defaults" and M.files.defaults or M.files.user))
end

return M
