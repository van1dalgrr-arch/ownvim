package docker

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

// Instruction — инструкция Dockerfile: слово (RUN, COPY…), аргументы (продолжения строк склеены) и строка (с 1).
type Instruction struct {
	Keyword string
	Args    string
	Line    int
}

var (
	instr  = regexp.MustCompile(`^\s*([A-Za-z]+)\s+(.*)$`)
	spaces = regexp.MustCompile(`\s+`)
)

func norm(s string) string { return strings.TrimSpace(spaces.ReplaceAllString(s, " ")) }

// LastStage — инструкции последней стадии (с её FROM): только она попадает в итоговый образ.
func LastStage(lines []string) []Instruction {
	var all []Instruction
	for i := 0; i < len(lines); i++ {
		l := lines[i]
		if strings.HasPrefix(strings.TrimSpace(l), "#") {
			continue
		}
		m := instr.FindStringSubmatch(l)
		if m == nil {
			continue
		}
		start, text := i+1, m[2]
		for strings.HasSuffix(strings.TrimRight(text, " \t"), "\\") && i+1 < len(lines) {
			i++
			text = strings.TrimSuffix(strings.TrimRight(text, " \t"), "\\") + " "
			if !strings.HasPrefix(strings.TrimSpace(lines[i]), "#") {
				text += lines[i]
			}
		}
		all = append(all, Instruction{Keyword: strings.ToUpper(m[1]), Args: norm(text), Line: start})
	}
	from := 0
	for k, in := range all {
		if in.Keyword == "FROM" {
			from = k
		}
	}
	return all[from:]
}

// Layer — строка docker history: какой инструкцией создан и сколько весит.
type Layer struct {
	CreatedBy string `json:"CreatedBy"`
	Size      any    `json:"Size"` // число (--human=false) — бывает строкой
}

func (l Layer) Bytes() int64 {
	switch v := l.Size.(type) {
	case float64:
		return int64(v)
	case string:
		var n int64
		_, _ = fmt.Sscan(v, &n)
		return n
	}
	return 0
}

var (
	buildkitArgs = regexp.MustCompile(`^\|\d+ .*?/bin/sh -c `)
	mountFlag    = regexp.MustCompile(`--(mount|network)=\S+`)
	upperWord    = regexp.MustCompile(`^([A-Z]+)\s*(.*)$`)
)

// historyStep — "RUN |2 A=1 /bin/sh -c go build # buildkit" → RUN, "go build"
func historyStep(created string) (string, string) {
	s := strings.TrimSuffix(norm(created), " # buildkit")
	s = strings.TrimPrefix(s, "/bin/sh -c #(nop) ")
	m := upperWord.FindStringSubmatch(s)
	if m == nil {
		return "RUN", s
	}
	kw, rest := m[1], m[2]
	if kw == "RUN" {
		rest = buildkitArgs.ReplaceAllString(rest, "")
		rest = strings.TrimPrefix(rest, "/bin/sh -c ")
	}
	return kw, rest
}

func matches(in Instruction, kw, text string) bool {
	if in.Keyword != kw {
		return false
	}
	if kw != "RUN" {
		return true
	}
	a := norm(mountFlag.ReplaceAllString(in.Args, ""))
	n := min(30, len(a), len(text))
	return n == 0 || a[:n] == text[:n] || strings.Contains(text, a[:n])
}

// LayerSize — вес слоя у строки Dockerfile.
type LayerSize struct {
	Line  int
	Bytes int64
}

// Assign сопоставляет слои образа (history — новые сверху) инструкциям последней стадии.
// → веса по строкам, итог и вес базового образа; ok=false — ни одна инструкция не нашлась.
func Assign(ins []Instruction, history []Layer) (sizes []LayerSize, total, base int64, ok bool) {
	j, matched := 0, 0
	for k := len(ins) - 1; k >= 1; k-- {
		for look := j; look < min(j+5, len(history)); look++ {
			kw, text := historyStep(history[look].CreatedBy)
			if matches(ins[k], kw, text) {
				b := history[look].Bytes()
				total += b
				matched++
				if b > 0 {
					sizes = append(sizes, LayerSize{Line: ins[k].Line, Bytes: b})
				}
				j = look + 1
				break
			}
		}
	}
	if matched == 0 || len(ins) == 0 {
		return nil, 0, 0, false
	}
	for k := j; k < len(history); k++ {
		base += history[k].Bytes()
	}
	return sizes, total + base, base, true
}

// Human — 1000-байтные единицы, как у docker: 5.6 MB, 312 MB, 4.1 kB.
func Human(b int64) string {
	units := []string{"B", "kB", "MB", "GB"}
	n, i := float64(b), 0
	for n >= 1000 && i < len(units)-1 {
		n, i = n/1000, i+1
	}
	switch {
	case i == 0:
		return fmt.Sprintf("%d %s", b, units[0])
	case n < 10:
		return fmt.Sprintf("%.1f %s", n, units[i])
	}
	return fmt.Sprintf("%.0f %s", n, units[i])
}

// SizeColor — серый до 10 MB, синий от 10, жёлтый от 100, красный от 500.
func SizeColor(b int64) string {
	switch {
	case b >= 500e6:
		return "red"
	case b >= 100e6:
		return "yellow"
	case b >= 10e6:
		return "blue"
	}
	return "grey"
}

// Image — образ из docker images.
type Image struct {
	Repository string `json:"Repository"`
	Tag        string `json:"Tag"`
}

func (i Image) Name() string { return i.Repository + ":" + i.Tag }

// Images — локальные образы, новые сверху.
func Images() ([]Image, error) {
	out, err := exec.Command("docker", "images", "--format", "json").Output()
	if err != nil {
		return nil, err
	}
	var list []Image
	for line := range strings.SplitSeq(strings.TrimSpace(string(out)), "\n") {
		var im Image
		if json.Unmarshal([]byte(line), &im) == nil && im.Repository != "" {
			list = append(list, im)
		}
	}
	return list, nil
}

var notName = regexp.MustCompile(`[^a-z0-9_\-]`)

// GuessImage — образ Dockerfile проекта: <папка>:dev (задача «docker build»), затем <папка>-*/<папка>:* (compose).
func GuessImage(root string, images []Image) string {
	project := notName.ReplaceAllString(strings.ToLower(lastDir(root)), "")
	for _, im := range images {
		if im.Name() == project+":dev" {
			return im.Name()
		}
	}
	for _, im := range images {
		if n := im.Name(); strings.HasPrefix(n, project+"-") || strings.HasPrefix(n, project+":") {
			return n
		}
	}
	return ""
}

func lastDir(p string) string {
	p = strings.TrimRight(p, "/")
	if i := strings.LastIndexByte(p, '/'); i >= 0 {
		return p[i+1:]
	}
	return p
}

// History — слои образа, новые сверху.
func History(image string) ([]Layer, error) {
	out, err := exec.Command("docker", "history", "--no-trunc", "--human=false", "--format", "json", image).Output()
	if err != nil {
		return nil, err
	}
	var list []Layer
	for line := range strings.SplitSeq(strings.TrimSpace(string(out)), "\n") {
		var l Layer
		if json.Unmarshal([]byte(line), &l) == nil {
			list = append(list, l)
		}
	}
	return list, nil
}
