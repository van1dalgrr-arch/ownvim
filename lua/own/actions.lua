-- Действия для клавиш в settings.jsonc: "n <leader>ff": "files". Имя действия — ключ этой таблицы.
-- Каждое — { функция, описание }; описание видно в which-key и в пробел s k.
-- Вместо имени можно написать клавиши как есть ("<C-w>h") или команду (":Lazy").
local M = {}

local root = require("own.root")

local function pick(source, opts)
  return function() Snacks.picker[source](opts and opts() or nil) end
end
local function at_root(source) return pick(source, function() return { cwd = root.get() } end) end
local function toggle(make) return function() make():toggle() end end

-- переход к следующей ошибке/предупреждению с открытием окна
local function diag(count, severity)
  return function()
    vim.diagnostic.jump({ count = count * vim.v.count1, severity = severity and vim.diagnostic.severity[severity], float = true })
  end
end

M.list = {
  -- файлы и поиск (Snacks picker)
  files = { at_root("files"), "Найти файл (в проекте)" },
  ["files.cwd"] = { pick("files"), "Найти файл (в папке запуска)" },
  ["files.git"] = { pick("git_files"), "Файлы git" },
  recent = { pick("recent"), "Недавние файлы" },
  ["recent.cwd"] = { pick("recent", function() return { filter = { cwd = true } } end), "Недавние в этой папке" },
  projects = { pick("projects"), "Проекты" },
  buffers = { pick("buffers"), "Открытые буферы" },
  ["buffers.all"] = { pick("buffers", function() return { hidden = true, nofile = true } end), "Все буферы" },
  grep = { at_root("grep"), "Поиск текста (в проекте)" },
  ["grep.cwd"] = { pick("grep"), "Поиск текста (в папке запуска)" },
  ["grep.word"] = { at_root("grep_word"), "Слово под курсором / выделение (в проекте)" },
  ["grep.word.cwd"] = { pick("grep_word"), "Слово под курсором / выделение (в папке)" },
  ["grep.buffers"] = { pick("grep_buffers"), "Поиск по открытым буферам" },
  lines = { pick("lines"), "Строки буфера" },
  commands = { pick("commands"), "Все команды" },
  ["command.history"] = { pick("command_history"), "История команд" },
  notifications = { pick("notifications"), "История уведомлений" },
  autocmds = { pick("autocmds"), "Автокоманды" },
  diagnostics = { pick("diagnostics"), "Ошибки проекта" },
  ["diagnostics.buffer"] = { pick("diagnostics_buffer"), "Ошибки файла" },
  help = { pick("help"), "Справка" },
  highlights = { pick("highlights"), "Группы подсветки" },
  icons = { pick("icons"), "Иконки" },
  jumps = { pick("jumps"), "Прыжки" },
  keymaps = { pick("keymaps"), "Все клавиши" },
  loclist = { pick("loclist"), "Location list" },
  man = { pick("man"), "man-страницы" },
  marks = { pick("marks"), "Метки" },
  resume = { pick("resume"), "Вернуть прошлый поиск" },
  quickfix = { pick("qflist"), "Quickfix" },
  undotree = { pick("undo"), "История правок" },
  explorer = {
    function()
      if (((require("own.settings").current or {}).explorer or {}).engine or "own") == "own" then
        return require("own.tree").toggle(root.get())
      end
      Snacks.explorer({ cwd = root.get() })
    end,
    "Дерево файлов (проект)",
  },
  ["explorer.cwd"] = {
    function()
      if (((require("own.settings").current or {}).explorer or {}).engine or "own") == "own" then
        return require("own.tree").toggle(vim.uv.cwd())
      end
      Snacks.explorer()
    end,
    "Дерево файлов (папка запуска)",
  },
  settings = { function() require("own.settings").open() end, "Мои настройки (settings.jsonc)" },
  ["settings.defaults"] = { function() require("own.settings").open("defaults") end, "Все настройки по умолчанию" },
  themes = { function() require("own.themes").pick() end, "Тема (предпросмотр, enter — запомнить)" },

  -- правка
  save = { "<cmd>write<cr><esc>", "Сохранить" },
  esc = {
    function()
      vim.cmd("nohlsearch")
      if vim.snippet then vim.snippet.stop() end
      return "<esc>"
    end,
    "Убрать подсветку поиска",
    expr = true,
  },
  down = { "v:count == 0 ? 'gj' : 'j'", "Вниз (по экранным строкам)", expr = true },
  up = { "v:count == 0 ? 'gk' : 'k'", "Вверх (по экранным строкам)", expr = true },
  ["search.next"] = { "'Nn'[v:searchforward].'zv'", "Следующее найденное", expr = true },
  ["search.prev"] = { "'nN'[v:searchforward].'zv'", "Предыдущее найденное", expr = true },
  ["lines.down"] = { ":m '>+1<cr>gv=gv", "Строки вниз" },
  ["lines.up"] = { ":m '<-2<cr>gv=gv", "Строки вверх" },

  -- буферы и окна
  ["buffer.delete"] = { function() Snacks.bufdelete() end, "Закрыть буфер" },
  ["buffer.others"] = { function() Snacks.bufdelete.other() end, "Закрыть остальные буферы" },
  ["window.zoom"] = { toggle(function() return Snacks.toggle.zoom() end), "Окно на весь экран" },
  zen = { toggle(function() return Snacks.toggle.zen() end), "Zen: только код" },
  terminal = { function() Snacks.terminal() end, "Терминал (папка запуска)" },
  ["terminal.root"] = { function() Snacks.terminal(nil, { cwd = root.get() }) end, "Терминал (проект)" },
  ["terminal.toggle"] = { function() Snacks.terminal.focus(nil, { cwd = root.get() }) end, "Терминал снизу" },

  -- ошибки
  ["diagnostic.float"] = { vim.diagnostic.open_float, "Ошибка строки целиком" },
  ["diagnostic.next"] = { diag(1), "Следующая проблема" },
  ["diagnostic.prev"] = { diag(-1), "Предыдущая проблема" },
  ["error.next"] = { diag(1, "ERROR"), "Следующая ошибка" },
  ["error.prev"] = { diag(-1, "ERROR"), "Предыдущая ошибка" },
  ["warning.next"] = { diag(1, "WARN"), "Следующее предупреждение" },
  ["warning.prev"] = { diag(-1, "WARN"), "Предыдущее предупреждение" },
  ["quickfix.toggle"] = {
    function()
      local ok, err = pcall(vim.fn.getqflist({ winid = 0 }).winid ~= 0 and vim.cmd.cclose or vim.cmd.copen)
      if not ok and err then vim.notify(err, vim.log.levels.ERROR) end
    end,
    "Quickfix: открыть/закрыть",
  },
  ["loclist.toggle"] = {
    function()
      local ok, err = pcall(vim.fn.getloclist(0, { winid = 0 }).winid ~= 0 and vim.cmd.lclose or vim.cmd.lopen)
      if not ok and err then vim.notify(err, vim.log.levels.ERROR) end
    end,
    "Location list: открыть/закрыть",
  },

  -- переключатели (пробел u …)
  ["toggle.spell"] = { toggle(function() return Snacks.toggle.option("spell", { name = "Орфография" }) end), "Орфография" },
  ["toggle.wrap"] = { toggle(function() return Snacks.toggle.option("wrap", { name = "Перенос строк" }) end), "Перенос строк" },
  ["toggle.relativenumber"] = { toggle(function() return Snacks.toggle.option("relativenumber", { name = "Относительные номера" }) end), "Относительные номера" },
  ["toggle.number"] = { toggle(function() return Snacks.toggle.line_number() end), "Номера строк" },
  ["toggle.diagnostics"] = { toggle(function() return Snacks.toggle.diagnostics() end), "Показ ошибок" },
  ["toggle.conceal"] = {
    toggle(function() return Snacks.toggle.option("conceallevel", { off = 0, on = 2, name = "Скрытие разметки" }) end),
    "Скрытие разметки",
  },
  ["toggle.treesitter"] = { toggle(function() return Snacks.toggle.treesitter() end), "Подсветка treesitter" },
  ["toggle.background"] = {
    toggle(function() return Snacks.toggle.option("background", { off = "light", on = "dark", name = "Тёмный фон" }) end),
    "Тёмный / светлый фон",
  },
  ["toggle.dim"] = { toggle(function() return Snacks.toggle.dim() end), "Приглушить код вне функции" },
  ["toggle.indent"] = { toggle(function() return Snacks.toggle.indent() end), "Линии отступов" },
  ["toggle.inlay_hints"] = { toggle(function() return Snacks.toggle.inlay_hints() end), "Подсказки типов" },
  ["toggle.auto_normal"] = {
    function()
      vim.g.auto_normal = vim.g.auto_normal == false
      vim.notify("автовыход из вставки: " .. (vim.g.auto_normal and "вкл" or "выкл"))
    end,
    "Автовыход из вставки",
  },
  inspect = { vim.show_pos, "Что за подсветка под курсором" },
  image_panel = { function() require("own.modules.image_panel").toggle() end, "Картинка сбоку (вкл/выкл)" },
  store = { function() require("own.store").open() end, "Магазин плагинов" },
  health = { "<cmd>checkhealth own<cr>", "Проверка здоровья ownvim" },
  ["session.load"] = { function() require("own.modules.sessions").load() end, "Вернуть сессию этой папки" },
  ["session.pick"] = { function() require("own.modules.sessions").pick() end, "Выбрать сессию" },
  ["session.stop"] = { function() require("own.modules.sessions").stop() end, "Не сохранять сессию при выходе" },

  -- код (языковые серверы)
  ["lsp.definition"] = { pick("lsp_definitions"), "Перейти к определению" },
  ["lsp.references"] = { pick("lsp_references"), "Где используется", nowait = true },
  ["lsp.implementation"] = { pick("lsp_implementations"), "Реализации" },
  ["lsp.type_definition"] = { pick("lsp_type_definitions"), "К определению типа" },
  ["lsp.declaration"] = { pick("lsp_declarations"), "К объявлению" },
  ["lsp.symbols"] = { pick("lsp_symbols"), "Символы файла" },
  ["lsp.workspace_symbols"] = { pick("lsp_workspace_symbols"), "Символы проекта" },
  ["lsp.incoming_calls"] = { pick("lsp_incoming_calls"), "Кто вызывает" },
  ["lsp.outgoing_calls"] = { pick("lsp_outgoing_calls"), "Что вызывает" },
  ["lsp.hover"] = { function() vim.lsp.buf.hover() end, "Описание под курсором" },
  ["lsp.signature"] = { function() vim.lsp.buf.signature_help() end, "Подсказка аргументов" },
  ["lsp.code_action"] = {
    function()
      -- с превью изменений (tiny-code-action, модуль go), если он есть
      local ok, tiny = pcall(require, "tiny-code-action")
      if ok then return tiny.code_action() end
      vim.lsp.buf.code_action()
    end,
    "Исправить / действия с кодом (с превью)",
  },
  ["cpp.switch"] = {
    function()
      if vim.fn.exists(":LspClangdSwitchSourceHeader") == 2 then return vim.cmd("LspClangdSwitchSourceHeader") end
      vim.notify("переключение .h ↔ .cpp — в C/C++-файле с clangd", vim.log.levels.WARN)
    end,
    "C/C++: заголовок ↔ исходник",
  },
  ["refactor.extract"] = {
    function() vim.lsp.buf.code_action({ context = { only = { "refactor.extract" }, diagnostics = {} } }) end,
    "Вынести: функцию, переменную, константу",
  },
  ["refactor.inline"] = {
    function() vim.lsp.buf.code_action({ context = { only = { "refactor.inline" }, diagnostics = {} } }) end,
    "Встроить вызов / переменную",
  },
  ["refactor.rewrite"] = {
    function() vim.lsp.buf.code_action({ context = { only = { "refactor.rewrite" }, diagnostics = {} } }) end,
    "Переписать: fill struct, if↔else, параметры…",
  },
  ["go.compiler_details"] = {
    function() vim.lsp.buf.code_action({ context = { only = { "source.toggleCompilerOptDetails" }, diagnostics = {} } }) end,
    "Оптимизации компилятора: куча / инлайн",
  },
  ["lsp.source_action"] = {
    function() vim.lsp.buf.code_action({ context = { only = { "source" }, diagnostics = {} } }) end,
    "Действия с файлом (импорты…)",
  },
  ["lsp.rename"] = { function() vim.lsp.buf.rename() end, "Переименовать" },
  ["lsp.rename_file"] = { function() Snacks.rename.rename_file() end, "Переименовать файл (и импорты)" },
  ["lsp.codelens"] = { function() vim.lsp.codelens.run() end, "Запустить codelens" },
  ["lsp.info"] = { "<cmd>checkhealth vim.lsp<cr>", "Какие серверы работают" },
  ["lsp.restart"] = { "<cmd>lsp restart<cr>", "Перезапустить серверы" },
  ["lsp.word_next"] = { function() Snacks.words.jump(vim.v.count1) end, "Следующее упоминание" },
  ["lsp.word_prev"] = { function() Snacks.words.jump(-vim.v.count1) end, "Предыдущее упоминание" },
  mason = { "<cmd>Mason<cr>", "Mason: серверы и утилиты" },
  format = { function() require("own.modules.format").format() end, "Отформатировать" },

  -- тесты (neotest)
  ["test.nearest"] = { function() require("neotest").run.run() end, "Тест под курсором" },
  ["test.file"] = { function() require("neotest").run.run(vim.fn.expand("%")) end, "Тесты файла" },
  ["test.all"] = { function() require("neotest").run.run(vim.uv.cwd()) end, "Все тесты проекта" },
  ["test.last"] = { function() require("neotest").run.run_last() end, "Повторить последний" },
  ["test.debug"] = { function() require("neotest").run.run({ strategy = "dap" }) end, "Тест под курсором — в отладчике" },
  ["test.stop"] = { function() require("neotest").run.stop() end, "Остановить тесты" },
  ["test.summary"] = { function() require("neotest").summary.toggle() end, "Дерево тестов" },
  ["test.output"] = { function() require("neotest").output.open({ enter = true, auto_close = true }) end, "Вывод теста" },
  ["test.output_panel"] = { function() require("neotest").output_panel.toggle() end, "Панель вывода тестов" },
  ["test.watch"] = { function() require("neotest").watch.toggle(vim.fn.expand("%")) end, "Перезапускать при сохранении" },

  -- отладчик (nvim-dap)
  ["debug.breakpoint"] = { function() require("persistent-breakpoints.api").toggle_breakpoint() end, "Точка останова" },
  ["debug.breakpoint_condition"] = { function() require("persistent-breakpoints.api").set_conditional_breakpoint() end, "Точка останова с условием" },
  ["debug.continue"] = { function() require("dap").continue() end, "Запустить / дальше" },
  ["debug.run_to_cursor"] = { function() require("dap").run_to_cursor() end, "До курсора" },
  ["debug.step_over"] = { function() require("dap").step_over() end, "Шаг" },
  ["debug.step_into"] = { function() require("dap").step_into() end, "Внутрь" },
  ["debug.step_out"] = { function() require("dap").step_out() end, "Наружу" },
  ["debug.run_last"] = { function() require("dap").run_last() end, "Повторить последний запуск" },
  ["debug.pause"] = { function() require("dap").pause() end, "Пауза" },
  ["debug.terminate"] = { function() require("dap").terminate() end, "Остановить" },
  ["debug.repl"] = { function() require("dap").repl.toggle() end, "REPL" },
  ["debug.ui"] = {
    function()
      require("dap")
      require("dapui").toggle({})
    end,
    "Панели отладчика",
  },
  ["debug.eval"] = { function() require("dapui").eval() end, "Значение выражения" },
  ["debug.up"] = { function() require("dap").up() end, "Кадр стека выше" },
  ["debug.down"] = { function() require("dap").down() end, "Кадр стека ниже" },

  -- git
  lazygit = { function() Snacks.lazygit({ cwd = root.git() }) end, "lazygit" },
  ["git.hunk_next"] = {
    function()
      if vim.wo.diff then return vim.cmd.normal({ "]c", bang = true }) end
      require("gitsigns").nav_hunk("next")
    end,
    "Следующее изменение",
  },
  ["git.hunk_prev"] = {
    function()
      if vim.wo.diff then return vim.cmd.normal({ "[c", bang = true }) end
      require("gitsigns").nav_hunk("prev")
    end,
    "Предыдущее изменение",
  },
  ["git.hunk_stage"] = { "<cmd>Gitsigns stage_hunk<cr>", "Кусок — в коммит (ещё раз — убрать)" },
  ["git.hunk_reset"] = { "<cmd>Gitsigns reset_hunk<cr>", "Вернуть кусок как было" },
  ["git.hunk_preview"] = { function() require("gitsigns").preview_hunk_inline() end, "Показать, что было" },
  ["git.buffer_stage"] = { function() require("gitsigns").stage_buffer() end, "Весь файл — в коммит" },
  ["git.buffer_reset"] = { function() require("gitsigns").reset_buffer() end, "Вернуть весь файл" },
  ["git.blame_line"] = { function() require("gitsigns").blame_line({ full = true }) end, "Кто менял строку (коммит целиком)" },
  ["git.blame"] = { function() require("gitsigns").blame() end, "Blame всего файла" },
  ["git.blame_toggle"] = { function() require("gitsigns").toggle_current_line_blame() end, "Blame строки серым справа" },
  ["git.diff"] = { "<cmd>DiffviewOpen<cr>", "Все изменения / конфликты (diffview)" },
  ["git.diff_close"] = { "<cmd>DiffviewClose<cr>", "Закрыть diffview" },
  ["git.file_history"] = { "<cmd>DiffviewFileHistory %<cr>", "История файла" },
  ["git.repo_history"] = { "<cmd>DiffviewFileHistory<cr>", "История репозитория" },
  ["git.branch_vs_base"] = {
    function() vim.cmd("DiffviewOpen " .. require("own.modules.git").base_branch() .. "...HEAD") end,
    "Ветка против main (как PR)",
  },
  ["git.status"] = { pick("git_status"), "Изменённые файлы" },
  ["git.log"] = { function() Snacks.picker.git_log({ cwd = root.git() }) end, "Коммиты" },
  ["git.log_file"] = { pick("git_log_file"), "Коммиты этого файла" },
  ["git.log_line"] = { pick("git_log_line"), "Коммиты этой строки" },
  ["git.branches"] = { pick("git_branches"), "Ветки (enter — переключиться)" },
  ["git.stash"] = { pick("git_stash"), "Stash" },
  ["git.browse"] = { function() Snacks.gitbrowse() end, "Открыть на GitHub" },
  undotree = {
    function()
      vim.cmd.packadd("nvim.undotree") -- встроен в nvim 0.12
      require("undotree").open({ command = "topleft 40vnew" })
    end,
    "История правок файла (без git)",
  },

  -- Go (модуль go)
  ["go.run"] = { function() require("own.tools.run").run(false) end, "▶ Запустить функцию под курсором (main / тест)" },
  ["go.debug"] = { function() require("own.tools.run").run(true) end, "▶ То же под отладчиком" },
  ["go.scratch"] = { function() require("own.modules.go").scratch() end, "Go-черновик" },
  ["go.coverage"] = { function() require("own.modules.go").coverage() end, "Покрытие: прогнать тесты и показать" },
  ["go.coverage_toggle"] = { "<cmd>CoverageToggle<cr>", "Покрытие: спрятать / показать" },
  ["go.coverage_summary"] = { "<cmd>CoverageSummary<cr>", "Покрытие: проценты по файлам" },
  ["go.tags_json"] = { "<cmd>GoTagAdd json<cr>", "Теги json у полей" },
  ["go.tags_yaml"] = { "<cmd>GoTagAdd yaml<cr>", "Теги yaml" },
  ["go.tags_db"] = { "<cmd>GoTagAdd db<cr>", "Теги db" },
  ["go.tags"] = {
    function()
      vim.ui.input({ prompt = "Какие теги добавить (json,validate…): " }, function(t) if t and t ~= "" then vim.cmd("GoTagAdd " .. t) end end)
    end,
    "Теги: свои",
  },
  ["go.tags_remove"] = { "<cmd>GoTagRm<cr>", "Убрать теги" },
  ["go.impl"] = {
    function()
      vim.ui.input({ prompt = "Какой интерфейс реализовать (io.Reader, http.Handler…): " }, function(t) if t and t ~= "" then vim.cmd("GoImpl " .. t) end end)
    end,
    "Реализовать интерфейс (курсор на типе)",
  },
  ["go.iferr"] = { "<cmd>GoIfErr<cr>", "if err != nil { return … }" },
  ["go.comment"] = { "<cmd>GoCmt<cr>", "Doc-комментарий" },
  ["go.test_add"] = { "<cmd>GoTestAdd<cr>", "Тест для функции под курсором" },
  ["go.tests_all"] = { "<cmd>GoTestsAll<cr>", "Тесты для всех функций файла" },
  ["go.mod_tidy"] = { "<cmd>GoMod tidy<cr>", "go mod tidy" },
  ["go.get"] = {
    function() vim.ui.input({ prompt = "go get: " }, function(t) if t and t ~= "" then vim.cmd("GoGet " .. t) end end) end,
    "go get пакет",
  },
  ["go.json2struct"] = { "<cmd>GoJson<cr>", "JSON → Go-структура" },
  ["peek.definition"] = { "<cmd>Glance definitions<cr>", "Посмотреть определение (без перехода)" },
  ["peek.references"] = { "<cmd>Glance references<cr>", "Посмотреть использования" },
  ["peek.implementations"] = { "<cmd>Glance implementations<cr>", "Посмотреть реализации" },
  ["peek.type"] = { "<cmd>Glance type_definitions<cr>", "Посмотреть тип" },

  -- задачи, HTTP, эндпоинты, тесты в фоне
  tasks = { "<cmd>OverseerRun<cr>", "Задачи (как ctrl-r в Zed)" },
  ["tasks.running"] = { "<cmd>OverseerToggle!<cr>", "Что запущено" },
  lazydocker = { function() Snacks.terminal("lazydocker", { cwd = root.get() }) end, "lazydocker" },
  endpoints = { function() require("own.tools.endpoints").pick() end, "Эндпоинты API (Gin)" },
  ["http.file"] = { function() require("own.tools.endpoints").http_file() end, "api.http — Postman в файле" },
  ["autotest.toggle"] = { function() require("own.tools.autotest").toggle() end, "Тесты в фоне вкл/выкл" },

  -- Claude
  ["ai.toggle"] = { function() require("own.modules.ai").toggle() end, "Claude: спрятать / показать" },
  ["ai.fix"] = { function() require("own.modules.ai").fix() end, "Claude: почини ошибку под курсором" },
  ["ai.review"] = { function() require("own.tools.review").run() end, "Claude: ревью ветки (замечания в коде)" },
  ["ai.review_clear"] = { function() require("own.tools.review").clear() end, "Claude: убрать замечания ревью" },
  ["ai.send"] = { "<cmd>ClaudeCodeSend<cr>", "Claude: отправить выделенное" },
  ["ai.add_file"] = { "<cmd>ClaudeCodeAdd %<cr>", "Claude: добавить файл в контекст" },
  ["ai.accept"] = { "<cmd>ClaudeCodeDiffAccept<cr>", "Claude: принять правку" },
  ["ai.deny"] = { "<cmd>ClaudeCodeDiffDeny<cr>", "Claude: отклонить правку" },

  -- система
  containers = { function() require("own.modules.system").containers() end, "Контейнеры (alt-o ещё раз — спрятать)" },
  github = { function() require("own.modules.system").github() end, "GitHub: PR, Actions, логи (gw)" },
  shot = {
    function()
      local mode = vim.fn.mode()
      if mode == "v" or mode == "V" or mode == "\22" then
        local a, b = vim.fn.line("v"), vim.fn.line(".")
        vim.cmd("normal! \27")
        return require("own.tools.shot").shot(math.min(a, b), math.max(a, b))
      end
      require("own.tools.shot").shot()
    end,
    "Скриншот кода → PNG в буфер обмена (freeze)",
  },
  kubernetes = { function() require("kubectl").toggle({ tab = true }) end, "Kubernetes (kubectl.nvim)" },

  -- файлы, замена, удобство
  yazi = { "<cmd>Yazi<cr>", "yazi — у текущего файла" },
  ["yazi.cwd"] = { "<cmd>Yazi cwd<cr>", "yazi — корень проекта" },
  replace = { function() require("own.modules.files").replace() end, "Найти и заменить по проекту" },
  ["replace.structural"] = { function() require("own.modules.files").structural() end, "Структурная замена (ast-grep)" },
  ["jump.line"] = { function() require("own.modules.comfort").jump_line() end, "Прыжок на строку (метки)" },
  ["learn.hints"] = {
    function()
      local p = require("precognition")
      vim.g.own_precognition = not vim.g.own_precognition
      if vim.g.own_precognition then p.show() else p.hide() end
    end,
    "Подсказки движений в строке",
  },
  ["learn.hardtime"] = { "<cmd>Hardtime toggle<cr>", "Тренер vim (hardtime) вкл/выкл" },
  ["learn.report"] = { "<cmd>Hardtime report<cr>", "Тренер vim: какие привычки чаще всего" },
  ["cloak.toggle"] = { "<cmd>CloakToggle<cr>", "Секреты в .env: показать / спрятать" },

  -- база данных (dadbod)
  database = { "<cmd>DBUIToggle<cr>", "База данных" },
  ["database.add"] = { "<cmd>DBUIAddConnection<cr>", "Добавить подключение" },
  ["format.info"] = { "<cmd>ConformInfo<cr>", "Чем форматируется этот файл" },
  ["toggle.format"] = {
    function()
      vim.g.autoformat = vim.g.autoformat == false
      vim.notify("форматирование при сохранении: " .. (vim.g.autoformat and "вкл" or "выкл"))
    end,
    "Форматирование при сохранении",
  },
}

--- Действие по имени: rhs, описание, доп. опции keymap. nil — такого нет.
function M.get(name)
  local a = M.list[name]
  if not a then return nil end
  return a[1], a[2], { expr = a.expr, nowait = a.nowait }
end

return M
