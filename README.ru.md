# ownvim — своя сборка Neovim

🇬🇧 [English](README.md)

Neovim без LazyVim: свой код на ~2300 строк, идеи взяты из LazyVim. Всё настраивается в одном
JSON-файле, без Lua. Стартует примерно за 40 мс (LazyVim-сборка из dotfiles — за 49).

## Установка

Нужны Neovim 0.12+, git, `tree-sitter` и `ripgrep` (`brew install neovim tree-sitter ripgrep`) и шрифт Nerd Font.

```bash
git clone https://github.com/van1dalgrr-arch/ownvim ~/dev/ownvim
ln -s ~/dev/ownvim ~/.config/ownvim
alias ownvim="NVIM_APPNAME=ownvim nvim"   # в ~/.zshrc
ownvim                                   # первый запуск сам поставит плагины
```

С [dotfiles](https://github.com/van1dalgrr-arch/dotfiles) всё это делает `install.sh`, а rose-pine
берёт палитру темы терминала (`themes/<тема>.sh`).

## Настройки

- `defaults.jsonc` — все умолчания с пояснениями. Его не правь.
- `settings.jsonc` — **только то, что меняешь ты** (`пробел f c` или `:Settings`). Удалил строку — вернулось умолчание.

Сохранил `settings.jsonc` — тема, опции, клавиши и настройки модулей **применяются сразу**.
Включить/выключить модуль или плагин — после `:restart`. Ошибка в JSON или опечатка в имени —
подсветка на её строке, редактор работает дальше на прошлых настройках.

```jsonc
{
  "theme": "rose-pine",                                  // или "auto" — та, что выбрана в alt-s
  "options": { "relativenumber": true },                 // любая опция :help options
  "modules": {
    "smear_cursor": true,                                // включить модуль
    "modes": { "auto_normal_ms": 0 },                    // настройки модуля
  },
  "keys": {
    "n <leader>z": ":Lazy",                              // команда
    "n <leader>ff": "files.git",                         // действие (список — пробел s k)
    "i jk": false,                                       // убрать клавишу
  },
  "plugins": {
    "folke/zen-mode.nvim": { "cmd": "ZenMode", "opts": {} }, // любой плагин, как в lazy.nvim
    "folke/flash.nvim": false,                           // убрать плагин модуля
  },
}
```

Комментарии и запятые в конце разрешены, как в settings.json у Zed и VS Code.

## Модули

| модуль | что внутри |
|---|---|
| `basics` | подсветка скопированного, курсор на прошлом месте, `q` закрывает служебные окна, папка нового файла создаётся сама |
| `ui` | стартовый экран из JSON (заголовок, кнопки, разделы — раздел `dashboard`), уведомления, which-key, линии отступов |
| `font` | шрифт в Ghostty из `settings.jsonc` (семейство, размер, лигатуры, высота строки, OpenType-фичи); `:Font` — выбрать из установленных, `:FontInstall <имя>` — поставить через brew / Nerd Fonts. Значки Nerd Font у Ghostty встроены — подойдёт любой шрифт |
| `tabline` | вкладки как в VS Code: значок, имя, ● несохранённого, крестик; клик мышью, средняя кнопка — закрыть; одинаковые имена — с папкой; прокрутка к текущей. Раздел `tabline` |
| `breadcrumbs` | хлебные крошки сверху: папка › файл › тип › функция под курсором (по дереву разбора, любой язык). Раздел `breadcrumbs` |
| `statusline` | своя статусная строка: блоки в JSON (режим, ветка, ошибки, файл, LSP, позиция, время, поиск, макрос + свои — текст или вывод команды по таймеру), стили bubbles / arrows / slant / flat / plain, цвета из темы. Раздел `statusline` |
| `picker` | поиск файлов, текста, команд, дерево файлов (Snacks); `alt-c` в поиске — проект ↔ папка запуска |
| `treesitter` | подсветка, отступы, складки; список языков в настройках, недостающие ставятся сами |
| `editing` | скобки, текстовые объекты `af`/`ic`/`ao`, обрамление `gsa`/`gsd`/`gsr`, прыжок `s`, TODO |
| `icons` | темы иконок — JSON в `icons/`: default, mono, accent, backend (Go/SQL/Docker/миграции заметнее), ascii; `:IconTheme` — выбрать, `:IconThemeInstall` — по ссылке; свои значки и цвета — `"icons.overrides"`. Значки — в дереве, поиске, меню дополнения |
| `themes` | свой движок тем: тема — JSON в `themes/` (Dev Night, Dev Day, Sunset); `:ThemeNew` — своя (сохранил — перекрасилось), `:ThemeInstall издатель.имя` — любая тема VS Code (Open VSX / Marketplace), `:ThemeEdit`; `"theme": { "dark", "light" }` — по системе; `"colors"` — правки поверх темы, как в VS Code; `alt-s` — выбор с предпросмотром, пишет в settings.jsonc. Темы-плагины (tokyonight, rose-pine…) тоже работают |
| `modes` | режим цветом курсора и строки, выход из вставки после паузы |
| `autosave` | файл пишется сам, изменения снаружи подхватываются |
| `russian` | команды в русской раскладке (`о` = `j`, `вв` = `dd`), alt-клавиши и в ней тоже |
| `scrollbar` | полоса прокрутки с метками ошибок, git и найденного |
| `smear_cursor` | летающий курсор (выключен) |
| `completion` | автодополнение (blink): меню с описанием, продолжение серым в строке, подсказка аргументов, сниппеты (свои — `snippets/<язык>.json`, для Go: `ife`, `errw`, `tt`, `gh`…). Раздел `completion` |
| `format` | форматирование при сохранении (conform): Go — goimports + gofumpt, SQL — pg_format, Python — ruff, Rust — rustfmt, shell — shfmt, TOML — taplo; остальное — языковой сервер. `пробел c f`, `пробел u f` — выкл. Раздел `format` |
| `lint` | линтеры сверх сервера (nvim-lint): Go — golangci-lint (с `.golangci.yml` проекта), Dockerfile — hadolint. Раздел `lint` |
| `test` | тесты (neotest): `пробел t r` — под курсором, `t t` — файл, `t T` — все, `t o` — вывод; упавшая проверка — ошибкой на её строке. Go, Python (Rust — с cargo-nextest). Раздел `test` |
| `debug` | отладчик (nvim-dap + delve): F9 запуск, F8 шаг, F7 внутрь, shift-F8 наружу, ctrl-F8 точка останова (сохраняются между запусками); панели и значения переменных в коде; подключение к dlv в Docker. Раздел `debug` |
| `database` | база (dadbod): `пробел D` / `alt-d` — подключения и таблицы, подключение проекта из `.env` само; в `.sql` дополнение по таблицам. Раздел `database` |
| `lsp` | языковые серверы для Go, SQL (Postgres), Docker, Python, Rust, JSON, YAML — ставятся сами через mason; ошибки на строках, `gd`/`gr`/`K`, переименование `пробел c r`, исправления `пробел c a`, подсказки типов. Разделы `lsp`, `diagnostics`, `tools` |

Код модулей — `lua/own/modules/<имя>.lua`, ядро — `lua/own/` (настройки, JSONC, клавиши, действия).

## Что дальше

Этап 1 из 4 — база. Дальше: Go как IDE (gopls, дополнение, форматирование, тесты, отладка),
git, перенос своих модулей (эндпоинты, `.http`, ▶, фоновые тесты, Claude). Когда догонит —
`ownvim` станет основным `nvim`.
