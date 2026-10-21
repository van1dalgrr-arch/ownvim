-- Отдых: ownvim считает время непрерывной работы и мягко напоминает о перерыве — без висящих часов, которые подгоняют.
--   Пауза дольше break_min (не нажимали клавиш) — это уже перерыв: счёт начинается заново.
--   Через work_min минут — один раз уведомление и в статусной строке «⏱ пора отдохнуть» (блок rest).
--   :Rest — начать перерыв (в строке ☕ и обратный отсчёт, в конце — «перерыв окончен»), :RestLater — напомнить через 10 мин.
-- Настройки модуля: { "work_min": 50, "break_min": 5, "show": "due" } — "always": показывать и время работы (⏱ 42м)
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

local function tick()
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
function M._shift(ms) started, last_key = started - ms, last_key end
M._tick = tick

return M
