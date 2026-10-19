-- Ходить без мыши: enter — метки на всех строках экрана, буква — ты там (в русской раскладке тоже).
local M = {}

function M.plugins()
  return {
    {
      "folke/flash.nvim",
      optional = true,
      config = function(_, opts)
        require("flash").setup(opts)
        -- метки по-русски: «о» = j и т.д. — через langmap
        local ru = {}
        for from, to in vim.o.langmap:gmatch("([^,;]+);([^,]+)") do
          local f, t = vim.fn.split(from, [[\zs]]), vim.fn.split(to, [[\zs]])
          for i, ch in ipairs(f) do ru[ch] = t[i] end
        end
        local util = require("flash.util")
        local get_char = util.get_char
        util.get_char = function()
          local ch = get_char()
          return ch and ru[ch] or ch
        end
      end,
    },
  }
end

function M.jump_line()
  if vim.bo.buftype ~= "" then return vim.cmd("normal! \r") end
  require("flash").jump({
    search = { mode = "search", max_length = 0, multi_window = false },
    label = { after = { 0, 0 }, uppercase = true },
    pattern = [[^\s*\zs\S]],
  })
end

return M
