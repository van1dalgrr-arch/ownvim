-- Движок тем ownvim. Тема — JSON в themes/<имя>.json (рядом с settings.jsonc):
--   { "name": "Dev Night", "type": "dark" | "light",
--     "palette": { "bg", "fg", "accent", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink",
--                  "bg_alt", "bg_highlight", "bg_visual", "border", "fg_dim", "fg_muted", "diff_*" } — обязательны bg и fg,
--     "syntax": { "keyword": "purple", "string": { "fg": "#eab308", "italic": true }, … } — роли кода,
--     "groups": { "Normal": { "bg": "none" }, "@keyword.return": { "fg": "red" } } — любые группы как есть,
--     "include": "dev-night" — взять другую тему и поменять только своё,
--     "image": "~/Pictures/a.png" — картинка для панели image_panel, пока стоит эта тема }
-- Цвет — имя из палитры или "#rrggbb". Каждая тема — обычная colorscheme: :colorscheme dev-night, alt-s.
-- Сохранил файл темы — она перекрасилась сразу. Поверх любой темы — раздел "colors" в settings.jsonc.
local jsonc = require("own.jsonc")
local groups = require("own.theme.groups")
local settings = require("own.settings")

local M = {}

M.dir = vim.fn.stdpath("config") .. "/themes"
local shim_dir = vim.fn.stdpath("data") .. "/own-colors"

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function merge(a, b)
  if type(b) ~= "table" then return b end
  if next(b) == nil then return a end -- пустой {} в Lua неотличим от списка — это «ничего не менять»
  if type(a) ~= "table" or vim.islist(b) then return b end
  local out = vim.deepcopy(a)
  for k, v in pairs(b) do out[k] = merge(out[k], v) end
  return out
end

--- Имена всех тем-JSON
function M.list()
  local out = {}
  for name, kind in vim.fs.dir(M.dir) do
    if kind == "file" and name:match("%.json$") then out[#out + 1] = name:gsub("%.json$", "") end
  end
  table.sort(out)
  return out
end

function M.exists(name) return name and vim.uv.fs_stat(M.dir .. "/" .. name .. ".json") ~= nil end

--- Прочитать тему (с include); nil и ошибка, если не вышло
function M.load(name, seen)
  seen = seen or {}
  if seen[name] then return nil, "include по кругу: " .. name end
  seen[name] = true
  local path = M.dir .. "/" .. name .. ".json"
  local text = read(path)
  if not text then return nil, "нет темы " .. name end
  local t, err = jsonc.decode(text)
  if not t then return nil, ("%s.json:%d — %s"):format(name, err.lnum, err.message) end
  if t.include then
    local base, e = M.load(t.include, seen)
    if not base then return nil, e end
    local inc = t.include
    t.include = nil
    t = merge(base, t)
    t.included = inc
  end
  return t
end

-- раздел "colors" в settings.jsonc: общий и для конкретной темы — "[dev-night]": {…}, как в VS Code
local function overrides(name)
  local c = (settings.current or {}).colors or {}
  local general, specific = {}, c["[" .. name .. "]"] or {}
  for k, v in pairs(c) do
    if not k:match("^%[") then general[k] = v end
  end
  return merge(general, specific)
end

local function appearance() return (settings.current or {}).appearance or {} end

--- Применить тему (вызывается из colors/<имя>.lua, то есть через :colorscheme)
function M.apply(name)
  local t, err = M.load(name)
  if not t then
    vim.notify("тема: " .. err, vim.log.levels.ERROR)
    return
  end
  t = merge(t, overrides(name))
  local g, _, light, term = groups.build(t, { transparent = appearance().transparent })
  if vim.g.colors_name then vim.cmd("hi clear") end
  vim.o.termguicolors = true
  local want = light and "light" or "dark"
  if vim.o.background ~= want then vim.o.background = want end
  vim.g.colors_name = name
  for group, spec in pairs(g) do vim.api.nvim_set_hl(0, group, spec) end
  for i, c in ipairs(term) do vim.g["terminal_color_" .. (i - 1)] = c end
end

--- colors/<имя>.lua для каждой темы — тогда работают :colorscheme, alt-s и всё, что знает про colorscheme
function M.sync_shims()
  vim.fn.mkdir(shim_dir .. "/colors", "p")
  local have = {}
  for _, name in ipairs(M.list()) do
    have[name .. ".lua"] = true
    local path = shim_dir .. "/colors/" .. name .. ".lua"
    if not vim.uv.fs_stat(path) then
      vim.fn.writefile({ ("require('own.theme').apply(%q)"):format(name) }, path)
    end
  end
  for file in vim.fs.dir(shim_dir .. "/colors") do
    if not have[file] then os.remove(shim_dir .. "/colors/" .. file) end
  end
end

--- Какую тему ставить по настройкам: строка или { "dark": …, "light": … } по фону системы
function M.wanted(setting)
  if type(setting) == "table" then return setting[vim.o.background] or setting.dark or setting.light end
  return setting
end

--- :ThemeNew <имя> [на основе] — копия текущей (или указанной) темы, открыть и править
function M.new(name, from)
  if not name or name == "" then return vim.notify("ThemeNew <имя> [тема-основа]", vim.log.levels.WARN) end
  name = name:lower():gsub("[^%w%-_]+", "-")
  if M.exists(name) then return vim.notify(name .. " уже есть — " .. M.dir .. "/" .. name .. ".json", vim.log.levels.WARN) end
  from = from or (M.exists(vim.g.colors_name) and vim.g.colors_name) or "dev-night"
  local lines = {
    ("// %s — своя тема. Меняй цвета и сохраняй: редактор перекрашивается сразу."):format(name),
    "// Цвет — имя из palette или \"#rrggbb\"; синтаксис — роли (keyword, function, string, type…);",
    "// groups — любые группы подсветки как есть (:Inspect под курсором покажет имя группы).",
    "{",
    ("  \"name\": %q,"):format(name),
    ("  \"include\": %q, // всё, что не задано здесь, — из этой темы"):format(from),
    "  \"palette\": {",
    "    // \"accent\": \"#f472b6\",",
    "  },",
    "  \"syntax\": {",
    "    // \"keyword\": { \"fg\": \"purple\", \"italic\": true },",
    "  },",
    "  \"groups\": {},",
    "}",
  }
  vim.fn.writefile(lines, M.dir .. "/" .. name .. ".json")
  M.sync_shims()
  vim.cmd.edit(vim.fn.fnameescape(M.dir .. "/" .. name .. ".json"))
  vim.cmd.colorscheme(name)
end

function M.setup()
  vim.fn.mkdir(M.dir, "p")
  M.sync_shims()
  vim.opt.rtp:append(shim_dir)
  local group = vim.api.nvim_create_augroup("own.theme", { clear = true })
  -- сохранил тему — перекрасилось (и тема, которая её include-ит)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.json",
    nested = true,
    callback = function(ev)
      local path = vim.fn.resolve(vim.api.nvim_buf_get_name(ev.buf))
      if vim.fs.dirname(path) ~= vim.fn.resolve(M.dir) then return end
      M.sync_shims()
      local name = vim.fn.fnamemodify(path, ":t:r")
      local cur = vim.g.colors_name
      if cur == name or (M.exists(cur) and (M.load(cur) or {}).included == name) then
        local _, err = M.load(cur)
        if err then return vim.notify("тема: " .. err, vim.log.levels.ERROR) end
        vim.cmd.colorscheme(cur)
      end
    end,
  })
  vim.api.nvim_create_user_command("ThemeNew", function(a) M.new(a.fargs[1], a.fargs[2]) end, {
    nargs = "+",
    complete = function(_, line)
      return #vim.split(line, "%s+") > 2 and M.list() or {}
    end,
    desc = "Своя тема: ThemeNew <имя> [тема-основа]",
  })
  vim.api.nvim_create_user_command("ThemeEdit", function(a)
    local name = a.args ~= "" and a.args or vim.g.colors_name
    if not M.exists(name) then return vim.notify(("%s — не JSON-тема ownvim"):format(name), vim.log.levels.WARN) end
    vim.cmd.edit(vim.fn.fnameescape(M.dir .. "/" .. name .. ".json"))
  end, { nargs = "?", complete = function() return M.list() end, desc = "Открыть файл темы" })
  require("own.theme.install").setup()
end

return M
