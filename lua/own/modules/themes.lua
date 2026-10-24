-- Темы: свои JSON (themes/*.json — Dev Night, Dev Day, Sunset; движок — lua/own/theme), tokyonight,
-- rose-pine в цветах терминала (палитра из themes/<тема>.sh — та же,
-- что красит Ghostty, если стоят dotfiles), kanagawa, catppuccin и др., и популярные темы VS Code (One Dark Pro,
-- GitHub, Dark+, Dracula, Monokai Pro, Material, Ayu, Nordic, Everforest, Oxocarbon) — alt-s, предпросмотр на всём редакторе.
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
        hl.TreesitterContext = { bg = c.bg_highlight }
        hl.TreesitterContextBottom = { sp = c.fg_gutter, underline = true }
        hl.Goplements = { fg = c.purple, italic = true }
        hl.DotfilesRunMain = { fg = c.green }
        hl.DotfilesRunTest = { fg = c.teal }
        hl.SnacksDashboardHeader = { fg = c.magenta }
        hl.SnacksDashboardKey = { fg = c.orange, bold = true }
      end,
    },
  },
  { "rose-pine/neovim", name = "rose-pine", lazy = true, opts = function() return require("own.palette").opts() end },
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
  -- самые популярные темы VS Code — их родные версии для nvim (грузятся, только когда выбраны)
  { "olimorris/onedarkpro.nvim", lazy = true }, -- One Dark Pro: onedark, onedark_vivid, onedark_dark, onelight
  { "projekt0n/github-nvim-theme", name = "github-theme", lazy = true }, -- github_dark_default, _dimmed, github_light…
  { "Mofiqul/vscode.nvim", lazy = true }, -- vscode — Dark+ / Light+ (по фону)
  { "Mofiqul/dracula.nvim", lazy = true }, -- dracula, dracula-soft
  { "loctvl842/monokai-pro.nvim", lazy = true }, -- monokai-pro, -octagon, -spectrum, -machine, -ristretto, -classic
  { "marko-cerovac/material.nvim", lazy = true }, -- material-darker, -oceanic, -palenight, -deep-ocean, -lighter
  { "Shatur/neovim-ayu", lazy = true }, -- ayu-dark, ayu-mirage, ayu-light
  { "AlexvZyl/nordic.nvim", lazy = true }, -- nordic
  { "neanias/everforest-nvim", lazy = true }, -- everforest
  { "nyoom-engineering/oxocarbon.nvim", lazy = true }, -- oxocarbon
}

local engine = require("own.theme")
local applied, applied_extra

--- Поставить тему из настроек: имя, { "dark": …, "light": … } (по фону системы) или "auto" — запомненная в alt-s.
--- JSON-темы перекрашиваются и когда поменялись "colors"/"appearance" в settings.jsonc.
function M.apply(setting)
  local s = require("own.settings").current or {}
  local name = engine.wanted(setting)
  local extra = vim.inspect({ s.colors, s.appearance })
  if name == applied and (extra == applied_extra or not engine.exists(name)) then return end
  applied, applied_extra = name, extra
  if not name or name == "auto" then return require("own.themes").load() end
  if not pcall(vim.cmd.colorscheme, name) then
    require("own.settings").warn("theme", ("нет темы %q — список: alt-s, свои — :ThemeNew, из VS Code — :ThemeInstall"):format(name))
    require("own.themes").load()
  end
end

function M.setup()
  engine.setup()
  -- свои группы (▶, «реализует:», мультикурсоры) в любой теме; rose-pine следит за темой dotfiles
  require("own.palette").watch()
  -- { "dark": …, "light": … }: система сменила тёмную/светлую — сменилась и тема
  vim.api.nvim_create_autocmd("OptionSet", {
    group = vim.api.nvim_create_augroup("own.themes.bg", { clear = true }),
    pattern = "background",
    callback = function()
      local setting = (require("own.settings").current or {}).theme
      if type(setting) == "table" then vim.schedule(function() M.apply(setting) end) end
    end,
  })
end

return M
