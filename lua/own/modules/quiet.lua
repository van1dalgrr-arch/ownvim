-- Тихий режим (пробел uq, :Quiet): убрать всё, что отвлекает, когда нужно просто подумать и писать, —
-- подсказки типов, плашки ошибок, надписи над кодом, blame, «реализует», анимации, линии отступов, липкую шапку,
-- хлебные крошки, полосу прокрутки. Ещё раз — всё как было. Ошибки не пропадают: значки слева и подчёркивания остаются.
-- Настройки модуля: { "hide": ["inlay_hints", "error_lens", "codelens", "blame", "implements", "animations",
--                              "indent", "sticky_scroll", "breadcrumbs", "scrollbar"] } — что прятать
local settings = require("own.settings")

local M = {}

local saved -- что было включено до тихого режима (nil — режим выключен)

local function s() return settings.current or {} end
local function loaded(mod) return package.loaded[mod] end

-- что прятать: off() → «было ли включено», on() — вернуть (только то, что было включено)
local ITEMS = {
  inlay_hints = { -- включаются в каждом файле отдельно (lsp.on_attach) — и выключаются так же
    off = function()
      local bufs = {}
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.lsp.inlay_hint.is_enabled({ bufnr = buf }) then
          vim.lsp.inlay_hint.enable(false, { bufnr = buf })
          bufs[#bufs + 1] = buf
        end
      end
      return #bufs > 0 and bufs
    end,
    on = function(bufs)
      for _, buf in ipairs(bufs) do
        if vim.api.nvim_buf_is_valid(buf) then vim.lsp.inlay_hint.enable(true, { bufnr = buf }) end
      end
    end,
  },
  error_lens = {
    off = function()
      local t = loaded("tiny-inline-diagnostic")
      if t then t.disable(); return true end
    end,
    on = function() require("tiny-inline-diagnostic").enable() end,
  },
  codelens = {
    off = function()
      if not (s().lsp or {}).codelens then return false end
      pcall(vim.lsp.codelens.enable, false)
      return true
    end,
    on = function() pcall(vim.lsp.codelens.enable, true) end,
  },
  blame = {
    off = function()
      local ok, cfg = pcall(function() return require("gitsigns.config").config end)
      if ok and loaded("gitsigns") and cfg.current_line_blame then
        require("gitsigns").toggle_current_line_blame(false)
        return true
      end
    end,
    on = function() require("gitsigns").toggle_current_line_blame(true) end,
  },
  implements = {
    off = function()
      local g = loaded("goplements")
      if g and ((s().go or {}).implements ~= false) then g.disable(); return true end
    end,
    on = function() require("goplements").enable() end,
  },
  animations = {
    off = function()
      local was = {}
      local smear = loaded("smear_cursor")
      if smear and smear.enabled then smear.enabled = false; was.smear = true end
      if rawget(_G, "Snacks") and Snacks.scroll.enabled then Snacks.scroll.disable(); was.scroll = true end
      return next(was) and was
    end,
    on = function(was)
      if was.smear then require("smear_cursor").enabled = true end
      if was.scroll then Snacks.scroll.enable() end
    end,
  },
  indent = {
    off = function()
      if rawget(_G, "Snacks") and Snacks.indent.enabled then Snacks.indent.disable(); return true end
    end,
    on = function() Snacks.indent.enable() end,
  },
  sticky_scroll = {
    off = function()
      local c = loaded("treesitter-context")
      if c and c.enabled() then c.disable(); return true end
    end,
    on = function() require("treesitter-context").enable() end,
  },
  breadcrumbs = {
    off = function()
      local b = loaded("own.modules.breadcrumbs")
      if not b then return false end
      vim.g.own_quiet_crumbs = true
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.wo[win].winbar:find("breadcrumbs", 1, true) then vim.wo[win].winbar = "" end
      end
      return true
    end,
    on = function()
      vim.g.own_quiet_crumbs = nil
      require("own.modules.breadcrumbs").refresh()
    end,
  },
  scrollbar = {
    off = function()
      local ok, view = pcall(require, "satellite.view")
      if ok and loaded("satellite") and view.enabled() then view.disable(); return true end
    end,
    on = function() require("satellite.view").enable() end,
  },
}

local DEFAULT = { "inlay_hints", "error_lens", "codelens", "blame", "implements", "animations", "indent",
  "sticky_scroll", "breadcrumbs", "scrollbar" }

local opts = {}

function M.active() return saved ~= nil end

function M.toggle()
  if saved then
    for name, was in pairs(saved) do
      if was then pcall(ITEMS[name].on, was) end
    end
    saved = nil
    vim.g.own_quiet = nil
    vim.notify("тихий режим выключен — всё как было")
  else
    saved = {}
    for _, name in ipairs(opts.hide or DEFAULT) do
      local item = ITEMS[name]
      if item then
        local ok, was = pcall(item.off)
        saved[name] = ok and was or false
      else
        settings.warn("quiet", ("тихий режим: не знаю, что такое %q — есть: %s"):format(name, table.concat(DEFAULT, ", ")))
      end
    end
    vim.g.own_quiet = true
    vim.notify("тихий режим: только код и ошибки на полях — пробел uq вернуть")
  end
  vim.cmd("redraw!")
end

function M.setup(o)
  opts = o or {}
  vim.api.nvim_create_user_command("Quiet", M.toggle, { desc = "Тихий режим: убрать всё, что отвлекает" })
end

function M.reload(o) opts = o or {} end

return M
