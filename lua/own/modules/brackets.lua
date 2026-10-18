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
      event = { "BufReadPost", "BufNewFile" },
      main = "rainbow-delimiters.setup",
      opts = { highlight = hl },
    },
  }
end

return M
