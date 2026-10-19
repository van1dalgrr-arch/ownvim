-- Git как в GoLand/VS Code: изменения на полях, кто менял строку, куски изменений (посмотреть, вернуть,
-- в коммит), трёхпанельный merge, история файла, ветка против main, lazygit. Раздел "git":
--   "signs": { "add": "▎", "change": "▎", "delete": "", … } — значки на полях
--   "blame": false — кто и когда менял строку, серым справа (пробел u B — на время)
--   "blame_format": "<author>, <author_time:%d.%m.%Y> · <summary>"
--   "base_branch": "auto" — с чем сравнивать ветку (пробел g m): auto — ветка origin/HEAD, или "main"/"develop"
-- Сохранил — применилось (кроме значков — после :restart).
local settings = require("own.settings")

local M = {}

local function g() return (settings.current or {}).git or {} end

--- ветка, с которой сравнивать текущую (для «ветка против main», как PR)
function M.base_branch()
  local b = g().base_branch
  if b and b ~= "auto" then return b end
  local ref = vim.fn.systemlist({ "git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })[1]
  return vim.v.shell_error == 0 and ref or "main"
end

function M.plugins()
  local o = g()
  local s = o.signs or {}
  local close = { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Закрыть diffview" } }
  return {
    {
      "lewis6991/gitsigns.nvim",
      event = { "BufReadPost", "BufNewFile" },
      opts = {
        signs = {
          add = { text = s.add or "▎" },
          change = { text = s.change or "▎" },
          delete = { text = s.delete or "" },
          topdelete = { text = s.topdelete or "" },
          changedelete = { text = s.changedelete or "▎" },
          untracked = { text = s.untracked or "▎" },
        },
        current_line_blame = o.blame == true,
        current_line_blame_opts = { delay = 300, virt_text_pos = "eol" },
        current_line_blame_formatter = "   " .. (o.blame_format or "<author>, <author_time:%d.%m.%Y> · <summary>"),
      },
    },
    {
      "sindrets/diffview.nvim",
      cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
      opts = {
        enhanced_diff_hl = true,
        -- конфликт: слева «наше», справа «их», снизу результат — как Merge в GoLand
        view = { merge_tool = { layout = "diff3_mixed", disable_diagnostics = true } },
        keymaps = { view = { close }, file_panel = { close }, file_history_panel = { close } },
      },
    },
  }
end

function M.reload()
  local gs = package.loaded["gitsigns"]
  if not gs then return end
  local o = g()
  gs.toggle_current_line_blame(o.blame == true)
  require("gitsigns.config").config.current_line_blame_formatter = "   " .. (o.blame_format or "<author>, <author_time:%d.%m.%Y> · <summary>")
end

return M
