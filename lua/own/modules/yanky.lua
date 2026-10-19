-- История копирования: пробел p — всё, что копировал, вставить любое; после p — [y / ]y листают.
local M = {}

function M.plugins()
  return {
    {
      "gbprod/yanky.nvim",
      event = "VeryLazy",
      opts = { highlight = { timer = 150 } },
      keys = {
        { "<leader>p", function() Snacks.picker.yanky() end, mode = { "n", "x" }, desc = "История копирования" },
        { "y", "<Plug>(YankyYank)", mode = { "n", "x" }, desc = "Копировать" },
        { "p", "<Plug>(YankyPutAfter)", mode = { "n", "x" }, desc = "Вставить после" },
        { "P", "<Plug>(YankyPutBefore)", mode = { "n", "x" }, desc = "Вставить перед" },
        { "[y", "<Plug>(YankyCycleForward)", desc = "Вставка: предыдущее из истории" },
        { "]y", "<Plug>(YankyCycleBackward)", desc = "Вставка: следующее из истории" },
      },
    },
  }
end

return M
