-- Панель-картинка сбоку (вместо миникарты): любая своя картинка, у каждой темы может быть своя.
-- Рисуется настоящей картинкой через протокол kitty (Ghostty, kitty, WezTerm). PNG — сразу; jpg, webp, gif —
-- нужен ImageMagick (brew install imagemagick). пробел u p — показать/спрятать.
-- Настройки модуля: { "image": "~/Pictures/girl.png" | "https://…/a.png", "side": "right", "width": 32,
--                     "themes": { "sunset": "~/Pictures/sunset.png" }, "auto": true }
-- Картинка темы: поле "image" в themes/<тема>.json или "themes" здесь (важнее). Сменил тему — сменилась картинка.
-- По ссылке картинка скачивается один раз в кэш.
local settings = require("own.settings")

local M = {}

local state = { win = nil, path = nil }

local function o() return require("own.settings").module_opts(settings.current or {}, "image_panel") end

local function cache_file(url)
  local name = url:gsub("[^%w%.]", "_"):sub(-80)
  return vim.fn.stdpath("cache") .. "/own-images/" .. name
end

-- какая картинка сейчас: тема → настройки модуля
local function wanted()
  local opts = o()
  local theme = vim.g.colors_name
  local src = theme and (opts.themes or {})[theme]
  if not src and theme then
    local ok, t = pcall(function() return require("own.theme").load(theme) end)
    if ok and type(t) == "table" then src = t.image end
  end
  return src or opts.image
end

local function resolve(src, done)
  if not src or src == "" then return done(nil) end
  if src:match("^https?://") then
    local file = cache_file(src)
    if vim.uv.fs_stat(file) then return done(file) end
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    return vim.system({ "curl", "-fsSL", "-o", file, src }, {}, vim.schedule_wrap(function(r)
      if r.code ~= 0 then vim.notify("картинка не скачалась: " .. src, vim.log.levels.WARN) return done(nil) end
      done(file)
    end))
  end
  local file = vim.fn.expand(src)
  if not file:match("^/") then file = vim.fn.stdpath("config") .. "/" .. file end
  if not vim.uv.fs_stat(file) then
    vim.notify("нет картинки " .. src, vim.log.levels.WARN)
    return done(nil)
  end
  done(file)
end

function M.is_open() return state.win and vim.api.nvim_win_is_valid(state.win) end

function M.close()
  if M.is_open() then pcall(vim.api.nvim_win_close, state.win, true) end
  state.win = nil
end

function M.open()
  local opts = o()
  resolve(wanted(), function(file)
    if not file then return M.close() end
    if M.is_open() and state.path == file then return end
    local back = vim.api.nvim_get_current_win()
    if not M.is_open() then
      vim.cmd((opts.side == "left" and "topleft" or "botright") .. " vertical " .. (opts.width or 32) .. "new")
      state.win = vim.api.nvim_get_current_win()
    else
      vim.api.nvim_set_current_win(state.win)
    end
    -- открыть сам файл картинки: snacks.image рисует его на всё окно
    vim.cmd("silent edit " .. vim.fn.fnameescape(file))
    state.path = file
    local wo = vim.wo[state.win]
    wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
    wo.cursorline, wo.winfixwidth, wo.winbar, wo.foldcolumn = false, true, "", "0"
    vim.bo.buflisted = false
    if vim.api.nvim_win_is_valid(back) then vim.api.nvim_set_current_win(back) end
  end)
end

function M.toggle() if M.is_open() then M.close() else M.open() end end

function M.plugins()
  return {
    { "folke/snacks.nvim", opts = { image = { enabled = true, doc = { enabled = false } } } },
  }
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.image_panel", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function() if M.is_open() then vim.schedule(M.open) end end,
  })
  if o().auto ~= false then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      once = true,
      callback = function() vim.defer_fn(function() if wanted() then M.open() end end, 100) end,
    })
  end
  -- осталась одна картинка — выйти, а не смотреть на неё
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local wins = vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == "" end, vim.api.nvim_tabpage_list_wins(0))
      if #wins == 2 and M.is_open() and vim.api.nvim_get_current_win() ~= state.win then M.close() end
    end,
  })
end

M.reload = function() if M.is_open() then M.open() end end

return M
