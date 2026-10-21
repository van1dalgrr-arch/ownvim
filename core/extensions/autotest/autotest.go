// Package autotest — тесты Go в фоне: сохранили Go-файл — через секунду go test его пакета (из кэша — мгновенно).
// В статусной строке ✓ 42 / ✗ 1 / ✗ сборка (в Go-файлах), упавшая проверка — ошибкой на своей строке в _test.go,
// даже если открыт другой файл. :TestsPanel (пробел tv) — панель «Тесты в фоне»: пакеты и тесты, упавшие первыми,
// enter — к тесту, r — перезапустить пакет. :AutoTests (пробел tA) — выключить / включить.
// Написано на sdk; модуль включается как раньше: "modules": { "autotest": false }.
package autotest

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/van1dalgrr-arch/ownvim/core/sdk"
)

type pkg struct {
	Dir     string
	Running bool
	Result  Result
	Ran     bool
	marked  []string // _test.go, где стоят замечания
}

var (
	mu      sync.Mutex
	pkgs    = map[string]*pkg{}
	timers  = map[string]*time.Timer{}
	cancels = map[string]context.CancelFunc{}
	off     bool
	root    string
)

// testable — папка пакета Go с тестами (есть go.mod выше и *_test.go рядом)
func testable(file string) (string, bool) {
	if !strings.HasSuffix(file, ".go") {
		return "", false
	}
	dir := filepath.Dir(file)
	if m, _ := filepath.Glob(filepath.Join(dir, "*_test.go")); len(m) == 0 {
		return "", false
	}
	for d := dir; ; d = filepath.Dir(d) {
		if _, err := os.Stat(filepath.Join(d, "go.mod")); err == nil {
			return dir, true
		}
		if d == filepath.Dir(d) {
			return "", false
		}
	}
}

func init() {
	sdk.On("BufWritePost,BufReadPost", "*.go", func(c *sdk.Ctx) error {
		mu.Lock()
		disabled := off
		root = c.Root
		mu.Unlock()
		dir, ok := testable(c.File)
		if disabled || !ok {
			return nil
		}
		schedule(c, dir)
		return nil
	})
	sdk.On("BufEnter", "*.go", func(c *sdk.Ctx) error {
		if dir, ok := testable(c.File); ok {
			return status(c, dir)
		}
		return c.SetStatus("", "", "go")
	})
	sdk.Command("AutoTests", "Тесты в фоне: выключить / включить", toggle)
	sdk.Command("TestsPanel", "Панель «Тесты в фоне»", func(c *sdk.Ctx) error { return c.ToggleView("tests") })
	sdk.View("tests", sdk.ViewSpec{
		Title: "Тесты в фоне",
		Side:  "right",
		Size:  48,
		Rows:  rows,
		Keys: map[string]sdk.RowKey{
			"r": {Desc: "перезапустить пакет", Run: func(c *sdk.Ctx, row sdk.Row) error {
				if row.Key != "" {
					run(c, row.Key)
				}
				return nil
			}},
		},
	})
}

// schedule — автосохранение пишет часто: ждём секунду тишины
func schedule(c *sdk.Ctx, dir string) {
	mu.Lock()
	defer mu.Unlock()
	if t := timers[dir]; t != nil {
		t.Stop()
	}
	timers[dir] = time.AfterFunc(time.Second, func() { run(c, dir) })
}

func get(dir string) *pkg {
	if pkgs[dir] == nil {
		pkgs[dir] = &pkg{Dir: dir}
	}
	return pkgs[dir]
}

func run(c *sdk.Ctx, dir string) {
	mu.Lock()
	if cancel := cancels[dir]; cancel != nil {
		cancel() // прошлый прогон устарел
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancels[dir] = cancel
	p := get(dir)
	p.Running = true
	wasBad := p.Ran && (p.Result.Failed > 0 || p.Result.Build)
	mu.Unlock()
	_ = status(c, dir)
	_ = c.RefreshView("tests")

	// профиль покрытия — туда же, где его ждёт подсветка покрытия (пробел GV): показано — обновится само
	cmd := exec.CommandContext(ctx, "go", "test", "-json", "-coverprofile=/tmp/cover.out", ".")
	cmd.Dir = dir
	out, err := cmd.Output()
	if ctx.Err() != nil {
		return // убили ради нового прогона
	}
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	}
	r := Parse(string(out), code)

	mu.Lock()
	p.Running, p.Result, p.Ran = false, r, true
	prev := p.marked
	mu.Unlock()

	mark(c, p, prev)
	_ = status(c, dir)
	_ = c.RefreshView("tests")
	// сообщить, только когда стало плохо (не на каждое сохранение)
	if (r.Failed > 0 || r.Build) && !wasBad {
		what := "не собирается"
		if !r.Build {
			var names []string
			for _, t := range r.Tests {
				if !t.Pass && !t.Skip {
					names = append(names, t.Name)
				}
			}
			what = fmt.Sprintf("упало %d: %s", r.Failed, strings.Join(names, ", "))
		}
		c.Warn("тесты %s — %s (пробел tv — панель)", filepath.Base(dir), what)
	}
}

// mark — упавшие проверки ошибками на своих строках в _test.go пакета (и убрать прошлые)
func mark(c *sdk.Ctx, p *pkg, prev []string) {
	by := map[string][]sdk.Problem{}
	for _, f := range p.Result.Fails {
		path := filepath.Join(p.Dir, f.File)
		by[path] = append(by[path], sdk.Problem{Line: f.Line, Severity: "error", Message: f.Test + ": " + f.Msg})
	}
	for _, path := range prev {
		if _, still := by[path]; !still {
			_ = c.ProblemsFor(path, nil)
		}
	}
	var marked []string
	for path, ps := range by {
		_ = c.ProblemsFor(path, ps)
		marked = append(marked, path)
	}
	mu.Lock()
	p.marked = marked
	mu.Unlock()
}

func status(c *sdk.Ctx, dir string) error {
	mu.Lock()
	p := pkgs[dir]
	disabled := off
	var text, color string
	switch {
	case disabled || p == nil:
	case p.Running:
		text, color = "󰙨 …", "grey"
	case p.Result.Build:
		text, color = "󰙨 ✗ сборка", "red"
	case p.Result.Failed > 0:
		text, color = fmt.Sprintf("󰙨 ✗ %d", p.Result.Failed), "red"
	default:
		text, color = fmt.Sprintf("󰙨 ✓ %d", p.Result.Passed), "green"
	}
	mu.Unlock()
	return c.SetStatus(text, color, "go")
}

func toggle(c *sdk.Ctx) error {
	mu.Lock()
	off = !off
	disabled := off
	var all []*pkg
	for _, p := range pkgs {
		all = append(all, p)
	}
	mu.Unlock()
	if disabled {
		for _, p := range all {
			for _, path := range p.marked {
				_ = c.ProblemsFor(path, nil)
			}
		}
		_ = c.SetStatus("", "", "go")
		c.Notify("тесты в фоне выключены")
		return nil
	}
	c.Notify("тесты в фоне включены")
	return nil
}

func rows(c *sdk.Ctx) []sdk.Row {
	mu.Lock()
	defer mu.Unlock()
	var dirs []string
	for d := range pkgs {
		dirs = append(dirs, d)
	}
	sort.Strings(dirs)
	if len(dirs) == 0 {
		return []sdk.Row{{Text: "сохраните Go-файл пакета с тестами — прогон появится здесь"}}
	}
	var out []sdk.Row
	for _, d := range dirs {
		p := pkgs[d]
		name := d
		if rel, err := filepath.Rel(root, d); err == nil && root != "" && !strings.HasPrefix(rel, "..") {
			name = "./" + rel
			if rel == "." {
				name = filepath.Base(d) // пакет в корне проекта
			}
		}
		head := []sdk.Part{}
		switch {
		case p.Running:
			head = append(head, sdk.Part{Text: "… ", Color: "grey"})
		case p.Result.Build:
			head = append(head, sdk.Part{Text: "✗ ", Color: "red"})
		case p.Result.Failed > 0:
			head = append(head, sdk.Part{Text: "✗ ", Color: "red"})
		default:
			head = append(head, sdk.Part{Text: "✓ ", Color: "green"})
		}
		head = append(head, sdk.Part{Text: name, Color: "Title"})
		if p.Result.Build {
			head = append(head, sdk.Part{Text: "  не собирается", Color: "red"})
		} else if p.Ran {
			head = append(head, sdk.Part{Text: fmt.Sprintf("  %d ✓", p.Result.Passed), Color: "grey"})
			if p.Result.Failed > 0 {
				head = append(head, sdk.Part{Text: fmt.Sprintf(" · %d ✗", p.Result.Failed), Color: "red"})
			}
		}
		out = append(out, sdk.Row{Parts: head, Key: d})
		where := Where(d)
		for _, t := range p.Result.Tests {
			mark, color := "✓", "green"
			if t.Skip {
				mark, color = "–", "grey"
			} else if !t.Pass {
				mark, color = "✗", "red"
			}
			row := sdk.Row{Depth: 1, Key: d, Parts: []sdk.Part{{Text: mark + " ", Color: color}, {Text: t.Name}}}
			if w, ok := where[t.Name]; ok {
				row.File, row.Line = w[0].(string), w[1].(int)
			}
			out = append(out, row)
			for _, f := range p.Result.Fails {
				if f.Test == t.Name || strings.HasPrefix(f.Test, t.Name+"/") {
					out = append(out, sdk.Row{Depth: 2, Key: d, File: filepath.Join(d, f.File), Line: f.Line,
						Parts: []sdk.Part{{Text: fmt.Sprintf("%s:%d ", f.File, f.Line), Color: "grey"}, {Text: f.Msg, Color: "red"}}})
				}
			}
		}
	}
	return out
}
