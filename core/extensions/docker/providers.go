package docker

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/van1dalgrr-arch/ownvim/core/sdk"
)

// compose.yaml как в IDE: дополнение ${VAR} из .env, K — значение переменной, пробел ca — добавить её в .env
// или поставить умолчание. Всё — провайдеры sdk: ownvim показывает их в обычном меню, по K и в пробел ca.
func init() {
	sdk.Completion("yaml", "${", completeVars)
	sdk.Hover("yaml", hoverVar)
	sdk.CodeActions("yaml", envActions)
}

// EnvEntry — переменная .env: значение и строка (с 1).
type EnvEntry struct {
	Value string
	Line  int
}

var envLine = regexp.MustCompile(`^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$`)

// EnvEntries — переменные .env со значениями (кавычки вокруг значения снимаются).
func EnvEntries(lines []string) map[string]EnvEntry {
	out := map[string]EnvEntry{}
	for i, l := range lines {
		m := envLine.FindStringSubmatch(l)
		if m == nil {
			continue
		}
		if _, ok := out[m[1]]; ok {
			continue
		}
		v := m[2]
		if len(v) >= 2 && (v[0] == '"' || v[0] == '\'') && v[len(v)-1] == v[0] {
			v = v[1 : len(v)-1]
		}
		out[m[1]] = EnvEntry{Value: v, Line: i + 1}
	}
	return out
}

var secretName = regexp.MustCompile(`(?i)(token|secret|passw|pass$|pwd|key|private|credential)`)

// Shown — значение для показа: секреты — первые символы и длина, остальное как есть.
func Shown(name, value string) string {
	if value == "" {
		return "(пусто)"
	}
	if secretName.MatchString(name) {
		r := []rune(value)
		if len(r) <= 4 {
			return "••••"
		}
		return fmt.Sprintf("%s… (%d симв.)", string(r[:3]), len(r))
	}
	return value
}

var varTyping = regexp.MustCompile(`\$\{?[A-Za-z0-9_]*$`)

func completeVars(c *sdk.Ctx, prefix string) []sdk.CompletionItem {
	if !IsCompose(c.File) {
		return nil
	}
	line := c.CurrentLine()
	before := line[:min(max(c.Col-1, 0), len(line))]
	if !varTyping.MatchString(before) {
		return nil // подсказывать только внутри $… / ${…
	}
	env := EnvEntries(readLines(filepath.Join(filepath.Dir(c.File), ".env")))
	var out []sdk.CompletionItem
	for name, e := range env {
		out = append(out, sdk.CompletionItem{Label: name, Kind: "variable", Detail: Shown(name, e.Value),
			Doc: fmt.Sprintf("`.env`, строка %d", e.Line)})
	}
	return out
}

// varAt — переменная под курсором
func varAt(c *sdk.Ctx) (Var, bool) {
	col := c.Col - 1
	for _, v := range VarsIn(c.CurrentLine()) {
		if col >= v.S && col < v.E {
			return v, true
		}
	}
	return Var{}, false
}

func hoverVar(c *sdk.Ctx) string {
	if !IsCompose(c.File) {
		return ""
	}
	v, ok := varAt(c)
	if !ok {
		return ""
	}
	env := EnvEntries(readLines(filepath.Join(filepath.Dir(c.File), ".env")))
	switch e, inEnv := env[v.Name]; {
	case inEnv:
		return fmt.Sprintf("**%s** = `%s`\n\nиз `.env`, строка %d", v.Name, Shown(v.Name, e.Value), e.Line)
	case os.Getenv(v.Name) != "":
		return fmt.Sprintf("**%s** = `%s`\n\nиз окружения (в `.env` нет)", v.Name, Shown(v.Name, os.Getenv(v.Name)))
	case v.Default:
		return fmt.Sprintf("**%s** — нет ни в `.env`, ни в окружении: compose возьмёт умолчание", v.Name)
	}
	return fmt.Sprintf("**%s** — нет ни в `.env`, ни в окружении, умолчания тоже нет: compose подставит пустую строку\n\n`пробел ca` — добавить в `.env`", v.Name)
}

func envActions(c *sdk.Ctx) []sdk.Action {
	if !IsCompose(c.File) {
		return nil
	}
	dir := filepath.Dir(c.File)
	env := EnvEntries(readLines(filepath.Join(dir, ".env")))
	var out []sdk.Action
	for _, v := range VarsIn(c.CurrentLine()) {
		if _, ok := env[v.Name]; ok || v.Default || os.Getenv(v.Name) != "" {
			continue
		}
		name, line := v.Name, c.Line
		out = append(out,
			sdk.Action{Title: fmt.Sprintf("Добавить %s в .env", name), Run: func(c *sdk.Ctx) error { return addToEnv(c, dir, name) }},
			sdk.Action{Title: fmt.Sprintf("Умолчание: ${%s:-…}", name), Run: func(c *sdk.Ctx) error { return addDefault(c, line, name) }},
		)
	}
	return out
}

// addToEnv — дописать NAME= в конец .env и встать туда во вставке
func addToEnv(c *sdk.Ctx, dir, name string) error {
	path := filepath.Join(dir, ".env")
	text := strings.TrimRight(strings.Join(readLines(path), "\n"), "\n")
	if text != "" {
		text += "\n"
	}
	text += name + "=\n"
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		return err
	}
	if err := c.Open(path, strings.Count(text, "\n")); err != nil {
		return err
	}
	return c.Feed("A")
}

// addDefault — ${NAME} → ${NAME:-} и курсор между - и }
func addDefault(c *sdk.Ctx, line int, name string) error {
	l := c.LinesRange(line, line)
	if len(l) == 0 {
		return nil
	}
	from := "${" + name + "}"
	i := strings.Index(l[0], from)
	if i < 0 {
		return nil
	}
	updated := l[0][:i] + "${" + name + ":-}" + l[0][i+len(from):]
	if err := c.SetLines(line, line, []string{updated}); err != nil {
		return err
	}
	if err := c.SetCursor(line, i+len("${"+name+":-")+1); err != nil {
		return err
	}
	return c.Feed("i")
}
