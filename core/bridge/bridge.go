// Package bridge — мост Go ↔ Neovim: msgpack-RPC через stdin/stdout (Neovim запускает ownvimd serve
// через jobstart(…, { rpc = true }) и зовёт методы через vim.rpcrequest / vim.rpcnotify).
//
// Новый метод — Register("имя", функция) в init() своего пакета (или здесь), Lua зовёт require("own.core").request("имя", …).
// Из функции можно звать Neovim обратно через Nvim(): буферы, метки, команды — всё, что есть в API.
package bridge

import (
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/neovim/go-client/nvim"
)

var (
	mu       sync.Mutex
	ready    []func(*nvim.Nvim)
	handlers = map[string]any{}
	client   *nvim.Nvim
	started  = time.Now()
)

// Register добавляет метод моста. fn — функция Go; аргументы и результат приходят и уходят через msgpack
// (как в go-client: последним результатом может быть error).
func Register(name string, fn any) {
	mu.Lock()
	defer mu.Unlock()
	handlers[name] = fn
}

// OnReady — выполнить fn с клиентом Neovim, когда мост запущен (фоновые задачи и т.п.).
func OnReady(fn func(*nvim.Nvim)) {
	mu.Lock()
	defer mu.Unlock()
	ready = append(ready, fn)
}

// Nvim — клиент для вызовов Neovim из обработчиков (после Serve).
func Nvim() *nvim.Nvim { return client }

func init() {
	// ping — проверка моста и замер его стоимости из Lua
	Register("ping", func() (string, error) { return "pong", nil })
	Register("info", func() (map[string]any, error) {
		return map[string]any{"pid": os.Getpid(), "uptime_ms": time.Since(started).Milliseconds()}, nil
	})
}

// Serve — работать мостом, пока Neovim не закроет канал.
func Serve() error {
	// stdout занят протоколом: всё, что печатается, — только в stderr
	v, err := nvim.New(os.Stdin, os.Stdout, os.Stdout, func(format string, args ...any) {
		fmt.Fprintf(os.Stderr, format+"\n", args...)
	})
	if err != nil {
		return err
	}
	client = v
	mu.Lock()
	for name, fn := range handlers {
		if err := v.RegisterHandler(name, fn); err != nil {
			mu.Unlock()
			return fmt.Errorf("метод %s: %w", name, err)
		}
	}
	starters := append([]func(*nvim.Nvim){}, ready...)
	mu.Unlock()
	for _, fn := range starters {
		fn(v)
	}
	return v.Serve()
}
