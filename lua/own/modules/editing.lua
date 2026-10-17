-- Правка как в LazyVim: парные скобки и кавычки, текстовые объекты (af/if — функция, ac/ic — тип,
-- ao/io — блок), обрамление (gsa — добавить, gsd — убрать, gsr — заменить), прыжок flash (s — по буквам,
-- S — по узлам кода), TODO/FIXME подсвечены и ищутся (пробел s t).
return {
  plugins = {
    {
      "nvim-mini/mini.pairs",
      event = "VeryLazy",
      opts = {
        modes = { insert = true, command = true, terminal = false },
        -- не закрывать скобку перед буквой/цифрой и внутри строки
        skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
        skip_ts = { "string" },
        skip_unbalanced = true,
        markdown = true,
      },
    },
    {
      "nvim-mini/mini.ai",
      event = "VeryLazy",
      dependencies = { { "nvim-treesitter/nvim-treesitter-textobjects", branch = "main" } },
      opts = function()
        local ai = require("mini.ai")
        return {
          n_lines = 500,
          custom_textobjects = {
            o = ai.gen_spec.treesitter({
              a = { "@block.outer", "@conditional.outer", "@loop.outer" },
              i = { "@block.inner", "@conditional.inner", "@loop.inner" },
            }),
            f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
            c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
            t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" },
            d = { "%f[%d]%d+" },
            u = ai.gen_spec.function_call(),
            U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
          },
        }
      end,
    },
    {
      "nvim-mini/mini.surround",
      keys = {
        { "gsa", desc = "Обрамить", mode = { "n", "x" } },
        { "gsd", desc = "Убрать обрамление" },
        { "gsr", desc = "Заменить обрамление" },
        { "gsf", desc = "Найти обрамление справа" },
        { "gsF", desc = "Найти обрамление слева" },
        { "gsh", desc = "Подсветить обрамление" },
      },
      opts = {
        mappings = { add = "gsa", delete = "gsd", find = "gsf", find_left = "gsF", highlight = "gsh", replace = "gsr", update_n_lines = "" },
      },
    },
    {
      "folke/flash.nvim",
      event = "VeryLazy",
      opts = {},
      keys = {
        { "s", function() require("flash").jump() end, mode = { "n", "x", "o" }, desc = "Flash: прыжок" },
        { "S", function() require("flash").treesitter() end, mode = { "n", "o", "x" }, desc = "Flash: узел кода" },
        { "r", function() require("flash").remote() end, mode = "o", desc = "Flash: действие там" },
        { "R", function() require("flash").treesitter_search() end, mode = { "o", "x" }, desc = "Flash: поиск по узлам" },
        { "<c-s>", function() require("flash").toggle() end, mode = { "c" }, desc = "Flash в поиске" },
      },
    },
    {
      "folke/todo-comments.nvim",
      event = { "BufReadPost", "BufNewFile" },
      opts = {},
      keys = {
        { "]t", function() require("todo-comments").jump_next() end, desc = "Следующий TODO" },
        { "[t", function() require("todo-comments").jump_prev() end, desc = "Предыдущий TODO" },
        { "<leader>st", function() Snacks.picker.todo_comments() end, desc = "Все TODO" },
        { "<leader>sT", function() Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME" } }) end, desc = "TODO/FIX/FIXME" },
      },
    },
  },
}
