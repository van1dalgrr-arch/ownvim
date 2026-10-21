// Package docker — Docker прямо в коде, без отдельных окон (контейнерами управляет своя утилита, alt-o):
//
//	compose.yaml — справа от каждого сервиса статус: ● работает · здоров · :8080, ○ остановлен (код 1);
//	  обновляется сам, пока файл на экране. enter на сервисе — up / собрать / restart / stop / логи / shell.
//	  ${VAR} без значения в .env и без умолчания — предупреждение; gd на ${VAR} — к .env (нет — допишет).
//	Dockerfile — справа от RUN / COPY / ADD вес слоя в собранном образе, на FROM — итог и база (:DockerLayers — образ).
//
// Написано на sdk — так же, как пишется любое своё расширение. Настройки — "modules": { "docker": { … } }:
// interval_ms (3000), compose_status, layers, env_check (true).
package docker

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/van1dalgrr-arch/ownvim/core/sdk"
)

const (
	composeFiles = "compose*.yaml,compose*.yml,docker-compose*.yaml,docker-compose*.yml"
	dockerfiles  = "Dockerfile,Dockerfile.*,*.Dockerfile,*.dockerfile,Containerfile"
)

// последние настройки модуля — фоновому опросу их некому передать, берём из последнего события
var (
	settingsMu   sync.Mutex
	lastSettings = map[string]any{}
	lastFetch    = map[string]time.Time{}
)

func remember(c *sdk.Ctx) {
	settingsMu.Lock()
	defer settingsMu.Unlock()
	if len(c.Settings) > 0 {
		lastSettings = c.Settings
	}
}

func on(key string) bool {
	settingsMu.Lock()
	defer settingsMu.Unlock()
	v, ok := lastSettings[key].(bool)
	return !ok || v
}

func interval() time.Duration {
	settingsMu.Lock()
	defer settingsMu.Unlock()
	if v, ok := lastSettings["interval_ms"].(float64); ok && v >= 500 {
		return time.Duration(v) * time.Millisecond
	}
	return 3 * time.Second
}

func init() {
	sdk.On("BufEnter,BufWritePost,FocusGained", composeFiles, func(c *sdk.Ctx) error {
		remember(c)
		if err := c.MapKey("n", "<cr>", "Сервис: up / restart / stop / логи / shell", serviceMenu); err != nil {
			return err
		}
		if err := c.MapKey("n", "gd", "${VAR} → .env", gotoEnv); err != nil {
			return err
		}
		checkEnv(c)
		return refreshCompose(c, true)
	})
	sdk.On("TextChanged,InsertLeave", composeFiles, func(c *sdk.Ctx) error {
		checkEnv(c)
		return renderCompose(c)
	})
	sdk.On("CursorMoved", composeFiles, renderCompose)
	sdk.Every(time.Second, func(c *sdk.Ctx) error {
		if !on("compose_status") {
			return nil
		}
		for _, b := range c.VisibleBuffers() {
			if IsCompose(b.File) {
				_ = refreshCompose(c.ForBuffer(b), false)
			}
		}
		return nil
	})

	sdk.On("BufEnter,BufWritePost,FocusGained", dockerfiles, func(c *sdk.Ctx) error {
		remember(c)
		return refreshLayers(c)
	})
	sdk.Command("DockerLayers", "Образ, вес слоёв которого показывать в Dockerfile", pickImage)

	// стартовый экран: статус compose проекта (require("own.ext").call("docker.status", { dir = … }))
	sdk.Func("docker.status", func(c *sdk.Ctx) error {
		dir, _ := c.Args["dir"].(string)
		if dir == "" {
			return nil
		}
		return c.Publish("docker.status:"+dir, Fetch(dir))
	})
}

// ── compose ──────────────────────────────────────────────────────────────────

// refreshCompose — спросить docker (не чаще interval, если force=false) и перерисовать
func refreshCompose(c *sdk.Ctx, force bool) error {
	if !on("compose_status") {
		return c.Marks(nil)
	}
	dir := filepath.Dir(c.File)
	every := interval() // до блокировки: interval() берёт ту же блокировку, а в Go она не повторная
	settingsMu.Lock()
	due := force || time.Since(lastFetch[dir]) >= every
	if due {
		lastFetch[dir] = time.Now()
	}
	settingsMu.Unlock()
	if due {
		Fetch(dir)
	}
	return renderCompose(c)
}

func renderCompose(c *sdk.Ctx) error {
	st, ok := Cached(filepath.Dir(c.File))
	if !ok || !on("compose_status") {
		return nil
	}
	var marks []sdk.Mark
	for _, s := range Services(c.Lines()) {
		var parts []sdk.Part
		if st.Down {
			parts = []sdk.Part{{Text: "○ docker не запущен", Color: "grey"}}
		} else if ct, ok := st.List[s.Name]; ok {
			parts = StatusParts(&ct)
		} else {
			parts = StatusParts(nil)
		}
		if c.Line == s.Line {
			parts = append(parts, sdk.Part{Text: "   ⏎ действия", Color: "grey"})
		}
		marks = append(marks, sdk.Mark{Line: s.Line, Parts: parts})
	}
	return c.Marks(marks)
}

func serviceMenu(c *sdk.Ctx) error {
	s, ok := ServiceAt(Services(c.Lines()), c.Line)
	if !ok {
		return sdk.ErrPass // не на сервисе — enter как обычно
	}
	dir := filepath.Dir(c.File)
	type action struct {
		label string
		run   func() error
	}
	compose := func(label string, args ...string) func() error {
		return func() error {
			c.Notify("%s: %s…", s.Name, label)
			cmd := exec.Command("docker", append([]string{"compose"}, args...)...)
			cmd.Dir = dir
			if out, err := cmd.CombinedOutput(); err != nil {
				return fmt.Errorf("%s — ошибка\n%s", label, strings.TrimSpace(string(out)))
			}
			c.Notify("%s: %s — готово", s.Name, label)
			return refreshCompose(c, true)
		}
	}
	term := func(args ...string) func() error {
		return func() error { return c.Terminal(append([]string{"docker", "compose"}, args...), dir) }
	}
	actions := []action{
		{"▶ up", compose("up", "up", "-d", s.Name)},
		{"⇪ собрать и up", term("up", "-d", "--build", s.Name)},
		{"⟳ restart", compose("restart", "restart", s.Name)},
		{"■ stop", compose("stop", "stop", s.Name)},
		{"≡ логи", term("logs", "-f", "--tail", "200", s.Name)},
		{"❯ shell", term("exec", s.Name, "sh", "-c", "command -v bash >/dev/null && exec bash || exec sh")},
	}
	labels := make([]string, len(actions))
	for i, a := range actions {
		labels[i] = a.label
	}
	i, ok := c.Select(s.Name, labels)
	if !ok {
		return nil
	}
	return actions[i].run()
}

func readLines(path string) []string {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	return strings.Split(string(b), "\n")
}

func checkEnv(c *sdk.Ctx) {
	if !on("env_check") {
		return
	}
	vars := EnvVars(readLines(filepath.Join(filepath.Dir(c.File), ".env")))
	var ps []sdk.Problem
	for i, line := range c.Lines() {
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		for _, v := range VarsIn(line) {
			_, inEnv := vars[v.Name]
			_, inProc := os.LookupEnv(v.Name)
			if !v.Default && !inEnv && !inProc {
				ps = append(ps, sdk.Problem{Line: i + 1, Col: v.S + 1, Severity: "warn",
					Message: fmt.Sprintf("%s нет в .env и нет умолчания (${%s:-…}) — gd допишет её в .env", v.Name, v.Name)})
			}
		}
	}
	_ = c.Problems(ps)
}

func gotoEnv(c *sdk.Ctx) error {
	col := c.Col - 1
	for _, v := range VarsIn(c.CurrentLine()) {
		if col < v.S || col >= v.E {
			continue
		}
		path := filepath.Join(filepath.Dir(c.File), ".env")
		lines := readLines(path)
		if n, ok := EnvVars(lines)[v.Name]; ok {
			return c.Open(path, n)
		}
		return addToEnv(c, filepath.Dir(c.File), v.Name) // нет — дописать VAR= и встать туда во вставке
	}
	return sdk.ErrPass // не на переменной — gd как обычно (к определению)
}

// ── Dockerfile ───────────────────────────────────────────────────────────────

func imageFor(c *sdk.Ctx) string {
	var chosen string
	if c.Store().Get("image:"+c.File, &chosen) && chosen != "" {
		return chosen
	}
	images, err := Images()
	if err != nil {
		return ""
	}
	return GuessImage(c.Root, images)
}

func refreshLayers(c *sdk.Ctx) error {
	if !on("layers") {
		return c.Marks(nil)
	}
	image := imageFor(c)
	if image == "" {
		return c.Marks(nil)
	}
	history, err := History(image)
	if err != nil {
		return nil // образа нет (удалили) — молча, без меток
	}
	ins := LastStage(c.Lines())
	sizes, total, base, ok := Assign(ins, history)
	if !ok {
		return c.Marks(nil)
	}
	var marks []sdk.Mark
	for _, s := range sizes {
		marks = append(marks, sdk.Mark{Line: s.Line, Text: "+" + Human(s.Bytes), Color: SizeColor(s.Bytes), Right: true})
	}
	marks = append(marks, sdk.Mark{Line: ins[0].Line, Right: true, Color: "grey",
		Text: fmt.Sprintf("%s · %s · база %s", image, Human(total), Human(base))})
	return c.Marks(marks)
}

func pickImage(c *sdk.Ctx) error {
	images, err := Images()
	if err != nil {
		return fmt.Errorf("docker не отвечает")
	}
	var names []string
	for _, im := range images {
		if im.Repository != "<none>" {
			names = append(names, im.Name())
		}
	}
	i, ok := c.Select("Образ этого Dockerfile", names)
	if !ok {
		return nil
	}
	if err := c.Store().Set("image:"+c.File, names[i]); err != nil {
		return err
	}
	return refreshLayers(c)
}
