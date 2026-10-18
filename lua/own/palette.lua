-- rose-pine в цветах терминала: `:colorscheme rose-pine`. Если стоят dotfiles (github.com/van1dalgrr-arch/dotfiles,
-- папка — $DOTFILES или ~/dotfiles), палитра берётся из их themes/<тема>.sh — той же, что красит Ghostty, starship,
-- lazygit, bat (themes/apply.sh). Роли там названы по Rosé Pine, поэтому они один в один ложатся
-- на палитру плагина rose-pine: тема меняется — меняются только цвета, вся подсветка остаётся.
-- Светлый режим macOS — themes/light/day.sh (Dev Day): nvim 0.12 сам узнаёт фон терминала.
-- Пока выбран rose-pine, смена темы командой theme перекрашивает открытые nvim сами, без перезапуска.
-- Без dotfiles — обычная палитра rose-pine. Свои группы (▶, «реализует:», мультикурсоры) — в M.defaults: они есть в любой теме.
local M = {}

local dotfiles = vim.env.DOTFILES or vim.fn.expand("~/dotfiles")
local state = vim.fn.expand("~/.config/dotfiles/theme")

-- роль dotfiles → имя цвета в палитре rose-pine
local roles = {
  BASE = "base", SURFACE = "surface", OVERLAY = "overlay",
  MUTED = "muted", SUBTLE = "subtle", TEXT = "text",
  LOVE = "love", GOLD = "gold", ROSE = "rose", PINE = "pine", FOAM = "foam", IRIS = "iris",
  HL_LOW = "highlight_low", HL_MED = "highlight_med", HL_HIGH = "highlight_high",
}

local function read(file)
  local f = io.open(file)
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  local p = {}
  for role, hex in text:gmatch("T_([%u_]+)=(%x%x%x%x%x%x)") do
    if roles[role] then p[roles[role]] = "#" .. hex end
  end
  return next(p) and p or nil
end

function M.name()
  local f = io.open(state)
  if not f then return "rose-pine" end
  local name = vim.trim(f:read("*l") or "")
  f:close()
  return name ~= "" and name or "rose-pine"
end

function M.opts()
  return {
    variant = "auto", -- тёмный фон — main (тема dotfiles), светлый — dawn (Dev Day)
    dark_variant = "main",
    styles = { bold = true, italic = true, transparency = true }, -- фон и размытие — от Ghostty
    palette = {
      main = read(dotfiles .. "/themes/" .. M.name() .. ".sh"),
      dawn = read(dotfiles .. "/themes/light/day.sh"),
    },
    highlight_groups = {
      -- рамки и разделители тише текста, чтобы окна не спорили с кодом
      FloatBorder = { fg = "highlight_high", bg = "none" },
      FloatTitle = { fg = "rose", bg = "none", bold = true },
      WinSeparator = { fg = "overlay" },
      CursorLineNr = { fg = "rose", bold = true },
      -- подсказки типов (inlay hints) — шёпотом, как в GoLand
      LspInlayHint = { fg = "muted", bg = "none", italic = true },
      LspCodeLens = { fg = "muted", italic = true },
      -- шапка функции, прилипшая сверху (treesitter-context)
      TreesitterContext = { bg = "surface" },
      TreesitterContextBottom = { sp = "highlight_med", underline = true },
      TreesitterContextLineNumber = { fg = "rose", bg = "surface" },
      -- «реализует: io.Reader» рядом с типом (goplements)
      Goplements = { fg = "iris", italic = true },
      -- ▶ у func main и тестов (lua/dotfiles/run.lua)
      DotfilesRunMain = { fg = "foam" },
      DotfilesRunTest = { fg = "pine" },
      -- стартовый экран
      SnacksDashboardHeader = { fg = "rose" },
      SnacksDashboardKey = { fg = "gold", bold = true },
      SnacksDashboardIcon = { fg = "iris" },
      SnacksDashboardDesc = { fg = "text" },
      SnacksDashboardFooter = { fg = "muted", italic = true },
      SnacksDashboardTitle = { fg = "foam", bold = true },
    },
  }
end

-- Группы, которых нет в темах: свои цвета у ▶, «реализует:», мультикурсоров — в любой теме.
-- default = true: тема, которая знает эти группы (rose-pine выше), задаёт их сама.
local defaults = {
  Goplements = { link = "Comment" },
  DotfilesRunMain = { link = "DiagnosticOk" },
  DotfilesRunTest = { link = "DiagnosticInfo" },
  MultiCursorCursor = { reverse = true },
  MultiCursorVisual = { link = "Visual" },
  MultiCursorSign = { link = "SignColumn" },
  MultiCursorMatchPreview = { link = "Search" },
  MultiCursorDisabledCursor = { reverse = true },
  MultiCursorDisabledVisual = { link = "Visual" },
  MultiCursorDisabledSign = { link = "SignColumn" },
}
function M.defaults()
  for name, hl in pairs(defaults) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", hl, { default = true }))
  end
end

-- перечитать палитру и перекрасить (после theme, после смены светлого/тёмного режима) — только если выбран rose-pine
local applied_bg
function M.apply()
  if vim.g.colors_name ~= "rose-pine" then return end
  applied_bg = vim.o.background
  require("rose-pine").setup(M.opts())
  vim.cmd.colorscheme("rose-pine")
end

local watching
function M.watch()
  if watching then return end
  watching = true
  local group = vim.api.nvim_create_augroup("own.palette", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.defaults })
  M.defaults()
  local timer = assert(vim.uv.new_timer())
  -- apply.sh пишет имя темы в ~/.config/dotfiles/theme; несколько событий подряд — одна перекраска
  local w = assert(vim.uv.new_fs_event())
  if vim.fn.isdirectory(vim.fn.fnamemodify(state, ":h")) == 1 then w:start(vim.fn.fnamemodify(state, ":h"), {}, function(err, fname)
    if err or (fname and fname ~= "theme") then return end
    timer:start(150, 0, vim.schedule_wrap(M.apply))
  end) end
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "background",
    callback = function()
      -- colorscheme сам может тронуть background — без проверки перекраска пошла бы по кругу
      if vim.o.background ~= applied_bg then vim.schedule(M.apply) end
    end,
  })
end

return M
