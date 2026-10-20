-- Docker прямо в коде — без отдельных окон (контейнерами управляет своя утилита, alt-o):
--   compose.yaml — справа от каждого сервиса его статус: ● работает · здоров · :8080, ○ остановлен (код 1);
--     обновляется сам, пока файл на экране. enter на сервисе — up / restart / stop / логи / shell.
--     ${VAR} без значения в .env и без умолчания (${VAR:-x}) — предупреждение на строке;
--     gd на ${VAR} — к строке в .env (нет её — допишет VAR= и встанет туда).
--   Dockerfile — справа от RUN / COPY / ADD вес слоя в собранном образе (+312 MB), на FROM — итог и база.
--     Образ: :DockerLayers — выбрать; сам ищет <папка>:dev (задачи ownvim) и <папка>-<сервис> (compose).
-- Настройки модуля: { "interval_ms": 3000, "compose_status": true, "layers": true, "env_check": true }
local M = {}

local opts = {}
local ns_status = vim.api.nvim_create_namespace("own.docker.compose")
local ns_layers = vim.api.nvim_create_namespace("own.docker.layers")
local ns_env = vim.api.nvim_create_namespace("own.docker.env")

M.cache = {} -- папка compose → { at = os.time(), list = { сервис → контейнер } }

local function have_docker() return vim.fn.executable("docker") == 1 end

local function docker(args, cwd, cb)
  vim.system(vim.list_extend({ "docker" }, args), { text = true, cwd = cwd, timeout = 10000 }, vim.schedule_wrap(function(r)
    cb(r.code == 0, r.stdout or "", r.stderr or "")
  end))
end

-- docker отдаёт json построчно (compose v2.21+) или массивом (старые версии)
local function json_lines(s)
  s = vim.trim(s)
  if s == "" then return {} end
  if s:sub(1, 1) == "[" then
    local ok, t = pcall(vim.json.decode, s)
    return ok and t or {}
  end
  local out = {}
  for line in s:gmatch("[^\n]+") do
    local ok, t = pcall(vim.json.decode, line)
    if ok then out[#out + 1] = t end
  end
  return out
end

local function is_compose(buf)
  local name = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
  return (name:match("^docker%-compose.*%.ya?ml$") or name:match("^compose.*%.ya?ml$")) ~= nil
end

local function is_dockerfile(buf) return vim.bo[buf].filetype == "dockerfile" end

local function dir_of(buf) return vim.fs.dirname(vim.api.nvim_buf_get_name(buf)) end

-- ── compose: сервисы и их статус ─────────────────────────────────────────────

--- Сервисы файла: { name, lnum (с 0), last (последняя строка блока) }
function M.services(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out, inside, indent = {}, false, nil
  for i, l in ipairs(lines) do
    if l:match("^services:") then
      inside, indent = true, nil
    elseif l:match("^[%w_%-]") then
      if inside and out[#out] then out[#out].last = out[#out].last or i - 2 end
      inside = false
    elseif inside then
      local sp, name = l:match("^(%s+)[\"']?([%w%._%-]+)[\"']?:%s*$")
      if not name then sp, name = l:match("^(%s+)[\"']?([%w%._%-]+)[\"']?:%s+#") end
      if name then
        indent = indent or #sp
        if #sp == indent then
          if out[#out] then out[#out].last = out[#out].last or i - 2 end
          out[#out + 1] = { name = name, lnum = i - 1 }
        end
      end
    end
  end
  if out[#out] then out[#out].last = out[#out].last or #lines - 1 end
  return out
end

local STATE = {
  running = { "●", "DiagnosticOk", "работает" },
  restarting = { "↻", "DiagnosticWarn", "перезапускается" },
  paused = { "⏸", "DiagnosticHint", "на паузе" },
  created = { "○", "Comment", "создан" },
  exited = { "○", "DiagnosticError", "остановлен" },
  dead = { "✗", "DiagnosticError", "мёртв" },
}
local HEALTH = { healthy = { "здоров", "DiagnosticOk" }, unhealthy = { "болен", "DiagnosticError" }, starting = { "стартует", "DiagnosticWarn" } }

local function status_chunks(c)
  if not c then return { { "○ не запущен", "Comment" } } end
  local st = STATE[c.State] or { "•", "Comment", c.State or "?" }
  local hl = st[2]
  local word = st[3]
  if c.State == "exited" then
    local code = tonumber(c.ExitCode) or tonumber((c.Status or ""):match("Exited %((%d+)%)")) or 0
    if code == 0 then hl = "Comment" end
    word = ("%s (код %d)"):format(word, code)
  end
  local chunks = { { st[1] .. " " .. word, hl } }
  local h = HEALTH[c.Health or ""]
  if h then
    chunks[#chunks + 1] = { " · ", "Comment" }
    chunks[#chunks + 1] = { h[1], h[2] }
  end
  local ports, seen = {}, {}
  for _, p in ipairs(c.Publishers or {}) do
    local port = tonumber(p.PublishedPort) or 0
    if port > 0 and not seen[port] then
      seen[port] = true
      ports[#ports + 1] = ":" .. port
    end
  end
  if #ports > 0 then chunks[#chunks + 1] = { " · " .. table.concat(ports, " "), "Comment" } end
  return chunks
end

local function render_compose(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns_status, 0, -1)
  local data = M.cache[dir_of(buf)]
  if not data then return end
  local cursor
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 and vim.api.nvim_get_current_win() == win then cursor = vim.api.nvim_win_get_cursor(win)[1] - 1 end
  for _, s in ipairs(M.services(buf)) do
    local chunks = data.down and { { "○ docker не запущен", "Comment" } } or status_chunks(data.list[s.name])
    table.insert(chunks, 1, { "   ", "Normal" })
    if cursor == s.lnum then chunks[#chunks + 1] = { "   ⏎ действия", "Comment" } end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns_status, s.lnum, 0, { virt_text = chunks, virt_text_pos = "eol", hl_mode = "combine" })
  end
end

local fetching = {}
--- Статус сервисов проекта в папке dir (async); done() — когда кэш обновлён
function M.fetch(dir, done)
  if fetching[dir] or not have_docker() then return end
  fetching[dir] = true
  docker({ "compose", "ps", "-a", "--format", "json" }, dir, function(ok, out, err)
    fetching[dir] = nil
    local list = {}
    for _, c in ipairs(ok and json_lines(out) or {}) do
      -- несколько реплик — показываем первую работающую
      if c.Service and (not list[c.Service] or (list[c.Service].State ~= "running" and c.State == "running")) then
        list[c.Service] = c
      end
    end
    local down = not ok and (err:find("Cannot connect", 1, true) or err:find("failed to connect", 1, true)) ~= nil
    M.cache[dir] = { at = os.time(), list = list, down = down }
    if done then done() end
  end)
end

local function refresh_compose(buf)
  if opts.compose_status == false or not is_compose(buf) then return end
  M.fetch(dir_of(buf), function() render_compose(buf) end)
end

-- ── compose: действия по enter ───────────────────────────────────────────────

local function service_at(buf, lnum)
  for _, s in ipairs(M.services(buf)) do
    if lnum >= s.lnum and lnum <= s.last then return s end
  end
end

local function in_terminal(cmd, cwd)
  Snacks.terminal(cmd, { cwd = cwd, auto_close = false, win = { position = "bottom", height = 0.35 } })
end

local function compose_action(buf, svc)
  local dir = dir_of(buf)
  local function run(args, label)
    vim.notify(("%s: %s…"):format(svc, label))
    docker(vim.list_extend({ "compose" }, args), dir, function(ok, _, err)
      if ok then vim.notify(("%s: %s — готово"):format(svc, label))
      else vim.notify(("%s: %s — ошибка\n%s"):format(svc, label, err), vim.log.levels.ERROR) end
      refresh_compose(buf)
    end)
  end
  local items = {
    { "▶ up", function() run({ "up", "-d", svc }, "up") end },
    { "⇪ собрать и up", function() in_terminal({ "docker", "compose", "up", "-d", "--build", svc }, dir) end },
    { "⟳ restart", function() run({ "restart", svc }, "restart") end },
    { "■ stop", function() run({ "stop", svc }, "stop") end },
    { "≡ логи", function() in_terminal({ "docker", "compose", "logs", "-f", "--tail", "200", svc }, dir) end },
    { "❯ shell", function()
      in_terminal({ "docker", "compose", "exec", svc, "sh", "-c", "command -v bash >/dev/null && exec bash || exec sh" }, dir)
    end },
  }
  vim.ui.select(items, { prompt = svc, format_item = function(i) return i[1] end }, function(choice)
    if choice then choice[2]() end
  end)
end

-- то, что висит на клавише глобально (enter — прыжок по меткам, gd — к определению)
local function fallback(lhs)
  local m = vim.fn.maparg(lhs, "n", false, true)
  if m.callback then return m.callback() end
  if m.rhs and m.rhs ~= "" then return vim.api.nvim_feedkeys(vim.keycode(m.rhs), m.noremap == 1 and "n" or "m", false) end
  vim.api.nvim_feedkeys(vim.keycode(lhs), "n", false)
end

-- ── compose: ${VAR} и .env ───────────────────────────────────────────────────

local function read_env(dir)
  local vars, path = {}, dir .. "/.env"
  local f = io.open(path)
  if not f then return vars, path end
  local n = 0
  for line in f:lines() do
    n = n + 1
    local k = line:match("^%s*export%s+([%w_]+)%s*=") or line:match("^%s*([%w_]+)%s*=")
    if k then vars[k] = n end
  end
  f:close()
  return vars, path
end

-- переменные в строке: { name, s, e (с 0, конец не включая), default }
local function vars_in(line)
  local out, i = {}, 1
  while true do
    local s = line:find("%$", i)
    if not s then break end
    local nxt = line:sub(s + 1, s + 1)
    if nxt == "$" then
      i = s + 2 -- $$ — экранированный доллар
    elseif nxt == "{" then
      local name, rest, close = line:match("^{([%w_]+)([^}]*)()}", s + 1)
      if name then
        out[#out + 1] = { name = name, s = s - 1, e = close, default = rest:match("^:?[-?+]") ~= nil }
        i = close + 1
      else
        i = s + 1
      end
    else
      local name, after = line:match("^([%a_][%w_]*)()", s + 1)
      if name then
        out[#out + 1] = { name = name, s = s - 1, e = after - 1, default = false }
        i = after
      else
        i = s + 1
      end
    end
  end
  return out
end

local function check_env(buf)
  if opts.env_check == false or not is_compose(buf) then return end
  local vars = read_env(dir_of(buf))
  local diags = {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if not line:match("^%s*#") then
      for _, v in ipairs(vars_in(line)) do
        if not v.default and not vars[v.name] and vim.env[v.name] == nil then
          diags[#diags + 1] = { lnum = lnum - 1, col = v.s, end_col = v.e, severity = vim.diagnostic.severity.WARN,
            source = "compose", message = ("%s нет в .env и нет умолчания (${%s:-…}) — gd допишет её в .env"):format(v.name, v.name) }
        end
      end
    end
  end
  vim.diagnostic.set(ns_env, buf, diags)
end

local function goto_env(buf)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  for _, v in ipairs(vars_in(line)) do
    if col >= v.s and col < v.e then
      local vars, path = read_env(dir_of(buf))
      vim.cmd.edit(vim.fn.fnameescape(path))
      if vars[v.name] then
        vim.api.nvim_win_set_cursor(0, { vars[v.name], 0 })
        vim.cmd("normal! f=l")
      else
        local last = vim.api.nvim_buf_line_count(0)
        local empty = last == 1 and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == ""
        vim.api.nvim_buf_set_lines(0, empty and 0 or last, -1, false, { v.name .. "=" })
        vim.api.nvim_win_set_cursor(0, { empty and 1 or last + 1, #v.name + 1 })
        vim.cmd("startinsert!")
      end
      return
    end
  end
  local _ = row
  fallback("gd")
end

-- ── Dockerfile: вес слоёв ────────────────────────────────────────────────────

local function human(bytes)
  local units = { "B", "kB", "MB", "GB" }
  local i, n = 1, bytes
  while n >= 1000 and i < #units do n, i = n / 1000, i + 1 end
  return (i == 1 and "%d %s" or (n < 10 and "%.1f %s" or "%.0f %s")):format(n, units[i])
end

local function size_hl(bytes)
  if bytes >= 500e6 then return "DiagnosticError" end
  if bytes >= 100e6 then return "DiagnosticWarn" end
  if bytes >= 10e6 then return "DiagnosticInfo" end
  return "Comment"
end

local function norm(s) return vim.trim((s or ""):gsub("%s+", " ")) end

--- Инструкции последней стадии: { kw, args, lnum (с 0) }
local function instructions(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local all, i = {}, 1
  while i <= #lines do
    local l = lines[i]
    local kw, rest = l:match("^%s*(%a+)%s+(.*)$")
    if kw and not l:match("^%s*#") then
      local start, text = i - 1, rest
      while text:match("\\%s*$") and i < #lines do
        i = i + 1
        text = text:gsub("\\%s*$", " ") .. (lines[i]:match("^%s*#") and "" or lines[i])
      end
      all[#all + 1] = { kw = kw:upper(), args = norm(text), lnum = start }
    end
    i = i + 1
  end
  local from = 1
  for k, ins in ipairs(all) do if ins.kw == "FROM" then from = k end end
  return vim.list_slice(all, from)
end

-- инструкция из истории образа: "RUN |2 A=1 B=2 /bin/sh -c go build # buildkit" → RUN, "go build"
local function parse_history(created)
  local s = norm(created):gsub(" # buildkit$", "")
  s = s:gsub("^/bin/sh %-c #%(nop%) ", "")
  local kw, rest = s:match("^(%u+)%s*(.*)$")
  if not kw then return "RUN", s end
  if kw == "RUN" then rest = rest:gsub("^|%d+ .-/bin/sh %-c ", ""):gsub("^/bin/sh %-c ", "") end
  return kw, rest
end

local function matches(ins, kw, text)
  if ins.kw ~= kw then return false end
  if kw ~= "RUN" then return true end
  local a = norm(ins.args:gsub("%-%-mount=%S+", ""):gsub("%-%-network=%S+", ""))
  local n = math.min(30, #a, #text)
  return n == 0 or a:sub(1, n) == text:sub(1, n) or text:find(a:sub(1, n), 1, true) ~= nil
end

local function render_layers(buf, image, history)
  vim.api.nvim_buf_clear_namespace(buf, ns_layers, 0, -1)
  local ins = instructions(buf)
  local j, matched, total = 1, 0, 0
  for k = #ins, 2, -1 do
    for look = j, math.min(j + 4, #history) do
      local kw, text = parse_history(history[look].CreatedBy)
      if matches(ins[k], kw, text) then
        local size = tonumber(history[look].Size) or 0
        total = total + size
        matched = matched + 1
        if size > 0 then
          vim.api.nvim_buf_set_extmark(buf, ns_layers, ins[k].lnum, 0, {
            virt_text = { { "+" .. human(size), size_hl(size) } }, virt_text_pos = "right_align", hl_mode = "combine" })
        end
        j = look + 1
        break
      end
    end
  end
  if matched == 0 or not ins[1] then return end
  local base = 0
  for k = j, #history do base = base + (tonumber(history[k].Size) or 0) end
  vim.api.nvim_buf_set_extmark(buf, ns_layers, ins[1].lnum, 0, {
    virt_text = { { ("%s · %s · база %s"):format(image, human(total + base), human(base)), "Comment" } },
    virt_text_pos = "right_align", hl_mode = "combine" })
end

-- образ этого Dockerfile: выбранный в :DockerLayers, <папка>:dev, <папка>-* из compose — самый свежий
local function guess_image(buf, images)
  if vim.b[buf].own_docker_image then return vim.b[buf].own_docker_image end
  local project = vim.fs.basename(require("own.root").get()):lower():gsub("[^%w_%-]", "")
  local names = {}
  for _, im in ipairs(images) do names[#names + 1] = im.Repository .. ":" .. im.Tag end
  if vim.tbl_contains(names, project .. ":dev") then return project .. ":dev" end
  for _, n in ipairs(names) do -- docker images — новые сверху
    if vim.startswith(n, project .. "-") or vim.startswith(n, project .. ":") then return n end
  end
end

local function refresh_layers(buf)
  if opts.layers == false or not is_dockerfile(buf) or not have_docker() then return end
  docker({ "images", "--format", "json" }, dir_of(buf), function(ok, out)
    if not ok then return end
    local image = guess_image(buf, json_lines(out))
    if not image then return vim.api.nvim_buf_clear_namespace(buf, ns_layers, 0, -1) end
    docker({ "history", "--no-trunc", "--human=false", "--format", "json", image }, dir_of(buf), function(ok2, hist)
      if ok2 and vim.api.nvim_buf_is_valid(buf) then render_layers(buf, image, json_lines(hist)) end
    end)
  end)
end

function M.pick_image()
  local buf = vim.api.nvim_get_current_buf()
  docker({ "images", "--format", "json" }, nil, function(ok, out)
    if not ok then return vim.notify("docker не отвечает", vim.log.levels.ERROR) end
    local names = {}
    for _, im in ipairs(json_lines(out)) do
      if im.Repository ~= "<none>" then names[#names + 1] = im.Repository .. ":" .. im.Tag end
    end
    vim.ui.select(names, { prompt = "Образ этого Dockerfile" }, function(choice)
      if not choice then return end
      vim.b[buf].own_docker_image = choice
      refresh_layers(buf)
    end)
  end)
end

-- ── стартовый экран: статус compose проекта ──────────────────────────────────

--- Статус compose для стартового экрана: кэш или nil (тогда запросит и вызовет on_ready)
function M.project_status(dir, on_ready)
  local found
  for _, n in ipairs({ "compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml" }) do
    if vim.uv.fs_stat(dir .. "/" .. n) then found = true end
  end
  if not found or not have_docker() then return nil end
  if not M.cache[dir] then M.fetch(dir, on_ready) end
  return M.cache[dir]
end

-- ── общее ────────────────────────────────────────────────────────────────────

local timer
local function tick()
  if not have_docker() then return end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if is_compose(buf) then refresh_compose(buf) end
  end
end

function M.setup(o)
  opts = o or {}
  local group = vim.api.nvim_create_augroup("own.docker", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained" }, {
    group = group,
    callback = function(ev)
      if is_compose(ev.buf) then
        refresh_compose(ev.buf)
        check_env(ev.buf)
      elseif is_dockerfile(ev.buf) then
        refresh_layers(ev.buf)
      elseif vim.fs.basename(ev.file or "") == ".env" and ev.event == "BufWritePost" then
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(b) and is_compose(b) then check_env(b) end
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
    group = group,
    callback = function(ev) if is_compose(ev.buf) then check_env(ev.buf); render_compose(ev.buf) end end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function(ev) if is_compose(ev.buf) then render_compose(ev.buf) end end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      if not is_compose(ev.buf) or vim.b[ev.buf].own_docker_keys then return end
      vim.b[ev.buf].own_docker_keys = true
      vim.keymap.set("n", "<cr>", function()
        local s = service_at(ev.buf, vim.api.nvim_win_get_cursor(0)[1] - 1)
        if s then compose_action(ev.buf, s.name) else fallback("<cr>") end
      end, { buffer = ev.buf, desc = "Сервис: up / restart / stop / логи / shell" })
      vim.keymap.set("n", "gd", function() goto_env(ev.buf) end, { buffer = ev.buf, desc = "${VAR} → .env" })
    end,
  })
  vim.api.nvim_create_user_command("DockerLayers", M.pick_image, { desc = "Образ для веса слоёв в Dockerfile" })
  if timer then timer:stop() end
  timer = vim.uv.new_timer()
  local every = opts.interval_ms or 3000
  timer:start(every, every, vim.schedule_wrap(tick))
end

function M.reload(o)
  opts = o or {}
  tick()
end

return M
