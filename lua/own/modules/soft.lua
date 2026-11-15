-- Мягкость: чтобы глаза не уставали и писать было приятно — поверх любой темы (своей JSON и темы-плагина).
--   filter — мягкий фильтр цветов в OKLab: чуть ниже контраст и насыщенность, фон не чисто чёрный (и не чисто белый),
--     яркие ошибки и строки не режут глаз; оттенки и разница между цветами остаются.
--   night — вечером тема плавно теплеет и тускнеет (как Night Shift, но только редактор): за ramp_min минут после from,
--     утром — обратно к to. Переход идёт по минутам, незаметно.
--   fade — окна поверх кода (поиск, K, which-key, уведомления, переименование) проявляются, а не выскакивают.
--   cursorline_active — подсветка текущей строки только в окне, где пишешь (в соседних сплитах её нет).
-- Раздел "soft":
--   "filter": { "enabled": true, "contrast": 0.92, "saturation": 0.86, "floor": 0.2, "ceiling": 0.965 }
--     contrast — 1 как в теме, меньше — тише; saturation — 1 как в теме; floor — самый тёмный фон (OKLab L: 0 — #000,
--     0.2 — ≈#1b1b1b), ceiling — самый светлый фон у светлых тем (1 — #fff)
--   "night": { "enabled": true, "from": "21:00", "to": "07:00", "ramp_min": 45, "warmth": 0.5, "dim": 0.06 }
--   "fade": { "enabled": true, "ms": 140, "from": 70 }  — from: насколько прозрачно окно в первый миг (0–100)
--   "cursorline_active": true
-- Пробел u S — фильтр вкл/выкл (сравнить с темой как есть).
local settings = require("own.settings")

local M = {}

local function o() return (settings.current or {}).soft or {} end

-- ── цвет: sRGB ↔ OKLab ──────────────────────────────────────────────────────

local function lin(c) c = c / 255; return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
local function unlin(c)
  c = c <= 0.0031308 and c * 12.92 or 1.055 * c ^ (1 / 2.4) - 0.055
  return math.floor(math.max(0, math.min(1, c)) * 255 + 0.5)
end
local function cbrt(x) return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3) end

local function to_lab(n)
  local r, g, b = lin(bit.rshift(n, 16)), lin(bit.band(bit.rshift(n, 8), 255)), lin(bit.band(n, 255))
  local l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  local m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  local s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

local function from_lab(L, a, b)
  local l = (L + 0.3963377774 * a + 0.2158037573 * b) ^ 3
  local m = (L - 0.1055613458 * a - 0.0638541728 * b) ^ 3
  local s = (L - 0.0894841775 * a - 1.2914855480 * b) ^ 3
  local r = unlin(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
  local g = unlin(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
  local bl = unlin(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
  return r * 65536 + g * 256 + bl
end

M._to_lab, M._from_lab = to_lab, from_lab

-- ── фильтр ──────────────────────────────────────────────────────────────────

local state = {
  orig = {},     -- группа → как её задала тема (до фильтра)
  done = {},     -- группа → что поставил фильтр (чтобы узнать, что группу потом поменял кто-то другой)
  term = {},     -- terminal_color_N → исходный
  night = 0,     -- 0..1 — сколько вечера сейчас
  off = false,   -- пробел u S
  bgL = nil,
}

--- Преобразование одного цвета (число 0xRRGGBB) — параметры заранее посчитаны
local function make(params)
  local cache = {}
  return function(n)
    if not n then return nil end
    local hit = cache[n]
    if hit then return hit end
    local L, a, b = to_lab(n)
    L = params.base + (L - params.bgL) * params.contrast
    a, b = a * params.sat, b * params.sat
    if params.warm > 0 then
      -- теплее: к янтарному, синий уходит; тусклее — чуть ниже яркость всего
      b = b + 0.045 * params.warm
      a = a + 0.012 * params.warm
      L = L * (1 - params.dim)
    end
    local out = from_lab(math.max(0, math.min(1, L)), a, b)
    cache[n] = out
    return out
  end
end

local function params()
  local f, nt = o().filter or {}, o().night or {}
  local on = f.enabled ~= false and not state.off
  local normal = state.orig.Normal or vim.api.nvim_get_hl(0, { name = "Normal" })
  local light = vim.o.background == "light"
  local bgL = normal.bg and (to_lab(normal.bg)) or (light and 0.97 or 0.18)
  local base = bgL
  if on then base = light and math.min(bgL, f.ceiling or 0.965) or math.max(bgL, f.floor or 0.2) end
  local w = (nt.enabled ~= false and not state.off) and state.night * (nt.warmth or 0.5) or 0
  return {
    bgL = bgL, base = base,
    contrast = on and (f.contrast or 0.92) or 1,
    sat = on and (f.saturation or 0.86) or 1,
    warm = w, dim = (nt.dim or 0.06) * (w > 0 and state.night or 0),
  }
end

-- группы, которые другие модули сами выводят из уже мягких цветов и меняют на ходу (режимы, рамки, тусклые окна):
-- фильтр их не трогает, а модули пересчитывают их на событие User OwnSoftApplied
local DERIVED = { CursorLine = true, CursorLineNr = true, OwnFrame = true, OwnFrameSide = true, OwnSLFrame = true,
  OwnFrameCursor = true, OwnLineNrNear = true, OwnFoldTitle = true, SnacksIndentScope = true }
local function derived(name)
  return DERIVED[name] or name:match("^vimade") or name:match("^Mode%u%l+[CLN]") or name:match("^OwnLineNrFade")
    or name:match("^OwnJump%d")
end

local function same(x, y)
  if x == nil or y == nil then return false end
  return x.fg == y.fg and x.bg == y.bg and x.sp == y.sp and x.link == y.link
end

-- снять текущее состояние: то, что поменяли другие после прошлого применения, — новый оригинал
local function capture(fresh)
  if fresh then state.orig, state.done, state.term = {}, {}, {} end
  for name, spec in pairs(vim.api.nvim_get_hl(0, {})) do
    if derived(name) then
      state.orig[name] = nil
    elseif not same(spec, state.done[name]) then
      state.orig[name] = spec
    end
  end
  for i = 0, 15 do
    local k = "terminal_color_" .. i
    local v = vim.g[k]
    if v and v ~= state.term[k .. "_done"] then state.term[k] = v end
  end
end

local function hex(n) return ("#%06x"):format(n) end

function M.apply(fresh)
  capture(fresh)
  local p = params()
  local identity = p.contrast == 1 and p.sat == 1 and p.warm == 0 and p.base == p.bgL
  local tf = make(p)
  state.tf = not identity and tf or nil
  for name, spec in pairs(state.orig) do
    if not spec.link then
      local s = vim.deepcopy(spec)
      if not identity then s.fg, s.bg, s.sp = tf(spec.fg), tf(spec.bg), tf(spec.sp) end
      s.default = nil
      pcall(vim.api.nvim_set_hl, 0, name, s)
      state.done[name] = vim.api.nvim_get_hl(0, { name = name })
    end
  end
  for i = 0, 15 do
    local k = "terminal_color_" .. i
    local v = state.term[k]
    if type(v) == "string" and v:match("^#%x%x%x%x%x%x$") then
      local out = identity and v or hex(tf(tonumber(v:sub(2), 16)))
      vim.g[k], state.term[k .. "_done"] = out, out
    end
  end
  -- тусклые неактивные окна — пересчитать от новых цветов
  if package.loaded["vimade"] then pcall(require("vimade").redraw) end
  vim.api.nvim_exec_autocmds("User", { pattern = "OwnSoftApplied", modeline = false })
end

--- Цвет (0xRRGGBB) так, как его показал бы фильтр сейчас; модуль выключен — как есть
function M.color(n)
  if not n or not state.tf then return n end
  return state.tf(n)
end

-- ── вечер ───────────────────────────────────────────────────────────────────

local function minutes_of(s)
  local h, m = tostring(s or ""):match("^(%d+):(%d+)$")
  return h and tonumber(h) * 60 + tonumber(m) or nil
end

--- Сколько вечера сейчас: 0 днём, 1 ночью, между — плавный переход (ramp_min)
function M.night_level(now_min)
  local nt = o().night or {}
  if nt.enabled == false then return 0 end
  local from, to = minutes_of(nt.from or "21:00"), minutes_of(nt.to or "07:00")
  if not from or not to then return 0 end
  local ramp = math.max(1, nt.ramp_min or 45)
  local t = tonumber(now_min) or (tonumber(os.date("%H")) * 60 + tonumber(os.date("%M")))
  local function since(a) return (t - a) % 1440 end
  local night_len = (to - from) % 1440
  local s = since(from)
  if s >= night_len then return 0 end
  -- после from — нарастает, перед to — спадает
  return math.min(1, s / ramp, (night_len - s) / ramp)
end

local timer
local function tick()
  local lvl = M.night_level()
  if math.abs(lvl - state.night) >= 0.01 or (lvl == 0) ~= (state.night == 0) then
    state.night = lvl
    M.apply()
  end
end

-- ── окна проявляются ────────────────────────────────────────────────────────

local seen = {}
local SKIP = { smear_cursor = true, noice = true, image = true, snacks_image = true, scrollbar = true }
-- меню дополнения открывается на каждом слове — проявляется быстрее остальных, чтобы не отставать от набора
local QUICK = { ["blink-cmp-menu"] = true, ["blink-cmp-documentation"] = true, ["blink-cmp-signature"] = true }

local function fade_in(win)
  local f = o().fade or {}
  if f.enabled == false or vim.g.own_no_fade then return end
  local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
  if not ok or cfg.relative == "" or cfg.hide then return end
  local border = cfg.border
  if border == nil or border == "none" or (type(border) == "table" and (border[1] == "" or border[1] == " ") and (border[2] == "" or border[2] == " ")) then
    return -- без рамки — служебное окно (шлейф курсора, полоса прокрутки, значки)
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if SKIP[vim.bo[buf].filetype] then return end
  local target = vim.wo[win].winblend
  local start = math.max(target, math.min(100, f.from or 70))
  if start == target then return end
  local total = math.max(40, f.ms or 140)
  if QUICK[vim.bo[buf].filetype] then total, start = math.min(total, f.menu_ms or 70), math.min(start, 45) end
  pcall(function() vim.wo[win].winblend = start end)
  local last = start
  local t0 = vim.uv.now()
  local tm = vim.uv.new_timer()
  tm:start(16, 16, vim.schedule_wrap(function()
    if not vim.api.nvim_win_is_valid(win) or vim.wo[win].winblend ~= last then
      -- закрыли или окно само поменяло прозрачность — не мешать
      if not tm:is_closing() then tm:stop(); tm:close() end
      return
    end
    local k = math.min(1, (vim.uv.now() - t0) / total)
    local e = 1 - (1 - k) * (1 - k) -- быстро в начале, мягко в конце
    last = math.floor(start + (target - start) * e + 0.5)
    vim.wo[win].winblend = last
    if k >= 1 and not tm:is_closing() then tm:stop(); tm:close() end
  end))
end

local function scan()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if not seen[w] then
      seen[w] = true
      fade_in(w)
    end
  end
end

-- ── текущая строка только в активном окне ───────────────────────────────────

local function cursorline(win, on)
  if not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" or vim.api.nvim_win_get_config(win).relative ~= "" then return end
  if not vim.go.cursorline then return end
  vim.wo[win].cursorline = on
end

function M.toggle()
  state.off = not state.off
  M.apply()
  vim.notify(state.off and "мягкий фильтр выключен — тема как есть" or "мягкий фильтр включён")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.soft", { clear = true })
  state.night = M.night_level()
  -- после всех, кто дорисовывает тему на ColorScheme (свои цвета, рамки, режимы)
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = function() vim.schedule(function() M.apply(true) end) end })
  if vim.g.colors_name then vim.schedule(function() M.apply(true) end) end
  for _, w in ipairs(vim.api.nvim_list_wins()) do seen[w] = true end
  vim.api.nvim_create_autocmd("WinNew", { group = group, callback = scan })
  vim.api.nvim_create_autocmd("WinClosed", { group = group, callback = function(ev) seen[tonumber(ev.match)] = nil end })
  if o().cursorline_active ~= false then
    vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, { group = group, callback = function() cursorline(0, true) end })
    vim.api.nvim_create_autocmd("WinLeave", { group = group, callback = function() cursorline(0, false) end })
  end
  if timer then timer:stop() end
  timer = vim.uv.new_timer()
  timer:start(60000, 60000, vim.schedule_wrap(tick))
end

function M.reload()
  state.night = M.night_level()
  M.apply()
end

return M
