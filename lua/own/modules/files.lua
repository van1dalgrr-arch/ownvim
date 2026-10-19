-- Файлы и замена: yazi (пробел f y — у файла, f Y — в корне), поиск-замена по проекту (пробел s r, grug-far),
-- структурная замена по коду (пробел s A, ast-grep), список ошибок правится как текст (quicker).
local M = {}

function M.plugins()
  return {
    {
      "mikavilpas/yazi.nvim",
      cmd = "Yazi",
      opts = { open_for_directories = false, floating_window_scaling_factor = 0.85 },
    },
    { "MagicDuck/grug-far.nvim", cmd = { "GrugFar", "GrugFarWithin" }, opts = { headerMaxWidth = 80 } },
    { "stevearc/quicker.nvim", ft = "qf", opts = {} },
  }
end

function M.replace()
  local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
  require("grug-far").open({ transient = true, prefills = { filesFilter = ext and ext ~= "" and "*." .. ext or nil } })
end

function M.structural()
  require("grug-far").open({ engine = "astgrep", prefills = { filesFilter = vim.bo.filetype == "go" and "*.go" or nil } })
end

return M
