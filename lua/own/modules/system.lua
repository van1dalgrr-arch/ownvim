-- Система: контейнеры (alt-o — orbstack/lazydocker в окне, ещё раз — спрятать), GitHub (alt-w — gw),
-- скриншот кода (пробел P — функция под курсором или выделенное → PNG в буфер обмена, freeze), dot (если стоят dotfiles).
-- Настройки модуля: { "containers": "orbstack" | "lazydocker", "github": "gw" | "gh dash" }
local M = {}

local opts = {}

local function float(name, cmd)
  Snacks.terminal.toggle(cmd, {
    cwd = require("own.root").get(),
    win = { position = "float", width = 0.9, height = 0.9, border = "rounded", title = " " .. name .. " " },
  })
end

function M.containers()
  local c = opts.containers or (vim.fn.executable("orbstack") == 1 and "orbstack" or "lazydocker")
  if c == "orbstack" then return require("own.tools.system").containers() end
  float(c, c)
end

function M.github()
  local g = opts.github or "gw"
  if g == "gw" then return require("own.tools.system").gw() end
  float("github", g)
end

function M.setup(o) opts = o or {} end
M.reload = M.setup

return M
