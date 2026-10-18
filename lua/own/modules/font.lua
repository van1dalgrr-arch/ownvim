-- Шрифт из settings.jsonc — в Ghostty (сам nvim в терминале шрифт не задаёт). Раздел "font":
--   "family": "JetBrains Mono", "size": 14, "ligatures": true, "line_height": "10%", "thicken": false,
--   "features": ["ss01", "zero"] — свои OpenType-фичи
-- ownvim пишет ~/.config/ghostty/ownvim.ghostty и просит Ghostty перечитать конфиг. В основном конфиге Ghostty
-- должна быть строка config-file = ?ownvim.ghostty (dotfiles её содержат; иначе ownvim добавит её сам).
-- Значки Nerd Font у Ghostty встроены — подходит любой шрифт. Шрифт в Ghostty общий для всех окон.
-- :Font — выбрать из установленных (сразу видно), :FontInstall <имя> — поставить (brew: все Google Fonts и
-- Nerd Fonts; иначе — релиз Nerd Fonts в ~/Library/Fonts).
local settings = require("own.settings")

local M = {}

local DIR = vim.fn.expand("~/.config/ghostty")
local FILE = DIR .. "/ownvim.ghostty"
local INCLUDE = "config-file = ?ownvim.ghostty"

local function o() return (settings.current or {}).font or {} end

local function main_config()
  for _, name in ipairs({ "config.ghostty", "config" }) do
    local p = DIR .. "/" .. name
    if vim.uv.fs_stat(p) then return p end
  end
end

local function reload_ghostty()
  vim.system({ "osascript", "-e",
    'tell application "Ghostty" to if (count terminals) > 0 then perform action "reload_config" on first terminal' })
end

-- строка include в основном конфиге Ghostty (один раз, если её нет)
local function ensure_include()
  local main = main_config()
  if not main then return false end
  local f = io.open(main)
  local text = f and f:read("*a") or ""
  if f then f:close() end
  if text:find(INCLUDE, 1, true) then return true end
  local out = io.open(main, "a")
  if not out then return false end
  out:write("\n# шрифт из ownvim (settings.jsonc, раздел font)\n" .. INCLUDE .. "\n")
  out:close()
  vim.notify("добавил в " .. main .. ": " .. INCLUDE)
  return true
end

local last

function M.apply()
  local f = o()
  local lines = { "# пишет ownvim из settings.jsonc (раздел font) — править там" }
  if f.family then
    lines[#lines + 1] = 'font-family = ""' -- сбросить список из основного конфига
    lines[#lines + 1] = "font-family = " .. f.family
  end
  if f.size then lines[#lines + 1] = "font-size = " .. f.size end
  if f.ligatures == false then
    for _, feat in ipairs({ "-calt", "-liga", "-dlig" }) do lines[#lines + 1] = "font-feature = " .. feat end
  end
  for _, feat in ipairs(f.features or {}) do lines[#lines + 1] = "font-feature = " .. feat end
  if f.line_height then lines[#lines + 1] = "adjust-cell-height = " .. f.line_height end
  if f.thicken ~= nil then lines[#lines + 1] = "font-thicken = " .. tostring(f.thicken) end
  local text = table.concat(lines, "\n") .. "\n"
  if text == last then return end
  last = text
  if vim.fn.isdirectory(DIR) == 0 then return end -- не Ghostty — нечего делать
  local old = io.open(FILE)
  local prev = old and old:read("*a")
  if old then old:close() end
  if prev == text then return end
  local out = assert(io.open(FILE, "w"))
  out:write(text)
  out:close()
  if #lines > 1 and not ensure_include() then
    settings.warn("font", "не нашёл конфиг Ghostty — добавь в него строку: " .. INCLUDE)
  end
  reload_ghostty()
end

-- семейства шрифтов, которые видит Ghostty
local function families()
  local out = {}
  for _, line in ipairs(vim.fn.systemlist({ "ghostty", "+list-fonts" })) do
    if line ~= "" and not line:match("^%s") then out[#out + 1] = line end
  end
  return out
end

local function set_family(family)
  settings.set("font", vim.tbl_extend("force", o(), { family = family }))
end

function M.pick()
  local list = families()
  if #list == 0 then return vim.notify("ghostty +list-fonts ничего не вернул — это Ghostty?", vim.log.levels.WARN) end
  vim.ui.select(list, { prompt = "Шрифт (Ghostty)" }, function(choice) if choice then set_family(choice) end end)
end

function M.install(name)
  if not name or name == "" then return vim.notify("FontInstall <имя шрифта>, например: FontInstall Geist Mono", vim.log.levels.WARN) end
  local slug = name:lower():gsub("%s+", "-")
  local function found()
    local want = name:lower():gsub("%s+", "")
    for _, fam in ipairs(families()) do
      if fam:lower():gsub("%s+", ""):find(want, 1, true) then return fam end
    end
  end
  local function done(how)
    vim.schedule(function()
      local fam = found()
      if not fam then return vim.notify(("%s поставлен (%s), но Ghostty его не видит — проверь имя: :Font"):format(name, how), vim.log.levels.WARN) end
      set_family(fam)
      vim.notify(("шрифт %s поставлен (%s) и включён"):format(fam, how))
    end)
  end
  -- 1) Nerd Fonts релиз (имя без пробелов: JetBrainsMono, FiraCode, GeistMono…)
  local function nerd()
    local zip = vim.fn.tempname() .. ".zip"
    local url = ("https://github.com/ryanoasis/nerd-fonts/releases/latest/download/%s.zip"):format(name:gsub("%s+", ""))
    vim.notify("brew не нашёл — качаю " .. url)
    vim.system({ "curl", "-fsSL", "-o", zip, url }, {}, function(r)
      if r.code ~= 0 then
        return vim.schedule(function() vim.notify(("шрифт %q не нашёлся ни в brew, ни в Nerd Fonts"):format(name), vim.log.levels.ERROR) end)
      end
      vim.system({ "unzip", "-o", "-q", zip, "*.ttf", "*.otf", "-d", vim.fn.expand("~/Library/Fonts") }, {}, function()
        done("Nerd Fonts")
      end)
    end)
  end
  if vim.fn.executable("brew") == 0 then return nerd() end
  vim.notify(("ставлю font-%s через brew…"):format(slug))
  vim.system({ "brew", "install", "--cask", "font-" .. slug }, { text = true }, function(r)
    if r.code == 0 then return done("brew") end
    vim.schedule(nerd)
  end)
end

function M.setup()
  M.apply()
  vim.api.nvim_create_user_command("Font", function(a)
    if a.args ~= "" then return set_family(a.args) end
    M.pick()
  end, { nargs = "?", desc = "Шрифт Ghostty: выбрать или указать" })
  vim.api.nvim_create_user_command("FontInstall", function(a) M.install(a.args) end, { nargs = "+", desc = "Поставить шрифт (brew / Nerd Fonts)" })
end

M.reload = M.apply

return M
