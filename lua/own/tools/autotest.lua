-- Тесты в фоне: сохранил Go-файл — через секунду `go test` его пакета. В статусной строке ✓ 42 / ✗ 1 / ✗ сборка,
-- а упавшая проверка подсвечивается ошибкой на своей строке в _test.go (как Error Lens) — видно ещё до коммита.
-- Результаты из кэша go test: если в пакете ничего не менялось, прогон мгновенный.
-- пробел t A — выключить / включить.
local M = { enabled = true }
local ns = vim.api.nvim_create_namespace("own.autotest")
local state = {} -- папка пакета → { running, passed, failed, build }
local jobs, timers, marked = {}, {}, {}

local function redraw() vim.schedule(function() pcall(vim.cmd.redrawstatus) end) end

local function pkg_dir(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or not name:match("%.go$") then return nil end
  local dir = vim.fs.dirname(name)
  if not vim.fs.root(dir, "go.mod") then return nil end
  if #vim.fn.glob(dir .. "/*_test.go", false, true) == 0 then return nil end
  return dir
end

-- упавшие проверки → диагностика в открытых _test.go пакета
local function mark(dir, fails)
  for _, buf in ipairs(marked[dir] or {}) do
    if vim.api.nvim_buf_is_valid(buf) then vim.diagnostic.reset(ns, buf) end
  end
  marked[dir] = {}
  local by_file = {}
  for _, f in ipairs(fails) do
    local path = dir .. "/" .. f.file
    by_file[path] = by_file[path] or {}
    table.insert(by_file[path], { lnum = f.line - 1, col = 0, severity = vim.diagnostic.severity.ERROR, source = "go test", message = f.test .. ": " .. f.msg })
  end
  for path, diags in pairs(by_file) do
    local buf = vim.fn.bufnr(path)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      vim.diagnostic.set(ns, buf, diags)
      table.insert(marked[dir], buf)
    end
  end
end

local function parse(dir, res)
  local passed, failed, failed_tests, output, fails = 0, 0, {}, {}, {}
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local ok, ev = pcall(vim.json.decode, line)
    if ok and type(ev) == "table" and ev.Test then
      local top = ev.Test:match("^[^/]+")
      if ev.Action == "output" then
        output[ev.Test] = output[ev.Test] or {}
        table.insert(output[ev.Test], ev.Output)
      elseif ev.Test == top and ev.Action == "pass" then
        passed = passed + 1
      elseif ev.Action == "fail" then
        if ev.Test == top then failed = failed + 1 end
        failed_tests[ev.Test] = true
      end
    end
  end
  -- «    notify_test.go:23: got 1, want 2» в выводе упавших тестов
  for test in pairs(failed_tests) do
    for _, out in ipairs(output[test] or {}) do
      local file, l, msg = out:match("^%s+([%w_%-%.]+_test%.go):(%d+): (.-)%s*$")
      if file then fails[#fails + 1] = { test = test, file = file, line = tonumber(l), msg = msg } end
    end
  end
  local build = res.code ~= 0 and passed == 0 and failed == 0
  local prev = state[dir]
  state[dir] = { passed = passed, failed = failed, build = build }
  mark(dir, fails)
  redraw()
  -- сообщить, только когда стало плохо (не на каждое сохранение)
  local was_bad = prev and (prev.failed and prev.failed > 0 or prev.build)
  if (failed > 0 or build) and not was_bad then
    local what = build and "не собирается" or (failed .. " упал" .. (failed == 1 and "" or "о") .. ": " .. table.concat(vim.tbl_keys(failed_tests), ", "))
    vim.notify("тесты " .. vim.fn.fnamemodify(dir, ":t") .. " — " .. what, vim.log.levels.WARN, { title = "go test" })
  end
end

function M.run(dir)
  if jobs[dir] then pcall(function() jobs[dir]:kill(15) end) end -- прошлый прогон уже устарел
  state[dir] = vim.tbl_extend("force", state[dir] or {}, { running = true })
  redraw()
  local job
  -- профиль покрытия — туда же, где его ждёт nvim-coverage: показано покрытие (пробел G V) — обновится само
  job = vim.system({ "go", "test", "-json", "-coverprofile=/tmp/cover.out", "." }, { cwd = dir, text = true }, function(res)
    if jobs[dir] ~= job then return end -- пришёл ответ убитого прогона
    jobs[dir] = nil
    vim.schedule(function() parse(dir, res) end)
  end)
  jobs[dir] = job
end

-- для lualine: результат пакета текущего файла
function M.status()
  local dir = M.enabled and pkg_dir(0)
  local s = dir and state[dir]
  if not s then return "" end
  if s.running then return "󰙨 …" end
  if s.build then return "󰙨 ✗ сборка" end
  if s.failed > 0 then return "󰙨 ✗ " .. s.failed end
  return "󰙨 ✓ " .. s.passed
end

function M.color()
  local dir = pkg_dir(0)
  local s = dir and state[dir]
  local group = not s and "Comment" or s.running and "Comment" or (s.build or s.failed > 0) and "DiagnosticError" or "DiagnosticOk"
  return { fg = Snacks.util.color(group) }
end

function M.toggle()
  M.enabled = not M.enabled
  if not M.enabled then
    for dir in pairs(marked) do mark(dir, {}) end
  end
  redraw()
  vim.notify("тесты в фоне " .. (M.enabled and "включены" or "выключены"))
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.autotest", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
    group = group,
    pattern = "*.go",
    callback = function(ev)
      if not M.enabled then return end
      local dir = pkg_dir(ev.buf)
      if not dir then return end
      -- открыл файл — тоже прогон (из кэша мгновенный): пометки упавших встанут и в этот файл.
      -- автосохранение пишет часто — ждём секунду тишины
      timers[dir] = timers[dir] or vim.uv.new_timer()
      timers[dir]:start(1000, 0, vim.schedule_wrap(function() M.run(dir) end))
    end,
  })
end

return M
