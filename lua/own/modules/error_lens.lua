-- Ошибки как Error Lens в VS Code: аккуратная плашка справа от строки, длинное сообщение — в несколько строк;
-- во вставке текст прячется (не мельтешит), значки и подчёркивание остаются. Встроенный текст ошибок — выключается.
-- Настройки модуля: { "preset": "modern" | "classic" | "minimal" | "ghost" | "simple" | "nonerdfont" | "amongus",
--                     "all_on_cursorline": true, "break_after": 60 }
local M = {}

function M.plugins(opts)
  return {
    {
      "rachartier/tiny-inline-diagnostic.nvim",
      event = "LspAttach",
      priority = 1000,
      opts = {
        preset = opts.preset or "modern",
        options = {
          show_source = { enabled = false },
          multilines = { enabled = true, always_show = false },
          show_all_diags_on_cursorline = opts.all_on_cursorline ~= false,
          break_line = { enabled = true, after = opts.break_after or 60 },
        },
      },
      config = function(_, o)
        require("tiny-inline-diagnostic").setup(o)
        vim.diagnostic.config({ virtual_text = false })
      end,
    },
  }
end

return M
