-- Темы: tokyonight (как была), rose-pine в цветах терминала (палитра из themes/<тема>.sh — та же,
-- что красит Ghostty), и ещё семь на выбор — alt-s, предпросмотр на всём редакторе.
-- Какая стоит — раздел theme: "auto" — та, что выбрана в alt-s (по умолчанию tokyonight),
-- или имя темы, например "rose-pine" / "kanagawa-dragon" / "catppuccin-mocha".
local M = {}

M.plugins = {
  {
    "folke/tokyonight.nvim",
    lazy = true,
    opts = {
      style = "night",
      transparent = true,
      styles = { sidebars = "transparent", floats = "transparent", keywords = { italic = true } },
      on_highlights = function(hl, c)
        hl.FloatBorder = { fg = c.blue7 }
        hl.FloatTitle = { fg = c.magenta, bold = true }
        hl.WinSeparator = { fg = c.bg_highlight }
        hl.CursorLineNr = { fg = c.orange, bold = true }
        hl.LspInlayHint = { fg = c.dark3, italic = true }
        hl.LspCodeLens = { fg = c.dark3, italic = true }
        hl.Goplements = { fg = c.purple, italic = true }
        hl.DotfilesRunMain = { fg = c.green }
        hl.DotfilesRunTest = { fg = c.teal }
        hl.SnacksDashboardHeader = { fg = c.magenta }
        hl.SnacksDashboardKey = { fg = c.orange, bold = true }
      end,
    },
  },
  { "rose-pine/neovim", name = "rose-pine", lazy = true, opts = function() return require("dotfiles.theme").opts() end },
  { "rebelot/kanagawa.nvim", lazy = true, opts = { transparent = true, theme = "wave" } },
  { "EdenEast/nightfox.nvim", lazy = true, opts = { options = { transparent = true } } },
  { "scottmckendry/cyberdream.nvim", lazy = true, opts = { transparent = true, italic_comments = true } },
  { "datsfilipe/vesper.nvim", lazy = true, opts = { transparent = true } },
  { "catppuccin/nvim", name = "catppuccin", lazy = true, opts = { transparent_background = true } },
  {
    "sainnhe/gruvbox-material",
    lazy = true,
    init = function()
      vim.g.gruvbox_material_background = "hard"
      vim.g.gruvbox_material_transparent_background = 1
    end,
  },
}

local applied

--- Поставить тему из настроек; "auto" — запомненная в alt-s
function M.apply(name)
  if name == applied then return end
  applied = name
  if not name or name == "auto" then return require("dotfiles.themes").load() end
  if not pcall(vim.cmd.colorscheme, name) then
    require("own.settings").warn("theme", ("нет темы %q — список: alt-s"):format(name))
    require("dotfiles.themes").load()
  end
end

function M.setup()
  -- свои группы (▶, «реализует:», мультикурсоры) в любой теме; rose-pine следит за темой dotfiles
  require("dotfiles.theme").watch()
end

return M
