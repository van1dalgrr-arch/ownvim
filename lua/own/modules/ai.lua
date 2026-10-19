-- Claude Code в nvim: alt-c — показать/спрятать (из любого места, и из своего терминала), пробел a x —
-- «почини ошибку под курсором», пробел a R — ревью ветки (замечания — на строках, как ошибки), пробел a X — убрать.
-- Раздел "ai": { "side": "right", "width": 0.4 }
local settings = require("own.settings")

local M = {}

local function a() return (settings.current or {}).ai or {} end

function M.plugins()
  return {
    {
      "coder/claudecode.nvim",
      cmd = { "ClaudeCode", "ClaudeCodeFocus", "ClaudeCodeSend", "ClaudeCodeAdd", "ClaudeCodeDiffAccept", "ClaudeCodeDiffDeny" },
      opts = {
        terminal = { split_side = a().side or "right", split_width_percentage = a().width or 0.4, provider = "snacks" },
        diff_opts = { open_in_new_tab = false, keep_terminal_focus = false },
      },
    },
  }
end

function M.toggle() require("claudecode.terminal").simple_toggle() end

function M.fix()
  local lnum = vim.fn.line(".")
  local diags = vim.diagnostic.get(0, { lnum = lnum - 1 })
  if #diags == 0 then return vim.notify("на этой строке нет ошибок — курсор на строку с ошибкой", vim.log.levels.WARN) end
  local msgs = vim.tbl_map(function(d) return (d.message:gsub("\n", " ")) end, diags)
  local text = ("Почини проблему в %s:%d — %s. Объясни коротко, в чём была ошибка."):format(vim.fn.expand("%:."), lnum, table.concat(msgs, "; "))
  local term = require("claudecode.terminal")
  if term.get_active_terminal_bufnr() then
    term.ensure_visible()
    return term.send_to_terminal(text, { submit = true })
  end
  term.open()
  vim.defer_fn(function() term.send_to_terminal(text, { submit = true }) end, 3000)
end

return M
