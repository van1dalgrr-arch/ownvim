-- Справочник клавиш из defaults.jsonc и описаний действий — docs/keys.ru.md всегда совпадает с настройками.
-- Запуск: NVIM_APPNAME=ownvim nvim --headless -l scripts/keys.lua > docs/keys.ru.md
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. package.path

local jsonc = require("own.jsonc")
local actions = require("own.actions")

local f = assert(io.open(root .. "/defaults.jsonc"))
local text = f:read("*a")
f:close()

-- порядок и разделы — как в файле: идём по строкам раздела keys
local out = {
  "# Клавиши ownvim",
  "",
  "Все клавиши по умолчанию — из `defaults.jsonc` (раздел `keys`). Поменять, убрать, добавить — в `settings.jsonc`:",
  "`\"n <leader>ff\": \"files.git\"`, `\"i jk\": false`. Внутри ownvim — `пробел s k` (поиск по всем клавишам).",
  "Клавиши плагинов (обрамление `gsa`, прыжок `s`, текстовые объекты `af`/`ic`) — в их модулях.",
  "",
  "`пробел` — leader. Режимы: n — обычный, i — вставка, x — выделение, t — терминал.",
  "",
  "Файл создан `scripts/keys.lua` — не правь руками.",
}

local MODES = { n = "обычный", i = "вставка", x = "выделение", s = "выбор", o = "оператор", t = "терминал", c = "команда" }

local function pretty(lhs)
  return (lhs:gsub("<leader>", "пробел "):gsub("<M%-(.)>", "alt-%1"):gsub("<D%-S%-(.)>", "cmd-shift-%1"):gsub("<D%-(.)>", "cmd-%1")
    :gsub("<C%-(.-)>", "ctrl-%1"):gsub("<S%-(.-)>", "shift-%1"):gsub("<space>", "пробел"):gsub("<cr>", "enter"):gsub("<CR>", "enter")
    :gsub("<tab>", "tab"):gsub("<esc>", "esc"):gsub("<Up>", "↑"):gsub("<Down>", "↓"):gsub("<Left>", "←"):gsub("<Right>", "→"))
end

local in_keys, section = false, nil
for line in text:gmatch("([^\n]*)\n") do
  if line:match('^  "keys": {') then
    in_keys = true
  elseif in_keys and line:match("^  },") then
    break
  elseif in_keys then
    local title = line:match("^%s*//%s*(.+)$")
    if title and line:match("^    //") then
      section = title
      out[#out + 1] = ""
      out[#out + 1] = "## " .. title:sub(1, 1):upper() .. title:sub(2)
      out[#out + 1] = ""
      out[#out + 1] = "| клавиша | режим | что делает |"
      out[#out + 1] = "|---|---|---|"
    else
      local key, value = line:match('^%s*"([^"]+)"%s*:%s*(.-),?%s*//?.*$')
      if not key then key, value = line:match('^%s*"([^"]+)"%s*:%s*(.-),?%s*$') end
      if key and value then
        local modes, lhs = key:match("^(%a+)%s+(.+)$")
        local v = jsonc.decode('{"v": ' .. value:gsub(",%s*$", "") .. "}")
        v = v and v.v
        local desc
        if type(v) == "table" then
          desc = v.desc or v["do"]
        elseif type(v) == "string" then
          local _, d = actions.get(v)
          desc = d or v
        end
        if modes and desc then
          local m = {}
          for ch in modes:gmatch(".") do m[#m + 1] = MODES[ch] or ch end
          out[#out + 1] = ("| `%s` | %s | %s |"):format(pretty(lhs):gsub("|", "\\|"), table.concat(m, ", "), desc:gsub("|", "\\|"))
        end
      end
    end
  end
end

io.stdout:write(table.concat(out, "\n") .. "\n")
