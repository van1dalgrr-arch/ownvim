-- «Поиск» — как панель Search в VS Code: слева запрос и совпадения по файлам, с заменой во всём проекте.
--   i или / — новый запрос        enter — к совпадению        r — заменить всё найденное (спросит на что и подтверждение)
--   c — учитывать регистр         w — слово целиком            x — регулярное выражение        R — искать заново
--   на строке файла: enter — свернуть / развернуть его совпадения
-- Ищет ripgrep по корню проекта (.gitignore учитывается). Открыть: пробел s p или значок над левой панелью;
-- в визуальном режиме — сразу ищет выделенное.
local root = require("own.root")

local M = {}

local ns = vim.api.nvim_create_namespace("own.search")
local state = { buf = nil, dir = nil, query = "", case = false, word = false, regex = false, files = {}, items = {}, total = 0, job = nil }
local MAX = 2000 -- больше совпадений в панели не нужно — уточни запрос

function M.win()
  if not state.buf then return nil end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(w) == state.buf then return w end
  end
end

local function flags()
  local on = {}
  if state.case then on[#on + 1] = "Aa" end
  if state.word then on[#on + 1] = "слово" end
  if state.regex then on[#on + 1] = ".*" end
  return #on > 0 and ("  [" .. table.concat(on, " ") .. "]") or ""
end

local function render(note)
  local buf = state.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  local lines, items, marks = {}, {}, {}
  local function add(text, hl, item)
    lines[#lines + 1] = text
    if item then items[#lines] = item end
    if hl then marks[#marks + 1] = { #lines - 1, 0, #text, hl } end
  end
  add(" \u{ea6d} " .. (state.query ~= "" and state.query or "i — что искать") .. flags(), state.query ~= "" and "Title" or "Comment")
  add(" i запрос · r замена · c w x режимы", "Comment")
  if note then
    add("")
    add(" " .. note, "Comment")
  elseif state.query ~= "" then
    add("")
    add((" %d в %d файлах%s"):format(state.total, #state.files, state.total >= MAX and " (показаны первые)" or ""), "OwnSideTitle")
    for _, f in ipairs(state.files) do
      local name, dirname = vim.fs.basename(f.path), vim.fs.dirname(f.path)
      local head = (" %s %s"):format(f.closed and "\u{eab6}" or "\u{eab4}", name)
      add(head .. (dirname ~= "." and ("  " .. dirname) or "") .. "  " .. #f.matches, nil, { file = f })
      marks[#marks + 1] = { #lines - 1, 0, #head, "Directory" }
      marks[#marks + 1] = { #lines - 1, #head, #lines[#lines], "Comment" }
      if not f.closed then
        for _, m in ipairs(f.matches) do
          local indent = m.text:match("^%s*") or ""
          local text = m.text:sub(#indent + 1)
          local prefix = ("   %d: "):format(m.lnum)
          add(prefix .. text, nil, { file = f, match = m })
          marks[#marks + 1] = { #lines - 1, 0, #prefix, "LineNr" }
          for _, s in ipairs(m.subs) do
            local from, to = #prefix + s[1] - #indent, #prefix + s[2] - #indent
            if from >= #prefix then marks[#marks + 1] = { #lines - 1, from, to, "Search" } end
          end
        end
      end
    end
  end
  local w = M.win()
  local row = w and vim.api.nvim_win_get_cursor(w)[1] or 1
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  state.items = items
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local len = #lines[m[1] + 1]
    if m[2] < math.min(m[3], len) then
      vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = math.min(m[3], len), hl_group = m[4] })
    end
  end
  if w then pcall(vim.api.nvim_win_set_cursor, w, { math.min(row, #lines), 0 }) end
end

-- вывод rg --json → файлы с совпадениями (смещения совпадений — в байтах строки, для точной замены)
local function parse(out)
  local files, by_path, total = {}, {}, 0
  for line in out:gmatch("[^\n]+") do
    local ok, ev = pcall(vim.json.decode, line)
    if ok and ev.type == "match" and ev.data.path.text and ev.data.lines.text then
      local path = ev.data.path.text:gsub("^%./", "")
      local f = by_path[path]
      if not f then
        f = { path = path, matches = {} }
        by_path[path] = f
        files[#files + 1] = f
      end
      local subs = {}
      for _, s in ipairs(ev.data.submatches or {}) do subs[#subs + 1] = { s.start, s["end"] } end
      f.matches[#f.matches + 1] = { lnum = ev.data.line_number, text = (ev.data.lines.text:gsub("\r?\n$", "")), subs = subs }
      total = total + 1
      if total >= MAX then break end
    end
  end
  return files, total
end

function M.run()
  if state.query == "" then return render() end
  if state.job then pcall(function() state.job:kill(15) end) end
  local cmd = { "rg", "--json", "--max-columns", "400", "--max-count", "200" }
  cmd[#cmd + 1] = state.case and "--case-sensitive" or "--smart-case"
  if state.word then cmd[#cmd + 1] = "--word-regexp" end
  if not state.regex then cmd[#cmd + 1] = "--fixed-strings" end
  vim.list_extend(cmd, { "--", state.query, "." })
  render("ищу…")
  local job
  job = vim.system(cmd, { text = true, cwd = state.dir }, vim.schedule_wrap(function(r)
    if state.job ~= job then return end -- уже запущен новый поиск
    state.job = nil
    if r.code > 1 then
      state.files, state.total = {}, 0
      return render("не получилось: " .. vim.trim((r.stderr or ""):match("[^\n]*") or ""))
    end
    state.files, state.total = parse(r.stdout or "")
    render(state.total == 0 and "ничего не найдено" or nil)
  end))
  state.job = job
end

function M.ask(default)
  vim.ui.input({ prompt = "Искать в проекте: ", default = default or state.query }, function(q)
    if not q or q == "" then return end
    state.query = q
    M.run()
  end)
end

local function code_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then return w end
  end
end

local function item()
  local w = M.win()
  return w and state.items[vim.api.nvim_win_get_cursor(w)[1]] or nil
end

local function jump()
  local it = item()
  if not it then return end
  if not it.match then
    it.file.closed = not it.file.closed
    return render()
  end
  local w = code_win()
  if w then vim.api.nvim_set_current_win(w) else vim.cmd("rightbelow vsplit") end
  vim.cmd.edit(vim.fn.fnameescape(state.dir .. "/" .. it.file.path))
  local col = it.match.subs[1] and it.match.subs[1][1] or 0
  pcall(vim.api.nvim_win_set_cursor, 0, { it.match.lnum, col })
  vim.cmd("normal! zz")
end

--- Заменить все найденные совпадения. Правятся ровно те места, что нашёл ripgrep; строка, которая с тех пор
--- изменилась, пропускается. Возвращает число замен и файлов.
function M.replace(with)
  local changed, nfiles, skipped = 0, 0, 0
  for _, f in ipairs(state.files) do
    local buf = vim.fn.bufadd(state.dir .. "/" .. f.path)
    vim.fn.bufload(buf)
    local touched = false
    for _, m in ipairs(f.matches) do
      local line = vim.api.nvim_buf_get_lines(buf, m.lnum - 1, m.lnum, false)[1]
      if line == m.text then
        for i = #m.subs, 1, -1 do -- с конца строки, чтобы смещения не поехали
          line = line:sub(1, m.subs[i][1]) .. with .. line:sub(m.subs[i][2] + 1)
          changed = changed + 1
        end
        vim.api.nvim_buf_set_lines(buf, m.lnum - 1, m.lnum, false, { line })
        touched = true
      else
        skipped = skipped + 1
      end
    end
    if touched then
      nfiles = nfiles + 1
      vim.api.nvim_buf_call(buf, function() vim.cmd("silent! update") end)
    end
  end
  return changed, nfiles, skipped
end

local function replace_ask()
  if state.total == 0 then return vim.notify("сначала найди, что менять (i)") end
  if state.total >= MAX then return vim.notify("совпадений слишком много — уточни запрос, заменяется только показанное") end
  vim.ui.input({ prompt = ("Заменить «%s» на: "):format(state.query) }, function(with)
    if with == nil then return end
    local msg = ("Заменить %d совпадений в %d файлах на «%s»?"):format(state.total, #state.files, with)
    if vim.fn.confirm(msg, "&Да\n&Нет", 2) ~= 1 then return end
    local n, nf, skipped = M.replace(with)
    vim.notify(("заменено %d в %d файлах%s (u в файле — отменить)"):format(n, nf, skipped > 0 and (", пропущено изменившихся строк: " .. skipped) or ""))
    M.run()
  end)
end

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "own_search"
  vim.bo[buf].bufhidden = "hide"
  local function map(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true, desc = desc }) end
  local function flip(key) return function() state[key] = not state[key]; M.run() end end
  map("<cr>", jump, "К совпадению / свернуть файл")
  map("o", jump, "К совпадению / свернуть файл")
  map("<2-LeftMouse>", jump, "К совпадению")
  map("i", function() M.ask() end, "Новый запрос")
  map("/", function() M.ask() end, "Новый запрос")
  map("r", replace_ask, "Заменить всё найденное")
  map("R", M.run, "Искать заново")
  map("c", flip("case"), "Учитывать регистр")
  map("w", flip("word"), "Слово целиком")
  map("x", flip("regex"), "Регулярное выражение")
  return buf
end

--- Открыть панель (рабочее место ставит её слева)
function M.open()
  state.dir = root.get()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then state.buf = make_buf() end
  local settings = require("own.settings")
  local width = settings.module_opts(settings.current or {}, "workspace").left_width or 32
  vim.cmd("topleft " .. width .. "vsplit")
  vim.api.nvim_win_set_buf(0, state.buf)
  local wo = vim.wo[0]
  wo.number, wo.relativenumber, wo.statuscolumn, wo.cursorline, wo.wrap, wo.list = false, false, "", true, false, false
  render()
end

--- Для тестов и действий: задать запрос и искать
function M.search(query)
  state.query = query
  M.run()
end

M.state = state

return M
