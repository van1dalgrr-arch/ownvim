package docker

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"gopkg.in/yaml.v3"

	"github.com/van1dalgrr-arch/ownvim/core/sdk"
)

// Service — сервис compose-файла: имя и его строки (с 1).
type Service struct {
	Name string
	Line int // строка с именем сервиса
	Last int // последняя строка блока сервиса
}

var composeName = regexp.MustCompile(`^(docker-)?compose.*\.ya?ml$`)

// IsCompose — compose-файл по имени: compose.yaml, docker-compose.yml, compose.override.yaml…
func IsCompose(file string) bool { return composeName.MatchString(filepath.Base(file)) }

// Services — сервисы файла. Сначала настоящим YAML-парсером (с номерами строк), а если файл сейчас
// не разбирается (недописан) — построчно, по отступам.
func Services(lines []string) []Service {
	if s, ok := servicesYAML(lines); ok {
		return s
	}
	return servicesByIndent(lines)
}

func servicesYAML(lines []string) ([]Service, bool) {
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(strings.Join(lines, "\n")), &doc); err != nil || len(doc.Content) == 0 {
		return nil, false
	}
	root := doc.Content[0]
	if root.Kind != yaml.MappingNode {
		return nil, false
	}
	var out []Service
	for i := 0; i+1 < len(root.Content); i += 2 {
		if root.Content[i].Value != "services" || root.Content[i+1].Kind != yaml.MappingNode {
			continue
		}
		end := len(lines) // конец раздела services — строка перед следующим ключом верхнего уровня
		if i+2 < len(root.Content) {
			end = root.Content[i+2].Line - 1
		}
		m := root.Content[i+1].Content
		for j := 0; j+1 < len(m); j += 2 {
			last := end
			if j+2 < len(m) {
				last = m[j+2].Line - 1
			}
			out = append(out, Service{Name: m[j].Value, Line: m[j].Line, Last: last})
		}
	}
	return out, true
}

var (
	serviceLine = regexp.MustCompile(`^(\s+)["']?([\w.\-]+)["']?:\s*(#.*)?$`)
	topLine     = regexp.MustCompile(`^[\w\-]`)
)

func servicesByIndent(lines []string) []Service {
	var out []Service
	inside, indent := false, -1
	closeLast := func(at int) {
		if n := len(out); n > 0 && out[n-1].Last == 0 {
			out[n-1].Last = at
		}
	}
	for i, l := range lines {
		switch {
		case strings.HasPrefix(l, "services:"):
			inside, indent = true, -1
		case topLine.MatchString(l):
			if inside {
				closeLast(i)
			}
			inside = false
		case inside:
			if m := serviceLine.FindStringSubmatch(l); m != nil {
				if indent < 0 {
					indent = len(m[1])
				}
				if len(m[1]) == indent {
					closeLast(i)
					out = append(out, Service{Name: m[2], Line: i + 1})
				}
			}
		}
	}
	closeLast(len(lines))
	return out
}

// ServiceAt — сервис, в блоке которого строка line (с 1).
func ServiceAt(services []Service, line int) (Service, bool) {
	for _, s := range services {
		if line >= s.Line && line <= s.Last {
			return s, true
		}
	}
	return Service{}, false
}

// ── статус контейнеров ───────────────────────────────────────────────────────

// Container — строка docker compose ps --format json.
type Container struct {
	Service    string `json:"Service"`
	State      string `json:"State"`
	Health     string `json:"Health"`
	Status     string `json:"Status"`
	ExitCode   int    `json:"ExitCode"`
	Publishers []struct {
		PublishedPort int `json:"PublishedPort"`
	} `json:"Publishers"`
}

// Status — состояние проекта compose в папке.
type Status struct {
	Down bool                 `json:"down"` // docker не запущен
	List map[string]Container `json:"list"` // сервис → контейнер (первый работающий)
	At   time.Time            `json:"-"`
}

var (
	cacheMu sync.Mutex
	cache   = map[string]Status{}
)

// jsonLines — docker отдаёт JSON построчно (compose v2.21+) или массивом (старые версии).
func jsonLines(out []byte) []Container {
	s := strings.TrimSpace(string(out))
	var list []Container
	if strings.HasPrefix(s, "[") {
		_ = json.Unmarshal([]byte(s), &list)
		return list
	}
	for line := range strings.SplitSeq(s, "\n") {
		var c Container
		if json.Unmarshal([]byte(line), &c) == nil {
			list = append(list, c)
		}
	}
	return list
}

// Fetch спрашивает docker compose ps в папке dir и кладёт ответ в кэш.
func Fetch(dir string) Status {
	cmd := exec.Command("docker", "compose", "ps", "-a", "--format", "json")
	cmd.Dir = dir
	out, err := cmd.Output()
	st := Status{List: map[string]Container{}, At: time.Now()}
	if err != nil {
		msg := ""
		if ee, ok := err.(*exec.ExitError); ok {
			msg = string(ee.Stderr)
		}
		st.Down = strings.Contains(msg, "Cannot connect") || strings.Contains(msg, "failed to connect")
	}
	for _, c := range jsonLines(out) {
		if prev, ok := st.List[c.Service]; c.Service != "" && (!ok || (prev.State != "running" && c.State == "running")) {
			st.List[c.Service] = c
		}
	}
	cacheMu.Lock()
	cache[dir] = st
	cacheMu.Unlock()
	return st
}

// Cached — последний известный статус папки.
func Cached(dir string) (Status, bool) {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	st, ok := cache[dir]
	return st, ok
}

// Part — кусок надписи и его цвет.
type Part = sdk.Part

var (
	stateWord = map[string][3]string{
		"running":    {"●", "green", "работает"},
		"restarting": {"↻", "yellow", "перезапускается"},
		"paused":     {"⏸", "blue", "на паузе"},
		"created":    {"○", "grey", "создан"},
		"exited":     {"○", "red", "остановлен"},
		"dead":       {"✗", "red", "мёртв"},
	}
	healthWord = map[string][2]string{"healthy": {"здоров", "green"}, "unhealthy": {"болен", "red"}, "starting": {"стартует", "yellow"}}
	exitCode   = regexp.MustCompile(`Exited \((\d+)\)`)
)

// StatusParts — надпись статуса сервиса: ● работает · здоров · :8080
func StatusParts(c *Container) []Part {
	if c == nil {
		return []Part{{Text: "○ не запущен", Color: "grey"}}
	}
	st, ok := stateWord[c.State]
	if !ok {
		st = [3]string{"•", "grey", c.State}
	}
	color, word := st[1], st[2]
	if c.State == "exited" {
		code := c.ExitCode
		if m := exitCode.FindStringSubmatch(c.Status); m != nil && code == 0 {
			code, _ = strconv.Atoi(m[1])
		}
		if code == 0 {
			color = "grey"
		}
		word = fmt.Sprintf("%s (код %d)", word, code)
	}
	parts := []Part{{Text: st[0] + " " + word, Color: color}}
	if h, ok := healthWord[c.Health]; ok {
		parts = append(parts, Part{Text: " · ", Color: "grey"}, Part{Text: h[0], Color: h[1]})
	}
	var ports []string
	seen := map[int]bool{}
	for _, p := range c.Publishers {
		if p.PublishedPort > 0 && !seen[p.PublishedPort] {
			seen[p.PublishedPort] = true
			ports = append(ports, ":"+strconv.Itoa(p.PublishedPort))
		}
	}
	if len(ports) > 0 {
		parts = append(parts, Part{Text: " · " + strings.Join(ports, " "), Color: "grey"})
	}
	return parts
}

// ── ${VAR} и .env ────────────────────────────────────────────────────────────

// Var — переменная в строке compose: имя, байты [S, E) и есть ли умолчание (${VAR:-x}).
type Var struct {
	Name    string
	S, E    int
	Default bool
}

var (
	braced = regexp.MustCompile(`^\{([A-Za-z_][A-Za-z0-9_]*)([^}]*)\}`)
	plain  = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*`)
	hasDef = regexp.MustCompile(`^:?[-?+]`)
)

// VarsIn — ${VAR}, ${VAR:-x}, $VAR в строке; $$ — экранированный доллар.
func VarsIn(line string) []Var {
	var out []Var
	for i := 0; i < len(line); i++ {
		if line[i] != '$' {
			continue
		}
		rest := line[i+1:]
		switch {
		case strings.HasPrefix(rest, "$"):
			i++
		case strings.HasPrefix(rest, "{"):
			if m := braced.FindStringSubmatchIndex(rest); m != nil {
				out = append(out, Var{Name: rest[m[2]:m[3]], S: i, E: i + 1 + m[1], Default: hasDef.MatchString(rest[m[4]:m[5]])})
				i += m[1]
			}
		default:
			if m := plain.FindStringIndex(rest); m != nil {
				out = append(out, Var{Name: rest[:m[1]], S: i, E: i + 1 + m[1]})
				i += m[1]
			}
		}
	}
	return out
}

var envKey = regexp.MustCompile(`^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=`)

// EnvVars — переменные .env: имя → строка (с 1).
func EnvVars(lines []string) map[string]int {
	out := map[string]int{}
	for i, l := range lines {
		if m := envKey.FindStringSubmatch(l); m != nil {
			if _, ok := out[m[1]]; !ok {
				out[m[1]] = i + 1
			}
		}
	}
	return out
}
