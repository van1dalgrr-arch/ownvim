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
  explorer = { function() Snacks.explorer({ cwd = root.get() }) end, "Дерево файлов (проект)" },
  ["explorer.cwd"] = { function() Snacks.explorer() end, "Дерево файлов (папка запуска)" },
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
  ["lsp.code_action"] = { function() vim.lsp.buf.code_action() end, "Исправить / действия с кодом" },
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
}

--- Действие по имени: rhs, описание, доп. опции keymap. nil — такого нет.
function M.get(name)
  local a = M.list[name]
  if not a then return nil end
  return a[1], a[2], { expr = a.expr, nowait = a.nowait }
end

return M
