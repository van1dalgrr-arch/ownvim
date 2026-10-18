-- Настройки в два слоя, как в Zed: defaults.jsonc — всё по умолчанию с объяснениями (в репозитории),
-- settings.jsonc — только то, что поменял ты. Удалил строку из settings.jsonc — вернулось умолчание.
-- Сохранил settings.jsonc — тема, опции, клавиши и настройки модулей применяются сразу;
-- включить/выключить модуль или плагин — после :restart. Ошибка в файле — подсветка на её строке,
-- редактор продолжает работать на прошлых настройках.
local jsonc = require("own.jsonc")

local M = {}

local dir = vim.fn.stdpath("config")
M.files = { defaults = dir .. "/defaults.jsonc", user = dir .. "/settings.jsonc" }

local ns = vim.api.nvim_create_namespace("own.settings")
local TOP = { theme = true, options = true, globals = true, modules = true, keys = true, plugins = true,
  lsp = true, diagnostics = true, tools = true, completion = true, format = true, lint = true,
  test = true, debug = true, database = true,
  colors = true, appearance = true, icons = true, statusline = true,
  tabline = true, breadcrumbs = true, dashboard = true }

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
  for k, v in pairs(over) do out[k] = merge(base[k], v) end
  return out
end

-- проверить верхний уровень и модули: опечатка в имени не должна молча ничего не делать
local function check(path, text, value, problems)
  for key in pairs(value) do
    if not TOP[key] then
      local lnum, col = jsonc.find_key(text, key)
      problems[#problems + 1] = { lnum = (lnum or 1) - 1, col = col or 0, severity = vim.diagnostic.severity.WARN,
        message = ("неизвестный раздел %q — есть: theme, options, globals, modules, keys, plugins, lsp, diagnostics, tools, completion, format, lint, test, debug, database, colors, appearance, icons, statusline, tabline, breadcrumbs, dashboard"):format(key) }
    end
  end
  for name in pairs(value.modules or {}) do
    if not vim.api.nvim_get_runtime_file("lua/own/modules/" .. name .. ".lua", false)[1] then
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
  for _, path in pairs(M.files) do
    local buf = vim.fn.bufnr(path)
    if buf == -1 then buf = vim.fn.bufnr(vim.fn.resolve(path)) end
    if buf ~= -1 then vim.diagnostic.set(ns, buf, M.problems[path] or {}) end
  end
end

--- Прочитать и слить оба слоя. Если файл не разобрался — nil и сообщение.
--- skip_user — только умолчания (когда settings.jsonc сломан; его ошибка остаётся в problems)
function M.load(skip_user)
  if not skip_user then M.problems = {} end
  local defaults = load_file(M.files.defaults)
  local user = skip_user and {} or load_file(M.files.user)
  if not defaults or not user then
    local path = defaults and M.files.user or M.files.defaults
    local p = M.problems[path][1]
    return nil, ("%s:%d — %s"):format(vim.fn.fnamemodify(path, ":t"), p.lnum + 1, p.message)
  end
  return merge(defaults, user)
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
      if not targets[vim.fn.resolve(vim.api.nvim_buf_get_name(ev.buf))] then return end
      local new, err = M.load()
      M.show_problems()
      if not new then
        vim.notify("настройки не применены: " .. err, vim.log.levels.ERROR)
        return
      end
      local old = M.current
      M.current = new
      on_change(new, old)
    end,
  })
  -- открыл файл настроек — сразу видно, что в нём не так
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    pattern = "*.jsonc",
    callback = function(ev)
      if targets[vim.fn.resolve(vim.api.nvim_buf_get_name(ev.buf))] then vim.schedule(M.show_problems) end
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
