// ownvim в VS Code: то, чего нет в готовых расширениях, — миграции и схема SQL, база проекта,
// Docker прямо в коде, ▶ у main и тестов (Go, Python, JS/TS), тест ↔ код, эндпоинты, задачи и команды
// из settings.jsonc, тесты Go в фоне, ревью Claude, заметки, скриншот, музыка и отдых в статусе. Остальное (gopls, отладка, тесты) — у расширений из extensions.txt.
import * as path from "path";
import * as vscode from "vscode";
import * as migrations from "./sql/migrations";
import * as complete from "./sql/complete";
import * as checks from "./sql/checks";
import * as query from "./sql/query";
import * as dockerExt from "./docker/docker";
import * as goExt from "./go/go";
import * as autosave from "./autosave";
import * as dial from "./dial";
import * as core from "./core";
import * as run from "./run";
import * as alternate from "./alternate";
import * as endpoints from "./endpoints";
import * as tasks from "./tasks";
import * as autotest from "./go/autotest";
import * as review from "./review";
import * as notes from "./notes";
import * as status from "./status";

const SQL: vscode.DocumentSelector = [{ language: "sql" }, { language: "postgres" }, { pattern: "**/*.sql" }];

export function activate(ctx: vscode.ExtensionContext) {
  const diags = vscode.languages.createDiagnosticCollection("ownvim.sql");
  const mark = vscode.window.createTextEditorDecorationType({ after: { margin: "0 0 0 2em", fontStyle: "italic" } });
  const lint = (d: vscode.TextDocument) => { if (d.uri.fsPath.endsWith(".sql")) diags.set(d.uri, checks.check(d)); };

  // ✓ / ○ / ✗ в первой строке миграции
  const paint = (ed: vscode.TextEditor) => {
    const f = ed.document.uri.fsPath;
    if (!migrations.isMigration(f) || vscode.workspace.getConfiguration("ownvim.sql").get("status") === false) return ed.setDecorations(mark, []);
    const m = migrations.markOf(f);
    if (!m) return ed.setDecorations(mark, []);
    const end = ed.document.lineAt(0).range.end;
    ed.setDecorations(mark, [{ range: new vscode.Range(end, end), renderOptions: { after: { contentText: m.text, color: new vscode.ThemeColor(m.color) } } }]);
  };
  const touch = (ed?: vscode.TextEditor) => {
    if (!ed) return;
    const f = ed.document.uri.fsPath;
    if (!migrations.isMigration(f)) return;
    paint(ed);
    migrations.refresh(path.dirname(f));
  };

  ctx.subscriptions.push(
    diags,
    vscode.languages.registerCompletionItemProvider(SQL, { provideCompletionItems: (d, p) => complete.complete(d, p) }, ".", "(", "'", ":", " "),
    vscode.languages.registerHoverProvider(SQL, { provideHover: (d, p) => complete.hover(d, p) }),
    vscode.languages.registerDefinitionProvider(SQL, { provideDefinition: (d, p) => complete.definition(d, p) }),
    vscode.commands.registerCommand("ownvim.sql.migrations", migrations.menu),
    vscode.commands.registerCommand("ownvim.sql.new", (name?: string) => migrations.create(typeof name === "string" ? name : undefined)),
    vscode.commands.registerCommand("ownvim.sql.up", migrations.up),
    vscode.commands.registerCommand("ownvim.sql.down", migrations.down),
    vscode.commands.registerCommand("ownvim.sql.redo", migrations.redo),
    vscode.commands.registerCommand("ownvim.sql.status", migrations.showStatus),
    vscode.commands.registerCommand("ownvim.sql.toggle", migrations.toggle),
    vscode.commands.registerCommand("ownvim.sql.run", query.run),
    vscode.commands.registerCommand("ownvim.sql.db", query.info),
    vscode.workspace.onDidSaveTextDocument((d) => {
      const f = d.uri.fsPath;
      if (f.endsWith(".sql") && !f.endsWith(".down.sql") && (f.endsWith(".up.sql") || migrations.dir(f) === path.dirname(f))) migrations.writeDown(d);
      lint(d);
    }),
    vscode.workspace.onDidOpenTextDocument(lint),
    vscode.workspace.onDidChangeTextDocument((e) => lint(e.document)),
    vscode.workspace.onDidCloseTextDocument((d) => diags.delete(d.uri)),
    vscode.window.onDidChangeActiveTextEditor(touch),
    migrations.onStatus((dir) => { for (const e of vscode.window.visibleTextEditors) if (path.dirname(e.document.uri.fsPath) === dir) paint(e); }),
  );
  for (const d of vscode.workspace.textDocuments) lint(d);
  touch(vscode.window.activeTextEditor);

  core.init(ctx);
  dockerExt.activate(ctx);
  goExt.activate(ctx);
  autosave.activate(ctx);
  dial.activate(ctx);
  run.activate(ctx);
  alternate.activate(ctx);
  endpoints.activate(ctx);
  tasks.activate(ctx);
  autotest.activate(ctx);
  review.activate(ctx);
  notes.activate(ctx);
  status.activate(ctx);
}

export function deactivate() {}
