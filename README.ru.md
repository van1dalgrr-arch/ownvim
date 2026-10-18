# ownvim — своя сборка Neovim

🇬🇧 [English](README.md)

Neovim без LazyVim: свой код на ~1500 строк, идеи взяты из LazyVim. Всё настраивается в одном
JSON-файле, без Lua. Стартует за 20 мс (тот же набор на LazyVim — за 49).

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
| `ui` | стартовый экран, уведомления, статусная строка «пузырями» с режимом по-русски, which-key, линии отступов |
| `picker` | поиск файлов, текста, команд, дерево файлов (Snacks); `alt-c` в поиске — проект ↔ папка запуска |
| `treesitter` | подсветка, отступы, складки; список языков в настройках, недостающие ставятся сами |
| `editing` | скобки, текстовые объекты `af`/`ic`/`ao`, обрамление `gsa`/`gsd`/`gsr`, прыжок `s`, TODO |
| `themes` | tokyonight, rose-pine в цветах терминала и ещё семь — `alt-s` с предпросмотром |
| `modes` | режим цветом курсора и строки, выход из вставки после паузы |
| `autosave` | файл пишется сам, изменения снаружи подхватываются |
| `russian` | команды в русской раскладке (`о` = `j`, `вв` = `dd`), alt-клавиши и в ней тоже |
| `scrollbar` | полоса прокрутки с метками ошибок, git и найденного |
| `smear_cursor` | летающий курсор (выключен) |
| `lsp` | языковые серверы для Go, SQL (Postgres), Docker, Python, Rust, JSON, YAML — ставятся сами через mason; ошибки на строках, `gd`/`gr`/`K`, переименование `пробел c r`, исправления `пробел c a`, подсказки типов. Разделы `lsp`, `diagnostics`, `tools` |

Код модулей — `lua/own/modules/<имя>.lua`, ядро — `lua/own/` (настройки, JSONC, клавиши, действия).

## Что дальше

Этап 1 из 4 — база. Дальше: Go как IDE (gopls, дополнение, форматирование, тесты, отладка),
git, перенос своих модулей (эндпоинты, `.http`, ▶, фоновые тесты, Claude). Когда догонит —
`ownvim` станет основным `nvim`.
