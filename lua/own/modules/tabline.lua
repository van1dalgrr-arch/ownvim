-- Вкладки как в VS Code: открытые файлы сверху — значок, имя, ● если не сохранён, крестик; клик — перейти,
-- клик по крестику (или средней кнопкой) — закрыть. Одинаковые имена различаются папкой. Не влезают — прокрутка
-- к текущей. shift-h / shift-l — соседняя вкладка, пробел b d — закрыть. Раздел "tabline":
--   "show": "auto" (когда файлов больше одного) | "always" | "never"
--   "style": "ide" | "underline" | "bar" | "slant" | "plain" — как выделена текущая
--   "close_button": true, "icons": true, "max_name": 24, "modified": "●"
-- Цвета — из темы. На лету.
local settings = require("own.settings")

local M = {}

local function o() return (settings.current or {}).tabline or {} end

local function color(group, attr)
  local h = vim.api.nvim_get_hl(0, { name = group, link = false })
  return h[attr or "fg"]
end

local icon_hl = {} -- значок вкладки: цвет значка на фоне вкладки (у текущей — с той же линией снизу)

local function define()
  icon_hl = {}
  local fill = color("TabLineFill", "bg") or color("StatusLine", "bg") or 0x1e1e1e
  local sel_bg = color("Normal", "bg") or 0x000000
  local accent = color("OwnIconAccent") or color("Title") or 0xbb9af7
  local muted = color("Comment") or 0x888888
  vim.api.nvim_set_hl(0, "OwnTabFill", { bg = fill })
  vim.api.nvim_set_hl(0, "OwnTab", { fg = muted, bg = fill })
  vim.api.nvim_set_hl(0, "OwnTabSel", { fg = color("Normal") or 0xffffff, bg = sel_bg, bold = true })
  vim.api.nvim_set_hl(0, "OwnTabSelLine", { fg = color("Normal") or 0xffffff, bg = sel_bg, bold = true, underline = true, sp = accent })
  vim.api.nvim_set_hl(0, "OwnTabBar", { fg = accent, bg = sel_bg })
  vim.api.nvim_set_hl(0, "OwnTabSlant", { fg = sel_bg, bg = fill })
  vim.api.nvim_set_hl(0, "OwnTabModified", { fg = color("DiagnosticWarn") or 0xe0af68, bg = fill })
  vim.api.nvim_set_hl(0, "OwnTabModifiedSel", { fg = color("DiagnosticWarn") or 0xe0af68, bg = sel_bg })
  vim.api.nvim_set_hl(0, "OwnTabClose", { fg = muted, bg = fill })
  vim.api.nvim_set_hl(0, "OwnTabCloseSel", { fg = muted, bg = sel_bg })
  vim.api.nvim_set_hl(0, "OwnTabArrow", { fg = accent, bg = fill, bold = true })
  vim.api.nvim_set_hl(0, "OwnTabOffset", { fg = color("WinSeparator") or muted, bg = fill })
end

local function icon_group(group, sel, line)
  local key = group .. (sel and (line and "L" or "S") or "")
  if not icon_hl[key] then
    local name = "OwnTabIcon" .. key:gsub("[^%w]", "")
    local spec = { fg = color(group), bg = sel and (color("Normal", "bg") or 0x000000) or (color("TabLineFill", "bg") or color("StatusLine", "bg")) }
    if line then spec.underline, spec.sp = true, color("OwnIconAccent") or color("Title") end
    vim.api.nvim_set_hl(0, name, spec)
    icon_hl[key] = name
  end
  return icon_hl[key]
end

-- вкладки начинаются над редактором, а не над деревом или панелью слева: колонка первого окна с файлом
local function offset()
  local min
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then
      local col = vim.api.nvim_win_get_position(w)[2]
      min = math.min(min or col, col)
    end
  end
  return min or 0
end

local function listed()
  return vim.tbl_filter(function(b)
    return vim.bo[b].buflisted and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == ""
  end, vim.api.nvim_list_bufs())
end

-- имена: одинаковые — с папкой
local function names(bufs)
  local base, count = {}, {}
  for _, b in ipairs(bufs) do
    local n = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
    if n == "" then n = "[без имени]" end
    base[b] = n
    count[n] = (count[n] or 0) + 1
  end
  for _, b in ipairs(bufs) do
    if count[base[b]] > 1 then
      local parent = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":h:t")
      base[b] = parent .. "/" .. base[b]
    end
  end
  return base
end

_G.OwnTabClick = function(b, _, button)
  if button == "m" then return require("snacks").bufdelete(b) end
  vim.api.nvim_set_current_buf(b)
end
_G.OwnTabClose = function(b) require("snacks").bufdelete(b) end

local function width(s)
  -- ширина без %-кодов
  return vim.api.nvim_strwidth((s:gsub("%%#[^#]*#", ""):gsub("%%%d*@[^@]*@", ""):gsub("%%X", ""):gsub("%%%%", "%%")))
end

function M.render()
  local opts = o()
  local style = opts.style or "underline"
  local bufs = listed()
  local cur = vim.api.nvim_get_current_buf()
  local label = names(bufs)
  local max = opts.max_name or 24
  local tabs, cur_i = {}, 1
  for i, b in ipairs(bufs) do
    local sel = b == cur
    if sel then cur_i = i end
    local name = label[b]
    if vim.api.nvim_strwidth(name) > max then name = "…" .. name:sub(-(max - 1)) end
    name = name:gsub("%%", "%%%%")
    local base = sel and (style == "underline" and "OwnTabSelLine" or "OwnTabSel") or "OwnTab"
    local s = "%" .. b .. "@v:lua.OwnTabClick@"
    if style == "ide" then
      -- ide: текущая — на фоне кода с полоской акцента, как вкладка, из которой «вырастает» редактор; остальные — тихо
      s = s .. (sel and "%#OwnTabBar#▎" or "%#OwnTab# ") .. "%#" .. base .. "# "
    elseif sel and style == "bar" then s = s .. "%#OwnTabBar#▎" else s = s .. "%#" .. base .. "# " end
    if sel and style == "slant" then s = "%#OwnTabSlant#\u{e0ba}" .. s end
    if opts.icons ~= false then
      local ok, icons = pcall(require, "mini.icons")
      if ok then
        local glyph, group = icons.get("file", vim.api.nvim_buf_get_name(b))
        s = s .. "%#" .. icon_group(group, sel, sel and style == "underline") .. "#" .. glyph .. "%#" .. base .. "# "
      end
    end
    s = s .. name .. " %X"
    if vim.bo[b].modified then
      s = s .. "%#" .. (sel and "OwnTabModifiedSel" or "OwnTabModified") .. "#" .. (opts.modified or "●") .. " "
    elseif opts.close_button ~= false and (sel or style ~= "ide") then
      s = s .. "%" .. b .. "@v:lua.OwnTabClose@%#" .. (sel and "OwnTabCloseSel" or "OwnTabClose") .. "#\u{ea76}%X "
    elseif style == "ide" then
      s = s .. "%#OwnTab#  "
    end
    if style == "ide" then s = s .. "%#" .. (sel and "OwnTabSel" or "OwnTab") .. "# " end
    if sel and style == "slant" then s = s .. "%#OwnTabSlant#\u{e0bc}" end
    tabs[#tabs + 1] = s
  end
  -- прокрутка: текущая всегда видна
  local pad = offset()
  -- над левой панелью — переключатель её видов (рабочее место), справа — что запускается (конфигурация запуска)
  local ws = package.loaded["own.modules.workspace"]
  local lead
  if ws then
    lead = ws.tabline_lead(pad > 0 and pad or (#ws.order.left * 3 + 2))
  else
    lead = pad > 0 and ("%#OwnTabOffset#" .. (" "):rep(pad - 1) .. "│") or ""
  end
  local right = ws and require("own.tools.launch").widget() or ""
  local avail = vim.o.columns - 2 - width(lead) - width(right)
  local first, last = cur_i, cur_i
  local used = tabs[cur_i] and width(tabs[cur_i]) or 0
  while true do
    local grew = false
    if last < #tabs and used + width(tabs[last + 1]) <= avail then last = last + 1; used = used + width(tabs[last]); grew = true end
    if first > 1 and used + width(tabs[first - 1]) <= avail then first = first - 1; used = used + width(tabs[first]); grew = true end
    if not grew then break end
  end
  local out = lead .. (first > 1 and "%#OwnTabArrow#‹" or "") .. table.concat(vim.list_slice(tabs, first, last), "")
  return out .. (last < #tabs and "%#OwnTabArrow#›" or "") .. "%#OwnTabFill#%T%=" .. right
end

local function update_visibility()
  local show = o().show or "auto"
  local n = #listed()
  -- на стартовом экране (файлов ещё нет) строка не нужна даже при "always"
  vim.o.showtabline = show == "never" and 0 or n == 0 and 0 or show == "always" and 2 or (n > 1 and 2 or 0)
end

M.define = define

function M.setup()
  define()
  vim.o.tabline = "%!v:lua.require'own.modules.tabline'.render()"
  update_visibility()
  local group = vim.api.nvim_create_augroup("own.tabline", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define })
  vim.api.nvim_create_autocmd({ "WinResized", "WinNew", "WinClosed" }, {
    group = group,
    callback = function() vim.schedule(function() vim.cmd("redrawtabline") end) end,
  })
  vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout", "BufEnter", "BufFilePost" }, {
    group = group,
    callback = function() vim.schedule(update_visibility) end,
  })
end

function M.reload()
  update_visibility()
  vim.cmd("redrawtabline")
end

return M
