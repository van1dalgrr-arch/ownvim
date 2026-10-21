# Расширения на Go

[← Документация](README.md) · 🇬🇧 [English](en/go-extensions.md)

Свои команды, клавиши и реакции на события — **на Go, без единой строки Lua**. Расширение — обычный Go-пакет в
`core/extensions/<имя>/`. Сохранили файл — ownvim сам пересобрал ядро и подхватил изменения, перезапуск не нужен.

- [Первое расширение за 5 минут](#первое-расширение-за-5-минут)
- [Почему не страшно](#почему-не-страшно)
- [Что можно: справочник](#что-можно-справочник)
- [Как языковой сервер: дополнение, K, исправления](#как-языковой-сервер-дополнение-k-исправления)
- [Панели и статусная строка](#панели-и-статусная-строка)
- [Рецепты](#рецепты)
- [Настройки расширения](#настройки-расширения)
- [Тесты](#тесты)
- [Если не работает](#если-не-работает)
- [Как это устроено](#как-это-устроено)

## Первое расширение за 5 минут

1. В ownvim: **`:GoExtensionNew hello`** — появится `core/extensions/hello/hello.go` с рабочей заготовкой и
   комментариями.
2. Поменяйте, что делает команда. Например:
   ```go
   sdk.Command("Hello", "Поздороваться", func(c *sdk.Ctx) error {
   	c.Notify("привет! ты в %s, строка %d, слово «%s»", c.File, c.Line, c.Word)
   	return nil
   })
   sdk.Key("n <leader>xh", "Hello")
   ```
3. Сохраните (`cmd-s` или само). Через пару секунд — уведомление «Go-ядро пересобрано».
4. **`:Hello`** или **`пробел x h`**.

Посмотреть, что объявили расширения, — **`:GoExtensions`**. Готовые примеры — `core/extensions/examples/`
(`:WordCount`, `:SortLines`, `:LongFuncs`).

## Почему не страшно

| что случилось | что будет |
|---|---|
| ошибка компиляции | подсветка **на строке** Go-файла (как у линтера) и уведомление; прежняя версия ядра продолжает работать |
| исправили и сохранили | подсветка уходит, новая версия подхватывается сама |
| расширение вернуло ошибку | уведомление `Имя: текст ошибки` |
| **паника** (nil map, выход за срез…) | уведомление с причиной и **файлом:строкой**, где она случилась; редактор и ядро живы |
| расширение долго думает (сеть, большой файл) | редактор не замирает: команды выполняются в фоне |
| забыли, что умеет `c` | `K` на `sdk.Ctx` или на методе — описание с примером; gopls дополняет всё, что ниже |
| файл назвали `что-то_test.go` | `:GoExtensionNew` не даст: для Go это файл тестов, он не попадает в сборку |
| сломали совсем | удалите папку `core/extensions/<имя>` и сохраните любой `.go` в `core/` — расширения не станет |

## Что можно: справочник

### Регистрация (в `init()`)

| функция | что |
|---|---|
| `sdk.Command(name, desc, func(c *sdk.Ctx) error)` | команда `:name`. Имя — с заглавной латинской: `WordCount`. Работает и с выделением (`:'<,'>Name`) |
| `sdk.Key("n <leader>xw", "Name")` | клавиша для команды: режимы (`n` обычный, `x` выделение, `i` вставка) и сочетание |
| `sdk.On("BufWritePost", "*.go", func(c *sdk.Ctx) error)` | реакция на событие; несколько — через запятую: `"BufEnter,BufWritePost"` |

Клавишу можно повесить и из `settings.jsonc`, не трогая Go: `"keys": { "n <leader>xw": ":WordCount" }`.

### Что известно (`c.…`)

| поле | что |
|---|---|
| `c.File` · `c.Root` · `c.Filetype` | путь файла · корень проекта · тип (`go`, `yaml`…) |
| `c.Line` · `c.Col` · `c.Word` | курсор (с 1) · слово под курсором |
| `c.SelStart` · `c.SelEnd` | выделенные строки (с 1); `0` — выделения нет |
| `c.Event` · `c.Match` | для `On`: какое событие и на каком файле |
| `c.Buf` · `c.Ext` | номер буфера · имя вашего расширения |

### Текст

| метод | что |
|---|---|
| `c.Lines()` | все строки файла |
| `c.LinesRange(from, to)` | строки с `from` по `to` (с 1, включительно) |
| `c.CurrentLine()` | строка под курсором |
| `c.Selection()` | выделенное одним текстом (`""` — нет выделения) |
| `c.SetLines(from, to, lines)` | заменить строки; весь файл — `SetLines(1, -1, …)` |
| `c.ReplaceSelection(text)` | заменить выделенное |
| `c.InsertBelow(text)` | вставить ниже курсора |

### Показать

| метод | что |
|---|---|
| `c.Notify(format, …)` · `c.Warn(…)` | уведомление (как `fmt.Sprintf`) |
| `c.Marks([]sdk.Mark{{Line: 5, Text: "60 строк", Color: "red"}})` | надписи справа от строк (как статусы в `compose.yaml`); `nil` — убрать |
| `c.Problems([]sdk.Problem{{Line: 3, Col: 5, Message: "…", Severity: "error"}})` | замечания на строках, как у линтера: подчёркивание, Error Lens, «Проблемы» |
| `c.Window(title, text, ft)` | окно снизу с текстом (`q` — закрыть); `ft` — подсветка: `"markdown"`, `"json"`, `"go"` |
| `c.ProblemsFor(path, problems)` | замечания в **любом** открытом файле (упавший тест — в своём `_test.go`, даже если вы в другом) |

Цвета надписей: `red`, `orange`, `yellow`, `green`, `blue`, `purple`, `grey` — или любая группа подсветки
(`"Comment"`). Надписи и замечания каждого расширения — свои: новые заменяют прежние этого же расширения.

Надпись из разноцветных кусков — `sdk.Mark{Line: 2, Parts: []sdk.Part{{Text: "● работает", Color: "green"}, {Text: " · :8080", Color: "grey"}}}`;
прижать к правому краю — `Right: true`.

### Спросить человека

| метод | что |
|---|---|
| `c.Select(prompt, items)` | выбор из списка → номер (с 0) и `true`; закрыли — `-1, false` |
| `c.Input(prompt, def)` | ввод строки → текст и `true` |
| `c.Pick(title, []sdk.PickItem, opts)` | список с поиском и **превью файла** (как `пробел пробел`): `enter` — перейти к `File:Line` (с `Definition: true` — ещё и к определению через LSP), `ctrl-y` — скопировать `Copy`, свои клавиши `opts.Keys` — вернуть их имя |

Расширение ждёт ответа в фоне — редактор при этом работает.

### Окна и клавиши

| метод | что |
|---|---|
| `c.SidePanel(title, text, ft)` · `c.CloseSidePanel()` | панель справа, одна на расширение: открыта — перерисовывается (ответы HTTP) |
| `c.Terminal(cmd, cwd)` | команда в терминале снизу: логи, shell, сборка |
| `c.MapKey("n", "<cr>", desc, func)` | клавиша **только в этом файле**; вернули `sdk.ErrPass` — клавиша работает как обычно (так `enter` на сервисе compose — меню, а на других строках — как всегда) |
| `c.SetCursor(line, col)` · `c.Feed("A")` · `c.Clipboard(text)` | курсор · «нажать» клавиши после всего остального · буфер обмена |

### Фон, данные, хранилище

| что | как |
|---|---|
| фоновая задача | `sdk.Every(3*time.Second, func(c) …)`; что на экране — `c.VisibleBuffers()`, работать с буфером — `c.ForBuffer(b)` |
| данные для Lua-интерфейса | `sdk.Func("имя", …)` — Lua зовёт `require("own.ext").call("имя", { … })` (аргументы — `c.Args`); ответ — `c.Publish(key, value)` → `require("own.ext").data[key]` и событие `User OwnExtData` |
| запомнить между запусками | `c.Store().Set("key", value)` · `c.Store().Get("key", &out)` |

### Действовать

| метод | что |
|---|---|
| `c.Open(file, line)` | открыть файл на строке |
| `c.Command("write")` | любая команда Vim |
| `c.Setting(key, def)` · `c.SettingInt(key, def)` | настройка расширения из `settings.jsonc` ([ниже](#настройки-расширения)) |
| `c.Nvim()` | полный клиент Neovim ([go-client](https://pkg.go.dev/github.com/neovim/go-client/nvim)) — для всего остального |

И вся стандартная библиотека Go: `os/exec`, `net/http`, `go/ast`, `encoding/json`, `regexp`… — плюс любые пакеты
(`cd core && go get …`).

## Как языковой сервер: дополнение, K, исправления

Расширение может стать **встроенным языковым сервером**: его подсказки появляются в обычном меню дополнения, описание —
по `K`, исправления — в `пробел ca`, рядом с gopls и rust-analyzer. Ничего не надо подключать: ownvim сам ставит
«сервер» ownvim к файлам тех типов, для которых есть провайдеры.

```go
// подсказки: после "${" в compose.yaml — переменные из .env
sdk.Completion("yaml", "${", func(c *sdk.Ctx, prefix string) []sdk.CompletionItem {
	return []sdk.CompletionItem{{Label: "DB_URL", Detail: "postgres://…", Kind: "variable", Doc: "из `.env`"}}
})

// K — markdown; "" — нечего сказать (пусть говорят другие серверы)
sdk.Hover("yaml", func(c *sdk.Ctx) string {
	return "**" + c.Word + "** — из `.env`, строка 3"
})

// пробел ca — исправления для строки курсора
sdk.CodeActions("yaml", func(c *sdk.Ctx) []sdk.Action {
	return []sdk.Action{{Title: "Добавить в .env", Run: func(c *sdk.Ctx) error { /* … */ return nil }}}
})
```

| что | поля |
|---|---|
| `CompletionItem` | `Label`, `Insert` (что вставить; `Snipp: true` — сниппет `${1:имя}`), `Detail`, `Doc` (markdown), `Kind` (`function`, `variable`, `field`, `keyword`, `snippet`…) |
| `Action` | `Title`, `Kind` (`quickfix`, `refactor`, `source`), `Run` — что сделать, когда выбрали |

Типы файлов — через запятую (`"go,gomod"`), `"*"` — все. Пример целиком — `core/extensions/docker/providers.go`:
дополнение `${VAR}` из `.env` (секреты замаскированы), `K` — значение переменной и откуда оно, `пробел ca` — добавить её
в `.env` или поставить умолчание.

## Панели и статусная строка

**Панель** — окно сбоку или снизу со строками, как «Тесты» или «Структура» в IDE:

```go
sdk.View("todo", sdk.ViewSpec{
	Title: "TODO проекта",
	Side:  "right", // left, bottom
	Rows: func(c *sdk.Ctx) []sdk.Row {
		return []sdk.Row{
			{Parts: []sdk.Part{{Text: "✗ ", Color: "red"}, {Text: "починить логин"}}, File: "/path/auth.go", Line: 42},
			{Depth: 1, Text: "подробности…"},
		}
	},
	Keys: map[string]sdk.RowKey{
		"d": {Desc: "готово", Run: func(c *sdk.Ctx, row sdk.Row) error { /* … */ return c.RefreshView("todo") }},
	},
})
sdk.Command("Todo", "Панель TODO", func(c *sdk.Ctx) error { return c.ToggleView("todo") })
```

В панели: `enter` — к `File:Line`, свои клавиши из `Keys`, `R` — обновить, `q` — закрыть; подсказка клавиш — в её
заголовке. Открыть: `c.ShowView` / `c.ToggleView` или `:View имя`; обновить, если открыта, — `c.RefreshView`.
Свой `enter` — `Open: func(c, row) (bool, error)`.

**Статусная строка** — `c.SetStatus("✓ 42", "green", "go")`: надпись в блоке `ext`, только когда открыт файл этих
типов (`""` — всегда); `c.SetStatus("", "", "")` — убрать.

Пример с обоими — `core/extensions/autotest`: тесты в фоне, панель «Тесты в фоне» (`пробел tv`) с пакетами и тестами
(`enter` — к функции теста, её место находит `go/ast`; `r` — перезапустить пакет), `✓ 42 / ✗ 1` в статусной строке,
упавшие проверки — в своих `_test.go` через `ProblemsFor`.

## Рецепты

**Заменить выделение** — base64, JSON → одна строка, что угодно:

```go
sdk.Command("B64", "Выделенное в base64", func(c *sdk.Ctx) error {
	return c.ReplaceSelection(base64.StdEncoding.EncodeToString([]byte(c.Selection())))
})
sdk.Key("x <leader>xb", "B64")
```

**Проверка при сохранении** — замечания на строках, как у линтера:

```go
sdk.On("BufWritePost", "*.go", func(c *sdk.Ctx) error {
	var ps []sdk.Problem
	for i, line := range c.Lines() {
		if strings.Contains(line, "fmt.Println(") {
			ps = append(ps, sdk.Problem{Line: i + 1, Message: "отладочный Println — убрать перед коммитом", Severity: "warn"})
		}
	}
	return c.Problems(ps)
})
```

**Запустить программу и показать вывод:**

```go
sdk.Command("GitLog", "Последние коммиты файла", func(c *sdk.Ctx) error {
	out, err := exec.Command("git", "-C", c.Root, "log", "--oneline", "-15", "--", c.File).CombinedOutput()
	if err != nil {
		return fmt.Errorf("git: %s", out)
	}
	return c.Window("git log "+filepath.Base(c.File), string(out), "git")
})
```

**Сходить в сеть** (редактор не замрёт):

```go
sdk.Command("Health", "GET /health", func(c *sdk.Ctx) error {
	resp, err := http.Get("http://localhost:8080/health")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	c.Notify("health: %s", resp.Status)
	return nil
})
```

**Разобрать Go-код настоящим парсером** — `go/ast`: см. `:LongFuncs` в `core/extensions/examples/examples.go`.

**Большие настоящие примеры** — встроенные модули ownvim написаны на этом же SDK, их можно читать как образец:

| расширение | что показывает |
|---|---|
| `core/extensions/docker` | события, фоновый опрос (`Every`), разноцветные надписи, замечания, `MapKey` + `ErrPass`, `Select`, `Terminal`, `Store`, `Func`/`Publish` для стартового экрана, YAML-разбор с номерами строк |
| `core/extensions/endpoints` | разбор Go-кода `go/ast` по всему проекту, `Pick` с превью и переходом к определению, `Input`, `SidePanel`, HTTP |
| `core/extensions/http` | клавиши в буфере, разбор формата `.http`, `net/http`, ответы между запусками (`Store`), `Clipboard`, `SetCursor` |
| `core/extensions/autotest` | панель (`View`), статусная строка (`SetStatus`), замечания в других файлах (`ProblemsFor`), отмена устаревших прогонов |
| `core/extensions/checks` | `Func` для Lua-модуля, запуск команд, разбор вывода регулярками |

## Настройки расширения

```jsonc
// settings.jsonc
"extensions": {
  "examples": { "max_lines": 60 },
  "hello": { "greeting": "здарова" },
},
```

```go
greeting := c.Setting("greeting", "привет").(string)
limit := c.SettingInt("max_lines", 40)
```

Ключ — имя папки расширения. Сохранили `settings.jsonc` — следующий запуск команды уже видит новое значение.

## Тесты

Расширение — обычный Go: логику удобно вынести в функцию без `sdk.Ctx` и проверить `go test`:

```go
// core/extensions/hello/hello_test.go
func TestGreet(t *testing.T) {
	if got := greet("мир"); got != "привет, мир" {
		t.Fatalf("получил %q", got)
	}
}
```

```bash
cd ~/dev/ownvim/core && go test ./...
```

## Если не работает

| симптом | что делать |
|---|---|
| команды нет после сохранения | ошибка сборки — смотрите подсветку в Go-файле и `:OwnHealth`; `:GoExtensions` — что ownvim видит |
| «нет go» | `brew install go` |
| имя команды не принято | с заглавной латинской, без пробелов и подчёркиваний: `WordCount` (уведомление при сборке скажет) |
| команда ничего не делает | добавьте `c.Notify(…)` в начало — проверить, что она вызывается; логи моста — `~/.local/state/ownvim/ownvimd.log` |
| нужно что-то, чего нет в `c` | `c.Nvim()` — полный API Neovim; или попросите добавить метод в `core/sdk` |

## Как это устроено

- `core/sdk` — то, чем вы пользуетесь: регистрация (`sdk.go`), контекст и методы (`ctx.go`), запуск в фоне с
  перехватом паник (`run.go`).
- `core/extensions/all.go` — список расширений; его пишет ownvim перед каждой сборкой (все папки `core/extensions/*`).
- На старте ownvim читает **манифест** (что объявили расширения) из кэша и создаёт команды, клавиши и события, не
  запуская Go. Срабатывание — `vim.rpcnotify` в мост (`ownvimd serve`), он запускается при первом вызове (~3 мс).
- Методы `c.…` вызывают обратно маленькие Lua-функции из `lua/own/ext.lua` (`M.api`) — там вся «магия Neovim», а
  Go-API остаётся простым.
- Подробнее о ядре — [Как устроено внутри → Go-ядро и мост](architecture.md#go-ядро-и-мост).
