// Package examples — примеры расширений ownvim на Go: смотреть, копировать, менять.
// Клавиш у них нет — запуск командой (:WordCount, :SortLines, :LongFuncs) или своей клавишей в settings.jsonc:
//
//	"keys": { "n <leader>xl": ":LongFuncs" }
//
// Настройки — в settings.jsonc: "extensions": { "examples": { "max_lines": 40 } }.
package examples

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"slices"
	"strings"

	"github.com/van1dalgrr-arch/ownvim/core/sdk"
)

func init() {
	// 1. Прочитать буфер и показать уведомление.
	sdk.Command("WordCount", "Сколько строк, слов и символов в файле", func(c *sdk.Ctx) error {
		text := strings.Join(c.Lines(), "\n")
		c.Notify("%d строк · %d слов · %d символов", strings.Count(text, "\n")+1, len(strings.Fields(text)), len([]rune(text)))
		return nil
	})

	// 2. Взять выделение и заменить его. Запуск: выделить строки → :SortLines (или своя клавиша "x <leader>xs").
	sdk.Command("SortLines", "Отсортировать выделенные строки", func(c *sdk.Ctx) error {
		if c.SelStart == 0 {
			return fmt.Errorf("выделите строки")
		}
		lines := strings.Split(c.Selection(), "\n")
		slices.SortFunc(lines, func(a, b string) int { return strings.Compare(strings.ToLower(a), strings.ToLower(b)) })
		return c.ReplaceSelection(strings.Join(lines, "\n"))
	})

	// 3. Разобрать Go-код настоящим парсером (go/ast) и поставить надписи у строк.
	// Длинные функции — справа от их заголовка «60 строк»: красным, если больше лимита.
	sdk.Command("LongFuncs", "Длинные функции Go-файла — надписи у заголовков", func(c *sdk.Ctx) error {
		if c.Filetype != "go" {
			return fmt.Errorf("это не Go-файл")
		}
		limit := c.SettingInt("max_lines", 40)
		fset := token.NewFileSet()
		file, err := parser.ParseFile(fset, c.File, strings.Join(c.Lines(), "\n"), 0)
		if err != nil {
			return fmt.Errorf("не разобрать: %w", err)
		}
		var marks []sdk.Mark
		for _, d := range file.Decls {
			fn, ok := d.(*ast.FuncDecl)
			if !ok || fn.Body == nil {
				continue
			}
			from, to := fset.Position(fn.Pos()).Line, fset.Position(fn.End()).Line
			n := to - from + 1
			color := "grey"
			if n > limit {
				color = "red"
			}
			marks = append(marks, sdk.Mark{Line: from, Text: fmt.Sprintf("%d строк", n), Color: color})
		}
		if err := c.Marks(marks); err != nil {
			return err
		}
		c.Notify("функций: %d, длиннее %d строк: %d", len(marks), limit, countRed(marks))
		return nil
	})
}

func countRed(marks []sdk.Mark) int {
	n := 0
	for _, m := range marks {
		if m.Color == "red" {
			n++
		}
	}
	return n
}
