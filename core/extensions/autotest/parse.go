package autotest

import (
	"encoding/json"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Fail — упавшая проверка: тест, файл _test.go (имя), строка и сообщение («got 1, want 2»).
type Fail struct {
	Test string
	File string
	Line int
	Msg  string
}

// Test — результат теста верхнего уровня (подтесты — в имени через /).
type Test struct {
	Name string
	Pass bool
	Skip bool
}

// Result — прогон пакета.
type Result struct {
	Passed, Failed int
	Build          bool // не собрался
	Tests          []Test
	Fails          []Fail
}

type event struct {
	Action string
	Test   string
	Output string
}

var failLine = regexp.MustCompile(`^\s+([\w\-.]+_test\.go):(\d+): (.*?)\s*$`)

// Parse разбирает вывод go test -json. exitCode — код go test: не ноль без единого теста — не собрался.
func Parse(out string, exitCode int) Result {
	var r Result
	output := map[string][]string{}
	failed := map[string]bool{}
	seen := map[string]int{} // тест верхнего уровня → индекс в r.Tests
	for line := range strings.SplitSeq(out, "\n") {
		var ev event
		if json.Unmarshal([]byte(line), &ev) != nil || ev.Test == "" {
			continue
		}
		top, _, _ := strings.Cut(ev.Test, "/")
		switch ev.Action {
		case "output":
			output[ev.Test] = append(output[ev.Test], ev.Output)
		case "pass", "fail", "skip":
			if ev.Action == "fail" {
				failed[ev.Test] = true
			}
			if ev.Test != top {
				continue
			}
			t := Test{Name: top, Pass: ev.Action == "pass", Skip: ev.Action == "skip"}
			if i, ok := seen[top]; ok {
				r.Tests[i] = t
			} else {
				seen[top] = len(r.Tests)
				r.Tests = append(r.Tests, t)
			}
		}
	}
	for _, t := range r.Tests {
		switch {
		case t.Pass:
			r.Passed++
		case !t.Skip:
			r.Failed++
		}
	}
	// «    notify_test.go:23: got 1, want 2» в выводе упавших тестов
	var names []string
	for t := range failed {
		names = append(names, t)
	}
	sort.Strings(names)
	for _, t := range names {
		for _, o := range output[t] {
			if m := failLine.FindStringSubmatch(o); m != nil {
				n := 0
				for _, ch := range m[2] {
					n = n*10 + int(ch-'0')
				}
				r.Fails = append(r.Fails, Fail{Test: t, File: m[1], Line: n, Msg: m[3]})
			}
		}
	}
	r.Build = exitCode != 0 && r.Passed == 0 && r.Failed == 0
	// упавшие — первыми, дальше по имени
	sort.SliceStable(r.Tests, func(i, j int) bool {
		if r.Tests[i].Pass != r.Tests[j].Pass {
			return !r.Tests[i].Pass
		}
		return r.Tests[i].Name < r.Tests[j].Name
	})
	return r
}

// Where — где объявлены тесты пакета: имя → файл и строка (go/ast по *_test.go папки).
func Where(dir string) map[string][2]any {
	out := map[string][2]any{}
	files, _ := filepath.Glob(filepath.Join(dir, "*_test.go"))
	fset := token.NewFileSet()
	for _, path := range files {
		src, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		f, err := parser.ParseFile(fset, path, src, 0)
		if err != nil {
			continue
		}
		for _, d := range f.Decls {
			if fn, ok := d.(*ast.FuncDecl); ok && fn.Recv == nil {
				out[fn.Name.Name] = [2]any{path, fset.Position(fn.Name.Pos()).Line}
			}
		}
	}
	return out
}
