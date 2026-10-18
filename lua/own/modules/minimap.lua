-- Миникарта справа, как в VS Code: весь файл в миниатюре, видимая часть подсвечена, ошибки и git — метками.
-- Выключена по умолчанию (полоса прокрутки с метками — модуль scrollbar — легче). пробел u m — показать/скрыть.
-- Настройки модуля: { "width": 18, "auto": true } — ширина и открывать ли сама в обычных файлах.
local M = {}

function M.plugins(opts)
  return {
    {
      "Isrothy/neominimap.nvim",
      version = "v3.x.x",
      lazy = false, -- плагин сам решает, когда рисовать
      init = function()
        vim.g.neominimap = {
          auto_enable = opts.auto ~= false,
          layout = "split",
          split = { minimap_width = opts.width or 18 },
          exclude_filetypes = { "snacks_dashboard", "help", "lazy", "mason" },
          diagnostic = { enabled = true, mode = "line" },
          git = { enabled = true, mode = "sign" },
          search = { enabled = true },
        }
      end,
    },
  }
end

return M
