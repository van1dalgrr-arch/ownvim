-- Полоса прокрутки с метками, как правый край в GoLand: где ошибки, git-изменения, найденное и курсор.
-- Не ловит мышь и не мешает тексту; в списках и деревьях не рисуется.
return {
  plugins = {
    {
      "lewis6991/satellite.nvim",
      event = "VeryLazy",
      opts = {
        winblend = 30,
        excluded_filetypes = { "snacks_dashboard", "snacks_picker_list", "snacks_layout_box", "own_tree", "own_search", "own_git", "own_extensions", "own_problems", "own_image", "lazy", "mason", "trouble", "Outline", "dbui" },
        handlers = {
          cursor = { enable = true, symbols = { "⎺", "⎻", "⎼", "⎽" } },
          search = { enable = true },
          diagnostic = { enable = true, min_severity = vim.diagnostic.severity.WARN },
          gitsigns = { enable = true },
          marks = { enable = false },
          quickfix = { enable = false },
        },
      },
      config = function(_, opts)
        require("satellite").setup(opts)
        -- при наборе полоса перерисовывалась целиком на каждую букву (метка курсора — на CursorMovedI), хотя сама
        -- не менялась. Во вставке обновляем её, только когда окно прокрутилось или строк стало больше / меньше
        local view = require("satellite.view")
        local refresh, seen = view.refresh_bars, nil
        view.refresh_bars = function(...)
          if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
            local win = vim.api.nvim_get_current_win()
            local key = win .. ":" .. vim.fn.line("w0") .. ":" .. vim.api.nvim_buf_line_count(0) .. ":" .. #vim.api.nvim_list_wins()
            if key == seen then return end
            seen = key
          else
            seen = nil
          end
          return refresh(...)
        end
        vim.api.nvim_create_autocmd("InsertLeave", {
          group = vim.api.nvim_create_augroup("own.scrollbar", { clear = true }),
          callback = function() seen = nil; view.schedule_refresh() end,
        })
      end,
    },
  },
}
