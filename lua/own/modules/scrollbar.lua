-- Полоса прокрутки с метками, как правый край в GoLand: где ошибки, git-изменения, найденное и курсор.
-- Не ловит мышь и не мешает тексту; в списках и деревьях не рисуется.
return {
  plugins = {
    {
      "lewis6991/satellite.nvim",
      event = "VeryLazy",
      opts = {
        winblend = 30,
        excluded_filetypes = { "snacks_dashboard", "snacks_picker_list", "snacks_layout_box", "own_tree", "own_problems", "own_image", "lazy", "mason", "trouble", "Outline", "dbui" },
        handlers = {
          cursor = { enable = true, symbols = { "⎺", "⎻", "⎼", "⎽" } },
          search = { enable = true },
          diagnostic = { enable = true, min_severity = vim.diagnostic.severity.WARN },
          gitsigns = { enable = true },
          marks = { enable = false },
          quickfix = { enable = false },
        },
      },
    },
  },
}
