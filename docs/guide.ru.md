# ownvim — руководство

🇬🇧 [English](guide.md) · [Все клавиши](keys.ru.md) · [README](../README.ru.md)

ownvim — своя IDE в терминале для бэкенда: Go, C/C++, SQL, Docker, Python, Rust. Всё, что видно и как работает, задаётся
в одном файле — `settings.jsonc`. Lua писать не нужно.

- [Установка](#установка)
- [Если vim незнаком: 13 клавиш](#если-vim-незнаком-13-клавиш)
- [Как устроены настройки](#как-устроены-настройки)
- [Рецепты](#рецепты) — тема, иконки, шрифт, статусная строка, клавиши, языки, задачи…
- [Все разделы settings.jsonc](#все-разделы-settingsjsonc)
- [Если что-то не так](#если-что-то-не-так)
- [Как это устроено внутри](#как-это-устроено-внутри)

## Установка

Нужны Neovim 0.12+, git, `tree-sitter`, `ripgrep` и терминал со шрифтом Nerd Font (в Ghostty значки встроены).

```bash
brew install neovim tree-sitter ripgrep
git clone https://github.com/van1dalgrr-arch/ownvim ~/dev/ownvim
ln -s ~/dev/ownvim ~/.config/ownvim
echo 'alias ownvim="NVIM_APPNAME=ownvim nvim"' >> ~/.zshrc && exec zsh
ownvim
```

Первый запуск сам ставит плагины, парсеры языков, языковые серверы, форматтеры и линтеры (mason). Минута — и готово.
С [dotfiles](https://github.com/van1dalgrr-arch/dotfiles) всё это делает `install.sh`.

## Если vim незнаком: 13 клавиш

| что | клавиша |
|---|---|
| начать печатать / закончить | `i` / `esc` или быстро `jk` (и само через 5 с паузы) |
| принять подсказку | `tab` или `enter` (серое продолжение в строке — тоже `tab`) |
| сохранить | `cmd-s` (и так сохраняется само) |
| найти файл | `пробел пробел` или `cmd-p` |
| найти текст по проекту | `пробел /` |
| дерево файлов | `пробел e` |
| прыгнуть на строку | `enter` — у строк появятся буквы, нажми нужную |
| к определению / где используется | `gd` / `gr` |
| описание под курсором | `K` |
| исправить ошибку / действия с кодом | `пробел c a` |
| мои настройки | `пробел f c` |
| все клавиши с поиском | `пробел s k` (или `пробел h`) |
| выйти | `пробел q q` |

Через секунду после `пробел` снизу появляется подсказка: что можно нажать дальше. В русской раскладке
команды тоже работают (`о` = `j`, `Ж` = `:`).

## Как устроены настройки

Два файла рядом:

- **`defaults.jsonc`** — всё по умолчанию, с пояснениями у каждой строки. Его не правь: это справочник
  (`пробел f C`).
- **`settings.jsonc`** — только то, что меняешь ты (`пробел f c` или `:Settings`). Удалил строку — вернулось умолчание.

Слияние — по ключам: в `settings.jsonc` достаточно написать одну строку раздела, остальное возьмётся из умолчаний.

```jsonc
{
  "theme": "sunset",
  "options": { "relativenumber": true },
  "statusline": { "style": "arrows" },
}
```

**Сохранил — применилось.** Тема, опции, клавиши, цвета, статусная строка, вкладки, иконки, шрифт, серверы,
форматтеры, линтеры — сразу. Включить/выключить модуль или плагин — после `:restart` (ownvim скажет сам).

**Подсказки, как в settings.json у VS Code.** В `settings.jsonc` работает дополнение ключей и значений (темы,
стили, модули, действия для клавиш, 400+ языковых серверов), `K` на ключе — описание из `defaults.jsonc`, неверный тип
или значение подчёркнуто сразу. Схема собирается сама из умолчаний, тем и модулей.

**Ошибся — видно сразу.** Сломанный JSON, опечатка в имени модуля, опции, действия или темы — подсветка на строке
в `settings.jsonc`, а редактор продолжает работать на прошлых настройках. Комментарии и запятые в конце — можно.

## Рецепты

### Тема

```jsonc
"theme": "dev-night",                                  // одна тема
"theme": { "dark": "dev-night", "light": "dev-day" },  // по тёмной/светлой теме системы
```

- **Выбрать с предпросмотром** — `alt-s`: курсор по списку перекрашивает весь редактор, `enter` пишет выбор
  в `settings.jsonc`.
- **Тема из VS Code** — любая с Open VSX или Marketplace, по id расширения (как в VS Code: издатель.имя):
  ```
  :ThemeInstall dracula-theme.theme-dracula
  :ThemeInstall GitHub.github-vscode-theme
  :ThemeInstall https://…/theme.vsix          (или .json, или путь к файлу)
  ```
  Тема конвертируется в формат ownvim (`themes/<имя>.json`) и включается; если в расширении их несколько —
  ownvim спросит, какую.
- **Своя тема** — `:ThemeNew моя-тема sunset` (на основе Sunset). Откроется файл: меняешь цвет, сохраняешь —
  редактор перекрашивается. Формат:
  ```jsonc
  {
    "name": "Моя",
    "include": "sunset",                    // всё, что не задано, — отсюда
    "palette": { "accent": "#f472b6", "bg": "#0d0b12" },
    "syntax": { "keyword": { "fg": "purple", "italic": true }, "string": "#fbbf24" },
    "groups": { "LineNr": { "fg": "#3a3a3a" } } // любая группа подсветки
  }
  ```
  Палитра: `bg`, `fg` (обязательны), `accent`, `red`, `orange`, `yellow`, `green`, `cyan`, `blue`, `purple`, `pink`,
  `bg_alt`, `bg_highlight`, `bg_visual`, `border`, `fg_dim`, `fg_muted`. Роли синтаксиса: `comment`, `keyword`,
  `function`, `method`, `builtin`, `string`, `number`, `boolean`, `constant`, `type`, `interface`, `variable`,
  `parameter`, `property`, `namespace`, `operator`, `punctuation`, `tag`, `attribute`, `escape`, `regex`, `label`, `macro`.
  Имя группы под курсором — `пробел u i`. `:ThemeEdit` — открыть файл текущей темы.
- **Поправить чужую тему, не трогая её** — как `workbench.colorCustomizations` в VS Code:
  ```jsonc
  "colors": {
    "syntax": { "comment": { "fg": "#6b7280", "italic": false } },  // для всех тем
    "[dracula-theme]": { "palette": { "bg": "#1e1e2e" } }            // только для этой
  },
  ```
- **Прозрачный фон** (размытие Ghostty видно сквозь редактор): `"appearance": { "transparent": true }`.

Темы-плагины тоже работают: `"theme": "tokyonight"`, `"catppuccin-mocha"`, `"kanagawa"`… — к ним `colors` не
применяется.

### Иконки

```jsonc
"icons": { "theme": "backend" },   // default, mono, accent, backend, ascii
```

`:IconTheme` — выбрать из списка, `:IconThemeInstall <ссылка на .json>` — поставить. Свои значки поверх любой темы:

```jsonc
"icons": {
  "theme": "default",
  "overrides": {
    "extension": { "go": { "glyph": "\ue627", "color": "cyan" } },
    "file": { "Makefile": { "glyph": "\ue779", "color": "orange" } },
    "directory": { "migrations": { "glyph": "\uf1c0", "color": "orange" } }
  }
},
```

Цвет — из темы (`red`…`pink`, `grey`, `accent`) или `"#rrggbb"`. Значки — любые символы Nerd Font
([список](https://www.nerdfonts.com/cheat-sheet)). Своя тема иконок — скопируй `icons/backend.json`.
SVG-иконки VS Code терминал показать не может — поэтому темы иконок свои.

### Шрифт

```jsonc
"font": { "family": "Geist Mono", "size": 15, "ligatures": false, "line_height": "10%" },
```

Шрифт задаёт Ghostty — ownvim пишет его в `~/.config/ghostty/ownvim.ghostty` и просит Ghostty перечитать конфиг
(это общий шрифт всех окон Ghostty). `:Font` — выбрать из установленных, `:FontInstall Geist Mono` — поставить
(brew: все Google Fonts и Nerd Fonts) и включить. Значки Nerd Font у Ghostty встроены — подходит любой шрифт.

### Статусная строка, вкладки, крошки, стартовый экран

```jsonc
"statusline": {
  "style": "bubbles",                        // arrows, slant, flat, plain
  "left": ["mode", "branch", "diagnostics", "file"],
  "right": ["tests", "diff", "lsp", "k8s", "position", "time"],
  "custom": {
    "k8s": { "shell": "kubectl config current-context", "every_ms": 10000, "icon": "\u2388", "color": "pink" },
    "env": { "text": "prod", "color": "red" }
  },
  "mode_names": { "n": "NORMAL", "i": "INSERT" }
},
"tabline": { "style": "bar", "show": "always" },        // underline, slant, plain; auto / never
"breadcrumbs": { "separator": " / ", "max_depth": 2 },
"dashboard": {
  "header": ["МОЙ РЕДАКТОР"],
  "buttons": [{ "key": "p", "icon": "\uf07b", "desc": "Проекты", "do": "projects" }],
  "sections": ["header", "buttons", "recent", "startup"]
},
```

Блоки статусной строки: `mode`, `branch`, `diagnostics`, `file`, `filetype`, `encoding`, `indent`, `lsp`, `diff`,
`tests`, `search`, `macro`, `position`, `progress`, `time` и свои из `custom` (текст или вывод команды — в фоне).

### Плавность и детали VS Code

```jsonc
"animations": {
  "cursor": { "enabled": true, "insert": true, "stiffness": 0.8 },  // false — без летающего курсора
  "scroll": { "enabled": false },                                   // без плавной прокрутки
},
"modules": {
  "brackets": { "colors": ["yellow", "purple", "blue"] },  // цветные пары скобок
  "sticky_scroll": { "max_lines": 3 },                     // шапка функции сверху
  "minimap": true,                                         // миникарта справа
  "scrollbar": false,                                      // без полосы прокрутки с метками
},
```

### Клавиши

```jsonc
"keys": {
  "n <leader>z": ":Lazy",                                  // команда
  "n <leader>ff": "files.git",                             // действие (список — пробел s k)
  "n <D-b>": "explorer",                                   // cmd-b — дерево, как в VS Code
  "i jk": false,                                           // убрать
  "n <leader>y": { "do": "\"+y", "desc": "В системный буфер", "remap": false },
},
```

Режимы — буквы перед клавишей: `n` обычный, `i` вставка, `x` выделение, `t` терминал (можно несколько: `nx`).
alt-клавиши сами работают и в русской раскладке. Все клавиши — [keys.ru.md](keys.ru.md).

### Язык: сервер, форматтер, линтер

Например, Zig:

```jsonc
"lsp": { "servers": { "zls": true } },
"format": { "languages": { "zig": ["zigfmt"] } },
```

Подсветку (парсер treesitter), сервер и программы ownvim поставит сам при первом открытии файла (`"tools": { "install": "system" }` — брать только
из PATH). Имена серверов — [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/tree/master/lsp), форматтеров —
[conform](https://github.com/stevearc/conform.nvim#formatters), линтеров —
[nvim-lint](https://github.com/mfussenegger/nvim-lint#available-linters). Настройки сервера — как в
`vim.lsp.config`: `"gopls": { "settings": { "gopls": { "staticcheck": true } } }` — уходят в работающий сервер сразу.

### C / C++

Из коробки: clangd (дополнение, ошибки, clang-tidy, переходы; `пробел c s` — `.h` ↔ `.cpp`), clang-format при
сохранении (стиль — `.clang-format` проекта, иначе LLVM), CMake-сервер для `CMakeLists.txt`, отладчик codelldb
(`F9` — «Запустить программу» спросит путь к бинарнику, или «Подключиться к процессу»), задачи cmake / make /
«собрать и запустить текущий файл» (`пробел r r`). Чтобы clangd знал флаги проекта, нужен `compile_commands.json` —
его делает задача «cmake: настроить» (нужен `brew install cmake`).

### Задачи

```jsonc
"tasks": {
  "list": [
    { "name": "миграции вверх", "cmd": "migrate -path migrations -database $DATABASE_URL up", "when": ["migrations"] },
    { "name": "тест файла", "cmd": "go test -run . ${file_dir}" }
  ]
},
```

`пробел r r` (или `alt-t`) — выбрать и запустить. `when` — задача видна, если в корне проекта есть такой файл или
папка. В `cmd`: `${root}`, `${file}`, `${file_dir}`, `${image}`. Список в `settings.jsonc` заменяет умолчания целиком.

### Плагин, которого нет

```jsonc
"plugins": {
  "folke/zen-mode.nvim": { "cmd": "ZenMode", "opts": { "window": { "width": 100 } } },
  "folke/flash.nvim": false,                 // убрать плагин встроенного модуля
},
```

Поля — как в [lazy.nvim](https://lazy.folke.io/spec): `opts`, `event`, `cmd`, `ft`, `keys`, `branch`, `version`…
Плагины — после `:restart`.

## Все разделы settings.jsonc

| раздел | что | сразу? |
|---|---|---|
| `theme` | тема или `{ dark, light }` | да |
| `colors` | правки цветов поверх темы | да |
| `appearance` | `transparent` | да |
| `icons` | тема иконок, свои значки | да |
| `font` | шрифт Ghostty | да |
| `statusline` · `tabline` · `breadcrumbs` | свой интерфейс | да |
| `dashboard` | стартовый экран | после `:restart` |
| `animations` | курсор, прокрутка | да |
| `options` · `globals` | опции nvim и `vim.g` | да |
| `keys` | клавиши | да |
| `modules` | модули: вкл/выкл и их настройки | вкл/выкл — после `:restart` |
| `plugins` | свои плагины | после `:restart` |
| `lsp` · `diagnostics` | языковые серверы, вид ошибок | да |
| `completion` | дополнение | частично (ownvim скажет) |
| `format` · `lint` | форматтеры и линтеры | да |
| `tools` | откуда ставить программы: mason / system | после `:restart` |
| `test` · `debug` · `database` | тесты, отладчик, база | частично |
| `go` · `tasks` · `ai` · `git` | Go, задачи, Claude, git | частично |

Полный список модулей и их настроек — раздел `modules` в `defaults.jsonc`.

## Если что-то не так

- **Подсветка в `settings.jsonc`** — наведи курсор на строку: в сообщении сказано, что не так и как правильно.
- **Сервер не подключился** — `пробел c l` (какие серверы работают), `:Mason` (что поставлено).
  Rust: нужен `rustup` (`brew install rustup && rustup-init`).
- **Форматирование** — `пробел c F` покажет, чем форматируется файл; `пробел u f` — выключить на время.
- **Плагин не встал** — `:Lazy` (`пробел l`): ошибки установки и кнопка «обновить».
- **Всё сломалось** — удали `settings.jsonc` (или переименуй): ownvim запустится на умолчаниях.

## Как это устроено внутри

```
init.lua               → require("own").setup()
defaults.jsonc         все умолчания (справочник)
settings.jsonc         твои настройки
themes/*.json          темы (свои, встроенные, из VS Code)
icons/*.json           темы иконок
snippets/<язык>.json   свои сниппеты (формат VS Code)
lua/own/
  init.lua             порядок старта: настройки → опции → плагины → модули → тема → клавиши
  settings.lua         чтение JSONC, слияние слоёв, проверка, применение при сохранении, запись (alt-s, :ThemeInstall)
  jsonc.lua            JSON с комментариями
  keys.lua actions.lua клавиши и действия для них
  tools.lua            mason: поставить сервер/программу, если её нет
  theme/               движок тем: группы подсветки из палитры, конвертер тем VS Code, установка
  modules/<имя>.lua    модули: plugins (для lazy.nvim), setup, reload (на лету)
  tools/               свои инструменты: эндпоинты, .http, ▶, фоновые тесты, ревью Claude, скриншот
scripts/keys.lua       docs/keys.ru.md из defaults.jsonc
```

Новый модуль — файл `lua/own/modules/<имя>.lua`, который возвращает `{ plugins = …, setup = function(opts), reload = … }`,
и строка `"<имя>": true` в `modules`. После правки клавиш в `defaults.jsonc` — обновить справочник:
`NVIM_APPNAME=ownvim nvim --headless -l scripts/keys.lua > docs/keys.ru.md`.
