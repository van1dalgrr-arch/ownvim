-- Темы иконок: значки файлов, папок, видов дополнения — в дереве, поиске, меню дополнения, статусной строке.
-- Тема иконок — JSON в icons/<имя>.json (рядом с settings.jsonc):
--   { "name": "…", "include": "default",
--     "style": "glyph" | "ascii",            — ascii: буквы вместо значков (без Nerd Font)
--     "monochrome": "muted",                 — все значки одним цветом
--     "default":   { "file": { "glyph": "…", "color": "blue" }, "directory": {…} },
--     "directory": { ".github": {…} }, "extension": { "go": {…} }, "file": { "go.mod": {…} },
--     "filetype":  { "dockerfile": {…} },    "lsp": { "Function": {…} } }
-- color — "red", "orange", "yellow", "green", "cyan", "azure", "blue", "purple", "pink", "grey", "accent"
-- (берутся из текущей темы) или "#rrggbb". Значки — любые символы шрифта (Nerd Font у Ghostty встроен).
-- Раздел "icons" в settings.jsonc: { "theme": "default", "overrides": { … как в теме … } }. На лету.
-- SVG-иконки VS Code терминал не покажет — их темы не ставятся; ставятся JSON-темы: :IconThemeInstall <ссылка>.
local jsonc = require("own.jsonc")
local settings = require("own.settings")

local M = {}

M.dir = vim.fn.stdpath("config") .. "/icons"
local CATEGORIES = { "default", "directory", "extension", "file", "filetype", "lsp", "os" }
local NAMED = {
  red = "MiniIconsRed", orange = "MiniIconsOrange", yellow = "MiniIconsYellow", green = "MiniIconsGreen",
  cyan = "MiniIconsCyan", azure = "MiniIconsAzure", blue = "MiniIconsBlue", purple = "MiniIconsPurple",
  grey = "MiniIconsGrey", gray = "MiniIconsGrey", muted = "MiniIconsGrey", pink = "OwnIconPink", accent = "OwnIconAccent",
}

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function opts() return (settings.current or {}).icons or {} end

function M.list()
  local out = {}
  for name, kind in vim.fs.dir(M.dir) do
    if kind == "file" and name:match("%.json$") then out[#out + 1] = name:gsub("%.json$", "") end
  end
  table.sort(out)
  return out
end

local function load(name, seen)
  seen = seen or {}
  if seen[name] then return nil, "include по кругу: " .. name end
  seen[name] = true
  local t, err = jsonc.decode(read(M.dir .. "/" .. name .. ".json") or "")
  if not t then return nil, err and err.message or ("нет темы иконок " .. name) end
  if t.include then
    local base, e = load(t.include, seen)
    if not base then return nil, e end
    t = vim.tbl_deep_extend("force", base, t)
  end
  return t
end

local hex_groups = {} -- свои группы "#rrggbb" — после смены темы (hi clear) поставить заново

-- цвет → группа подсветки (именованные — из темы, hex — своя группа)
local function hl_of(c)
  if not c then return nil end
  if NAMED[c] then return NAMED[c] end
  if type(c) == "string" and c:match("^#%x%x%x%x%x%x$") then
    local g = "OwnIcon_" .. c:sub(2)
    hex_groups[g] = c
    vim.api.nvim_set_hl(0, g, { fg = c })
    return g
  end
  return "MiniIconsGrey"
end

local current_theme = {}
local last_mono

-- свои группы иконок: розовый, акцент, одноцветный режим — из темы, пересчитать при её смене
local function define_groups()
  local function fg(group, fallback)
    local h = vim.api.nvim_get_hl(0, { name = group, link = false })
    return h.fg or fallback
  end
  -- JSON-темы задают их сами (из палитры); у тем-плагинов — ближайшее
  if not next(vim.api.nvim_get_hl(0, { name = "OwnIconPink" })) then vim.api.nvim_set_hl(0, "OwnIconPink", { fg = fg("Special", 0xf5a8d0) }) end
  if not next(vim.api.nvim_get_hl(0, { name = "OwnIconAccent" })) then vim.api.nvim_set_hl(0, "OwnIconAccent", { fg = fg("Title", 0xbb9af7) }) end
  for g, c in pairs(hex_groups) do vim.api.nvim_set_hl(0, g, { fg = c }) end
  local mono = current_theme.monochrome
  if mono then
    local target = NAMED[mono] and fg(NAMED[mono], fg("Comment", 0x888888)) or (mono:match("^#") and mono) or fg("Comment", 0x888888)
    for _, g in pairs(NAMED) do vim.api.nvim_set_hl(0, g, { fg = target }) end
  end
end

local function to_mini(t)
  local cfg = { style = t.style or "glyph" }
  for _, cat in ipairs(CATEGORIES) do
    local src = t[cat]
    if type(src) == "table" and next(src) then
      cfg[cat] = {}
      for name, icon in pairs(src) do
        cfg[cat][name] = { glyph = icon.glyph, hl = hl_of(icon.color) }
      end
    end
  end
  return cfg
end

--- force — из config плагина: mini.icons ещё грузится, package.loaded пока пуст
function M.apply(force)
  local o = opts()
  local name = o.theme or "default"
  local t, err = load(name)
  if not t then
    settings.warn("icons", ("тема иконок %q: %s — список: :IconTheme"):format(name, err))
    t = {}
  end
  t = vim.tbl_deep_extend("force", t, o.overrides or {})
  current_theme = t
  if not force and not package.loaded["mini.icons"] then return end
  -- одноцветный режим включили/выключили — тема заново раскрасит MiniIcons*, потом define_groups — поверх
  if (t.monochrome or false) ~= (last_mono or false) and vim.g.colors_name then
    last_mono = t.monochrome
    pcall(vim.cmd.colorscheme, vim.g.colors_name)
  end
  last_mono = t.monochrome
  require("mini.icons").setup(to_mini(t))
  define_groups()
  vim.cmd("redraw!")
end

function M.plugins()
  return {
    {
      "nvim-mini/mini.icons",
      lazy = true,
      init = function()
        package.preload["nvim-web-devicons"] = function()
          require("mini.icons").mock_nvim_web_devicons()
          return package.loaded["nvim-web-devicons"]
        end
      end,
      config = function() M.apply(true) end,
    },
  }
end

function M.setup()
  vim.fn.mkdir(M.dir, "p")
  M.apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("own.icons", { clear = true }),
    callback = define_groups, -- тема уже поставила MiniIcons* — свои группы и одноцветный режим поверх
  })
  vim.api.nvim_create_user_command("IconTheme", function(a)
    if a.args == "" then
      return vim.ui.select(M.list(), { prompt = "Тема иконок" }, function(choice)
        if choice then settings.set("icons", vim.tbl_extend("force", opts(), { theme = choice })) end
      end)
    end
    settings.set("icons", vim.tbl_extend("force", opts(), { theme = a.args }))
  end, { nargs = "?", complete = function() return M.list() end, desc = "Тема иконок (без имени — выбрать)" })
  vim.api.nvim_create_user_command("IconThemeInstall", function(a)
    local url = a.args
    local name = vim.fn.fnamemodify(url, ":t:r"):lower():gsub("[^%w%-_]+", "-")
    vim.system({ "curl", "-fsSL", "-o", M.dir .. "/" .. name .. ".json", url }, {}, function(r)
      vim.schedule(function()
        if r.code ~= 0 then return vim.notify("не скачалось: " .. (r.stderr or ""), vim.log.levels.ERROR) end
        local _, err = load(name)
        if err then return vim.notify(("%s.json не разобрался: %s"):format(name, err), vim.log.levels.ERROR) end
        settings.set("icons", vim.tbl_extend("force", opts(), { theme = name }))
        vim.notify("тема иконок " .. name .. " поставлена")
      end)
    end)
  end, { nargs = 1, desc = "Тема иконок по ссылке на JSON" })
end

function M.reload() M.apply() end

return M
