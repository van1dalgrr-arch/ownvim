-- Внешний вид: стартовый экран, уведомления, статусная строка «пузырями» с режимом по-русски,
-- подсказка клавиш (which-key), линии отступов, номера и значки слева (snacks statuscolumn).
-- Snacks грузится сразу: на нём поиск, дерево, терминал и переключатели из раздела keys.
local M = {}

local ru = { NORMAL = "ОБЫЧНЫЙ", INSERT = "ВСТАВКА", VISUAL = "ВЫДЕЛЕНИЕ", ["V-LINE"] = "СТРОКИ", ["V-BLOCK"] = "БЛОК",
  REPLACE = "ЗАМЕНА", COMMAND = "КОМАНДА", TERMINAL = "ТЕРМИНАЛ", SELECT = "ВЫБОР", ["O-PENDING"] = "КУДА?" }

local header = [[
 ██████╗ ██╗    ██╗███╗   ██╗
██╔═══██╗██║    ██║████╗  ██║
██║   ██║██║ █╗ ██║██╔██╗ ██║
██║   ██║██║███╗██║██║╚██╗██║
╚██████╔╝╚███╔███╔╝██║ ╚████║
 ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═══╝
своя сборка · настройки в settings.jsonc]]

M.plugins = {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      quickfile = { enabled = true },
      notifier = { enabled = true },
      input = { enabled = true },
      indent = { enabled = true, animate = { enabled = false } },
      scope = { enabled = true },
      words = { enabled = true },
      statuscolumn = { enabled = true },
      dim = { animate = { enabled = false } },
      dashboard = {
        preset = {
          header = header,
          keys = {
            { icon = "\u{f002} ", key = "f", desc = "Найти файл", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = "\u{f1da} ", key = "r", desc = "Недавние файлы", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = "\u{f422} ", key = "g", desc = "Поиск по проекту", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = "\u{f013} ", key = "c", desc = "Мои настройки", action = ":Settings" },
            { icon = "\u{f11c} ", key = "k", desc = "Все клавиши", action = function() Snacks.picker.keymaps() end },
            { icon = "󰒲 ", key = "l", desc = "Плагины", action = ":Lazy" },
            { icon = "\u{f426} ", key = "q", desc = "Выйти", action = ":qa" },
          },
        },
        sections = {
          { section = "header" },
          { section = "keys", gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
    },
    config = function(_, opts)
      require("snacks").setup(opts)
      vim.o.statuscolumn = [[%!v:lua.require'snacks.statuscolumn'.get()]]
    end,
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      spec = {
        {
          mode = { "n", "x" },
          { "<leader><tab>", group = "вкладки" },
          { "<leader>b", group = "буферы" },
          { "<leader>c", group = "код" },
          { "<leader>d", group = "отладка" },
          { "<leader>t", group = "тесты" },
          { "<leader>f", group = "файлы" },
          { "<leader>g", group = "git" },
          { "<leader>q", group = "выход" },
          { "<leader>s", group = "поиск" },
          { "<leader>u", group = "переключатели" },
          { "<leader>w", group = "окна", proxy = "<c-w>" },
          { "<leader>x", group = "ошибки и списки" },
          { "[", group = "назад" },
          { "]", group = "вперёд" },
          { "g", group = "переход" },
          { "gs", group = "обрамление" },
          { "z", group = "складки" },
        },
      },
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    init = function()
      vim.g.lualine_laststatus = vim.o.laststatus
      -- пока lualine не загрузился — пустая строка, без мигания стандартной
      vim.o.statusline = " "
    end,
    opts = function()
      return {
        options = {
          theme = "auto",
          globalstatus = vim.o.laststatus == 3,
          disabled_filetypes = { statusline = { "snacks_dashboard" } },
          section_separators = { left = "\u{e0b4}", right = "\u{e0b6}" },
          component_separators = { left = "", right = "" },
        },
        sections = {
          lualine_a = { { "mode", fmt = function(m) return ru[m] or m end, separator = { left = "\u{e0b6}" }, right_padding = 2 } },
          lualine_b = { "branch" },
          lualine_c = {
            { "diagnostics" },
            { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
            { "filename", path = 1, symbols = { modified = " ●", readonly = " 󰌾", unnamed = "" } },
          },
          lualine_x = {
            -- какие языковые серверы подключены к файлу (как значок gopls в углу GoLand)
            {
              function()
                local names = vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = 0 }))
                return #names > 0 and ("\u{f085} " .. table.concat(names, " ")) or ""
              end,
              color = function() return { fg = Snacks.util.color("Comment") } end,
            },
            { "diff", symbols = { added = "\u{f0fe} ", modified = "\u{f14b} ", removed = "\u{f146} " } },
          },
          lualine_y = { { "progress", separator = " ", padding = { left = 1, right = 0 } }, { "location", padding = { left = 0, right = 1 } } },
          lualine_z = { { function() return "\u{f43a} " .. os.date("%H:%M") end, separator = { right = "\u{e0b4}" }, left_padding = 2 } },
        },
        extensions = { "lazy", "quickfix", "man" },
      }
    end,
  },
}

return M
