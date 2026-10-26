// Package settings — движок настроек ownvim: defaults.jsonc + слой автоустановки + settings.jsonc.
//
// Слои сливаются по ключам: объекты — по ключам, остальное заменяется; true поверх объекта оставляет объект.
// Ошибки (сломанный JSON, неизвестный раздел, модуль, опция) — с местом в файле, чтобы ownvim подсветил строку.
// Результат пишется в кэш вместе с «отпечатком» исходных файлов: на старте Lua сверяет отпечаток и читает кэш,
// не запуская эту программу (запуск процесса медленнее, чем чтение готового JSON).
package settings

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/van1dalgrr-arch/ownvim/core/jsonc"
)

// Уровни ошибок — как vim.diagnostic.severity.
const (
	SeverityError = 1
	SeverityWarn  = 2
)

// Problem — замечание к строке файла настроек (строка и столбец с 0, как в vim.diagnostic).
type Problem struct {
	Lnum     int    `json:"lnum"`
	Col      int    `json:"col"`
	Severity int    `json:"severity"`
	Message  string `json:"message"`
}

// Result — итог загрузки; его же пишет кэш.
type Result struct {
	Settings map[string]any       `json:"settings,omitempty"` // нет — settings.jsonc или defaults.jsonc сломан
	Fallback map[string]any       `json:"fallback,omitempty"` // settings.jsonc сломан — только умолчания
	Error    string               `json:"error,omitempty"`    // "settings.jsonc:3 — JSON: …"
	Problems map[string][]Problem `json:"problems"`           // путь файла → замечания
	Stamp    map[string]string    `json:"stamp"`              // отпечаток исходных файлов
}

// Paths — где лежат настройки ownvim (config) и его данные (data, stdpath("data")).
type Paths struct {
	Config string
	Data   string
}

func (p Paths) Defaults() string { return filepath.Join(p.Config, "defaults.jsonc") }
func (p Paths) User() string     { return filepath.Join(p.Config, "settings.jsonc") }
func (p Paths) Modules() string  { return filepath.Join(p.Config, "lua", "own", "modules") }
func (p Paths) Auto() string     { return filepath.Join(p.Data, "own-auto.json") }
func (p Paths) Options() string  { return filepath.Join(p.Data, "own-options.json") }
func (p Paths) Cache() string    { return filepath.Join(p.Data, "own-settings.cache.json") }
func (p Paths) Plugins() string  { return filepath.Join(p.Config, "extensions") }

// PluginFiles — JSONC-наборы: extensions/*.jsonc по алфавиту.
func (p Paths) PluginFiles() []string {
	files, _ := filepath.Glob(filepath.Join(p.Plugins(), "*.jsonc"))
	sort.Strings(files)
	return files
}

// служебные поля набора: имя, описание, выключатель
var pluginMeta = map[string]bool{"name": true, "description": true, "enabled": true}

// top — разделы верхнего уровня; опечатка в имени не должна молча ничего не делать.
var top = map[string]bool{
	"theme": true, "options": true, "globals": true, "modules": true, "keys": true, "plugins": true,
	"lsp": true, "diagnostics": true, "tools": true, "completion": true, "format": true, "lint": true,
	"test": true, "debug": true, "database": true,
	"colors": true, "appearance": true, "icons": true, "statusline": true,
	"tabline": true, "breadcrumbs": true, "dashboard": true, "font": true, "animations": true, "git": true,
	"go": true, "tasks": true, "ai": true, "sessions": true, "explorer": true, "commands": true, "auto": true,
	"extensions": true, "checks": true, "run": true,
}

const topList = "theme, options, globals, modules, keys, plugins, lsp, diagnostics, tools, completion, format, lint, " +
	"test, debug, database, colors, appearance, icons, statusline, tabline, breadcrumbs, dashboard, font, animations, " +
	"git, go, tasks, ai, sessions, explorer, commands, auto, extensions, checks, run"

// Load читает оба файла, проверяет и сливает слои.
func Load(p Paths) Result {
	r := Result{Problems: map[string][]Problem{}, Stamp: Stamp(p)}
	options := readOptions(p.Options())
	defaults, derr := r.loadFile(p, p.Defaults(), options)
	user, uerr := r.loadFile(p, p.User(), options)
	if derr != nil {
		r.Error = fmt.Sprintf("defaults.jsonc:%d — %s", derr.Lnum, derr.Message)
		return r
	}
	// JSONC-наборы — слои между умолчаниями и settings.jsonc; сломанный набор пропускается (ошибка — на его строке)
	base := defaults
	for _, path := range p.PluginFiles() {
		v, err := r.loadFile(p, path, options)
		if err != nil {
			continue
		}
		if on, ok := v["enabled"].(bool); ok && !on {
			continue
		}
		layer := map[string]any{}
		for k, x := range v {
			if !pluginMeta[k] {
				layer[k] = x
			}
		}
		base = asMap(merge(base, layer))
	}
	if uerr != nil {
		r.Error = fmt.Sprintf("settings.jsonc:%d — %s", uerr.Lnum, uerr.Message)
		r.Fallback = build(p, base, map[string]any{})
		return r
	}
	r.Settings = build(p, base, user)
	return r
}

func (r *Result) loadFile(p Paths, path string, options map[string]bool) (map[string]any, *jsonc.Error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return map[string]any{}, nil // нет файла — пустой слой
	}
	text := string(data)
	value, jerr := jsonc.Decode(text)
	if jerr != nil {
		r.Problems[path] = []Problem{{Lnum: jerr.Lnum - 1, Col: jerr.Col, Severity: SeverityError, Message: jerr.Message}}
		return nil, jerr
	}
	r.Problems[path] = check(p, path, text, value, options)
	return value, nil
}

// build — merge(merge(defaults, слой автоустановки), user): слой лежит под settings.jsonc, пользователь сильнее.
func build(p Paths, defaults, user map[string]any) map[string]any {
	s := asMap(merge(defaults, user))
	if layer := autoLayer(p, s); layer != nil {
		s = asMap(merge(merge(defaults, layer), user))
	}
	return s
}

// check — неизвестные разделы, модули без файла, опции, которых нет у nvim.
func check(p Paths, path, text string, value map[string]any, options map[string]bool) []Problem {
	out := []Problem{}
	at := func(key, msg string) {
		lnum, col, ok := jsonc.FindKey(text, key)
		if !ok {
			lnum, col = 1, 0
		}
		out = append(out, Problem{Lnum: lnum - 1, Col: col, Severity: SeverityWarn, Message: msg})
	}
	plugin := filepath.Dir(path) == p.Plugins() // JSONC-набор: можно name, description, enabled
	for key := range value {
		if plugin && pluginMeta[key] {
			continue
		}
		if !top[key] && !strings.HasSuffix(key, "+") {
			at(key, fmt.Sprintf("неизвестный раздел %q — есть: %s", key, topList))
		}
	}
	if mods, ok := value["modules"].(map[string]any); ok {
		for name := range mods {
			if _, err := os.Stat(filepath.Join(p.Modules(), name+".lua")); err != nil {
				at(name, fmt.Sprintf("нет модуля %q (список — в defaults.jsonc, раздел modules)", name))
			}
		}
	}
	if opts, ok := value["options"].(map[string]any); ok && options != nil {
		for name := range opts {
			if !options[name] {
				at(name, fmt.Sprintf("у nvim нет опции %q (:help options)", name))
			}
		}
	}
	return out
}

// readOptions — имена опций nvim (полные и короткие); список пишет ownvim из nvim_get_all_options_info().
// Нет файла — опции не проверяются.
func readOptions(path string) map[string]bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var f struct {
		Names []string `json:"names"`
	}
	if json.Unmarshal(data, &f) != nil || len(f.Names) == 0 {
		return nil
	}
	set := make(map[string]bool, len(f.Names))
	for _, n := range f.Names {
		set[n] = true
	}
	return set
}

// Stamp — отпечаток всего, от чего зависит результат: время изменения и размер файлов, сама программа.
// Lua считает такой же через vim.uv.fs_stat и сверяет.
func Stamp(p Paths) map[string]string {
	engine, _ := os.Executable()
	return map[string]string{
		"defaults": stampOf(p.Defaults()),
		"user":     stampOf(p.User()),
		"auto":     stampOf(p.Auto()),
		"options":  stampOf(p.Options()),
		"modules":  stampOf(p.Modules()),
		"plugins":  pluginsStamp(p),
		"engine":   stampOf(engine),
	}
}

// pluginsStamp — отпечаток наборов: папка (добавили или убрали файл) и каждый *.jsonc (правка)
func pluginsStamp(p Paths) string {
	parts := []string{stampOf(p.Plugins())}
	for _, f := range p.PluginFiles() {
		parts = append(parts, filepath.Base(f)+"="+stampOf(f))
	}
	return strings.Join(parts, ";")
}

func stampOf(path string) string {
	st, err := os.Stat(path)
	if err != nil {
		return "-"
	}
	t := st.ModTime()
	return fmt.Sprintf("%d.%09d:%d", t.Unix(), t.Nanosecond(), st.Size())
}

// WriteCache кладёт результат в кэш атомарно: Lua никогда не прочитает половину файла.
func WriteCache(p Paths, r Result) error {
	data, err := json.Marshal(r)
	if err != nil {
		return err
	}
	tmp := p.Cache() + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, p.Cache())
}
