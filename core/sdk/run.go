package sdk

import (
	"encoding/json"
	"fmt"
	"runtime/debug"
	"strings"

	"github.com/neovim/go-client/nvim"
)

// Dispatch выполняет команду или событие id в фоне. Вызывает мост (ext.run) — по vim.rpcnotify, без ожидания:
// медленное расширение не морозит редактор. Ошибка и паника — уведомлением, редактор и ядро продолжают работать.
//
// Всё — в отдельной горутине: обработчик зовёт Neovim обратно, а цикл чтения RPC должен оставаться свободным.
func Dispatch(v *nvim.Nvim, id string, data map[string]any) {
	go func() {
		run, name, ok := lookup(id)
		c := &Ctx{nv: v}
		if raw, err := json.Marshal(data); err == nil {
			_ = json.Unmarshal(raw, c)
		}
		if !ok {
			_ = c.lua("notify", nil, fmt.Sprintf("нет команды %q — пересоберите ядро (сохраните любой .go в core/)", id), "error", "go")
			return
		}
		defer func() {
			if r := recover(); r != nil {
				_ = c.lua("notify", nil, fmt.Sprintf("%s: паника — %v\n%s", name, r, where()), "error", c.Ext)
			}
		}()
		err := run(c)
		switch {
		case err == ErrPass: // клавиша MapKey «не наша» — выполнить то, что на ней обычно
			if mode, lhs, ok := keyOf(id); ok {
				_ = c.lua("fallback", nil, mode, lhs)
			}
		case err != nil:
			_ = c.lua("notify", nil, fmt.Sprintf("%s: %v", name, err), "error", c.Ext)
		}
	}()
}

// keyOf — режим и клавиша из id клавиши MapKey ("ext|mode|lhs")
func keyOf(id string) (string, string, bool) {
	parts := strings.SplitN(id, "|", 3)
	if len(parts) != 3 {
		return "", "", false
	}
	return parts[1], parts[2], true
}

// where — строки стека из кода расширений: где именно случилась паника.
func where() string {
	var out []string
	for line := range strings.SplitSeq(string(debug.Stack()), "\n") {
		if strings.Contains(line, "/extensions/") && strings.Contains(line, ".go:") {
			out = append(out, strings.TrimSpace(line))
		}
	}
	if len(out) == 0 {
		return ""
	}
	return "место: " + strings.Join(out, "\n")
}
