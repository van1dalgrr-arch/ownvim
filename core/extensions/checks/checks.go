// Package checks — свои проверки без кода: раздел "checks" в settings.jsonc или в JSONC-наборе.
// Команда запускается по событию (по умолчанию — сохранение), её вывод «файл:строка:столбец: текст» —
// замечания на строках, как у линтера. Подходит почти любой инструмент: go vet, shellcheck -f gcc, eslint -f unix,
// свой скрипт.
//
//	"checks": {
//	  "go vet": { "run": "go vet ./...", "pattern": "*.go" },
//	  "todo":   { "run": "rg -n --no-heading 'TODO\\(' ${file}", "format": "^(?P<file>[^:]+):(?P<line>\\d+):(?P<message>.*)$", "severity": "info" }
//	}
package checks

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/van1dalgrr-arch/ownvim/core/sdk"
)

// Default — формат вывода по умолчанию: файл:строка[:столбец]: [error|warning|…:] текст
var Default = regexp.MustCompile(`^(?P<file>[^:\s][^:]*?):(?P<line>\d+)(?::(?P<col>\d+))?:\s*(?:(?P<severity>error|warning|warn|info|note|hint)[:\s]+)?(?P<message>.+)$`)

// Finding — одна находка проверки.
type Finding struct {
	File     string
	Line     int
	Col      int
	Severity string
	Message  string
}

// Parse — находки из вывода команды: re с группами file, line и message (col и severity — по желанию).
func Parse(out string, re *regexp.Regexp, severity string) []Finding {
	var found []Finding
	for line := range strings.SplitSeq(out, "\n") {
		m := re.FindStringSubmatch(strings.TrimRight(line, "\r"))
		if m == nil {
			continue
		}
		f := Finding{Severity: severity}
		for i, name := range re.SubexpNames() {
			v := m[i]
			switch name {
			case "file":
				f.File = v
			case "line":
				f.Line, _ = strconv.Atoi(v)
			case "col":
				f.Col, _ = strconv.Atoi(v)
			case "message":
				f.Message = strings.TrimSpace(v)
			case "severity":
				switch strings.ToLower(v) {
				case "error":
					f.Severity = "error"
				case "warning", "warn":
					f.Severity = "warn"
				case "info", "note":
					f.Severity = "info"
				case "hint":
					f.Severity = "hint"
				}
			}
		}
		if f.File != "" && f.Line > 0 && f.Message != "" {
			found = append(found, f)
		}
	}
	return found
}

var (
	mu      sync.Mutex
	marked  = map[string][]string{}           // проверка → файлы, где стоят её замечания
	running = map[string]context.CancelFunc{} // проверка → идущий прогон
)

func init() {
	sdk.Func("checks.run", run)
}

func str(m map[string]any, k, def string) string {
	if s, ok := m[k].(string); ok && s != "" {
		return s
	}
	return def
}

func run(c *sdk.Ctx) error {
	name, _ := c.Args["name"].(string)
	spec, _ := c.Args["spec"].(map[string]any)
	if name == "" || spec == nil || str(spec, "run", "") == "" {
		return nil
	}
	re := Default
	if f := str(spec, "format", ""); f != "" {
		var err error
		if re, err = regexp.Compile(f); err != nil {
			return fmt.Errorf("проверка %q: format — не регулярное выражение: %v", name, err)
		}
	}
	cwd := c.Root
	if str(spec, "cwd", "root") == "file" {
		cwd = filepath.Dir(c.File)
	}
	cmdline := strings.NewReplacer("${file}", shellQuote(c.File), "${root}", shellQuote(c.Root),
		"${file_dir}", shellQuote(filepath.Dir(c.File))).Replace(str(spec, "run", ""))

	mu.Lock()
	if cancel := running[name]; cancel != nil {
		cancel() // прошлый прогон этой проверки устарел
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	running[name] = cancel
	mu.Unlock()
	defer cancel()

	cmd := exec.CommandContext(ctx, "sh", "-c", cmdline)
	cmd.Dir = cwd
	out, err := cmd.CombinedOutput()
	if ctx.Err() == context.Canceled {
		return nil
	}
	if ee, ok := err.(*exec.ExitError); ok && ee.ExitCode() == 127 {
		return fmt.Errorf("проверка %q: нет программы — %s", name, strings.TrimSpace(string(out)))
	}

	by := map[string][]sdk.Problem{}
	for _, f := range Parse(string(out), re, str(spec, "severity", "warn")) {
		path := f.File
		if !filepath.IsAbs(path) {
			path = filepath.Join(cwd, path)
		}
		by[path] = append(by[path], sdk.Problem{Line: f.Line, Col: f.Col, Severity: f.Severity, Message: f.Message})
	}
	cc := *c
	cc.Ext = "checks." + name // своё пространство замечаний у каждой проверки
	mu.Lock()
	prev := marked[name]
	mu.Unlock()
	for _, path := range prev {
		if _, still := by[path]; !still {
			_ = cc.ProblemsFor(path, nil)
		}
	}
	var now []string
	for path, ps := range by {
		_ = cc.ProblemsFor(path, ps)
		now = append(now, path)
	}
	mu.Lock()
	marked[name] = now
	mu.Unlock()
	return nil
}

func shellQuote(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }
