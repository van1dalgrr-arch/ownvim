-- Цветные пары скобок, как bracketPairColorization в VS Code: каждый уровень вложенности — свой цвет темы.
-- Настройки модуля: { "colors": ["yellow", "purple", "blue"] } — свои цвета уровней (имена: red, orange, yellow,
-- green, cyan, blue, purple; по кругу). По умолчанию — как в VS Code: жёлтый, фиолетовый, синий.
local M = {}

local GROUPS = { red = "RainbowDelimiterRed", orange = "RainbowDelimiterOrange", yellow = "RainbowDelimiterYellow",
  green = "RainbowDelimiterGreen", cyan = "RainbowDelimiterCyan", blue = "RainbowDelimiterBlue", purple = "RainbowDelimiterViolet" }

function M.plugins(opts)
  local hl = {}
  for _, c in ipairs(opts.colors or { "yellow", "purple", "blue" }) do hl[#hl + 1] = GROUPS[c] or GROUPS.yellow end
  return {
    {
      "HiPhish/rainbow-delimiters.nvim",
      event = "VeryLazy", -- после первой отрисовки: файл виден раньше, украшение — через миг
      opts = { highlight = hl },
      config = function(_, o)
        require("rainbow-delimiters.setup").setup(o)
        -- файл открыли раньше, чем плагин загрузился, — раскрасить и его
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then
            pcall(require("rainbow-delimiters.lib").attach, buf)
          end
        end
      end,
    },
  }
end

return M
