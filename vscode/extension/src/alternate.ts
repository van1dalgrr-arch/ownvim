// Тест ↔ код (cmd-shift-t, как Navigate → Test в GoLand) — как lua/own/tools/alternate.lua, для любого языка:
//   Go        foo.go ↔ foo_test.go
//   TS / JS   foo.ts ↔ foo.test.ts, foo.spec.ts, __tests__/foo.test.ts
//   Python    foo.py ↔ test_foo.py, foo_test.py, tests/test_foo.py
//   Rust      src/foo.rs ↔ tests/foo.rs (тесты внутри файла — прыжок к mod tests)
//   C / C++   foo.cpp ↔ foo_test.cpp, tests/foo_test.cpp
//   Lua       foo.lua ↔ foo_spec.lua, spec/foo_spec.lua
//   SQL       000003_x.up.sql ↔ 000003_x.down.sql (миграции)
// Есть пара — открывается; нет — создаётся первый вариант (папка тоже), как «Create New Test» в GoLand.
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { root } from "./core";

/** для файла кода: варианты пути к тесту (первый — что создавать) */
export function testsFor(dir: string, name: string, ext: string): string[] {
  const up = path.dirname(dir);
  const j = path.join;
  if (ext === "go") return [j(dir, `${name}_test.go`)];
  if (ext === "py") return [j(dir, `test_${name}.py`), j(dir, `${name}_test.py`), j(dir, "tests", `test_${name}.py`), j(up, "tests", `test_${name}.py`)];
  if (ext === "rs") {
    const crate = dir.match(/^(.*)\/src(\/|$)/)?.[1] || up;
    return [j(crate, "tests", `${name}.rs`)];
  }
  if (ext === "lua") return [j(dir, `${name}_spec.lua`), j(up, "spec", `${name}_spec.lua`)];
  if (["c", "cc", "cpp", "cxx"].includes(ext)) return [j(dir, `${name}_test.${ext}`), j(up, "tests", `${name}_test.${ext}`), j(up, "test", `${name}_test.${ext}`)];
  return [j(dir, `${name}.test.${ext}`), j(dir, `${name}.spec.${ext}`), j(dir, "__tests__", `${name}.test.${ext}`)];
}

/** для файла теста: варианты пути к коду (undefined — это не тест) */
export function codeFor(dir: string, name: string, ext: string): string[] | undefined {
  const up = path.dirname(dir);
  const base = name.match(/^(.+)_test$/)?.[1] || name.match(/^(.+)_spec$/)?.[1] || name.match(/^(.+)\.test$/)?.[1]
    || name.match(/^(.+)\.spec$/)?.[1] || name.match(/^test_(.+)$/)?.[1];
  if (base) {
    let dirs = [dir];
    if (["tests", "test", "spec", "__tests__"].includes(path.basename(dir))) dirs = [up, path.join(up, "src"), path.join(up, path.basename(up))];
    return dirs.map((d) => path.join(d, `${base}.${ext}`));
  }
  if (ext === "rs" && path.basename(dir) === "tests") return [path.join(up, "src", `${name}.rs`), path.join(up, "src", name, "mod.rs")];
}

/** пара миграции: x.up.sql ↔ x.down.sql */
function migration(file: string): string | undefined {
  const m = file.match(/^(.*)\.(up|down)\.sql$/);
  if (m) return `${m[1]}.${m[2] === "up" ? "down" : "up"}.sql`;
}

async function open(file: string) { await vscode.window.showTextDocument(vscode.Uri.file(file)); }

export async function toggle() {
  const ed = vscode.window.activeTextEditor;
  if (!ed || ed.document.isUntitled) return vscode.window.showWarningMessage("сначала сохрани файл");
  const file = ed.document.uri.fsPath;
  const mig = migration(file);
  if (mig) return vscode.commands.executeCommand("ownvim.sql.toggle");
  const dir = path.dirname(file);
  const ext = path.extname(file).slice(1);
  const name = path.basename(file, "." + ext);
  if (!ext) return vscode.window.showWarningMessage("у файла нет расширения — не понять, где его тест");

  const code = codeFor(dir, name, ext);
  const list = code || testsFor(dir, name, ext);
  for (const p of list) if (fs.existsSync(p)) return open(p);
  // код не рядом (tests/ → pkg/calc.py) — ищем по имени в проекте
  if (code) {
    const want = path.basename(list[0]);
    const found = await vscode.workspace.findFiles(new vscode.RelativePattern(root(file), `**/${want}`), "{**/node_modules/**,**/tests/**,**/test/**}", 1);
    if (found[0]) return open(found[0].fsPath);
    return vscode.window.showWarningMessage("не нашёл код для этого теста: " + vscode.workspace.asRelativePath(list[0]));
  }
  // Rust: тесты внутри файла — #[cfg(test)] mod tests
  if (ext === "rs") {
    for (let i = 0; i < ed.document.lineCount; i++) {
      if (/^\s*#\[cfg\(test\)\]/.test(ed.document.lineAt(i).text)) {
        ed.selection = new vscode.Selection(i, 0, i, 0);
        return ed.revealRange(new vscode.Range(i, 0, i, 0), vscode.TextEditorRevealType.InCenter);
      }
    }
  }
  const target = list[0];
  fs.mkdirSync(path.dirname(target), { recursive: true });
  let body = "";
  if (ext === "go") {
    // тот же пакет, что у кода
    const pkg = ed.document.getText().match(/^package\s+(\w+)/m)?.[1] || "main";
    body = `package ${pkg}\n\nimport "testing"\n\n`;
  } else if (ext === "py") {
    const mod = name;
    body = `from ${mod} import *  # noqa: F403\n\n\ndef test_${mod}() -> None:\n    assert True\n`;
  }
  fs.writeFileSync(target, body);
  await open(target);
  vscode.window.setStatusBarMessage("новый тест: " + vscode.workspace.asRelativePath(target), 4000);
}

export function activate(ctx: vscode.ExtensionContext) {
  ctx.subscriptions.push(vscode.commands.registerCommand("ownvim.alternate", toggle));
}
