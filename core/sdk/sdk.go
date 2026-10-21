// Package sdk — расширения ownvim на Go: команды, клавиши и реакции на события без единой строки Lua.
//
// Расширение — пакет в core/extensions/<имя>/. Всё регистрируется в init():
//
//	package hello
//
//	import "github.com/van1dalgrr-arch/ownvim/core/sdk"
//
//	func init() {
//		sdk.Command("Hello", "Поздороваться", func(c *sdk.Ctx) error {
//			c.Notify("привет из Go, файл %s", c.File)
//			return nil
//		})
//		sdk.Key("n <leader>xh", "Hello")
//	}
//
// Сохранили файл — ownvim пересобрал ядро и подхватил расширение сам. Ошибка компиляции — подсветка на строке.
// Команды и события выполняются в фоне: медленное расширение не морозит редактор, паника — не роняет его.
// Создать заготовку — :GoExtensionNew имя. Руководство — docs/go-extensions.md.
package sdk

import (
	"fmt"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"sync"
)

// Handler — то, что выполняет команда или событие. Вернули ошибку — ownvim покажет её уведомлением.
type Handler func(c *Ctx) error

type command struct {
	Name string `json:"name"`
	Desc string `json:"desc"`
	Ext  string `json:"ext"`
	run  Handler
}

type key struct {
	Modes   string `json:"modes"`
	Lhs     string `json:"lhs"`
	Command string `json:"command"`
	Ext     string `json:"ext"`
}

type event struct {
	ID      string   `json:"id"`
	Events  []string `json:"events"`
	Pattern string   `json:"pattern"`
	Ext     string   `json:"ext"`
	run     Handler
}

var (
	mu       sync.Mutex
	commands = map[string]*command{}
	keys     []key
	events   []*event
	problems []string // ошибки регистрации — покажет :OwnHealth и уведомление
)

var commandName = regexp.MustCompile(`^[A-Z][A-Za-z0-9]*$`)

// extOf — имя расширения: папка пакета, из которого вызвали Command/Key/On (core/extensions/<имя>/…).
func extOf() string {
	_, file, _, ok := runtime.Caller(2)
	if !ok {
		return "?"
	}
	return filepath.Base(filepath.Dir(file))
}

// Command добавляет команду :name. Имя — с заглавной буквы, латиницей и цифрами, как у команд Vim (WordCount).
// desc видно в списке команд и подсказках. Команда работает и с выделением: :'<,'>Name, c.Selection().
func Command(name, desc string, run Handler) {
	mu.Lock()
	defer mu.Unlock()
	switch {
	case !commandName.MatchString(name):
		problems = append(problems, fmt.Sprintf("команда %q: имя — с заглавной латинской буквы, без пробелов (WordCount)", name))
	case commands[name] != nil:
		problems = append(problems, fmt.Sprintf("команда %q объявлена дважды (%s и %s)", name, commands[name].Ext, extOf()))
	default:
		commands[name] = &command{Name: name, Desc: desc, Ext: extOf(), run: run}
	}
}

// Key вешает команду на клавишу: "n <leader>xw" — режимы буквами (n обычный, x выделение, i вставка), потом клавиша.
// Можно и из settings.jsonc: "keys": { "n <leader>xw": ":WordCount" }.
func Key(spec, commandName string) {
	mu.Lock()
	defer mu.Unlock()
	modes, lhs, ok := strings.Cut(strings.TrimSpace(spec), " ")
	if !ok || modes == "" || lhs == "" {
		problems = append(problems, fmt.Sprintf("клавиша %q: нужно «режимы клавиша», например \"n <leader>xw\"", spec))
		return
	}
	keys = append(keys, key{Modes: modes, Lhs: strings.TrimSpace(lhs), Command: commandName, Ext: extOf()})
}

// On — реагировать на события Neovim: "BufWritePost", "BufEnter", "InsertLeave"… (несколько — через запятую).
// pattern — для каких файлов: "*.go", "*" — для всех. В c.Event и c.Match — что случилось и с каким файлом.
func On(eventNames, pattern string, run Handler) {
	mu.Lock()
	defer mu.Unlock()
	var list []string
	for e := range strings.SplitSeq(eventNames, ",") {
		if e = strings.TrimSpace(e); e != "" {
			list = append(list, e)
		}
	}
	if pattern == "" {
		pattern = "*"
	}
	ext := extOf()
	events = append(events, &event{ID: fmt.Sprintf("%s:%d", ext, len(events)), Events: list, Pattern: pattern, Ext: ext, run: run})
}

// Manifest — что зарегистрировано: ownvim читает его на старте и создаёт команды, клавиши и события,
// не запуская Go (ownvimd extensions manifest).
type Manifest struct {
	Commands  []command  `json:"commands"`
	Keys      []key      `json:"keys"`
	Events    []event    `json:"events"`
	Providers []provider `json:"providers"`
	Views     []string   `json:"views"`
	Problems  []string   `json:"problems"`
}

func GetManifest() Manifest {
	mu.Lock()
	defer mu.Unlock()
	m := Manifest{Commands: []command{}, Events: []event{}, Keys: append([]key{}, keys...), Problems: append([]string{}, problems...)}
	for _, c := range commands {
		m.Commands = append(m.Commands, *c)
	}
	sort.Slice(m.Commands, func(i, j int) bool { return m.Commands[i].Name < m.Commands[j].Name })
	for _, e := range events {
		m.Events = append(m.Events, *e)
	}
	m.Views = viewNames()
	if m.Views == nil {
		m.Views = []string{}
	}
	m.Providers = []provider{}
	for _, p := range providers {
		m.Providers = append(m.Providers, *p)
	}
	for _, k := range m.Keys {
		if commands[k.Command] == nil {
			m.Problems = append(m.Problems, fmt.Sprintf("клавиша %s %s: нет команды %q", k.Modes, k.Lhs, k.Command))
		}
	}
	return m
}

func lookup(id string) (Handler, string, bool) {
	mu.Lock()
	defer mu.Unlock()
	if c := commands[id]; c != nil {
		return c.run, c.Name, true
	}
	if c := funcs[id]; c != nil {
		return c.run, c.Name, true
	}
	if c := dynamic[id]; c != nil {
		return c.run, c.Name, true
	}
	mu.Unlock()
	a := pendingAction(id)
	mu.Lock()
	if a != nil {
		return a.run, a.Name, true
	}
	for _, e := range events {
		if e.ID == id {
			return e.run, e.ID, true
		}
	}
	return nil, "", false
}
