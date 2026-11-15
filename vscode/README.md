# ownvim в VS Code

Отдельная копия VS Code с возможностями ownvim. Основной VS Code из dotfiles она не трогает: у неё своя папка
`~/.local/share/ownvim/vscode`, свои настройки и свои расширения.

```bash
./vscode/install.sh     # один раз (и после правок extensions.txt); можно запускать повторно
ownvim-code .           # или «ownvim Code» в Spotlight / Launchpad
```

## Что откуда

| ownvim | здесь |
|---|---|
| пробел + буквы (which-key) | VSCodeVim + Which Key, те же буквы: `пробел r x`, `пробел r m`, `пробел G …`, `пробел f f`… (`User/settings.json` → `whichkey.bindings`) |
| Go: gopls, тесты, отладка, теги, impl, покрытие | расширение Go + gofumpt, staticcheck, golangci-lint, подсказки типов |
| ▶ у `func main`, «реализует: io.Reader» | своё расширение `extension/` (линзы над кодом), `cmd-enter` — запустить |
| SQL: схема из миграций, дополнение, K, gd | своё расширение: FROM → таблицы, `u.` → колонки, JOIN → готовое `ON` по внешнему ключу, enum в `= '…'` |
| миграции: новая / up / down / redo / статус | `пробел r m`; down пишется сам при сохранении up; ✓ / ○ / ✗ в первой строке; `cmd-shift-t` — up ↔ down |
| опасные миграции | NOT NULL без DEFAULT, индекс без CONCURRENTLY, FK без NOT VALID, смена типа — предупреждения в строке |
| dadbod: запрос → таблица | `cmd-enter` в .sql — выражение под курсором в базу проекта, результат таблицей справа |
| база проекта сама | `.env DATABASE_URL` → postgres из compose → `postgres://…/<папка>`; своя — `ownvim.database.url` |
| postgres_lsp | Postgres Language Server (supabase.postgrestools) |
| compose: статус сервисов, действия, `${VAR}` ↔ .env | своё расширение: ● работает · :8080 справа, «действия» над сервисом, F12 на `${VAR}` |
| Dockerfile: вес слоёв | своё расширение; образ — «Docker: образ для веса слоёв» |
| Enter на сервисе compose | меню: up / собрать и up / restart / stop / логи / shell / up всех / down; короткое — тихо, долгое — в терминале |
| статус compose проекта | в строке состояния: работает / всего, красным — если кто-то упал; клик или alt-d — сервис |
| alt-o — контейнеры | все контейнеры: логи, shell, restart, stop, start, inspect, удалить |
| compose в запуске | задачи (пробел r t): compose up / up --build / up -d / down / логи / ps / pull |
| отладка в Docker | пробел r c: подключиться к dlv :2345, debugpy :5678, node :9229; папка в контейнере — WORKDIR из Dockerfile |
| темы ownvim | все 18 тем из `themes/` (alt-s) |
| автосохранение | вышел из вставки (Esc / ctrl-[ / ctrl-c / jk), правка в normal (`dd`, `p`, `u`), другой файл — записано, с форматированием и импортами; выключить — `ownvim.autosave` |
| langmap | команды в русской раскладке: `о` = `j`, `вв` = `dd`, `Ж` = `:` |
| dial | ctrl-a / ctrl-x: `true` ↔ `false`, `:=` ↔ `=`, `var` ↔ `const`, GET → POST…, числа ±1 |
| glance / flash / cloak | `gpd` `gpr` `gpi` `gpt` — peek; `s` + две буквы — прыжок; `пробел u e` — скрыть значения .env |
| сниппеты | `snippets/*.json` — те же файлы |
| ▶ у main и тестов в Python и JS/TS | `if __name__ == "__main__"`, `test_*`, `class Test*`, `#!/usr/bin/env node`, `it` / `test` / `describe`: `пробел r x` / `cmd-enter` — запустить (main — задачей с `.env`, тест — через панель тестов), `пробел r X` / `cmd-shift-enter` — в отладчике |
| черновики | `пробел r g` — Go, `пробел r p` — Python, `пробел r P` — TypeScript |
| тест ↔ код в любом языке | `cmd-shift-t` (`пробел T`): Go, Python, TS/JS, Rust (`mod tests`), C/C++, Lua, миграции; теста нет — создаётся |
| эндпоинты (Endpoints в GoLand) | `alt-a` / `пробел r e`: все маршруты Gin (тот же разбор go/ast — `ownvimd routes`), enter — к хендлеру, ▷ — запрос на запущенный API (токен запоминается), ⧉ — curl |
| api.http из маршрутов | `пробел r h` (`alt-p` вне .http); запрос — «Send Request» / `alt-p` в файле |
| задачи из settings.jsonc | `tasks.list` ownvim — в списке задач VS Code (`пробел r t`, `alt-t`), раздел «ownvim»: `when`, `ft`, `cwd`, `env`, `${file_dir}`, `${python}`, `${input:…}` — спросит в терминале |
| свои команды-скрипты | `commands` из settings.jsonc — `alt-x` / `пробел x c`: выделение / файл / строка / слово → скрипт → заменить / вставить / окно |
| тесты Go в фоне | сохранил Go-файл — `go test` пакета, ✓ 42 / ✗ 1 слева в статусе, упавшая проверка — ошибкой на строке; клик — тесты пакета; `пробел t A` — вкл/выкл |
| ревью от Claude | `пробел a R` — diff ветки против main → замечания на строках и в «Проблемах»; `пробел a X` — убрать |
| заметки о неудобствах | `пробел ?` — записать с местом, `пробел N` — список; файл общий с nvim (`~/.local/share/ownvim/own-notes.json`) |
| скриншот кода | `пробел P` — выделенное или функция под курсором → PNG (freeze) в буфер обмена и `~/Pictures/code` |
| музыка в статусе | что играет (media-control), клик — пауза, `пробел u M` — следующий / предыдущий; `statusline.music` из settings.jsonc |
| отдых | как модуль rest: «⏱ пора отдохнуть» через `work_min`, клик — перерыв с отсчётом; включается тем же `modules.rest` (или `ownvim.rest`) |
| RAM и uptime | значок ownvim слева в статусе: подсказка — RAM и время работы Mac, клик — все команды ownvim |

## Своё расширение

`extension/` — TypeScript, собирается esbuild. Ставится ссылкой, поэтому после правок хватает пересборки
и «Reload Window».

Общее с nvim берётся из самого ownvim: настройки (задачи, команды, музыка, отдых) — через `ownvimd settings load`
по `settings.jsonc` репозитория, маршруты — `ownvimd routes`. ownvimd расширение собирает само из `core/`
(нужен `go`) и пересобирает, когда `core/` новее.

```bash
cd vscode/extension
npm run build    # сборка + темы + сниппеты
npm test         # схема, down, дополнение, проверки, ▶, тест ↔ код, задачи, go test -json, ревью
npm run check    # типы
```
