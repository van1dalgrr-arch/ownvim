-- Красивый скриншот кода: выделил → пробел P → PNG в окне с тенью, в цветах текущей темы, с номерами строк.
-- Картинка сразу в буфере обмена (⌘V в Telegram) и в ~/Pictures/code. Без выделения — функция под курсором.
-- Рисует freeze (charmbracelet). С рамками (appearance.frames) — в стиле ownvim: цвета — из подсветки самого
-- редактора (любая тема, семантика LSP), вокруг рамка ─[ файл › функция ]─ … ( dev㉿host )─[ ownvim ];
-- без рамок — окно freeze его темой (та же, что в nvim, а если у freeze такой нет — ближайшая).
local M = {}

-- темы, которые freeze знает под тем же именем
local same = {}
for _, n in ipairs({
  "tokyonight-night", "tokyonight-moon", "tokyonight-storm", "tokyonight-day", "rose-pine", "rose-pine-moon",
  "rose-pine-dawn", "catppuccin-mocha", "catppuccin-macchiato", "catppuccin-frappe", "catppuccin-latte",
  "gruvbox", "gruvbox-light", "nord", "dracula",
}) do same[n] = true end

local function theme()
  local name = vim.g.colors_name or ""
  if same[name] then return name end
  local light = vim.o.background == "light"
  if name:match("^tokyonight") then return light and "tokyonight-day" or "tokyonight-night" end
  if name:match("^rose%-pine") then return light and "rose-pine-dawn" or "rose-pine" end
  if name:match("^catppuccin") then return light and "catppuccin-latte" or "catppuccin-mocha" end
  if name:match("^gruvbox") then return light and "gruvbox-light" or "gruvbox" end
  return light and "tokyonight-day" or "tokyonight-night" -- kanagawa, nightfox, vesper… — у freeze их нет
end

-- функция или метод под курсором (treesitter), иначе весь файл; третьим — имя функции (для заголовка рамки)
local function current_function()
  local ok, node = pcall(vim.treesitter.get_node)
  while ok and node do
    local t = node:type()
    if t:match("function") or t:match("method") then
      local s, _, e = node:range()
      local n = node:field("name")[1]
      return s + 1, e + 1, n and vim.treesitter.get_node_text(n, 0) or nil
    end
    node = node:parent()
  end
  return 1, vim.api.nvim_buf_line_count(0)
end

-- ── рамка ownvim: текст в цветах редактора → ANSI → freeze ─────────────────────────

local style_cache = {}
-- группа → ANSI-код цвета и начертания; nil — у группы нет своего цвета (тогда смотрим следующую)
local function style(group)
  if style_cache[group] ~= nil then return style_cache[group] end
  local h = vim.api.nvim_get_hl(0, { name = group, link = false })
  local s = false
  if h.fg then
    s = ("\27[38;2;%d;%d;%dm"):format(bit.rshift(h.fg, 16), bit.band(bit.rshift(h.fg, 8), 0xff), bit.band(h.fg, 0xff))
      .. (h.italic and "\27[3m" or "") .. (h.bold and "\27[1m" or "")
  end
  style_cache[group] = s
  return s
end

-- цвет знака как на экране: семантика LSP поверх treesitter поверх синтаксиса; первая группа, у которой есть цвет
local function style_at(buf, row, col)
  local info = vim.inspect_pos(buf, row, col, { semantic_tokens = true, treesitter = true, syntax = true, extmarks = false })
  local groups = {}
  for i = #info.semantic_tokens, 1, -1 do groups[#groups + 1] = info.semantic_tokens[i].opts.hl_group end
  for i = #info.treesitter, 1, -1 do groups[#groups + 1] = info.treesitter[i].hl_group end
  for i = #info.syntax, 1, -1 do groups[#groups + 1] = info.syntax[i].hl_group end
  for _, g in ipairs(groups) do
    local s = style(g)
    if s then return s end
  end
  return style("Normal") or ""
end

local function ansi_line(buf, row, text, tabstop)
  local out, last, col, i = {}, nil, 0, 1
  while i <= #text do
    local j = i + vim.str_utf_end(text, i)
    local ch = text:sub(i, j)
    if ch == "\t" then ch = (" "):rep(tabstop - col % tabstop) end
    local s = ch:match("^%s+$") and last or style_at(buf, row, i - 1)
    if s ~= last then out[#out + 1] = "\27[0m" .. (s or ""); last = s end
    out[#out + 1] = ch
    col = col + vim.fn.strdisplaywidth(ch)
    i = j + 1
  end
  return table.concat(out) .. "\27[0m", col
end

local function framed(l1, l2, symbol)
  style_cache = {}
  local buf = vim.api.nvim_get_current_buf()
  local F, A, N, M = style("Comment") or "", style("OwnIconAccent") or style("Title") or "", style("LineNr") or "", style("Comment") or ""
  local R = "\27[0m"
  local nw = #tostring(l2)
  local body, width = {}, 0
  for row = l1, l2 do
    local text = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local code, w = ansi_line(buf, row - 1, text, vim.bo[buf].tabstop)
    body[#body + 1] = { code = code, w = w, n = row }
    width = math.max(width, w)
  end
  local title = vim.fn.expand("%:t") .. (symbol and (" › " .. symbol) or "")
  local who = (vim.env.USER or "me") .. "㉿" .. (vim.fn.hostname():gsub("%..*$", ""))
  local W = vim.api.nvim_strwidth
  local inner = math.max(nw + 2 + width + 2, W(title) + 8, W(who) + W("ownvim") + 14)
  local lines = {}
  lines[1] = F .. "╭─[ " .. R .. A .. title .. R .. F .. " ]" .. ("─"):rep(inner - W(title) - 5) .. "╮" .. R
  lines[2] = F .. "│" .. (" "):rep(inner) .. "│" .. R
  for _, b in ipairs(body) do
    lines[#lines + 1] = F .. "│ " .. R .. N .. ("%" .. nw .. "d"):format(b.n) .. R .. "  " .. b.code
      .. (" "):rep(inner - 1 - nw - 2 - b.w) .. F .. "│" .. R
  end
  lines[#lines + 1] = F .. "│" .. (" "):rep(inner) .. "│" .. R
  -- ╰─( who )───…───[ ownvim ]─╯ — ширина как у остальных строк: inner + 2
  lines[#lines + 1] = F .. "╰─( " .. R .. A .. who .. R .. F .. " )" .. ("─"):rep(inner - W(who) - 16) .. "[ " .. R
    .. M .. "\27[3mownvim" .. R .. F .. " ]─╯" .. R
  return lines
end

function M.shot(l1, l2)
  if vim.fn.executable("freeze") == 0 then
    return vim.notify("нужен freeze: brew install charmbracelet/tap/freeze", vim.log.levels.ERROR)
  end
  local symbol
  if not l1 then l1, l2, symbol = current_function() end
  local name = vim.fn.expand("%:t")
  if name == "" then name = "code." .. (vim.bo.filetype ~= "" and vim.bo.filetype or "txt") end
  -- рисуем то, что в буфере (даже несохранённое); имя файла — чтобы freeze понял язык
  local tmp = vim.fn.stdpath("cache") .. "/shot/" .. name
  vim.fn.mkdir(vim.fs.dirname(tmp), "p")
  vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), tmp)
  local out = vim.fn.expand("~/Pictures/code/") .. vim.fn.fnamemodify(name, ":r") .. os.date("-%Y%m%d-%H%M%S") .. ".png"
  vim.fn.mkdir(vim.fs.dirname(out), "p")
  local cmd
  if require("own.frames").enabled then
    -- рамка ownvim: цвета — из самого редактора; фон картинки — фон темы
    vim.fn.writefile(framed(l1, l2, symbol), tmp .. ".ansi")
    local bgv = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
    cmd = { "freeze", tmp .. ".ansi", "--language", "ansi", "--background", bgv and ("#%06x"):format(bgv) or "#000000",
      "--font.family", "JetBrainsMono Nerd Font", "--font.size", "14",
      "--border.radius", "10", "--shadow.blur", "20", "--shadow.y", "8", "--padding", "16,20", "--margin", "32", "-o", out }
  else
    cmd = {
      "freeze", tmp, "--lines", l1 .. "," .. l2, "--theme", theme(),
      "--window", "--show-line-numbers", "--font.family", "JetBrainsMono Nerd Font", "--font.size", "14",
      "--border.radius", "10", "--shadow.blur", "20", "--shadow.y", "8", "--padding", "20,28", "--margin", "32",
      "-o", out,
    }
  end
  vim.system(cmd, { text = true, stdin = false }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then return vim.notify("freeze: " .. (res.stderr or ""), vim.log.levels.ERROR) end
    -- PNG в буфер обмена macOS: ⌘V вставит картинку
    vim.system({ "osascript", "-e", ('set the clipboard to (read (POSIX file "%s") as «class PNGf»)'):format(out) })
    vim.notify(("строки %d–%d → картинка в буфере обмена (⌘V)\n%s"):format(l1, l2, out:gsub(vim.env.HOME, "~")), vim.log.levels.INFO, { title = "скриншот кода" })
  end))
end

return M
