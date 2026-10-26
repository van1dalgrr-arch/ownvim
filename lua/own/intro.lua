-- «Включение» ownvim: дождь знаков на миг поверх стартового экрана и переливающийся градиент логотипа.
-- Раздел "dashboard": { "intro": true, "animate": true }. Цвета — из темы (те же OwnDashGrad, что у логотипа).
-- Дождь рисуется после запуска (VimEnter) и сам закрывается — время старта он не трогает;
-- перелив идёт, только пока стартовый экран на виду, ушёл с него — таймер остановлен.
local settings = require("own.settings")

local M = {}

local function o() return (settings.current or {}).dashboard or {} end
local function c(g, a) local v = vim.api.nvim_get_hl(0, { name = g, link = false })[a or "fg"] return v and ("#%06x"):format(v) end

local function on_dashboard()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "snacks_dashboard" then return true end
  end
end

-- ── дождь ───────────────────────────────────────────────────────────────────

local GLYPHS = vim.fn.split("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎ0123456789<>*+=:", [[\zs]])

function M.rain(ms)
  ms = ms or 400
  local W, H = vim.o.columns, vim.o.lines - 1
  local ns = vim.api.nvim_create_namespace("own.intro")
  local color = require("own.theme.color")
  local bg = c("Normal", "bg") or "#000000"
  local accent = c("OwnIconAccent") or c("Title") or "#bb9af7"
  vim.api.nvim_set_hl(0, "OwnRainHead", { fg = c("Normal") or "#ffffff", bold = true })
  vim.api.nvim_set_hl(0, "OwnRainBody", { fg = accent })
  vim.api.nvim_set_hl(0, "OwnRainTail", { fg = color.blend(accent, bg, 0.35) })
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = 0, col = 0, width = W, height = H, style = "minimal", zindex = 250, focusable = false,
    border = "none", -- winborder (скруглённые рамки) окну-дождю не нужен
  })
  vim.wo[win].winhighlight = "Normal:Normal"
  local drops = {}
  -- капли сразу на экране: дождь длится доли секунды, сверху они бы не успели дойти до середины
  for x = 1, W, 2 do drops[x] = { y = math.random(-6, H), speed = math.random(1, 3) } end
  local grid = {}
  for y = 1, H do grid[y] = {} for x = 1, W do grid[y][x] = " " end end
  local timer = vim.uv.new_timer()
  local started = vim.uv.now()
  timer:start(0, 40, vim.schedule_wrap(function()
    if not vim.api.nvim_win_is_valid(win) or vim.uv.now() - started > ms then
      timer:stop(); timer:close()
      pcall(vim.api.nvim_win_close, win, true)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      return
    end
    local marks = {}
    for x, d in pairs(drops) do
      d.y = d.y + d.speed
      if d.y > H + 6 then d.y = -math.random(0, 6) end
      for k, hl in ipairs({ "OwnRainHead", "OwnRainBody", "OwnRainBody", "OwnRainTail", "OwnRainTail" }) do
        local y = d.y - (k - 1)
        if y >= 1 and y <= H then
          grid[y][x] = GLYPHS[math.random(#GLYPHS)]
          marks[#marks + 1] = { y, x, hl }
        end
      end
      local gone = d.y - 6
      if gone >= 1 and gone <= H then grid[gone][x] = " " end
    end
    local lines = {}
    for y = 1, H do lines[y] = table.concat(grid[y]) end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, m in ipairs(marks) do
      local line = lines[m[1]]
      local col = vim.str_byteindex(line, "utf-32", m[2] - 1, false)
      local len = #grid[m[1]][m[2]]
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, m[1] - 1, col, { end_col = col + len, hl_group = m[3] })
    end
  end))
end

-- ── перелив логотипа ────────────────────────────────────────────────────────

local GRADIENT = 6 -- столько же групп OwnDashGrad, сколько у стартового экрана (modules/ui.lua)

function M.shimmer()
  if M.timer then return end
  local color = require("own.theme.color")
  local phase = 0
  M.timer = vim.uv.new_timer()
  M.timer:start(0, 100, vim.schedule_wrap(function()
    if not on_dashboard() then
      M.timer:stop(); M.timer:close(); M.timer = nil
      return
    end
    -- концы градиента — как у логотипа: акцент и второй цвет темы; волна бежит сверху вниз
    local from = c("OwnIconAccent") or c("Statement") or "#bb9af7"
    local to = c("Statement") ~= from and c("Statement") or c("Function") or "#7aa2f7"
    phase = phase + 0.06
    for i = 1, GRADIENT do
      local t = 0.5 + 0.5 * math.sin(phase * math.pi * 2 + (i - 1) / (GRADIENT - 1) * math.pi)
      vim.api.nvim_set_hl(0, "OwnDashGrad" .. i, { fg = color.blend(to, from, t), bold = true })
    end
  end))
end

-- ── водяной знак в пустом окне ──────────────────────────────────────────────

local wm_ns = vim.api.nvim_create_namespace("own.watermark")

local function is_blank(buf)
  return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) == "" and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" and not vim.bo[buf].modified
end

-- логотип со стартового экрана (строки из █╗), бледно и по центру; в файл не пишется — это виртуальные строки
function M.watermark()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  vim.api.nvim_buf_clear_namespace(buf, wm_ns, 0, -1)
  if o().watermark == false or vim.api.nvim_win_get_config(win).relative ~= "" or not is_blank(buf) then return end
  local logo = vim.tbl_filter(function(l) return vim.fn.match(l, [=[[▀-▟]]=]) >= 0 end, o().header or {})
  if #logo == 0 then return end
  local color = require("own.theme.color")
  vim.api.nvim_set_hl(0, "OwnWatermark", { fg = color.blend(c("Comment") or "#888888", c("Normal", "bg") or "#000000", 0.35) })
  local W, H = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
  local lw = vim.api.nvim_strwidth(logo[1])
  if lw + 4 > W or #logo + 2 > H then return end
  local lines = {}
  for _ = 1, math.floor((H - #logo) / 2) - 1 do lines[#lines + 1] = { { "" } } end
  for _, l in ipairs(logo) do lines[#lines + 1] = { { (" "):rep(math.floor((W - lw) / 2) - 4) .. l, "OwnWatermark" } } end
  vim.api.nvim_buf_set_extmark(buf, wm_ns, 0, 0, { virt_lines = lines })
end

-- ── «до встречи» при выходе ─────────────────────────────────────────────────

M.started = vim.uv.hrtime()
M.saved = {}

local function plural(n, one, few, many)
  local m10, m100 = n % 10, n % 100
  if m10 == 1 and m100 ~= 11 then return one end
  if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then return few end
  return many
end

--- рамка в центре на миг: ╭─( dev㉿van1dal )──╮ │ до встречи · 2ч 14м · 12 файлов │ ╰──╯
function M.outro(ms)
  local mins = math.floor((vim.uv.hrtime() - M.started) / 6e10)
  local dur = mins >= 60 and ("%dч %dм"):format(math.floor(mins / 60), mins % 60) or ("%d мин"):format(mins)
  local n = vim.tbl_count(M.saved)
  local body = ("до встречи · %s · %d %s"):format(dur, n, plural(n, "файл", "файла", "файлов"))
  local who = (vim.env.USER or "me") .. "㉿" .. (vim.fn.hostname():gsub("%..*$", ""))
  local Wd = vim.api.nvim_strwidth
  local inner = math.max(Wd(body) + 2, Wd(who) + 6)
  local F, A = "OwnDashKeyBracket", "OwnDashKey"
  local rows = {
    { { "╭─( ", F }, { who, A }, { " )" .. ("─"):rep(inner - Wd(who) - 5) .. "╮", F } },
    { { "│ ", F }, { body, "Normal" }, { (" "):rep(inner - Wd(body) - 1) .. "│", F } },
    { { "╰" .. ("─"):rep(inner) .. "╯", F } },
  }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "", "" })
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", style = "minimal", border = "none", zindex = 300, focusable = false,
    width = inner + 2, height = 3, row = math.floor((vim.o.lines - 3) / 2), col = math.floor((vim.o.columns - inner - 2) / 2),
  })
  vim.wo[win].winhighlight = "Normal:Normal"
  local ns = vim.api.nvim_create_namespace("own.outro")
  for i, chunks in ipairs(rows) do
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { virt_text = chunks, virt_text_pos = "overlay" })
  end
  vim.cmd("redraw")
  vim.wait(ms or 450)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.intro", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinResized", "VimResized" }, {
    group = group, callback = function() vim.schedule(M.watermark) end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertEnter" }, {
    group = group, callback = function(ev) vim.api.nvim_buf_clear_namespace(ev.buf, wm_ns, 0, -1) end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group, callback = function(ev) M.saved[vim.api.nvim_buf_get_name(ev.buf)] = true end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if o().outro == false or #vim.api.nvim_list_uis() == 0 then return end
      pcall(M.outro, o().outro_ms or 450)
    end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "snacks_dashboard",
    callback = function()
      if o().animate ~= false then vim.schedule(M.shimmer) end
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      -- только когда открыт сам ownvim, без файла, и в настоящем терминале
      if o().intro == false or vim.fn.argc() > 0 or #vim.api.nvim_list_uis() == 0 then return end
      -- snacks открывает стартовый экран на том же VimEnter — подождать его кадр
      vim.defer_fn(function() if on_dashboard() then M.rain(o().intro_ms or 400) end end, 30)
    end,
  })
end

return M
