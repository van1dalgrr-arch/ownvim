-- Стартовый экран «home»: всё полезное на одном взгляде, в рамках, как остальной ownvim.
--
--            ▄▀▀▄ █   █ █▀▀▄ █   █ ▀█▀ █▀▄▀█           ← логотип градиентом темы (переливается)
--         Добрый вечер, van1dal · воскресенье, 15 ноября · 16:53
--
--   ╭─[ Начать ]──────────╮   ╭─[ Проекты ]──────────────────────────────╮
--   │  Найти файл     f │   │ 1  ownvim      main ● 3      2 ч назад    │
--   │ …                   │   ╰──────────────────────────────────────────╯
--   ╰─────────────────────╯   ╭─[ Недавние файлы ]───────────────────────╮
--   ╭─[ Сегодня ]─────────╮   │ 6  soft.lua   ownvim · lua/own/modules  │
--   │ ⚡ старт 52 мс       │   ╰──────────────────────────────────────────╯
--   ╰─────────────────────╯
--                 💡 пробел sp — поиск по проекту с заменой
--
-- Проекты — из недавних файлов (корни git), рядом ветка, изменения и когда работал (git — в фоне, экран дорисуется).
-- Клавиши: кнопки — свои буквы из "dashboard.buttons", проекты — 1…5, файлы — 6…0. Узкое окно — одна колонка.
-- "dashboard": { "style": "home" } — этот экран; "classic" — прежний (логотип, кнопки, разделы из "sections").
local settings = require("own.settings")

local M = {}

local W = vim.api.nvim_strwidth

local function d() return (settings.current or {}).dashboard or {} end

-- ── текст ───────────────────────────────────────────────────────────────────

local function trunc(s, w)
  if W(s) <= w then return s end
  local out = ""
  for _, ch in ipairs(vim.fn.split(s, [[\zs]])) do
    if W(out .. ch) > w - 1 then break end
    out = out .. ch
  end
  return out .. "…"
end

-- строка = список кусков { текст, hl }; ширина строки
local function width(line)
  local n = 0
  for _, c in ipairs(line) do n = n + W(c[1]) end
  return n
end

-- дотянуть строку пробелами до w; длиннее — обрезать с «…» (рамка не должна разъезжаться)
local function pad(line, w)
  local n = width(line)
  while n > w and #line > 0 do
    local last = line[#line]
    local over = n - w
    if W(last[1]) > over + 1 then
      last[1] = trunc(last[1], W(last[1]) - over)
    else
      table.remove(line)
    end
    n = width(line)
  end
  if n < w then line[#line + 1] = { (" "):rep(w - n) } end
  return line
end

-- рамка: ╭─[ заголовок ]───╮ / │ строка │ / ╰───╯; inner — ширина внутри
local function box(title, rows, inner)
  local F = "OwnDashFrame"
  local out = {}
  local head = { { "╭─", F }, { "[ ", F }, { title, "OwnDashTitle" }, { " ]", F } }
  head[#head + 1] = { ("─"):rep(math.max(0, inner + 2 - width(head) + 1)) .. "╮", F }
  out[#out + 1] = head
  for _, r in ipairs(rows) do
    local line = { { "│ ", F } }
    vim.list_extend(line, pad(vim.deepcopy(r), inner))
    line[#line + 1] = { " │", F }
    out[#out + 1] = line
  end
  out[#out + 1] = { { "╰" .. ("─"):rep(inner + 2) .. "╯", F } }
  return out
end

-- ── логотип ─────────────────────────────────────────────────────────────────

local LOGO = {
  "▄▀▀▄ █   █ █▀▀▄ █   █ ▀█▀ █▀▄▀█",
  "▀▄▄▀ ▀▄▀▄▀ █  █  ▀▄▀  ▄█▄ █ ▀ █",
}
local GRADIENT = 6

-- градиент слева направо: каждая буква логотипа — своим оттенком (группы OwnDashGrad — их же переливает intro)
local function logo(lines)
  local out = {}
  local wmax = 0
  for _, l in ipairs(lines) do wmax = math.max(wmax, W(l)) end
  for _, l in ipairs(lines) do
    local line, col = {}, 0
    local art = vim.fn.match(l, [=[[▀-▟─-╿]]=]) >= 0
    if not art then
      out[#out + 1] = { { l, "OwnDashTagline" } }
    else
      for _, ch in ipairs(vim.fn.split(l, [[\zs]])) do
        local g = math.floor(col / math.max(1, wmax - 1) * (GRADIENT - 1) + 1.5)
        line[#line + 1] = { ch, ch == " " and nil or ("OwnDashGrad" .. g) }
        col = col + W(ch)
      end
      out[#out + 1] = line
    end
  end
  return out
end

-- ── приветствие ─────────────────────────────────────────────────────────────

local DAYS = { "воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота" }
local MONTHS = { "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря" }

local name_cache
local function who()
  if d().name then return d().name end
  if name_cache == nil then
    local n = vim.trim(vim.fn.system({ "git", "config", "--global", "user.name" }) or "")
    name_cache = (vim.v.shell_error == 0 and n ~= "") and n or (vim.env.USER or "")
  end
  return name_cache
end

local function greeting()
  local h = tonumber(os.date("%H"))
  local hello = h < 5 and "Доброй ночи" or h < 12 and "Доброе утро" or h < 17 and "Добрый день" or h < 23 and "Добрый вечер" or "Доброй ночи"
  local t = os.date("*t")
  return {
    { hello .. (who() ~= "" and (", " .. who()) or ""), "OwnDashKey" },
    { ("  ·  %s, %d %s  ·  %s"):format(DAYS[t.wday], t.day, MONTHS[t.month], os.date("%H:%M")), "OwnDashTagline" },
  }
end

-- ── сколько времени назад ───────────────────────────────────────────────────

local function ago(ts)
  if not ts then return "" end
  local s = os.time() - ts
  if s < 90 then return "только что" end
  if s < 3600 then return math.floor(s / 60) .. " мин назад" end
  if s < 86400 then return math.floor(s / 3600) .. " ч назад" end
  local days = math.floor(s / 86400)
  if days == 1 then return "вчера" end
  if days < 7 then return days .. " дн назад" end
  if days < 60 then return math.floor(days / 7) .. " нед назад" end
  return math.floor(days / 30) .. " мес назад"
end

-- ── проекты и файлы из недавних ─────────────────────────────────────────────

local function home(p) return (p:gsub("^" .. vim.pesc(vim.env.HOME or ""), "~")) end

local function recent(nproj, nfiles)
  local projects, files, seen = {}, {}, {}
  for _, f in ipairs(vim.v.oldfiles) do
    if #projects >= nproj and #files >= nfiles then break end
    if not f:match("/%.git/") and not f:match("^%a+://") and vim.uv.fs_stat(f) then
      local root = vim.fs.root(f, ".git")
      if root and not seen[root] and #projects < nproj then
        seen[root] = true
        projects[#projects + 1] = root
      end
      if #files < nfiles then files[#files + 1] = { path = f, root = root } end
    end
  end
  return projects, files
end

-- git о проекте — в фоне, раз в полминуты; ответ пришёл — экран дорисовывается
local git, waiting = {}, {}
local function git_info(dir, on_ready)
  local c = git[dir]
  if c and (vim.uv.now() - c.at) < 30000 then return c end
  if waiting[dir] then return c end
  waiting[dir] = true
  local res = {}
  local pending = 2
  local function done()
    pending = pending - 1
    if pending > 0 then return end
    waiting[dir] = nil
    res.at = vim.uv.now()
    git[dir] = res
    vim.schedule(on_ready)
  end
  vim.system({ "git", "-C", dir, "status", "--porcelain=v1", "--branch" }, { text = true }, function(r)
    local lines = vim.split(r.stdout or "", "\n", { trimempty = true })
    if lines[1] then
      res.branch = lines[1]:match("^## No commits yet on (%S+)") or lines[1]:match("^## ([^%s%.]+)")
      res.ahead = tonumber(lines[1]:match("ahead (%d+)"))
      res.changed = #lines - 1
    end
    done()
  end)
  vim.system({ "git", "-C", dir, "log", "-1", "--format=%ct" }, { text = true }, function(r)
    res.last = tonumber(vim.trim(r.stdout or ""))
    done()
  end)
  return c
end

-- ── советы ──────────────────────────────────────────────────────────────────

local TIPS = {
  { "пробел sp", "поиск по проекту с заменой — слева, как в VS Code" },
  { "пробел ge", "изменения git: индекс, diff, коммит, не выходя из редактора" },
  { "пробел r x", "▶ запустить main или тест, где курсор; r X — в отладчике" },
  { "пробел tv", "тесты в фоне: какие упали и где — одним списком" },
  { "пробел bu", "вернуть случайно закрытый файл" },
  { "alt-s", "выбрать тему с предпросмотром на всём редакторе" },
  { "пробел u S", "сравнить тему с мягким фильтром и без" },
  { "пробел uq", "тихий режим: без подсказок, крошек и анимаций" },
  { ":Smooth", "проверить плавность и посмотреть демо" },
  { "gpd", "посмотреть объявление, не уходя из файла" },
  { "пробел ca", "исправления и действия под курсором" },
  { "пробел r m", "миграции: новая, up, down, статус — down пишется сам" },
  { "alt-t", "задачи проекта: тесты, линтеры, сборка, docker" },
  { "пробел D", "база данных проекта: таблицы, запросы, подключение из .env" },
  { "пробел ux", "расширения: включить или выключить модуль одной клавишей" },
  { "cmd-,", "все настройки списком, с поиском и описанием" },
  { "пробел R m", "Rust: раскрыть макрос под курсором" },
  { "пробел c t", "вписать подсказку типа в код" },
  { "пробел пробел", "найти что угодно: файл, символ, команду, тему" },
}

local function tip()
  local t = TIPS[(tonumber(os.date("%j")) % #TIPS) + 1] -- один совет на день
  return { { "\u{f0eb}  ", "OwnDashGrad1" }, { t[1], "OwnDashKey" }, { "  —  " .. t[2], "OwnDashTagline" } }
end

-- ── разделы ─────────────────────────────────────────────────────────────────

local function key(k) return { { "[", "OwnDashKeyBracket" }, { k, "OwnDashKey" }, { "]", "OwnDashKeyBracket" } } end

-- строка: слева куски, справа клавиша (или подпись) — прижата к правому краю
local function row(left, right, inner)
  local line = vim.deepcopy(left)
  local rw = width(right)
  local lw = width(line)
  if lw + rw + 1 > inner then
    -- обрезать последний кусок слева, чтобы влезла клавиша
    local last = line[#line]
    last[1] = trunc(last[1], math.max(1, W(last[1]) - (lw + rw + 1 - inner)))
    lw = width(line)
  end
  line[#line + 1] = { (" "):rep(math.max(1, inner - lw - rw)) }
  vim.list_extend(line, right)
  return line
end

local function start_rows(buttons, inner)
  local rows = {}
  for _, b in ipairs(buttons) do
    rows[#rows + 1] = row({ { (b.icon or " ") .. "  ", "OwnDashGrad3" }, { b.desc or b["do"] or "", "Normal" } }, key(b.key), inner)
  end
  return rows
end

local function today_rows(inner)
  local rows = {}
  local ok, stats = pcall(function() return require("lazy.stats").stats() end)
  if ok and stats then
    rows[#rows + 1] = { { "\u{f0e7}  ", "OwnDashGrad2" }, { "старт  ", "OwnDashTagline" }, { ("%d мс"):format(math.floor(stats.startuptime + 0.5)), "Normal" } }
  end
  rows[#rows + 1] = { { "\u{f1fc}  ", "OwnDashGrad3" }, { "тема   ", "OwnDashTagline" }, { vim.g.colors_name or "—", "Normal" } }
  local soft = package.loaded["own.modules.soft"]
  local lvl = soft and soft.night_level() or 0
  rows[#rows + 1] = lvl > 0
    and { { "\u{f0594}  ", "OwnDashGrad4" }, { "вечер  ", "OwnDashTagline" }, { ("тема теплее · %d%%"):format(math.floor(lvl * 100 + 0.5)), "Normal" } }
    or { { "\u{f0599}  ", "OwnDashGrad4" }, { "день   ", "OwnDashTagline" }, { "мягкий фильтр", "Normal" } }
  local rest = (settings.current or {}).modules and settings.enabled(settings.current, "rest")
  if rest then
    rows[#rows + 1] = { { "\u{f06e}  ", "OwnDashGrad5" }, { "глаза  ", "OwnDashTagline" }, { "вдаль каждые 20 мин", "Normal" } }
  end
  for i, r in ipairs(rows) do rows[i] = pad(r, inner) end
  return rows
end

local function project_rows(list, inner, redraw)
  local rows = {}
  for i, dir in ipairs(list) do
    local g = git_info(dir, redraw) or {}
    local right = {}
    if g.branch then
      right[#right + 1] = { "\u{e725} " .. trunc(g.branch, 14), "OwnDashBranch" }
      if g.ahead and g.ahead > 0 then right[#right + 1] = { " ↑" .. g.ahead, "DiagnosticWarn" } end
      right[#right + 1] = (g.changed or 0) > 0 and { " ● " .. g.changed, "DiagnosticWarn" } or { " ✓", "DiagnosticOk" }
      right[#right + 1] = { "  " .. ago(g.last), "OwnDashTagline" }
    else
      right[#right + 1] = { "…", "OwnDashTagline" }
    end
    local name = vim.fs.basename(dir)
    local parent = home(vim.fs.dirname(dir))
    local left = { { tostring(i % 10) .. "  ", "OwnDashKey" }, { "\u{f07b} ", "OwnDashGrad" .. math.min(GRADIENT, i + 1) }, { name, "Normal" }, { "  " .. parent, "OwnDashTagline" } }
    rows[#rows + 1] = row(left, right, inner)
  end
  if #rows == 0 then rows[1] = { { "откройте папку проекта — она появится здесь", "OwnDashTagline" } } end
  return rows
end

local function file_rows(list, first, inner)
  local rows = {}
  for i, f in ipairs(list) do
    local ic = Snacks.dashboard.icon(f.path, "file")
    local rel = f.root and f.path:sub(#f.root + 2) or home(f.path)
    local dir = vim.fs.dirname(rel)
    local where = f.root and (vim.fs.basename(f.root) .. ((dir ~= "." and dir ~= "") and (" · " .. dir) or "")) or dir
    local st = vim.uv.fs_stat(f.path)
    local left = { { tostring((first + i - 1) % 10) .. "  ", "OwnDashKey" }, { ic[1] .. " ", ic.hl }, { vim.fs.basename(f.path), "Normal" }, { "  " .. where, "OwnDashTagline" } }
    rows[#rows + 1] = row(left, { { st and ago(st.mtime.sec) or "", "OwnDashTagline" } }, inner)
  end
  if #rows == 0 then rows[1] = { { "здесь будут недавние файлы", "OwnDashTagline" } } end
  return rows
end

-- ── сборка ──────────────────────────────────────────────────────────────────

local function hl_define()
  local function c(g, a) return vim.api.nvim_get_hl(0, { name = g, link = false })[a or "fg"] end
  local color = require("own.theme.color")
  local hx = function(v) return v and ("#%06x"):format(v) end
  local bg = hx(c("Normal", "bg")) or "#000000"
  local frame = hx(c("Comment")) or "#666666"
  vim.api.nvim_set_hl(0, "OwnDashFrame", { fg = color.blend(frame, bg, 0.7) })
  vim.api.nvim_set_hl(0, "OwnDashTitle", { fg = c("OwnDashKey") or c("Title"), bold = true })
  vim.api.nvim_set_hl(0, "OwnDashBranch", { fg = c("Function") or c("Title") })
end

--- Раздел для snacks.dashboard: весь экран одним текстом; клавиши — скрытыми пунктами (keys())
function M.section(self)
  hl_define()
  local o = d()
  local cols = (self and self._size and self._size.width) or vim.o.columns
  local two = cols >= 108
  local LW, RW, GAP = 30, 62, 4
  local inner_l, inner_r = LW - 4, RW - 4
  if not two then
    LW = math.min(cols - 4, 66)
    RW, inner_l = LW, LW - 4
    inner_r = inner_l
  end
  local total = two and (LW + GAP + RW) or LW
  if self and self.opts then self.opts.width = total end

  local redraw = function() if self and self.update then pcall(self.update, self) end end
  local projects, files = recent(o.projects or 5, o.recent or 5)
  M._projects, M._files = projects, files

  local left = {}
  vim.list_extend(left, box("Начать", start_rows(o.buttons or {}, inner_l), inner_l))
  vim.list_extend(left, box("Сегодня", today_rows(inner_l), inner_l))
  local right = {}
  vim.list_extend(right, box("Проекты", project_rows(projects, inner_r, redraw), inner_r))
  vim.list_extend(right, box("Недавние файлы", file_rows(files, #projects + 1, inner_r), inner_r))

  local lines = {}
  local function center(line)
    local w = width(line)
    local l = vim.deepcopy(line)
    table.insert(l, 1, { (" "):rep(math.max(0, math.floor((total - w) / 2))) })
    return l
  end
  local header = o.header_lines or LOGO
  for _, l in ipairs(logo(header)) do lines[#lines + 1] = center(l) end
  lines[#lines + 1] = {}
  lines[#lines + 1] = center(greeting())
  lines[#lines + 1] = {}
  lines[#lines + 1] = {}
  if two then
    for i = 1, math.max(#left, #right) do
      local line = pad(vim.deepcopy(left[i] or {}), LW)
      line[#line + 1] = { (" "):rep(GAP) }
      vim.list_extend(line, right[i] or {})
      lines[#lines + 1] = line
    end
  else
    -- узко: проекты и файлы — первыми (за ними и приходят), действия — ниже
    for _, l in ipairs(right) do lines[#lines + 1] = l end
    for _, l in ipairs(box("Начать", start_rows(o.buttons or {}, inner_l), inner_l)) do lines[#lines + 1] = l end
  end
  lines[#lines + 1] = {}
  lines[#lines + 1] = center(tip())

  -- в формат snacks: куски с переводами строк
  local text = {}
  for i, line in ipairs(lines) do
    for _, c in ipairs(line) do text[#text + 1] = { c[1], hl = c[2] } end
    if i < #lines then text[#text + 1] = { "\n" } end
  end
  return { text = text, align = "left" }
end

--- Клавиши: кнопки, проекты (1…5), файлы (6…0) — скрытые пункты snacks, видны в рамках
function M.keys(buttons)
  local items = {}
  for _, b in ipairs(buttons) do
    local what = b["do"] or ""
    local action = what
    local fn = require("own.actions").get(what)
    if fn then
      action = type(fn) == "function" and fn or function() vim.api.nvim_feedkeys(vim.keycode(fn), "m", false) end
    end
    items[#items + 1] = { key = b.key, action = action, hidden = true }
  end
  for i = 1, 10 do
    items[#items + 1] = {
      key = tostring(i % 10), hidden = true,
      action = function()
        local p = M._projects or {}
        if i <= #p then
          -- проект: туда, и вернуть его сессию (вкладки, разбиения); сессии нет — выбрать файл
          vim.cmd.cd(vim.fn.fnameescape(p[i]))
          local ok, s = pcall(require, "own.modules.sessions")
          if ok and s.exists and s.exists(p[i]) then return s.load() end
          return Snacks.picker.files({ cwd = p[i] })
        end
        local f = (M._files or {})[i - #p]
        if f then vim.cmd.edit(vim.fn.fnameescape(f.path)) end
      end,
    }
  end
  return items
end

return M
