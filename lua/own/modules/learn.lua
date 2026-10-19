-- Учиться на ходу: метки движений в строке (precognition, пробел u P), тренер привычек в режиме подсказок
-- (hardtime: ничего не запрещает, подсказывает; пробел u H — вкл/выкл, пробел u R — отчёт).
-- Настройки модуля: { "hints_visible": false, "hardtime": true }
local M = {}

function M.plugins(opts)
  return {
    {
      "tris203/precognition.nvim",
      event = "VeryLazy",
      opts = {
        startVisible = opts.hints_visible == true,
        showBlankVirtLine = false,
        highlightColor = { link = "Comment" },
        targetedMotionHints = { enabled = false },
        hints = {
          Caret = { text = "^", prio = 2 }, Dollar = { text = "$", prio = 1 }, MatchingPair = { text = "%", prio = 5 },
          w = { text = "w", prio = 10 }, b = { text = "b", prio = 9 }, e = { text = "e", prio = 8 },
          Zero = { text = "0", prio = 0 }, W = { text = "W", prio = 0 }, B = { text = "B", prio = 0 }, E = { text = "E", prio = 0 },
        },
      },
    },
    {
      "m4xshen/hardtime.nvim",
      enabled = opts.hardtime ~= false,
      event = "VeryLazy",
      dependencies = { "MunifTanjim/nui.nvim" },
      opts = {
        restriction_mode = "hint",
        disabled_keys = { ["<Up>"] = false, ["<Down>"] = false, ["<Left>"] = false, ["<Right>"] = false },
        disable_mouse = false,
      },
    },
  }
end

return M
