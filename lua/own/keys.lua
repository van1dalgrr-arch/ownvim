-- Клавиши из раздела keys: "режимы клавиша": что делать.
--   "n <leader>ff": "files"                     — действие (список — lua/own/actions.lua, или пробел s k)
--   "i jk": "<esc>"                             — клавиши как есть
--   "n <leader>L": ":Lazy"                      — команда
--   "n <D-/>": { "do": "gcc", "remap": true, "desc": "Комментарий" }   (ещё "nowait", "expr", "silent")
--   "n <leader>l": false                        — убрать (и умолчание тоже)
-- Режимы — буквы подряд: n обычный, i вставка, x выделение, s выбор, o после оператора, t терминал, c команда.
-- Сохранил файл — старые клавиши сняты, новые стоят, перезапуск не нужен.
local actions = require("own.actions")
local settings = require("own.settings")

local M = {}

local applied = {} -- { {mode, lhs}, … } — что поставили в прошлый раз

-- alt-буквы в русской раскладке: langmap на сочетания с alt не действует, ставим дубли сами
local ru_of = {}
do
  local en = [[qwertyuiop[]asdfghjkl;'zxcvbnm,.]]
  local ru = { "й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ", "ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э",
    "я", "ч", "с", "м", "и", "т", "ь", "б", "ю" }
  for i = 1, #en do ru_of[en:sub(i, i)] = ru[i] end
end

local function russian(lhs)
  local letter = lhs:match("^<[MA]%-(.)>$")
  return letter and ru_of[letter] and ("<M-" .. ru_of[letter] .. ">")
end

local function resolve(key, value)
  local spec = type(value) == "table" and value or { ["do"] = value }
  local what = spec["do"]
  if type(what) ~= "string" then return nil, "нужно имя действия, клавиши или :команда" end
  local rhs, desc, extra = actions.get(what)
  local opts = { desc = spec.desc, remap = spec.remap, silent = spec.silent ~= false, expr = spec.expr, nowait = spec.nowait }
  if rhs then
    opts.desc = opts.desc or desc
    opts.expr = opts.expr or extra.expr
    opts.nowait = opts.nowait or extra.nowait
  elseif what:sub(1, 1) == ":" then
    rhs = "<cmd>" .. what:sub(2) .. "<cr>"
    opts.desc = opts.desc or what
  elseif what:match("^%l[%l_]*%.[%l_%.]+$") or what:match("^%l%l%l%l%l+$") then
    -- похоже на имя действия, но такого нет — скорее опечатка, чем клавиши
    return nil, ("нет действия %q — список: пробел s k или lua/own/actions.lua"):format(what)
  else
    rhs = what
  end
  return rhs, opts
end

-- cmd-сочетания, которых нет в keys, во вставке не печатаются текстом «<D-c>» (Ghostty передаёт их в nvim)
local function swallow_cmd(keys)
  local taken = {}
  for key in pairs(keys or {}) do
    local modes, lhs = key:match("^(%a+)%s+(.+)$")
    if modes and modes:find("i") then taken[lhs] = true end
  end
  for c in ("abcdefghijklmnopqrstuvwxyz0123456789"):gmatch(".") do
    for _, lhs in ipairs({ "<D-" .. c .. ">", "<D-S-" .. c .. ">" }) do
      if not taken[lhs] and vim.fn.maparg(lhs, "i") == "" then
        vim.keymap.set("i", lhs, "<Nop>", { desc = "cmd-клавиша без действия" })
      end
    end
  end
end

--- Поставить клавиши; with_ru — дубли alt-букв для русской раскладки
function M.apply(keys, with_ru)
  swallow_cmd(keys)
  for _, k in ipairs(applied) do pcall(vim.keymap.del, k[1], k[2]) end
  applied = {}
  for key, value in pairs(keys or {}) do
    local modes, lhs = key:match("^(%a+)%s+(.+)$")
    if not modes then
      settings.warn(key, "ждал «режимы клавиша», например \"n <leader>ff\"")
    elseif value ~= false then
      local rhs, opts = resolve(key, value)
      if not rhs then
        settings.warn(key, opts)
      else
        local list = vim.split(modes, "")
        local ok, err = pcall(vim.keymap.set, list, lhs, rhs, opts)
        if not ok then
          settings.warn(key, tostring(err))
        else
          for _, m in ipairs(list) do applied[#applied + 1] = { m, lhs } end
          local ru = with_ru and russian(lhs)
          if ru then
            vim.keymap.set(list, ru, rhs, opts)
            for _, m in ipairs(list) do applied[#applied + 1] = { m, ru } end
          end
        end
      end
    end
  end
end

return M
