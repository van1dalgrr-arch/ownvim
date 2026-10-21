-- Расширения на Go (core/extensions/*, пакет core/sdk): их команды, клавиши и события — в ownvim.
-- На старте — из манифеста (own-ext.json, без запуска Go), срабатывание — через мост (vim.rpcnotify, в фоне).
-- Сохранили .go в core/ — ядро пересобирается, расширения перерегистрируются без перезапуска;
-- ошибки компиляции — на строках Go-файлов. :GoExtensionNew имя — заготовка. Руководство — docs/go-extensions.md.
-- M.api — то, что Go зовёт обратно (sdk.Ctx → ExecLua): строки, надписи, замечания, окна, уведомления.
local M = {}

local core = require("own.core")
local data = vim.fn.stdpath("data")
local manifest_path = data .. "/own-ext.json"
local JSON = { luanil = { object = true, array = true } }

local registered = { commands = {}, keys = {} }
M.manifest = nil

local function stamp_of(p)
  local st = vim.uv.fs_stat(p)
  return st and ("%d.%09d:%d"):format(st.mtime.sec, st.mtime.nsec, st.size) or "-"
end

-- ── что выполнить и с каким контекстом ───────────────────────────────────────

-- настройки расширения: "extensions": { "<имя>": {…} }; у встроенных — ещё и "modules": { "<имя>": {…} }
local function ext_settings(ext)
  local s = require("own.settings").current or {}
  local out = {}
  local m = (s.modules or {})[ext]
  if type(m) == "table" then out = vim.deepcopy(m) end
  local e = (s.extensions or {})[ext]
  if type(e) == "table" then out = vim.tbl_extend("force", out, e) end
  out.enabled = nil
  return next(out) and out or vim.empty_dict()
end

-- расширение выключено: "extensions": { "<имя>": false } или "modules": { "<имя>": false }
local MODULE_OF = { endpoints = "http" } -- расширение → модуль, которым оно включается (было частью модуля)

local function disabled(ext)
  local s = require("own.settings").current or {}
  local e, m = (s.extensions or {})[ext], (s.modules or {})[MODULE_OF[ext] or ext]
  return e == false or m == false or (type(m) == "table" and m.enabled == false)
end

local function context(ext, opts, ev)
  local buf = ev and ev.buf or vim.api.nvim_get_current_buf()
  local s, e = 0, 0
  if opts and opts.range and opts.range > 0 then
    s, e = opts.line1, opts.line2
  else
    local mode = vim.fn.mode()
    if mode:match("[vV\22]") then
      s, e = vim.fn.line("v"), vim.fn.line(".")
      if s > e then s, e = e, s end
      vim.cmd("normal! \27")
    end
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  return {
    ext = ext,
    buf = buf,
    file = vim.api.nvim_buf_get_name(buf),
    root = require("own.root").get(),
    filetype = vim.bo[buf].filetype,
    word = vim.fn.expand("<cword>"),
    line = cur[1],
    col = cur[2] + 1,
    sel_start = s,
    sel_end = e,
    event = ev and ev.event or "",
    match = ev and ev.match or "",
    settings = ext_settings(ext),
    data = data,
    args = vim.empty_dict(),
  }
end

--- Контекст для буфера и позиции (строка и столбец с 1) — для провайдеров (lua/own/ext_lsp.lua)
function M.context_at(ext, buf, line, col)
  local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  local s = col
  while s > 1 and text:sub(s - 1, s - 1):match("[%w_]") do s = s - 1 end
  local e = col
  while e <= #text and text:sub(e, e):match("[%w_]") do e = e + 1 end
  return {
    ext = ext, buf = buf, file = vim.api.nvim_buf_get_name(buf), root = require("own.root").get(),
    filetype = vim.bo[buf].filetype, word = text:sub(s, e - 1), line = line, col = col,
    sel_start = 0, sel_end = 0, event = "", match = "", settings = ext_settings(ext), data = data, args = vim.empty_dict(),
  }
end

M.disabled = function(ext) return disabled(ext) end

local function dispatch(id, ctx)
  local ok, err = pcall(core.notify, "ext.run", id, ctx)
  if not ok then vim.notify("Go-расширение " .. id .. ": " .. tostring(err), vim.log.levels.ERROR) end
end

-- ── регистрация из манифеста ─────────────────────────────────────────────────

local function unregister()
  for _, name in ipairs(registered.commands) do pcall(vim.api.nvim_del_user_command, name) end
  for _, k in ipairs(registered.keys) do pcall(vim.keymap.del, k[1], k[2]) end
  registered = { commands = {}, keys = {} }
  vim.api.nvim_create_augroup("own.ext.events", { clear = true })
end

local function register(m)
  unregister()
  local by_name = {}
  for _, c in ipairs(m.commands or {}) do
    if disabled(c.ext) then goto continue end
    by_name[c.name] = c
    vim.api.nvim_create_user_command(c.name, function(a) dispatch(c.name, context(c.ext, a)) end,
      { range = true, desc = c.desc .. " (Go: " .. c.ext .. ")" })
    registered.commands[#registered.commands + 1] = c.name
    ::continue::
  end
  for _, k in ipairs(m.keys or {}) do
    local c = by_name[k.command]
    if c then
      for mode in k.modes:gmatch(".") do
        vim.keymap.set(mode, k.lhs, function() dispatch(c.name, context(c.ext)) end, { desc = c.desc })
        registered.keys[#registered.keys + 1] = { mode, k.lhs }
      end
    end
  end
  local group = vim.api.nvim_create_augroup("own.ext.events", { clear = true })
  for _, e in ipairs(m.events or {}) do
    if disabled(e.ext) then goto next_event end
    vim.api.nvim_create_autocmd(e.events, {
      group = group,
      pattern = vim.split(e.pattern, ",", { trimempty = true }),
      callback = function(ev) dispatch(e.id, context(e.ext, nil, ev)) end,
    })
    ::next_event::
  end
  for _, p in ipairs(m.problems or {}) do vim.notify("Go-расширения: " .. p, vim.log.levels.WARN) end
end

-- манифест: из кэша, если программа та же; иначе — спросить ownvimd
local function load_manifest(force)
  local stamp = stamp_of(core.bin)
  if not force then
    local f = io.open(manifest_path)
    if f then
      local ok, m = pcall(vim.json.decode, f:read("*a"), JSON)
      f:close()
      if ok and type(m) == "table" and m.stamp == stamp then return m end
    end
  end
  local r = core.run({ "extensions", "manifest" })
  if not r or r.code ~= 0 then return nil end
  local ok, m = pcall(vim.json.decode, r.stdout, JSON)
  if not ok or type(m) ~= "table" then return nil end
  m.stamp = stamp
  local f = io.open(manifest_path, "w")
  if f then f:write(vim.json.encode(m)); f:close() end
  return m
end

M.dispatch = function(id, ctx) dispatch(id, ctx) end

function M.reload(force)
  local m = load_manifest(force)
  if m then
    M.manifest = m
    register(m)
    require("own.ext_lsp").refresh(m)
  end
end

--- Позвать функцию расширения (sdk.Func) — в фоне; результат она отдаст через c.Publish → M.data[key]
M.data = {}
function M.call(name, args, ext)
  if not vim.uv.fs_stat(core.bin) then return end
  local ctx = context(ext or "", nil, nil)
  ctx.args = args and next(args) and args or vim.empty_dict()
  dispatch(name, ctx)
end

-- ── API для Go (sdk.Ctx) ─────────────────────────────────────────────────────

local COLORS = { red = "DiagnosticError", orange = "DiagnosticWarn", yellow = "DiagnosticWarn", green = "DiagnosticOk",
  blue = "DiagnosticInfo", purple = "Special", grey = "Comment", gray = "Comment" }
local SEVERITY = { error = 1, warn = 2, info = 3, hint = 4 }

M.api = {}

function M.api.notify(msg, level, title)
  vim.schedule(function()
    vim.notify(msg, vim.log.levels[(level or "info"):upper()] or vim.log.levels.INFO, { title = title })
  end)
end

-- строки from..to (с 1, to = -1 — до конца)
function M.api.lines(buf, from, to)
  if not vim.api.nvim_buf_is_valid(buf) then return {} end
  return vim.api.nvim_buf_get_lines(buf, from - 1, to == -1 and -1 or to, false)
end

function M.api.set_lines(buf, from, to, lines)
  vim.api.nvim_buf_set_lines(buf, from - 1, to == -1 and -1 or to, false, lines)
end

function M.api.marks(buf, ext, marks)
  local ns = vim.api.nvim_create_namespace("own.ext." .. ext)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks or {}) do
    local chunks = {}
    for _, p in ipairs(m.parts or {}) do chunks[#chunks + 1] = { p.text, COLORS[p.color] or (p.color ~= "" and p.color) or "Comment" } end
    if #chunks == 0 then chunks = { { m.text, COLORS[m.color] or (m.color ~= "" and m.color) or "Comment" } } end
    if not m.right then table.insert(chunks, 1, { "  ", "Normal" }) end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.line - 1, 0, {
      virt_text = chunks,
      virt_text_pos = m.right and "right_align" or "eol",
      hl_mode = "combine",
    })
  end
end

function M.api.problems(buf, ext, list)
  local ns = vim.api.nvim_create_namespace("own.ext." .. ext .. ".problems")
  local diags = {}
  for _, p in ipairs(list or {}) do
    diags[#diags + 1] = { lnum = p.line - 1, col = math.max((p.col or 1) - 1, 0), message = p.message,
      severity = SEVERITY[p.severity] or 2, source = ext }
  end
  vim.diagnostic.set(ns, buf, diags)
end

function M.api.window(title, lines, ft)
  vim.schedule(function()
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    if ft and ft ~= "" then vim.bo[b].filetype = ft end
    vim.bo[b].modifiable = false
    vim.cmd("botright 12split")
    vim.api.nvim_win_set_buf(0, b)
    vim.wo.winbar = " " .. (title or "")
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = b })
  end)
end

function M.api.open(file, line)
  vim.schedule(function()
    vim.cmd.edit(vim.fn.fnameescape(file))
    if line and line > 0 then pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 }) end
  end)
end

local function reply(id, value) pcall(core.notify, "ext.reply", id, value == nil and vim.NIL or value) end

function M.api.select(id, prompt, items)
  vim.schedule(function()
    vim.ui.select(items, { prompt = prompt }, function(_, idx) reply(id, idx or 0) end)
  end)
end

function M.api.input(id, prompt, default)
  vim.schedule(function()
    vim.ui.input({ prompt = prompt .. " ", default = default }, function(text) reply(id, text) end)
  end)
end

-- к определению символа под курсором через LSP (сервер мог ещё не подключиться к только что открытому файлу)
local function goto_definition()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local function jump(client)
    local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
    client:request("textDocument/definition", params, function(_, result)
      local loc = vim.islist(result) and result[1] or result
      if loc and vim.api.nvim_get_current_win() == win then vim.lsp.util.show_document(loc, client.offset_encoding, { focus = true }) end
    end, buf)
  end
  local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/definition" })[1]
  if client then return jump(client) end
  vim.api.nvim_create_autocmd("LspAttach", {
    buffer = buf,
    once = true,
    callback = function(ev)
      local c = vim.lsp.get_client_by_id(ev.data.client_id)
      if c and c:supports_method("textDocument/definition") then jump(c) end
    end,
  })
end

function M.api.pick(id, title, list, opts)
  vim.schedule(function()
    local items = {}
    for i, it in ipairs(list) do
      items[#items + 1] = {
        idx = i,
        text = table.concat({ it.tag or "", it.text or "", it.hint or "" }, " "),
        file = it.file ~= "" and it.file or nil,
        pos = it.file ~= "" and { math.max(it.line or 1, 1), math.max((it.col or 1) - 1, 0) } or nil,
        item = it,
      }
    end
    local answered = false
    local function answer(idx, action)
      if answered then return end
      answered = true
      reply(id, { idx, action })
    end
    local actions, keys = {}, {}
    for lhs, name in pairs(opts.keys or {}) do
      actions["own_" .. name] = function(picker, item)
        picker:close()
        answer(item and item.idx or 0, name)
      end
      keys[lhs] = { "own_" .. name, mode = { "n", "i" } }
    end
    actions.own_copy = function(_, item)
      if item and item.item.copy ~= "" then
        vim.fn.setreg("+", item.item.copy)
        vim.notify(item.item.copy, vim.log.levels.INFO, { title = "скопировано" })
      end
    end
    keys["<c-y>"] = { "own_copy", mode = { "n", "i" } }
    Snacks.picker.pick({
      title = title,
      items = items,
      preview = "file",
      format = function(item)
        local it = item.item
        local out = {}
        if it.tag ~= "" then out[#out + 1] = { ("%-7s"):format(it.tag), COLORS[it.color] or (it.color ~= "" and it.color) or "Special" } end
        out[#out + 1] = { it.text, "Title" }
        if it.hint ~= "" then out[#out + 1] = { "  " .. it.hint, "Comment" } end
        return out
      end,
      confirm = function(picker, item)
        picker:close()
        if not item then return answer(0, "") end
        answer(item.idx, "open")
        if item.file then
          vim.schedule(function()
            vim.cmd.edit(vim.fn.fnameescape(item.file))
            pcall(vim.api.nvim_win_set_cursor, 0, item.pos)
            if opts.definition then goto_definition() end
          end)
        end
      end,
      on_close = function() vim.schedule(function() answer(0, "") end) end,
      actions = actions,
      win = { input = { keys = keys } },
    })
  end)
end

function M.api.terminal(cmd, cwd)
  vim.schedule(function()
    Snacks.terminal(cmd, { cwd = cwd, auto_close = false, win = { position = "bottom", height = 0.35 } })
  end)
end

-- клавиша в буфере: срабатывание — в Go (id), там решают, «своя» ли она (иначе — fallback)
function M.api.map(buf, mode, lhs, desc, id, ext)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.keymap.set(mode, lhs, function() dispatch(id, context(ext)) end, { buffer = buf, desc = desc })
end

-- то, что висит на клавише без буферной привязки: глобальная привязка или встроенное действие
function M.api.fallback(mode, lhs)
  vim.schedule(function()
    local m = vim.fn.maparg(lhs, mode, false, true)
    if m.buffer == 1 then m = {} end -- своя же буферная — не она
    local global = vim.tbl_filter(function(x) return x.lhs == vim.keycode(lhs) or x.lhsraw == vim.keycode(lhs) end, vim.api.nvim_get_keymap(mode))[1]
    if global and global.callback then return global.callback() end
    if global and global.rhs and global.rhs ~= "" then
      return vim.api.nvim_feedkeys(vim.keycode(global.rhs), global.noremap == 1 and "n" or "m", false)
    end
    vim.api.nvim_feedkeys(vim.keycode(lhs), "n", false)
  end)
end

local panels = {} -- расширение → { buf, win }
function M.api.side_panel(ext, title, lines, ft)
  vim.schedule(function()
    local p = panels[ext] or {}
    if not (p.buf and vim.api.nvim_buf_is_valid(p.buf)) then
      p.buf = vim.api.nvim_create_buf(false, true)
      vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = p.buf, desc = "закрыть" })
    end
    vim.bo[p.buf].modifiable = true
    vim.api.nvim_buf_set_lines(p.buf, 0, -1, false, lines)
    vim.bo[p.buf].modifiable = false
    if ft and ft ~= "" then vim.bo[p.buf].filetype = ft end
    if not (p.win and vim.api.nvim_win_is_valid(p.win)) then
      local from = vim.api.nvim_get_current_win()
      vim.cmd("botright vsplit")
      p.win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(p.win, p.buf)
      vim.api.nvim_set_current_win(from)
    end
    vim.wo[p.win].winbar = " " .. (title or "")
    panels[ext] = p
  end)
end

function M.api.close_side_panel(ext)
  vim.schedule(function()
    local p = panels[ext]
    if p and p.win and vim.api.nvim_win_is_valid(p.win) and #vim.api.nvim_list_wins() > 1 then vim.api.nvim_win_close(p.win, true) end
  end)
end

function M.api.clipboard(text)
  vim.fn.setreg("+", text)
  M.api.notify(text, "info", "скопировано")
end

function M.api.feed(keys)
  vim.schedule(function() vim.api.nvim_feedkeys(vim.keycode(keys), "n", false) end)
end

function M.api.cursor(line, col)
  vim.schedule(function() pcall(vim.api.nvim_win_set_cursor, 0, { line, math.max((col or 1) - 1, 0) }) end)
end

function M.api.publish(key, value)
  vim.schedule(function()
    M.data[key] = value
    vim.api.nvim_exec_autocmds("User", { pattern = "OwnExtData", data = { key = key }, modeline = false })
  end)
end

function M.api.visible()
  local out, cur = {}, vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "" then
      out[#out + 1] = { buf = buf, file = vim.api.nvim_buf_get_name(buf), filetype = vim.bo[buf].filetype,
        line = vim.api.nvim_win_get_cursor(win)[1], current = win == cur }
    end
  end
  return out
end

-- ── панели (sdk.View) ────────────────────────────────────────────────────────

local views = {} -- имя → { buf, win, ext, rows }
local view_ns = vim.api.nvim_create_namespace("own.ext.view")

local function view_open(v, side, size)
  local from = vim.api.nvim_get_current_win()
  if side == "bottom" then
    vim.cmd("botright " .. (size > 0 and size or 12) .. "split")
  elseif side == "left" then
    vim.cmd("topleft " .. (size > 0 and size or 40) .. "vsplit")
  else
    vim.cmd("botright " .. (size > 0 and size or 40) .. "vsplit")
  end
  v.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(v.win, v.buf)
  local wo = vim.wo[v.win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn, wo.foldcolumn = false, false, "no", "", "0"
  wo.wrap, wo.cursorline, wo.winfixwidth, wo.winfixheight, wo.spell, wo.list = false, true, true, true, false, false
  v.from = from
  vim.api.nvim_set_current_win(from)
end

function M.api.view(ext, name, title, side, size, rows, keys, custom_enter, mode)
  vim.schedule(function()
    local v = views[name] or {}
    views[name] = v
    local open = v.win and vim.api.nvim_win_is_valid(v.win)
    if mode == "refresh" and not open then return end
    if mode == "toggle" and open then
      vim.api.nvim_win_close(v.win, true)
      v.win = nil
      return
    end
    if not (v.buf and vim.api.nvim_buf_is_valid(v.buf)) then
      v.buf = vim.api.nvim_create_buf(false, true)
      vim.bo[v.buf].filetype = "ownview"
      vim.bo[v.buf].bufhidden = "hide"
      local function row() return vim.api.nvim_win_get_cursor(0)[1] end
      local function map(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = v.buf, nowait = true, desc = desc }) end
      map("q", function() vim.api.nvim_win_close(0, true) end, "закрыть панель")
      map("R", function() local c = context(ext); c.args = { row = row() }; dispatch("view.show:" .. name, c) end, "обновить")
      v.ext = ext
    end
    v.rows = rows
    -- enter: свой обработчик в Go или открыть файл строки в окне, из которого открыли панель
    pcall(vim.keymap.del, "n", "<cr>", { buffer = v.buf })
    vim.keymap.set("n", "<cr>", function()
      local i = vim.api.nvim_win_get_cursor(0)[1]
      if custom_enter then
        local c = context(ext); c.args = { row = i }
        return dispatch("view|" .. name .. "|<cr>", c)
      end
      local r = v.rows[i]
      if not r or r.file == "" then return end
      local target = v.from and vim.api.nvim_win_is_valid(v.from) and v.from or vim.fn.win_getid(vim.fn.winnr("#"))
      vim.api.nvim_set_current_win(target)
      vim.cmd.edit(vim.fn.fnameescape(r.file))
      if r.line > 0 then pcall(vim.api.nvim_win_set_cursor, 0, { r.line, 0 }) end
    end, { buffer = v.buf, nowait = true, desc = "открыть" })
    for lhs, desc in pairs(keys or {}) do
      vim.keymap.set("n", lhs, function()
        local c = context(ext); c.args = { row = vim.api.nvim_win_get_cursor(0)[1] }
        dispatch("view|" .. name .. "|" .. lhs, c)
      end, { buffer = v.buf, nowait = true, desc = desc })
    end
    -- строки и цвета
    local lines, marks = {}, {}
    for i, r in ipairs(rows) do
      local indent = string.rep("  ", r.depth or 0)
      if r.parts and #r.parts > 0 then
        local text, col = indent, #indent
        for _, p in ipairs(r.parts) do
          marks[#marks + 1] = { i - 1, col, col + #p.text, COLORS[p.color] or (p.color ~= "" and p.color) or nil }
          text = text .. p.text
          col = col + #p.text
        end
        lines[i] = text
      else
        lines[i] = indent .. (r.text or "")
      end
    end
    if #lines == 0 then lines = { "  (пусто)" } end
    vim.bo[v.buf].modifiable = true
    vim.api.nvim_buf_set_lines(v.buf, 0, -1, false, lines)
    vim.bo[v.buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(v.buf, view_ns, 0, -1)
    for _, m in ipairs(marks) do
      if m[4] then pcall(vim.api.nvim_buf_set_extmark, v.buf, view_ns, m[1], m[2], { end_col = m[3], hl_group = m[4] }) end
    end
    if not open then view_open(v, side, size or 0) end
    local hint = {}
    for lhs, desc in pairs(keys or {}) do hint[#hint + 1] = lhs .. " " .. desc end
    table.sort(hint)
    vim.wo[v.win].winbar = " " .. (title or name) .. "  %#Comment#" .. table.concat(vim.list_extend({ "⏎ открыть" }, hint), " · ") .. " · R обновить · q закрыть"
  end)
end

-- ── статусная строка (c.SetStatus) и замечания в файле (c.ProblemsFor) ──────

M.status = {} -- расширение → { text, color, filetypes }

function M.api.status(ext, text, color, filetypes)
  M.status[ext] = text ~= "" and { text = text, color = color, filetypes = filetypes or {} } or nil
  vim.schedule(function() pcall(vim.cmd.redrawstatus) end)
end

--- Надписи расширений для текущего буфера (statusline: блок ext) → { { text, color } }
function M.status_for(buf)
  local ft = vim.bo[buf].filetype
  local out = {}
  for ext, s in vim.spairs(M.status) do
    if not disabled(ext) and (#s.filetypes == 0 or vim.tbl_contains(s.filetypes, ft)) then out[#out + 1] = s end
  end
  return out
end

function M.api.problems_file(path, ext, list)
  local buf = vim.fn.bufnr(path)
  if buf == -1 then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.fn.resolve(vim.api.nvim_buf_get_name(b)) == vim.fn.resolve(path) then buf = b end
    end
  end
  if buf == -1 or not vim.api.nvim_buf_is_loaded(buf) then return end
  M.api.problems(buf, ext, list)
end

-- ── заготовка нового расширения ──────────────────────────────────────────────

local TEMPLATE = [[
// Package %s — моё расширение ownvim на Go.
//
// Как устроено: в init() регистрируете команды (sdk.Command), клавиши (sdk.Key) и реакции на события (sdk.On).
// Сохранили файл — ownvim пересоберёт ядро и подхватит изменения сам; ошибка компиляции — подсветка на строке.
// Что умеет c (*sdk.Ctx): наведите курсор на sdk.Ctx и нажмите K или gd. Руководство — docs/go-extensions.md.
package %s

import (
	"strings"

	"github.com/van1dalgrr-arch/ownvim/core/sdk"
)

func init() {
	// команда :%s — запуск: :%s или клавишей ниже
	sdk.Command("%s", "Что делает моя команда", func(c *sdk.Ctx) error {
		// c.Lines() — строки файла, c.Selection() — выделенное, c.Word — слово под курсором, c.File — путь
		words := len(strings.Fields(strings.Join(c.Lines(), " ")))
		c.Notify("в %%s %%d слов", c.File, words)
		return nil // вернули ошибку — ownvim покажет её уведомлением
	})

	// клавиша: режимы (n — обычный, x — выделение) и сочетание; <leader> — пробел
	sdk.Key("n <leader>x%s", "%s")

	// реакция на событие — раскомментируйте:
	// sdk.On("BufWritePost", "*.go", func(c *sdk.Ctx) error {
	// 	c.Notify("сохранён %%s", c.File)
	// 	return nil
	// })
}
]]

function M.new(name)
  if not name or not name:match("^[a-z][a-z0-9_]*$") then
    return vim.notify("GoExtensionNew <имя> — маленькими латинскими буквами: hello, todo_check", vim.log.levels.WARN)
  end
  if name:match("_test$") then
    -- файл <имя>_test.go Go считает тестами и в сборку не берёт — расширение молча не появилось бы
    return vim.notify("имя не может кончаться на _test: для Go это файл тестов, он не попадёт в сборку", vim.log.levels.WARN)
  end
  local dir = core.src .. "/extensions/" .. name
  local file = dir .. "/" .. name .. ".go"
  if vim.uv.fs_stat(file) then return vim.cmd.edit(vim.fn.fnameescape(file)) end
  vim.fn.mkdir(dir, "p")
  local cmd = name:gsub("_(%l)", string.upper):gsub("^%l", string.upper)
  local key = name:sub(1, 1)
  vim.fn.writefile(vim.split(TEMPLATE:format(name, name, cmd, cmd, cmd, key, cmd), "\n"), file)
  vim.cmd.edit(vim.fn.fnameescape(file))
  vim.notify(("расширение %s создано — сохраните файл, и команда :%s появится"):format(name, cmd))
end

-- ── JSONC-набор (без кода) ───────────────────────────────────────────────────

local JSONC_TEMPLATE = [[
// %s — мой набор для ownvim: JSONC, без кода. Всё здесь ложится поверх умолчаний; settings.jsonc — сильнее.
// Разделы — те же, что в settings.jsonc (K на ключе — описание). Списки дописываются через "ключ+" ("list+"),
// без плюса — заменяются целиком. Сохранили — применилось. Выключить набор — "enabled": false.
// Раскомментируйте нужное (gcc на строке). Руководство — docs/jsonc-plugins.md.
{
  "name": "%s",
  "description": "что делает этот набор",

  // клавиши: "режимы клавиша": действие (список — пробел sk), ":команда" или клавиши как есть
  "keys": {
    // "n <leader>xg": ":Git status",
  },

  // задачи (пробел rr) — дописать к стандартным
  "tasks": {
    "list+": [
      // { "name": "мой сервер", "cmd": "go run ./cmd/api", "when": ["go.mod"] },
    ],
  },

  // проверки: команда на сохранение, её ошибки «файл:строка:столбец: текст» — на строках, как у линтера
  "checks": {
    // "go vet": { "run": "go vet ./...", "pattern": "*.go" },
    // "shellcheck": { "run": "shellcheck -f gcc ${file}", "pattern": "*.sh" },
  },

  // свои команды-скрипты на любом языке: stdin → stdout (docs/extensions.ru.md)
  "commands": {
    // "UUID": { "run": "uuidgen | tr A-Z a-z", "input": "none", "output": "insert", "key": "n <leader>xu" },
  },

  // блок в статусной строке: вывод команды раз в every_ms
  "statusline": {
    "custom": {
      // "k8s": { "shell": "kubectl config current-context", "every_ms": 10000, "icon": "⎈", "color": "pink" },
    },
    // "right+": ["k8s"],
  },
}
]]

function M.new_jsonc(name)
  if not name or not name:match("^[%w_%-]+$") then
    return vim.notify("PluginNew <имя> — латиницей, цифрами, - и _: go-quality, my-keys", vim.log.levels.WARN)
  end
  local dir = vim.fn.stdpath("config") .. "/extensions"
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/" .. name .. ".jsonc"
  if not vim.uv.fs_stat(file) then vim.fn.writefile(vim.split(JSONC_TEMPLATE:format(name, name), "\n"), file) end
  vim.cmd.edit(vim.fn.fnameescape(file))
end

-- ── пересборка после правки Go-кода ──────────────────────────────────────────

local function rebuilt(ok)
  if not ok then return end
  M.reload(true)
  local n = #((M.manifest or {}).commands or {})
  vim.notify(("Go-ядро пересобрано · расширений-команд: %d"):format(n))
end

function M.setup()
  M.reload(false)
  vim.api.nvim_create_user_command("PluginNew", function(a) M.new_jsonc(a.args) end,
    { nargs = 1, desc = "Новый JSONC-набор без кода (extensions/<имя>.jsonc)" })
  vim.api.nvim_create_user_command("GoExtensionNew", function(a) M.new(a.args) end,
    { nargs = 1, desc = "Новое расширение на Go (core/extensions/<имя>)" })
  vim.api.nvim_create_user_command("View", function(a)
    if a.args == "" then
      return vim.ui.select((M.manifest or {}).views or {}, { prompt = "Панель" }, function(n)
        if n then dispatch("view:" .. n, context("")) end
      end)
    end
    dispatch("view:" .. a.args, context(""))
  end, { nargs = "?", complete = function() return (M.manifest or {}).views or {} end, desc = "Открыть или закрыть панель Go-расширения" })
  vim.api.nvim_create_user_command("GoExtensions", function()
    local m = M.manifest or {}
    local lines = {}
    for _, c in ipairs(m.commands or {}) do lines[#lines + 1] = (":%s — %s (%s)"):format(c.name, c.desc, c.ext) end
    for _, e in ipairs(m.events or {}) do lines[#lines + 1] = ("%s %s — событие (%s)"):format(table.concat(e.events, ","), e.pattern, e.ext) end
    vim.notify(#lines > 0 and table.concat(lines, "\n") or "расширений нет — :GoExtensionNew имя", vim.log.levels.INFO, { title = "Go-расширения" })
  end, { desc = "Что объявили Go-расширения" })
  -- сохранили Go-файл ядра — пересобрать и перерегистрировать
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("own.ext", { clear = true }),
    pattern = { "*.go", "go.mod" },
    callback = function(ev)
      local path = vim.fs.normalize(vim.fn.resolve(ev.file ~= "" and vim.fn.fnamemodify(ev.file, ":p") or ""))
      if vim.startswith(path, vim.fs.normalize(vim.fn.resolve(core.src)) .. "/") then core.rebuild_async(rebuilt, true) end
    end,
  })
end

return M
