-- Конфигурации запуска, как в GoLand: справа в строке вкладок «▶ api ▾» — что запускается одной клавишей.
--   пробел r r — запустить (уже идёт — перезапустить), пробел r d — под отладчиком, пробел r s — остановить,
--   пробел r c — выбрать конфигурацию; клик по имени — тоже выбор, по ▶ / 󰃤 / ■ — запуск, отладка, стоп.
-- Находятся сами: Go — каждый package main (./cmd/api, корень), Rust — cargo run, compose — docker compose up,
-- package.json — npm run dev/start; плюс свои — раздел "run": { "configs": [ { "name", "cmd", "env", "cwd" } ] }
-- и задачи из "tasks" без ${input:…}. .env проекта подхватывается для Go сам (как в GoLand с EnvFile).
-- Вывод — во вкладке «Запуск» нижней панели; выбранная конфигурация помнится для каждого проекта.
local root = require("own.root")
local settings = require("own.settings")

local M = {}

local cache = {} -- корень → список (Go ищется командой go list — один раз на проект)
local job = { buf = nil, conf = nil }

local function ws() return require("own.modules.workspace") end

local function exists(dir, name) return vim.uv.fs_stat(dir .. "/" .. name) ~= nil end

local function env_of(dir, files)
  if files == false then return nil end
  files = files or ".env"
  local env = {}
  for _, f in ipairs(type(files) == "table" and files or { files }) do
    env = vim.tbl_extend("force", env, require("own.modules.tasks").read_env(dir .. "/" .. f))
  end
  return next(env) and env or nil
end

local function go_mains(dir, done)
  if not exists(dir, "go.mod") or vim.fn.executable("go") == 0 then return done({}) end
  -- пути через ссылку (/var ↔ /private/var) у go list и у nvim могут не совпасть — сравнивать настоящие
  local real = vim.uv.fs_realpath(dir) or dir
  vim.system({ "go", "list", "-f", "{{if eq .Name \"main\"}}{{.Dir}}{{end}}", "./..." }, { cwd = dir, text = true }, function(r)
    local out = {}
    for line in (r.stdout or ""):gmatch("[^\n]+") do
      local p = vim.uv.fs_realpath(line) or line
      if p ~= real and not vim.startswith(p, real .. "/") then goto continue end
      local rel = p == real and "." or "./" .. p:sub(#real + 2)
      local name = rel == "." and vim.fs.basename(dir) or vim.fs.basename(line)
      out[#out + 1] = {
        id = "go:" .. rel, name = name, kind = "go", cmd = { "go", "run", rel }, cwd = dir, env = env_of(dir),
        detail = "go run " .. rel,
        debug = { type = "go", request = "launch", name = name, program = line, cwd = dir },
      }
      ::continue::
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    vim.schedule(function() done(out) end)
  end)
end

local function static(dir)
  local out = {}
  if exists(dir, "Cargo.toml") then
    out[#out + 1] = { id = "cargo:run", name = vim.fs.basename(dir), kind = "rust", cmd = { "cargo", "run" }, cwd = dir,
      detail = "cargo run", debug = "rust" }
  end
  for _, f in ipairs({ "compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml" }) do
    if exists(dir, f) then
      out[#out + 1] = { id = "compose:up", name = "compose", kind = "docker", cmd = { "docker", "compose", "up" }, cwd = dir,
        detail = "docker compose up" }
      break
    end
  end
  if exists(dir, "package.json") then
    local f = io.open(dir .. "/package.json")
    local ok, pkg = pcall(vim.json.decode, f and f:read("*a") or "")
    if f then f:close() end
    for _, s in ipairs({ "dev", "start" }) do
      if ok and type(pkg) == "table" and type(pkg.scripts) == "table" and pkg.scripts[s] then
        out[#out + 1] = { id = "npm:" .. s, name = "npm " .. s, kind = "node", cmd = { "npm", "run", s }, cwd = dir,
          detail = pkg.scripts[s] }
      end
    end
  end
  -- свои: "run": { "configs": [ … ] }
  for i, c in ipairs(((settings.current or {}).run or {}).configs or {}) do
    if c.name and c.cmd then
      out[#out + 1] = { id = "user:" .. c.name, name = c.name, kind = "user", cmd = c.cmd, detail = type(c.cmd) == "string" and c.cmd or table.concat(c.cmd, " "),
        cwd = c.cwd and vim.fs.normalize(dir .. "/" .. c.cwd) or dir, env = env_of(dir, c.env or false), debug = c.debug, order = i }
    end
  end
  -- задачи этого проекта (с when, совпавшим с корнем) без вопросов при запуске; общие (без when) — в пробел r t
  for _, t in ipairs(((settings.current or {}).tasks or {}).list or {}) do
    local visible = false
    for _, w in ipairs(t.when or {}) do if exists(dir, w) then visible = true end end
    if visible and t.cmd and not t.cmd:find("${input:", 1, true) and not t.cmd:find("${file", 1, true) then
      out[#out + 1] = { id = "task:" .. t.name, name = t.name, kind = "task", cmd = t.cmd, detail = t.cmd, cwd = dir,
        env = t.env and env_of(dir, t.env) or nil }
    end
  end
  return out
end

--- Все конфигурации проекта; done(list) — когда найдены (Go — асинхронно, потом из кэша)
function M.list(done, fresh)
  local dir = root.get()
  if cache[dir] and not fresh then return done(cache[dir]) end
  go_mains(dir, function(mains)
    local all = vim.list_extend(mains, static(dir))
    cache[dir] = all
    done(all)
  end)
end

function M.cached() return cache[root.get()] end

function M.current()
  local dir = root.get()
  local id = ws().project_state(dir).run
  local list = cache[dir]
  if not list then return nil end
  for _, c in ipairs(list) do if c.id == id then return c end end
  return list[1]
end

function M.current_name()
  local c = (job.conf and M.running()) and job.conf or M.current()
  return c and c.name
end

function M.buf() return job.buf and vim.api.nvim_buf_is_valid(job.buf) and job.buf or nil end

-- идёт ли запуск: флаг, а не jobwait — строка вкладок рисуется там, где jobwait нельзя
function M.running() return job.running == true and M.buf() ~= nil end

function M.stop()
  local b = M.buf()
  if not b then return end
  local id = vim.b[b].terminal_job_id
  if id and M.running() then
    job.stopped = true -- остановлен руками: код выхода (129, 143) — не повод для предупреждения
    vim.fn.jobstop(id)
  end
  vim.cmd("redrawtabline")
end

function M.show()
  local b = M.buf()
  if not b then return end
  -- окно запуска — нижней панелью; edgy поставит его на место
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == b then return vim.api.nvim_set_current_win(w) end
  end
  vim.cmd("botright 12split")
  vim.api.nvim_win_set_buf(0, b)
  vim.w.snacks_win = { position = "bottom", relative = "editor" }
end

local function start(c)
  M.stop()
  if M.buf() then pcall(vim.api.nvim_buf_delete, job.buf, { force = true }) end
  ws().hide("bottom")
  local cmd = type(c.cmd) == "table" and c.cmd or { vim.o.shell, "-c", c.cmd }
  local term = Snacks.terminal.open(cmd, {
    cwd = c.cwd, env = c.env, auto_close = false, interactive = false,
    win = { position = "bottom", height = (require("own.settings").module_opts(settings.current or {}, "workspace").bottom_height or 12) },
  })
  job.buf, job.conf, job.running, job.stopped = term.buf, c, true, false
  vim.b[term.buf].own_run = c.id
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = term.buf,
    once = true,
    callback = function()
      local by_hand = job.buf == term.buf and job.stopped
      if job.buf == term.buf then job.running = false end
      local code = vim.v.event.status
      vim.schedule(function()
        vim.cmd("redrawtabline")
        if code ~= 0 and not by_hand then
          vim.notify(("%s завершился с кодом %d"):format(c.name, code), vim.log.levels.WARN)
        end
      end)
    end,
  })
  -- курсор остаётся в коде, вывод виден снизу
  vim.cmd("wincmd p")
  vim.cmd("redrawtabline")
end

local function with_current(fn)
  M.list(function(list)
    local c = M.current()
    if not c then
      return vim.notify("запускать нечего: нет package main, Cargo.toml, compose, package.json — свои в \"run\".configs", vim.log.levels.WARN)
    end
    fn(c, list)
  end)
end

--- Запустить выбранную (идёт — перезапустить)
function M.run()
  with_current(function(c) start(c) end)
end

function M.debug()
  with_current(function(c)
    if not c.debug then return vim.notify(c.name .. ": отладка для такого запуска не настроена — \"debug\" в конфигурации", vim.log.levels.WARN) end
    local ok, dap = pcall(require, "dap")
    if not ok then return vim.notify("отладчик выключен (modules.debug)", vim.log.levels.WARN) end
    local conf = c.debug
    if conf == "rust" then conf = (dap.configurations.rust or {})[1] end
    if type(conf) ~= "table" then return end
    conf = vim.deepcopy(conf)
    conf.env = conf.env or c.env
    ws().set_mode("debug")
    dap.run(conf)
  end)
end

local ICON = { go = "\u{e627}", rust = "\u{e7a8}", docker = "\u{f308}", node = "\u{e718}", user = "\u{eaf8}", task = "\u{eab3}" }

function M.choose()
  M.list(function(list)
    if #list == 0 then return vim.notify("конфигураций нет — свои в settings.jsonc, раздел \"run\".configs", vim.log.levels.WARN) end
    local cur = M.current()
    Snacks.picker.pick({
      title = "Конфигурация запуска",
      items = vim.tbl_map(function(c) return { text = c.name .. " " .. (c.detail or ""), conf = c } end, list),
      format = function(item)
        local c = item.conf
        return {
          { (cur and cur.id == c.id) and "● " or "  ", "Special" },
          { (ICON[c.kind] or "\u{f040a}") .. "  ", "Function" },
          { c.name, "Normal" },
          { "  " .. (c.detail or "") .. (c.env and "  · .env" or ""), "Comment" },
        }
      end,
      layout = { preset = "select" },
      confirm = function(picker, item)
        picker:close()
        if not item then return end
        ws().set_project("run", item.conf.id)
        vim.cmd("redrawtabline")
      end,
    })
  end, true)
end

-- ── виджет в строке вкладок ──────────────────────────────────────────────────

_G.OwnRunClick = function(what)
  if what == 1 then M.choose() elseif what == 2 then M.run() elseif what == 3 then M.debug() else M.stop() end
end

function M.widget()
  local dir = root.get()
  if not cache[dir] then
    if not M._asked then
      M._asked = true
      M.list(function() M._asked = false; vim.cmd("redrawtabline") end)
    end
    return ""
  end
  local c = (job.conf and M.running()) and job.conf or M.current()
  if not c then return "" end
  local mode = ws().mode_info()
  local s = ""
  if mode and mode.name ~= "code" then s = ("%%#OwnRunMode# %s %s "):format(mode.icon, mode.title) end
  local on = M.running()
  s = s .. ("%%1@v:lua.OwnRunClick@%%#OwnRunName# %s %s \u{eab4} %%X"):format(ICON[c.kind] or "\u{f040a}", c.name)
  s = s .. ("%%2@v:lua.OwnRunClick@%%#%s# %s %%X"):format(on and "OwnRunOn" or "OwnRunBtn", on and "\u{f0709}" or "\u{f040a}")
  if c.debug then s = s .. "%3@v:lua.OwnRunClick@%#OwnRunBtn# \u{ead8} %X" end
  if on then s = s .. "%4@v:lua.OwnRunClick@%#OwnRunStop# \u{f04db} %X" end
  return s .. "%#OwnTabFill# "
end

function M.define()
  local function c(g, a) return vim.api.nvim_get_hl(0, { name = g, link = false })[a or "fg"] end
  local fill = c("TabLineFill", "bg") or c("StatusLine", "bg")
  vim.api.nvim_set_hl(0, "OwnRunName", { fg = c("Normal"), bg = fill })
  vim.api.nvim_set_hl(0, "OwnRunBtn", { fg = c("DiagnosticOk") or c("String"), bg = fill })
  vim.api.nvim_set_hl(0, "OwnRunOn", { fg = c("DiagnosticOk") or c("String"), bg = fill, bold = true })
  vim.api.nvim_set_hl(0, "OwnRunStop", { fg = c("DiagnosticError"), bg = fill })
  vim.api.nvim_set_hl(0, "OwnRunMode", { fg = c("OwnIconAccent") or c("Title"), bg = fill, bold = true })
end

function M.setup()
  M.define()
  local group = vim.api.nvim_create_augroup("own.launch", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.define })
  -- новый main или go.mod — найти заново
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = { "*.go", "go.mod", "Cargo.toml", "package.json", "compose.y*ml", "docker-compose.y*ml" },
    callback = function(ev)
      if ev.file:match("%.go$") then
        local head = vim.api.nvim_buf_get_lines(ev.buf, 0, 30, false)
        if not vim.iter(head):any(function(l) return l:match("^package main") end) then return end
      end
      cache[root.get()] = nil
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", { group = group, callback = function() vim.cmd("redrawtabline") end })
end

return M
