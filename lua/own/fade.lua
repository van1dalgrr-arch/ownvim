-- Плавная смена цвета: вместо мгновенного переключения (режим, вспышка) цвет перетекает за ms миллисекунд.
-- fade.run(key, from, to, fn, ms) — fn(цвет) зовётся на каждом кадре, последний — ровно to; новый run с тем же key
-- отменяет прошлый (быстро нажал i и Esc — без рывков). Анимации выключены (тихий режим) — сразу to.
local M = {}

local timers = {}

local function mix(a, b, t)
  local function ch(x, s) return math.floor(x / s) % 256 end
  local out = 0
  for _, s in ipairs({ 65536, 256, 1 }) do
    out = out + math.floor(ch(a, s) + (ch(b, s) - ch(a, s)) * t + 0.5) * s
  end
  return out
end
M.mix = mix

function M.ms()
  local s = ((require("own.settings").current or {}).soft or {}).mode_fade_ms
  if vim.g.own_no_fade then return 0 end
  return s == nil and 150 or s
end

function M.run(key, from, to, fn, ms)
  ms = ms or M.ms()
  local old = timers[key]
  if old and not old:is_closing() then old:stop(); old:close() end
  timers[key] = nil
  if not from or not to or from == to or ms <= 0 then return fn(to) end
  local t0 = vim.uv.now()
  local tm = vim.uv.new_timer()
  timers[key] = tm
  tm:start(0, 16, vim.schedule_wrap(function()
    if tm:is_closing() then return end
    local k = math.min(1, (vim.uv.now() - t0) / ms)
    local e = 1 - (1 - k) * (1 - k) -- мягко в конце
    fn(k >= 1 and to or mix(from, to, e))
    if k >= 1 then tm:stop(); tm:close(); if timers[key] == tm then timers[key] = nil end end
  end))
end

return M
