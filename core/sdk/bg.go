package sdk

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/neovim/go-client/nvim"
)

// ── фоновые задачи ───────────────────────────────────────────────────────────

type ticker struct {
	every time.Duration
	ext   string
	run   Handler
}

var tickers []ticker

// Every — выполнять run каждые every, пока работает ядро (опрос Docker, проверка сервиса…).
// У c нет текущего буфера: что видно на экране — c.VisibleBuffers(), работать с буфером — c.ForBuffer(b).
// Первый раз — сразу после запуска моста.
func Every(every time.Duration, run Handler) {
	mu.Lock()
	defer mu.Unlock()
	tickers = append(tickers, ticker{every: every, ext: extOf(), run: run})
}

// Start запускает фоновые задачи (зовёт ownvimd serve, когда мост готов).
func Start(v *nvim.Nvim) {
	mu.Lock()
	list := append([]ticker{}, tickers...)
	mu.Unlock()
	for _, t := range list {
		go func() {
			for {
				safely(&Ctx{Ext: t.ext, Data: os.Getenv("OWNVIM_DATA"), nv: v}, "фоновая задача", t.run)
				time.Sleep(t.every)
			}
		}()
	}
}

// safely — выполнить с перехватом паники и ошибки (уведомлением).
func safely(c *Ctx, name string, run Handler) {
	defer func() {
		if r := recover(); r != nil {
			c.Warn("%s: паника — %v\n%s", name, r, where())
		}
	}()
	if err := run(c); err != nil && err != ErrPass {
		c.Warn("%s: %v", name, err)
	}
}

// ── функции, которые зовёт Lua (стартовый экран, свои модули) ────────────────

var funcs = map[string]*command{}
var dynamic = map[string]*command{} // клавиши MapKey

// Func — функция, которую можно позвать из Lua: require("own.ext").call("имя", { … }); аргументы — в c.Args.
// Нужна, когда интерфейс на Lua (стартовый экран, статусная строка) хочет данные из Go: Func считает,
// c.Publish отдаёт результат.
func Func(name string, run Handler) {
	mu.Lock()
	defer mu.Unlock()
	funcs[name] = &command{Name: name, Ext: extOf(), run: run}
}

// Publish — отдать данные в Lua: require("own.ext").data[key] = value и событие User OwnExtData (data = { key = … }).
// value — что угодно, что умеет json.Marshal: поля структур называются по json-тегам.
func (c *Ctx) Publish(key string, value any) error { return c.lua("publish", nil, key, plain(value)) }

// plain — значение через JSON: так поля структур идут под json-тегами (msgpack-клиент о них не знает).
func plain(v any) any {
	b, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	var out any
	_ = json.Unmarshal(b, &out)
	return out
}

// ── что на экране ────────────────────────────────────────────────────────────

// BufInfo — буфер, видимый в окне.
type BufInfo struct {
	Buf      int    `json:"buf"`
	File     string `json:"file"`
	Filetype string `json:"filetype"`
	Line     int    `json:"line"` // курсор в этом окне (с 1)
	Current  bool   `json:"current"`
}

// VisibleBuffers — буферы, которые сейчас видны в окнах текущей вкладки.
func (c *Ctx) VisibleBuffers() []BufInfo {
	var raw []map[string]any
	if c.lua("visible", &raw) != nil {
		return nil
	}
	out := make([]BufInfo, 0, len(raw))
	for _, m := range raw {
		b, _ := json.Marshal(m)
		var bi BufInfo
		_ = json.Unmarshal(b, &bi)
		out = append(out, bi)
	}
	return out
}

// ForBuffer — тот же контекст, но для другого буфера (метки, замечания, строки — уже в нём).
func (c *Ctx) ForBuffer(b BufInfo) *Ctx {
	cc := *c
	cc.Buf, cc.File, cc.Filetype, cc.Line = b.Buf, b.File, b.Filetype, b.Line
	return &cc
}

// ── хранилище расширения ─────────────────────────────────────────────────────

// Store — маленькое хранилище расширения: переживает перезапуск (~/.local/share/ownvim/ext-state/<имя>.json).
type Store struct {
	path string
}

var storeMu sync.Mutex

// Store — хранилище этого расширения.
func (c *Ctx) Store() *Store {
	return &Store{path: filepath.Join(c.Data, "ext-state", c.Ext+".json")}
}

func (s *Store) load() map[string]json.RawMessage {
	m := map[string]json.RawMessage{}
	if b, err := os.ReadFile(s.path); err == nil {
		_ = json.Unmarshal(b, &m)
	}
	return m
}

// Get читает значение key в out (как json.Unmarshal); нет — false.
func (s *Store) Get(key string, out any) bool {
	storeMu.Lock()
	defer storeMu.Unlock()
	raw, ok := s.load()[key]
	return ok && json.Unmarshal(raw, out) == nil
}

// Set записывает значение (любое, что умеет json.Marshal).
func (s *Store) Set(key string, value any) error {
	storeMu.Lock()
	defer storeMu.Unlock()
	m := s.load()
	b, err := json.Marshal(value)
	if err != nil {
		return err
	}
	m[key] = b
	out, _ := json.MarshalIndent(m, "", "  ")
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(s.path, out, 0o644)
}

func splitLines(s string) []string { return strings.Split(strings.TrimRight(s, "\n"), "\n") }
