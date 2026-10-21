// ownvimd — Go-ядро ownvim. Два режима:
//
//	ownvimd settings load --config DIR --data DIR      собрать настройки, записать кэш, напечатать JSON
//	ownvimd settings set  --config DIR KEY JSON        записать ключ верхнего уровня в settings.jsonc
//	ownvimd serve                                      мост: msgpack-RPC с Neovim через stdin/stdout
//	ownvimd extensions manifest                        какие команды, клавиши и события объявили расширения
//	ownvimd version
//
// Настройки нужны до загрузки плагинов, синхронно, — поэтому это обычный вызов программы, а не RPC.
// Мост (serve) — для модулей, которым нужно говорить с Neovim: читать буферы, ставить метки, получать события.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/van1dalgrr-arch/ownvim/core/bridge"
	_ "github.com/van1dalgrr-arch/ownvim/core/extensions" // все расширения из core/extensions/*
	"github.com/van1dalgrr-arch/ownvim/core/sdk"
	"github.com/van1dalgrr-arch/ownvim/core/settings"
)

const version = "0.1.0"

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "settings":
		settingsCmd(os.Args[2:])
	case "extensions":
		_ = json.NewEncoder(os.Stdout).Encode(sdk.GetManifest())
	case "serve":
		bridge.Register("ext.run", sdk.Dispatch) // команды и события расширений (vim.rpcnotify)
		bridge.Register("ext.reply", sdk.Reply)  // ответы диалогов: выбор, ввод, список
		// расширения как языковой сервер: дополнение, описание по K, исправления (vim.rpcrequest)
		bridge.Register("ext.complete", sdk.Complete)
		bridge.Register("ext.hover", sdk.HoverText)
		bridge.Register("ext.actions", sdk.Actions)
		bridge.OnReady(sdk.Start) // фоновые задачи (sdk.Every) — когда мост готов
		if err := bridge.Serve(); err != nil {
			fmt.Fprintln(os.Stderr, "ownvimd serve:", err)
			os.Exit(1)
		}
	case "version":
		fmt.Println(version)
	default:
		usage()
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "ownvimd settings load|set … | extensions manifest | serve | version")
	os.Exit(2)
}

func settingsCmd(args []string) {
	if len(args) < 1 {
		usage()
	}
	fs := flag.NewFlagSet("settings", flag.ExitOnError)
	cfg := fs.String("config", "", "папка ownvim (stdpath config)")
	data := fs.String("data", "", "данные ownvim (stdpath data)")
	_ = fs.Parse(args[1:])
	p := settings.Paths{Config: *cfg, Data: *data}
	switch args[0] {
	case "load":
		r := settings.Load(p)
		if err := settings.WriteCache(p, r); err != nil {
			fmt.Fprintln(os.Stderr, "кэш не записан:", err)
		}
		_ = json.NewEncoder(os.Stdout).Encode(r)
	case "set":
		if fs.NArg() != 2 {
			usage()
		}
		if err := settings.Set(p, fs.Arg(0), fs.Arg(1)); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	default:
		usage()
	}
}
