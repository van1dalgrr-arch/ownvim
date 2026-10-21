package endpoints

import (
	"bytes"
	"go/ast"
	"go/parser"
	"go/printer"
	"go/token"
	"io/fs"
	"maps"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Route — маршрут Gin: метод, полный путь, хендлер и где он в коде (строка и столбец с 1 — на имени хендлера).
type Route struct {
	Method  string
	Path    string
	Handler string
	File    string
	Line    int
	Col     int
}

var methods = map[string]bool{"GET": true, "POST": true, "PUT": true, "PATCH": true, "DELETE": true,
	"HEAD": true, "OPTIONS": true, "Any": true, "Handle": false}

// типы, через которые передают группу маршрутов в другую функцию
var routerTypes = map[string]bool{"RouterGroup": true, "IRouter": true, "IRoutes": true, "Engine": true}

type pkgFile struct {
	path string
	src  []byte
	ast  *ast.File
}

// Collect — все маршруты Gin проекта: разбор Go-кода (go/ast), без запуска.
// Группы складываются по цепочке: api := r.Group("/api"); v1 := api.Group("/v1"); v1.GET("/x") → /api/v1/x.
// Группа, переданная в функцию того же пакета (registerUsers(api.Group("/users"))), тоже учитывается.
func Collect(root string) []Route {
	pkgs := map[string][]pkgFile{} // папка → файлы пакета
	fset := token.NewFileSet()
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if path != root && (name == "vendor" || name == "testdata" || name == "node_modules" || strings.HasPrefix(name, ".")) {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		src, err := os.ReadFile(path)
		if err != nil || !bytes.Contains(src, []byte("gin")) {
			return nil
		}
		f, err := parser.ParseFile(fset, path, src, 0)
		if err != nil {
			return nil
		}
		dir := filepath.Dir(path)
		pkgs[dir] = append(pkgs[dir], pkgFile{path: path, src: src, ast: f})
		return nil
	})
	var out []Route
	for _, files := range pkgs {
		out = append(out, collectPackage(fset, files)...)
	}
	order := map[string]int{"GET": 1, "POST": 2, "PUT": 3, "PATCH": 4, "DELETE": 5}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Path != out[j].Path {
			return out[i].Path < out[j].Path
		}
		oi, oj := order[out[i].Method], order[out[j].Method]
		if oi == 0 {
			oi = 9
		}
		if oj == 0 {
			oj = 9
		}
		return oi < oj
	})
	return out
}

// collectPackage — маршруты одного пакета. Префиксы параметров-групп функций берутся из мест вызова;
// несколько проходов — чтобы цепочки вызовов (main → registerAPI → registerUsers) сошлись.
func collectPackage(fset *token.FileSet, files []pkgFile) []Route {
	funcs := map[string]*ast.FuncDecl{}
	for _, f := range files {
		for _, d := range f.ast.Decls {
			if fn, ok := d.(*ast.FuncDecl); ok && fn.Recv == nil && fn.Body != nil {
				funcs[fn.Name.Name] = fn
			}
		}
	}
	params := map[string]map[string]string{} // функция → параметр-группа → префикс
	var routes []Route
	for range 4 {
		routes = nil
		changed := false
		for _, f := range files {
			for _, d := range f.ast.Decls {
				fn, ok := d.(*ast.FuncDecl)
				if !ok || fn.Body == nil {
					continue
				}
				env := map[string]string{}
				maps.Copy(env, params[fn.Name.Name])
				w := &walker{fset: fset, src: f.src, file: f.path, env: env, funcs: funcs, params: params}
				ast.Inspect(fn.Body, w.visit)
				routes = append(routes, w.routes...)
				changed = changed || w.changed
			}
		}
		if !changed {
			break
		}
	}
	return routes
}

type walker struct {
	fset    *token.FileSet
	src     []byte
	file    string
	env     map[string]string // переменная → префикс группы
	funcs   map[string]*ast.FuncDecl
	params  map[string]map[string]string
	routes  []Route
	changed bool
}

// prefix — полный префикс выражения-группы: переменная, r.Group("/p"), цепочка .Group().Group()
func (w *walker) prefix(e ast.Expr) (string, bool) {
	switch x := e.(type) {
	case *ast.Ident:
		p, ok := w.env[x.Name]
		return p, ok
	case *ast.CallExpr:
		sel, ok := x.Fun.(*ast.SelectorExpr)
		if !ok || sel.Sel.Name != "Group" || len(x.Args) == 0 {
			return "", false
		}
		base, _ := w.prefix(sel.X)
		if s, ok := stringLit(x.Args[0]); ok {
			return base + s, true
		}
	}
	return "", false
}

func stringLit(e ast.Expr) (string, bool) {
	lit, ok := e.(*ast.BasicLit)
	if !ok || lit.Kind != token.STRING {
		return "", false
	}
	s, err := strconv.Unquote(lit.Value)
	return s, err == nil
}

func (w *walker) visit(n ast.Node) bool {
	switch x := n.(type) {
	case *ast.AssignStmt:
		for i, rhs := range x.Rhs {
			if i >= len(x.Lhs) {
				break
			}
			if id, ok := x.Lhs[i].(*ast.Ident); ok {
				if p, ok := w.prefix(rhs); ok {
					w.env[id.Name] = p
				}
			}
		}
	case *ast.CallExpr:
		w.call(x)
	}
	return true
}

func (w *walker) call(x *ast.CallExpr) {
	// registerUsers(api.Group("/users")) — префикс переходит в параметр функции
	if id, ok := x.Fun.(*ast.Ident); ok {
		if fn := w.funcs[id.Name]; fn != nil {
			names := routerParams(fn)
			for i, arg := range x.Args {
				if i < len(names) && names[i] != "" {
					if p, ok := w.prefix(arg); ok {
						if w.params[id.Name] == nil {
							w.params[id.Name] = map[string]string{}
						}
						if old, had := w.params[id.Name][names[i]]; !had || old != p {
							w.params[id.Name][names[i]] = p
							w.changed = true
						}
					}
				}
			}
		}
		return
	}
	sel, ok := x.Fun.(*ast.SelectorExpr)
	if !ok || !methods[sel.Sel.Name] || len(x.Args) < 2 {
		return
	}
	path, ok := stringLit(x.Args[0])
	if !ok {
		return
	}
	base, _ := w.prefix(sel.X)
	h := x.Args[len(x.Args)-1]
	name, at := w.handler(h)
	pos := w.fset.Position(at)
	w.routes = append(w.routes, Route{
		Method:  strings.ToUpper(sel.Sel.Name),
		Path:    cleanPath(base + path),
		Handler: name,
		File:    w.file,
		Line:    pos.Line,
		Col:     pos.Column,
	})
}

// handler — текст хендлера и где стоит его имя (для перехода к определению):
// h.List → «h.List», на List; handler.Health(db) → «handler.Health», на Health; func(c) {…} → «func»
func (w *walker) handler(e ast.Expr) (string, token.Pos) {
	switch x := e.(type) {
	case *ast.FuncLit:
		return "func", x.Pos()
	case *ast.CallExpr:
		name, pos := w.handler(x.Fun)
		return name, pos
	case *ast.SelectorExpr:
		return w.text(x), x.Sel.Pos()
	case *ast.Ident:
		return x.Name, x.Pos()
	}
	return w.text(e), e.Pos()
}

func (w *walker) text(e ast.Expr) string {
	var b bytes.Buffer
	_ = printer.Fprint(&b, w.fset, e)
	return b.String()
}

// routerParams — имена параметров функции, через которые передают группу маршрутов ("" — не группа)
func routerParams(fn *ast.FuncDecl) []string {
	var out []string
	for _, f := range fn.Type.Params.List {
		group := false
		t := f.Type
		if st, ok := t.(*ast.StarExpr); ok {
			t = st.X
		}
		if s, ok := t.(*ast.SelectorExpr); ok && routerTypes[s.Sel.Name] {
			group = true
		}
		if len(f.Names) == 0 {
			out = append(out, "")
		}
		for _, n := range f.Names {
			if group {
				out = append(out, n.Name)
			} else {
				out = append(out, "")
			}
		}
	}
	return out
}

func cleanPath(p string) string {
	for strings.Contains(p, "//") {
		p = strings.ReplaceAll(p, "//", "/")
	}
	return p
}

// ExamplePath — путь для запроса: :id → 1, *rest → пусто
func ExamplePath(p string) string {
	parts := strings.Split(p, "/")
	for i, s := range parts {
		switch {
		case strings.HasPrefix(s, ":"):
			parts[i] = "1"
		case strings.HasPrefix(s, "*"):
			parts[i] = ""
		}
	}
	return cleanPath(strings.Join(parts, "/"))
}
