package autotest

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// crate — папка крейта Rust (ближайший Cargo.toml вверх от .rs-файла).
func crate(file string) (string, bool) {
	if !strings.HasSuffix(file, ".rs") {
		return "", false
	}
	for d := filepath.Dir(file); ; d = filepath.Dir(d) {
		if _, err := os.Stat(filepath.Join(d, "Cargo.toml")); err == nil {
			return d, true
		}
		if d == filepath.Dir(d) {
			return "", false
		}
	}
}

var (
	rsTestLine = regexp.MustCompile(`^test (.+?) \.\.\. (ok|FAILED|ignored)`)
	// новый формат: thread 'a::b' (1234) panicked at src/lib.rs:12:5:   старый: thread 'a::b' panicked at 'msg', src/lib.rs:12:5
	rsPanicNew = regexp.MustCompile(`^thread '([^']+)'(?: \(\d+\))? panicked at ([^\s:]+\.rs):(\d+):\d+:\s*$`)
	rsPanicOld = regexp.MustCompile(`^thread '([^']+)'(?: \(\d+\))? panicked at '(.*)', ([^\s:]+\.rs):(\d+):\d+`)
)

// ParseCargo разбирает вывод cargo test (обычный, не -q). Тест — путь как у libtest (tests::adds).
// File в Fail — абсолютный путь: cargo пишет его от корня воркспейса, а не от крейта.
func ParseCargo(out string, exitCode int, dir string) Result {
	var r Result
	seen := map[string]int{}
	lines := strings.Split(out, "\n")
	for i := 0; i < len(lines); i++ {
		line := strings.TrimRight(lines[i], "\r")
		if m := rsTestLine.FindStringSubmatch(line); m != nil {
			t := Test{Name: m[1], Pass: m[2] == "ok", Skip: m[2] == "ignored"}
			if j, ok := seen[t.Name]; ok {
				r.Tests[j] = t
			} else {
				seen[t.Name] = len(r.Tests)
				r.Tests = append(r.Tests, t)
			}
			continue
		}
		var test, file, msg string
		var ln int
		if m := rsPanicNew.FindStringSubmatch(line); m != nil {
			test, file = m[1], m[2]
			ln, _ = strconv.Atoi(m[3])
			// сообщение — следующие строки до пустой или note:
			var parts []string
			for j := i + 1; j < len(lines); j++ {
				l := strings.TrimSpace(lines[j])
				if l == "" || strings.HasPrefix(l, "note:") || strings.HasPrefix(l, "stack backtrace") {
					break
				}
				parts = append(parts, l)
				i = j
			}
			msg = strings.Join(parts, " ")
		} else if m := rsPanicOld.FindStringSubmatch(line); m != nil {
			test, msg, file = m[1], m[2], m[3]
			ln, _ = strconv.Atoi(m[4])
		} else {
			continue
		}
		if path := resolve(dir, file); path != "" {
			r.Fails = append(r.Fails, Fail{Test: test, File: path, Line: ln, Msg: msg})
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
	r.Build = exitCode != 0 && r.Passed == 0 && r.Failed == 0
	sort.SliceStable(r.Tests, func(i, j int) bool {
		if r.Tests[i].Pass != r.Tests[j].Pass {
			return !r.Tests[i].Pass
		}
		return r.Tests[i].Name < r.Tests[j].Name
	})
	return r
}

// resolve — путь из паники (от корня воркспейса или крейта) → настоящий файл; чужие (std, зависимости) — "".
func resolve(dir, file string) string {
	if filepath.IsAbs(file) {
		if _, err := os.Stat(file); err == nil && strings.HasPrefix(file, dir) {
			return file
		}
		return ""
	}
	for d := dir; ; d = filepath.Dir(d) {
		p := filepath.Join(d, file)
		if _, err := os.Stat(p); err == nil {
			return p
		}
		if _, err := os.Stat(filepath.Join(d, ".git")); err == nil || d == filepath.Dir(d) {
			return ""
		}
	}
}

var rsFn = regexp.MustCompile(`^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+(\w+)`)

// WhereRust — где объявлены тесты крейта: последнее имя пути (adds из tests::adds) → файл и строка.
func WhereRust(dir string) map[string][2]any {
	out := map[string][2]any{}
	for _, sub := range []string{"src", "tests", "benches"} {
		_ = filepath.WalkDir(filepath.Join(dir, sub), func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() || !strings.HasSuffix(path, ".rs") {
				return nil
			}
			f, err := os.Open(path)
			if err != nil {
				return nil
			}
			defer f.Close()
			sc := bufio.NewScanner(f)
			n, attr := 0, false
			for sc.Scan() {
				n++
				l := strings.TrimSpace(sc.Text())
				if strings.HasPrefix(l, "#[") {
					if strings.Contains(l, "test") || strings.Contains(l, "bench") {
						attr = true
					}
					continue
				}
				if m := rsFn.FindStringSubmatch(sc.Text()); m != nil && attr {
					out[m[1]] = [2]any{path, n}
				}
				if l != "" && !strings.HasPrefix(l, "//") {
					attr = false
				}
			}
			return nil
		})
	}
	return out
}

// lastName — tests::math::adds → adds
func lastName(name string) string {
	if i := strings.LastIndex(name, "::"); i >= 0 {
		return name[i+2:]
	}
	return name
}
