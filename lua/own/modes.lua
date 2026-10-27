-- Режим видно сразу, и из вставки не нужно выходить самому.
-- Цвет курсора, его шлейфа (smear), строки под ним и номера строки меняется по режиму: обычный — акцент темы,
-- вставка — зелёный, выделение — фиолетовый, замена — красный. Те же цвета у статусной строки и рамок (M.colors).
-- "appearance": { "cursor_by_mode": false } — в обычном режиме курсор цветом текста, шлейф — цветом символа под ним.
-- Не печатаешь 5 секунд — nvim сам выходит из вставки (а автосохранение пишет файл).
-- Выключить автовыход: пробел u I.
local M = {}

local IDLE_MS = 5000

-- смешать цвет с фоном: строка под курсором — лёгкий оттенок, а не заливка
local function blend(fg, bg, alpha)
  local function rgb(c) return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256 end
  local r1, g1, b1 = rgb(fg)
  local r2, g2, b2 = rgb(bg)
  local function mix(a, b) return math.floor(a * alpha + b * (1 - alpha) + 0.5) end
  return string.format("#%02x%02x%02x", mix(r1, r2), mix(g1, g2), mix(b1, b2))
end

local function fg(group, fallback)
  local h = vim.api.nvim_get_hl(0, { name = group, link = false })
  return h.fg or fallback
end

local function by_mode()
  return (((require("own.settings").current or {}).appearance or {}).cursor_by_mode) ~= false
end

--- цвета режимов из темы (группы есть в любой теме) — одни на всех: курсор, статусная строка, рамки
function M.colors()
  return {
    Normal = fg("OwnIconAccent") or fg("Title") or 0xbb9af7,
    Insert = fg("DiagnosticOk") or fg("String") or 0x9ece6a, -- зелёный «ок», а не цвет строк (в Dev Night они жёлтые)
    Visual = fg("Statement") or 0xbb9af7,
    Replace = fg("DiagnosticError") or 0xf7768e,
    Command = fg("DiagnosticWarn") or 0xe0af68,
    Terminal = fg("Special") or 0x7dcfff,
  }
end

local base = {} -- CursorLine/CursorLineNr темы — к ним возвращаемся в обычном режиме
local cursor = {} -- вид режима → цвет курсора "#rrggbb" (для шлейфа smear)

local function define()
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  -- прозрачная тема: фона нет — смешиваем с цветом фона терминала
  bg = bg or (vim.o.background == "light" and 0xfaf4ed or 0x1a1b26)
  base.line = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false })
  base.nr = vim.api.nvim_get_hl(0, { name = "CursorLineNr", link = false })
  local colors = M.colors()
  if not by_mode() then colors.Normal = fg("Normal", 0xc0caf5) end
  for name, c in pairs(colors) do
    vim.api.nvim_set_hl(0, "Mode" .. name .. "Cursor", { bg = c, fg = bg })
    vim.api.nvim_set_hl(0, "Mode" .. name .. "Line", { bg = blend(c, bg, 0.14) })
    vim.api.nvim_set_hl(0, "Mode" .. name .. "Nr", { fg = c, bold = true })
    cursor[name] = ("#%06x"):format(c)
  end
end

local function kind_of(mode)
  local m = mode:sub(1, 1)
  if m == "i" then return "Insert" end
  if m == "v" or m == "V" or m == "\22" or m == "s" or m == "S" or m == "\19" then return "Visual" end
  if m == "R" then return "Replace" end
end

-- шлейф smear — цветом курсора режима; "none" — цветом символа под курсором (как без cursor_by_mode)
local smear_color
local function paint_smear(kind)
  local smear = package.loaded["smear_cursor"]
  if not smear then return end
  local want = by_mode() and cursor[kind or "Normal"] or "none"
  if want == smear_color then return end
  smear_color = want
  smear.cursor_color = want
  smear.cursor_color_insert_mode = want
  require("smear_cursor.color").clear_cache() -- цвет запомнен в группах SmearCursor* — перекрасить
end

local function paint()
  local kind = kind_of(vim.api.nvim_get_mode().mode)
  paint_smear(kind)
  if not kind then
    vim.api.nvim_set_hl(0, "CursorLine", base.line or {})
    vim.api.nvim_set_hl(0, "CursorLineNr", base.nr or {})
    return
  end
  vim.api.nvim_set_hl(0, "CursorLine", { link = "Mode" .. kind .. "Line" })
  vim.api.nvim_set_hl(0, "CursorLineNr", { link = "Mode" .. kind .. "Nr" })
end

--- настройки поменялись (appearance.cursor_by_mode) или smear только что загрузился — перекрасить
function M.reload()
  smear_color = nil
  define()
  paint()
end

-- автовыход из вставки после паузы
local timer = assert(vim.uv.new_timer())

local function idle_exit()
  if vim.g.auto_normal == false then return end
  if vim.api.nvim_get_mode().mode ~= "i" then return end
  if vim.bo.buftype ~= "" then return end -- только обычные файлы: не в терминале, поиске, окне Claude
  if vim.fn.reg_recording() ~= "" then return end -- пишется макрос
  if vim.snippet.active() then return end -- идёт заполнение сниппета
  local ok, blink = pcall(require, "blink.cmp")
  if ok and blink.is_menu_visible() then return end -- открыт список дополнения
  vim.cmd.stopinsert()
end

local function restart()
  timer:stop()
  timer:start(vim.g.auto_normal_ms or IDLE_MS, 0, vim.schedule_wrap(idle_exit)) -- пауза — modules.modes.auto_normal_ms
end

function M.setup()
  vim.o.cursorline = true
  vim.o.guicursor = table.concat({
    "n-c:block-ModeNormalCursor",
    "v:block-ModeVisualCursor",
    "i-ci-ve:ver25-ModeInsertCursor",
    "r-cr-o:hor20-ModeReplaceCursor",
  }, ",")

  local group = vim.api.nvim_create_augroup("own.modes", { clear = true })
  -- после темы: акцент (OwnIconAccent) задают другие модули на том же событии — перекрасить, когда они закончат
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = function() vim.schedule(M.reload) end })
  vim.api.nvim_create_autocmd("ModeChanged", { group = group, callback = paint })
  vim.api.nvim_create_autocmd({ "InsertEnter", "TextChangedI", "TextChangedP", "CursorMovedI" }, { group = group, callback = restart })
  vim.api.nvim_create_autocmd("InsertLeave", { group = group, callback = function() timer:stop() end })
  define()

  Snacks.toggle({
    name = "Автовыход из вставки (5 с)",
    get = function() return vim.g.auto_normal ~= false end,
    set = function(on) vim.g.auto_normal = on end,
  }):map("<leader>uI")
end

return M
