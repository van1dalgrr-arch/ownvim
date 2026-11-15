-- Отдых: ownvim считает время непрерывной работы и мягко напоминает о перерыве — без висящих часов, которые подгоняют.
--   Пауза дольше break_min (не нажимали клавиш) — это уже перерыв: счёт начинается заново.
--   Через work_min минут — один раз уведомление и в статусной строке «⏱ пора отдохнуть» (блок rest).
--   :Rest — начать перерыв (в строке ☕ и обратный отсчёт, в конце — «перерыв окончен»), :RestLater — напомнить через 10 мин.
-- Настройки модуля: { "work_min": 50, "break_min": 5, "show": "due" } — "always": показывать и время работы (⏱ 42м)
-- Глаза (правило 20-20-20): каждые eyes_min минут за экраном — тихая подсказка посмотреть вдаль на eyes_sec секунд,
--   в строке статуса — «👁 0:20» и обратный отсчёт; печатать можно дальше, это не перерыв. "eyes_min": 0 — выкл.
--   Две минуты без клавиш — скорее всего, отходил: счёт заново.
local M = {}

local opts = {}
local function work_min() return opts.work_min or 50 end
local function break_min() return opts.break_min or 5 end

local now = function() return vim.uv.now() end -- мс, монотонно
local MIN = 60 * 1000

local started = now()      -- начало непрерывной работы
local last_key = now()     -- последняя клавиша
local snooze_until = 0     -- :RestLater
local reminded = false     -- уведомление уже было
local break_until = nil    -- идёт перерыв (:Rest) — до этого момента
local eyes_from = now()    -- с какого момента глаза смотрят в экран
local eyes_until = nil     -- идёт отдых глаз — до этого момента

local function eyes_min() return opts.eyes_min == nil and 20 or opts.eyes_min end
local function eyes_sec() return opts.eyes_sec or 20 end

-- 1 минута, 2 минуты, 5 минут, 21 минута, 11 минут
local function minutes(n)
  local d, h = n % 10, n % 100
  local w = (d == 1 and h ~= 11) and "минута" or (d >= 2 and d <= 4 and (h < 12 or h > 14)) and "минуты" or "минут"
  return n .. " " .. w
end
M._minutes = minutes

--- минуты непрерывной работы
function M.worked() return math.floor((now() - started) / MIN) end

local function due() return not break_until and M.worked() >= work_min() and now() >= snooze_until end

local function reset()
  started, reminded, snooze_until = now(), false, 0
end

local eyes_timer
local function eyes_tick()
  local t = now()
  if eyes_until then
    if t >= eyes_until then
      eyes_until, eyes_from = nil, t
      if eyes_timer then eyes_timer:stop() end
    end
    vim.cmd.redrawstatus()
    return
  end
  if eyes_min() <= 0 or break_until then return end
  if t - last_key >= 2 * MIN then eyes_from = t; return end -- две минуты без клавиш — скорее всего, отходил
  if t - eyes_from >= eyes_min() * MIN then
    eyes_until = t + eyes_sec() * 1000
    vim.notify(("👁 %d секунд — посмотри вдаль, метров на шесть, и поморгай. Можно не отрываться от мысли"):format(eyes_sec()),
      vim.log.levels.INFO, { title = "глаза", timeout = eyes_sec() * 1000 })
    eyes_timer = eyes_timer or vim.uv.new_timer()
    eyes_timer:start(1000, 1000, vim.schedule_wrap(eyes_tick))
  end
end
M._eyes_tick = eyes_tick

local function tick()
  eyes_tick()
  local t = now()
  if break_until then
    if t >= break_until then
      break_until = nil
      reset()
      vim.notify("перерыв окончен — с новыми силами", vim.log.levels.INFO, { title = "отдых" })
    end
  elseif t - last_key >= break_min() * MIN then
    reset() -- долго не печатали — это и был перерыв
  elseif due() and not reminded then
    reminded = true
    vim.notify(("%s без перерыва. Встаньте, разомнитесь, посмотрите вдаль — %s.\n:Rest — начать перерыв · :RestLater — через 10 минут")
      :format(minutes(M.worked()), minutes(break_min()):gsub("^1 минута$", "минуту")), vim.log.levels.WARN, { title = "отдых" })
  end
end

--- Текст и цвет для статусной строки (nil — ничего не показывать)
function M.status()
  if eyes_until then
    return ("👁 0:%02d"):format(math.max(0, math.ceil((eyes_until - now()) / 1000))), "cyan"
  end
  if break_until then
    local left = math.max(0, math.floor((break_until - now()) / 1000))
    return ("☕ %d:%02d"):format(math.floor(left / 60), left % 60), "green"
  end
  if due() then return "⏱ пора отдохнуть", "yellow" end
  if opts.show == "always" and M.worked() >= 1 then return ("⏱ %dм"):format(M.worked()), nil end
end

function M.start_break()
  break_until = now() + break_min() * MIN
  vim.notify(("перерыв: %s — ownvim подождёт"):format(minutes(break_min())), vim.log.levels.INFO, { title = "отдых" })
  vim.cmd.redrawstatus()
end

function M.later()
  snooze_until, reminded = now() + 10 * MIN, false
  vim.notify("напомню через 10 минут", vim.log.levels.INFO, { title = "отдых" })
  vim.cmd.redrawstatus()
end

local timer
function M.setup(o)
  opts = o or {}
  vim.on_key(function() last_key = now() end, vim.api.nvim_create_namespace("own.rest"))
  vim.api.nvim_create_user_command("Rest", M.start_break, { desc = "Начать перерыв" })
  vim.api.nvim_create_user_command("RestLater", M.later, { desc = "Напомнить о перерыве через 10 минут" })
  if timer then timer:stop() end
  timer = vim.uv.new_timer()
  timer:start(30000, 30000, vim.schedule_wrap(function()
    tick()
    vim.cmd.redrawstatus()
  end))
end

function M.reload(o) opts = o or {} end

-- для проверки: сдвинуть часы (тесты не ждут 50 минут)
function M._shift(ms) started, eyes_from, last_key = started - ms, eyes_from - ms, last_key end
M._tick = tick

return M
