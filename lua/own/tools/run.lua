-- ▶ слева от func main и func TestX / BenchmarkX / FuzzX / ExampleX — как значки запуска в GoLand.
-- пробел r x — запустить функцию, в которой курсор; пробел r X — то же под отладчиком (delve).
-- Тесты идут через neotest (результат ✓/✗ рядом с тестом), main — в терминале снизу, остальное — go test.
local M = {}
local ns = vim.api.nvim_create_namespace("own.run")

-- строка «func …» → что это и как называется
local function kind(line, file)
  if line:match("^func main%(%)") then return "main", "main" end
  if not file:match("_test%.go$") then return nil end
  for _, k in ipairs({ "Test", "Benchmark", "Fuzz", "Example" }) do
    local name = line:match("^func (" .. k .. "[%w_]*)%(")
    if name then return k:lower(), name end
  end
end

function M.marks(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "go" then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local file = vim.api.nvim_buf_get_name(buf)
  -- на строке с ошибкой или предупреждением слева нужен их значок, а не ▶
  local problem = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do problem[d.lnum + 1] = true end
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local k = kind(line, file)
    if k and not problem[i] then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
        sign_text = "▶",
        sign_hl_group = k == "main" and "DotfilesRunMain" or "DotfilesRunTest",
        priority = 5, -- ниже ошибок и git
      })
    end
  end
end

-- функция, в которой курсор: ближайшая «func …» выше
local function current()
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, row, false)
  for i = #lines, 1, -1 do
    if lines[i]:match("^func ") then
      local k, name = kind(lines[i], file)
      return k, name, i
    end
  end
end

local function term(cmd, dir)
  Snacks.terminal(cmd, { cwd = dir, auto_close = false, win = { position = "bottom", height = 0.3 } })
end

function M.run(debug)
  if vim.bo.filetype ~= "go" then return vim.notify("▶ работает в Go-файлах", vim.log.levels.WARN) end
  local k, name, line = current()
  local dir = vim.fn.expand("%:p:h")
  if not k then
    if vim.fn.expand("%"):match("_test%.go$") then
      return require("neotest").run.run({ vim.fn.expand("%:p"), strategy = debug and "dap" or nil }) -- весь файл
    end
    return vim.notify("курсор не в func main и не в тесте", vim.log.levels.WARN)
  end
  if k == "main" then
    if debug then
      return require("dap").run({ type = "go", name = "main", request = "launch", program = dir })
    end
    return term("go run .", dir)
  end
  if k == "test" then
    vim.api.nvim_win_set_cursor(0, { line, 5 }) -- neotest берёт тест под курсором
    return require("neotest").run.run({ strategy = debug and "dap" or nil })
  end
  local cmds = {
    benchmark = "go test -run '^$' -bench '^" .. name .. "$' -benchmem .",
    fuzz = "go test -run '^$' -fuzz '^" .. name .. "$' -fuzztime 30s .",
    example = "go test -run '^" .. name .. "$' -v .",
  }
  if debug then
    return require("dap").run({ type = "go", name = name, request = "launch", mode = "test", program = dir,
      args = k == "benchmark" and { "-test.run", "^$", "-test.bench", "^" .. name .. "$" } or { "-test.run", "^" .. name .. "$" } })
  end
  term(cmds[k], dir)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("own.run", { clear = true })
  local timers = {}
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "InsertLeave", "DiagnosticChanged" }, {
    group = group,
    pattern = "*.go",
    callback = function(ev)
      -- после паузы в 200 мс, а не на каждое нажатие
      local t = timers[ev.buf] or vim.uv.new_timer()
      timers[ev.buf] = t
      t:start(200, 0, vim.schedule_wrap(function() M.marks(ev.buf) end))
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      if timers[ev.buf] then timers[ev.buf]:close(); timers[ev.buf] = nil end
    end,
  })
end

return M
