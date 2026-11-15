-- Rust как Go в ownvim (сверх rust-analyzer, rustfmt и codelldb):
--   ▶ слева от fn main, #[test] / #[tokio::test] / #[bench] и mod tests: пробел r x — запустить (что именно — решает
--     rust-analyzer: пакет, --bin / --lib / --test, путь теста), пробел r X — то же под отладчиком (cargo собирает сам);
--   тесты в фоне: сохранил .rs — cargo test крейта, ✓ 12 / ✗ 1 в статусе, упавший assert — ошибкой на своей строке;
--   покрытие (пробел R v) — cargo llvm-cov, полосы слева, как у Go; черновик (пробел r R) — cargo-проект, сразу ▶;
--   пробел R — действия rust-analyzer: раскрыть макрос, Cargo.toml, родительский модуль, docs.rs, объяснить ошибку
--     (rustc --explain / страница clippy), ошибка целиком как в cargo, двигать элемент вверх / вниз, cargo add…;
--   Cargo.toml — версии зависимостей справа, K — описание крейта, пробел ca — обновить (crates.nvim).
-- Раздел "rust": { "run_marks": true, "coverage_file": "/tmp/rust-lcov.info" }
-- Сам Rust: brew install rustup && rustup default stable; покрытие — cargo install cargo-llvm-cov,
-- тесты в neotest (пробел t t) — brew install cargo-nextest.
local settings = require("own.settings")
local root = require("own.root")

local M = {}

local function r() return (settings.current or {}).rust or {} end

function M.plugins()
  return {
    {
      "saecki/crates.nvim",
      tag = "stable",
      event = { "BufRead Cargo.toml" },
      opts = {
        completion = { crates = { enabled = true } },
        lsp = { enabled = true, actions = true, completion = true, hover = true },
      },
    },
    { "andythigpen/nvim-coverage", dependencies = { "nvim-lua/plenary.nvim" }, cmd = { "Coverage", "CoverageLoadLcov", "CoverageToggle", "CoverageSummary" } },
  }
end

-- ── rust-analyzer ───────────────────────────────────────────────────────────

local function client(buf)
  return vim.lsp.get_clients({ bufnr = buf or 0, name = "rust_analyzer" })[1]
end

-- запрос к rust-analyzer; нет сервера — сказать и не звать fn
local function request(method, params, fn)
  local c = client()
  if not c then return vim.notify("rust-analyzer не подключён к этому файлу", vim.log.levels.WARN) end
  c:request(method, params, function(err, res)
    if err then return vim.notify(method .. ": " .. tostring(err.message or err), vim.log.levels.WARN) end
    fn(res, c)
  end, 0)
end

local function pos_params()
  local c = client()
  return vim.lsp.util.make_position_params(0, c and c.offset_encoding or "utf-16")
end

local function jump(loc, c)
  if not loc then return end
  if vim.islist(loc) then loc = loc[1] end
  if not loc then return vim.notify("некуда идти", vim.log.levels.WARN) end
  vim.lsp.util.show_document(loc, c.offset_encoding, { focus = true })
end

-- текст в окне справа (только чтение)
local function show(lines, ft, name)
  vim.cmd("botright vnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "wipe", false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype, vim.bo[buf].modifiable = ft, false
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
end

--- Раскрыть макрос под курсором (println!, derive, свой macro_rules!) — что увидит компилятор
function M.expand_macro()
  request("rust-analyzer/expandMacro", pos_params(), function(res)
    if not res then return vim.notify("курсор не на макросе", vim.log.levels.WARN) end
    show(vim.list_extend({ "// " .. res.name .. "!", "" }, vim.split(res.expansion, "\n")), "rust", "macro://" .. res.name)
  end)
end

function M.open_cargo()
  request("experimental/openCargoToml", { textDocument = vim.lsp.util.make_text_document_params() }, jump)
end

function M.parent_module()
  request("experimental/parentModule", pos_params(), jump)
end

--- Документация на docs.rs (или std) для того, что под курсором
function M.docs()
  request("experimental/externalDocs", pos_params(), function(res)
    local url = type(res) == "table" and (res["local"] and vim.uv.fs_stat((res["local"]:gsub("^file://", ""))) and res["local"] or res.web) or res
    if not url or url == vim.NIL then return vim.notify("для этого нет документации", vim.log.levels.WARN) end
    vim.ui.open(url)
  end)
end

function M.reload_workspace()
  for _, c in ipairs(vim.lsp.get_clients({ name = "rust_analyzer" })) do
    c:request("rust-analyzer/reloadWorkspace", nil, function() vim.notify("rust-analyzer: проект перечитан") end)
    c:request("rust-analyzer/rebuildProcMacros", nil, function() end)
  end
end

--- Сдвинуть функцию / impl / поле / match-ветку целиком вверх или вниз
function M.move(dir)
  local c = client()
  if not c then return end
  local p = pos_params()
  request("experimental/moveItem", {
    textDocument = p.textDocument, range = { start = p.position, ["end"] = p.position }, direction = dir == "up" and "Up" or "Down",
  }, function(edits)
    if not edits or #edits == 0 then return end
    local cursor
    for _, e in ipairs(edits) do
      if e.insertTextFormat == 2 then -- сниппет: $0 — где окажется курсор
        local before = e.newText:match("^(.-)%$0") or e.newText:match("^(.-)%${0[^}]*}")
        if before then
          local lines = vim.split(before, "\n")
          cursor = { e.range.start.line + #lines, (#lines == 1 and e.range.start.character or 0) + #lines[#lines] }
        end
        e.newText = e.newText:gsub("%${0:([^}]*)}", "%1"):gsub("%$0", "")
      end
    end
    vim.lsp.util.apply_text_edits(edits, 0, c.offset_encoding)
    if cursor then pcall(vim.api.nvim_win_set_cursor, 0, cursor) end
  end)
end

-- замечание под курсором (сначала rust-analyzer, ближайшее к колонке)
local function diag_here()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local best
  for _, d in ipairs(vim.diagnostic.get(0, { lnum = row - 1 })) do
    if not best or (d.col <= col and d.end_col >= col) then best = d end
  end
  return best
end

--- Объяснить ошибку под курсором: E0308 — rustc --explain, clippy::… — страница линта
function M.explain()
  local d = diag_here()
  local code = d and (d.code or (d.user_data and d.user_data.lsp and d.user_data.lsp.code))
  if not code then return vim.notify("под курсором нет ошибки с кодом", vim.log.levels.WARN) end
  code = tostring(code)
  local lint = code:match("^clippy::(.+)")
  if lint then return vim.ui.open("https://rust-lang.github.io/rust-clippy/master/index.html#" .. lint) end
  if not code:match("^E%d+$") then
    return vim.ui.open("https://doc.rust-lang.org/rustc/lints/listing/index.html") -- unused_variables и др.
  end
  vim.system({ "rustc", "--explain", code }, { text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then return vim.notify("rustc --explain " .. code .. ": " .. vim.trim(res.stderr or ""), vim.log.levels.WARN) end
    show(vim.split("# " .. code .. "\n\n" .. res.stdout, "\n"), "markdown", "rustc://" .. code)
  end))
end

--- Ошибка под курсором целиком, как её рисует cargo build (со стрелками и подсказками)
function M.rendered()
  local d = diag_here()
  local data = d and d.user_data and d.user_data.lsp and d.user_data.lsp.data
  local text = data and data.rendered or (d and d.message)
  if not text then return vim.notify("под курсором нет ошибки", vim.log.levels.WARN) end
  local lines = vim.split(vim.trim(text), "\n")
  local width = 20
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  local buf = vim.lsp.util.open_floating_preview(lines, "", { border = "rounded", max_width = math.min(width + 2, vim.o.columns - 4), focus_id = "own.rust.rendered" })
  pcall(vim.treesitter.stop, buf)
end

-- ── cargo ───────────────────────────────────────────────────────────────────

--- Папка крейта файла (ближайший Cargo.toml вверх), иначе корень проекта
function M.crate_dir(file)
  local found = vim.fs.find("Cargo.toml", { upward = true, path = vim.fs.dirname(file or vim.api.nvim_buf_get_name(0)) })[1]
  return found and vim.fs.dirname(found) or root.get()
end

--- cargo add: пакет (можно с фичами: serde -F derive, tokio@1 -F full)
function M.add()
  local dir = M.crate_dir()
  vim.ui.input({ prompt = "cargo add: " }, function(t)
    if not t or vim.trim(t) == "" then return end
    vim.notify("cargo add " .. t .. "…")
    vim.system(vim.list_extend({ "cargo", "add" }, vim.split(vim.trim(t), "%s+")), { cwd = dir, text = true }, vim.schedule_wrap(function(res)
      if res.code ~= 0 then return vim.notify("cargo add: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR) end
      vim.notify(vim.trim((res.stderr or ""):gsub("%s*Updating[^\n]*\n?", "")))
      vim.cmd("checktime")
    end))
  end)
end

-- собрать по аргументам cargo и найти исполняемый файл (для отладчика); внутри корутины dap — не замораживая nvim
local function build_exe(cargo_args, cwd, env)
  local cmd = { "cargo" }
  for _, a in ipairs(cargo_args) do
    if a == "run" then a = "build" end
    cmd[#cmd + 1] = a
  end
  if cmd[2] == "test" then table.insert(cmd, 3, "--no-run") end
  if cmd[2] == "bench" then table.insert(cmd, 3, "--no-run") end
  cmd[#cmd + 1] = "--message-format=json"
  local opts = { cwd = cwd, text = true, env = env }
  local co = coroutine.running()
  local res
  if co and coroutine.isyieldable() then
    vim.system(cmd, opts, function(x) vim.schedule(function() coroutine.resume(co, x) end) end)
    res = coroutine.yield()
  else
    res = vim.system(cmd, opts):wait()
  end
  local exe
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local ok, m = pcall(vim.json.decode, line)
    if ok and type(m) == "table" and m.reason == "compiler-artifact" and type(m.executable) == "string" then exe = m.executable end
  end
  if res.code ~= 0 or not exe then
    local err = {}
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      local ok, m = pcall(vim.json.decode, line)
      if ok and type(m) == "table" and m.reason == "compiler-message" and m.message and m.message.level == "error" then
        err[#err + 1] = m.message.rendered or m.message.message
      end
    end
    return nil, #err > 0 and table.concat(err, "\n") or vim.trim(res.stderr or "")
  end
  return exe
end

--- program для dap: собрать cargo-аргументами и вернуть путь к бинарнику (или dap.ABORT)
function M.program(cargo_args, cwd)
  return function()
    vim.notify("cargo " .. table.concat(cargo_args, " ") .. " — собираю для отладчика…")
    local exe, err = build_exe(cargo_args, cwd or root.get())
    if not exe then
      vim.notify("не собралось:\n" .. (err or ""), vim.log.levels.ERROR)
      return require("dap").ABORT
    end
    return exe
  end
end

local function debug_runnable(run)
  local a = run.args
  local cwd = a.cwd or a.workspaceRoot or root.get()
  local cargo_args = vim.list_extend(vim.deepcopy(a.cargoArgs or {}), a.cargoExtraArgs or {})
  local ok, dap = pcall(require, "dap")
  if not ok then return vim.notify("отладчик выключен (modules.debug)", vim.log.levels.WARN) end
  local exec_args = vim.tbl_filter(function(x) return x ~= "--nocapture" end, a.executableArgs or {})
  dap.run({
    name = run.label, type = "codelldb", request = "launch", cwd = cwd, stopOnEntry = false,
    program = M.program(cargo_args, cwd), args = exec_args, env = a.environment,
  })
end

local function term(cmd, cwd, env)
  Snacks.terminal(cmd, { cwd = cwd, env = env, auto_close = false, win = { position = "bottom", height = 0.3 } })
end

local function exec_runnable(run)
  local a = run.args
  local cmd = { a.overrideCargo or "cargo" }
  vim.list_extend(cmd, a.cargoArgs or {})
  vim.list_extend(cmd, a.cargoExtraArgs or {})
  if a.executableArgs and #a.executableArgs > 0 then
    cmd[#cmd + 1] = "--"
    vim.list_extend(cmd, a.executableArgs)
  end
  term(cmd, a.cwd or a.workspaceRoot or root.get(), a.environment)
end

-- запасной путь без rust-analyzer: main — cargo run, тест — cargo test имя
local function fallback(kind, name, debug)
  local dir = M.crate_dir()
  if kind == "main" then
    local file = vim.api.nvim_buf_get_name(0)
    local bin = file:match("/src/bin/([^/]+)%.rs$") or file:match("/src/bin/([^/]+)/main%.rs$")
    local args = { "run" }
    if bin then vim.list_extend(args, { "--bin", bin }) end
    if debug then return debug_runnable({ label = "cargo " .. table.concat(args, " "), args = { cargoArgs = args, cwd = dir } }) end
    return term(vim.list_extend({ "cargo" }, args), dir)
  end
  local args = { "test", "--", name, "--nocapture" }
  if debug then return debug_runnable({ label = name, args = { cargoArgs = { "test" }, executableArgs = { name }, cwd = dir } }) end
  term(vim.list_extend({ "cargo" }, args), dir)
end

--- ▶ под курсором: rust-analyzer говорит, какой cargo-командой это запускается (пакет, цель, точный путь теста)
function M.run_at(kind, name, debug)
  local c = client()
  if not c then return fallback(kind, name, debug) end
  c:request("experimental/runnables", { textDocument = vim.lsp.util.make_text_document_params(), position = pos_params().position }, function(err, list)
    if err or type(list) ~= "table" then return fallback(kind, name, debug) end
    -- самый внутренний: тест внутри mod tests, а не весь модуль
    local best, size
    for _, run in ipairs(list) do
      local rng = run.location and run.location.targetRange
      if run.kind == "cargo" and rng then
        local s = (rng["end"].line - rng.start.line) * 10000 + (rng["end"].character - rng.start.character)
        if not best or s < size then best, size = run, s end
      end
    end
    if not best then return fallback(kind, name, debug) end
    if debug then return debug_runnable(best) end
    exec_runnable(best)
  end, 0)
end

--- Все запускаемое в файле — выбрать (пробел R r): тесты, модули, main, doc-тесты
function M.runnables(debug)
  request("experimental/runnables", { textDocument = vim.lsp.util.make_text_document_params() }, function(list)
    list = vim.tbl_filter(function(x) return x.kind == "cargo" end, list or {})
    if #list == 0 then return vim.notify("запускать нечего", vim.log.levels.WARN) end
    vim.ui.select(list, { prompt = debug and "Отладить" or "Запустить", format_item = function(x) return x.label end }, function(run)
      if not run then return end
      if debug then return debug_runnable(run) end
      exec_runnable(run)
    end)
  end)
end

--- Покрытие: cargo llvm-cov → полосы слева (зелёная — выполнялась, красная — нет), как у Go
function M.coverage()
  if vim.fn.executable("cargo-llvm-cov") == 0 then
    return vim.notify("нужен cargo-llvm-cov: cargo install cargo-llvm-cov (rustup component add llvm-tools-preview — сам)", vim.log.levels.WARN)
  end
  local file = r().coverage_file or "/tmp/rust-lcov.info"
  vim.notify("cargo llvm-cov — жду тесты")
  vim.system({ "cargo", "llvm-cov", "--lcov", "--output-path", file }, { cwd = M.crate_dir(), text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 and not vim.uv.fs_stat(file) then
      return vim.notify("cargo llvm-cov:\n" .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
    end
    if res.code ~= 0 then vim.notify("часть тестов упала — покрытие по тем, что прошли", vim.log.levels.WARN) end
    require("coverage").load_lcov(file, true)
  end))
end

--- Rust-черновик: cargo-проект в данных nvim, src/main.rs — сразу ▶ (пробел r x); зависимости — пробел R a
function M.scratch()
  local dir = vim.fn.stdpath("data") .. "/rust-scratch"
  local file = dir .. "/src/main.rs"
  if not vim.uv.fs_stat(file) then
    vim.fn.mkdir(dir .. "/src", "p")
    vim.fn.writefile({ "[package]", 'name = "scratch"', 'version = "0.1.0"', 'edition = "2024"', "", "[dependencies]" }, dir .. "/Cargo.toml")
    vim.fn.writefile({ "fn main() {", '    println!("черновик");', "}", "", "#[cfg(test)]", "mod tests {", "    #[test]",
      "    fn works() {", "        assert_eq!(2 + 2, 4);", "    }", "}" }, file)
  end
  vim.cmd.edit(file)
end

function M.setup()
  if r().run_marks ~= false then require("own.tools.run").setup("rust") end
end

return M
