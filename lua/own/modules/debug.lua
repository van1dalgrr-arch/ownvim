-- Отладчик (nvim-dap + delve для Go): точки останова переживают перезапуск, панели переменных/стека
-- открываются сами, значения переменных — серым прямо в коде. Клавиши как в GoLand: F8 шаг, F7 внутрь,
-- shift-F8 наружу, F9 дальше, ctrl-F8 точка останова; пробел d … — всё остальное.
-- Раздел "debug" в settings.jsonc:
--   "ui": true — панели сами при старте/конце; "virtual_text": true — значения в коде
--   "signs": { "breakpoint": "●", … } — значки
--   "go": { "delve": "dlv", "configurations": [ … ] } — свои конфигурации запуска (как в nvim-dap-go),
--     по умолчанию — подключение к dlv в Docker на :2345
-- Всё — после :restart, кроме значков.
local settings = require("own.settings")
local tools = require("own.tools")

local M = {}

local function d() return (settings.current or {}).debug or {} end

local SIGNS = {
  breakpoint = { "DapBreakpoint", "DiagnosticError" },
  condition = { "DapBreakpointCondition", "DiagnosticWarn" },
  rejected = { "DapBreakpointRejected", "DiagnosticError" },
  log = { "DapLogPoint", "DiagnosticInfo" },
  stopped = { "DapStopped", "DiagnosticWarn", "DapStoppedLine" },
}

local function signs()
  vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })
  for key, s in pairs(SIGNS) do
    local text = (d().signs or {})[key]
    if text then vim.fn.sign_define(s[1], { text = text, texthl = s[2], linehl = s[3], numhl = s[3] }) end
  end
end

function M.plugins()
  local o = d()
  return {
    {
      "mfussenegger/nvim-dap",
      dependencies = {
        { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
        "theHamsta/nvim-dap-virtual-text",
        "leoluz/nvim-dap-go",
      },
      lazy = true,
      config = function()
        local dap = require("dap")
        signs()
        if o.ui ~= false then
          local dapui = require("dapui")
          dapui.setup(o.dapui or {})
          dap.listeners.after.event_initialized.own = function() dapui.open({}) end
          dap.listeners.before.event_terminated.own = function() dapui.close({}) end
          dap.listeners.before.event_exited.own = function() dapui.close({}) end
        end
        if o.virtual_text ~= false then require("nvim-dap-virtual-text").setup({}) end
        local go = o.go or {}
        if go ~= false then
          require("dap-go").setup({
            delve = { path = go.delve or "dlv" },
            dap_configurations = go.configurations,
          })
        end
      end,
    },
    -- точки останова грузятся с файлом, даже если отладчик ещё не запускали
    { "Weissle/persistent-breakpoints.nvim", event = "BufReadPost", opts = { load_breakpoints_event = { "BufReadPost" } } },
  }
end

function M.setup()
  if (d().go or {}) ~= false then tools.ensure_bin((d().go or {}).delve or "dlv", "debug") end
end

function M.reload()
  if package.loaded["dap"] then signs() end
end

return M
