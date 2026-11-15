// Ревью от Claude прямо в коде (lua/own/tools/review.lua): пробел a R — Claude читает diff ветки против main
// (и незакоммиченное), замечания встают на свои строки, как ошибки линтера (Error Lens — плашкой справа),
// и списком — в «Проблемах». Пока Claude думает, работать можно дальше. Убрать — пробел a X.
import * as path from "path";
import * as vscode from "vscode";
import { root, run } from "./core";

const prompt = `Ты — внимательный ревьюер кода. Ниже diff ветки. Найди настоящие проблемы: баги, гонки, утечки
горутин и ресурсов, необработанные ошибки, проблемы безопасности, неверную логику, пропущенные
проверки. Стиль и мелочи — только если они реально мешают. Не хвали и не пересказывай diff.

Ответ — только строки такого вида, по одной на замечание, не больше 15:
путь/к/файлу.go:НОМЕР_СТРОКИ: error|warn|info: коротко, что не так и как исправить
Номер строки — в НОВОЙ версии файла (после изменений). Если проблем нет — одна строка: NONE`;

const sev: Record<string, vscode.DiagnosticSeverity> = { error: vscode.DiagnosticSeverity.Error, warn: vscode.DiagnosticSeverity.Warning, info: vscode.DiagnosticSeverity.Information };

export function parse(stdout: string, dir: string) {
  const out: { file: string; line: number; level: string; msg: string }[] = [];
  for (const l of stdout.split("\n")) {
    const m = l.match(/^\s*`?([^:`]+):(\d+):\s*([a-z]+):\s*(.+)$/i);
    if (m && m[3].toLowerCase() in sev) out.push({ file: path.join(dir, m[1]), line: +m[2], level: m[3].toLowerCase(), msg: m[4] });
  }
  return out;
}

async function git(dir: string, args: string[]) {
  const r = await run("git", ["-C", dir, ...args]);
  return r.code === 0 ? r.out.trim() : "";
}

export function activate(ctx: vscode.ExtensionContext) {
  const diags = vscode.languages.createDiagnosticCollection("claude");
  ctx.subscriptions.push(
    diags,
    vscode.commands.registerCommand("ownvim.review.clear", () => diags.clear()),
    vscode.commands.registerCommand("ownvim.review", async () => {
      const top = await git(root(), ["rev-parse", "--show-toplevel"]);
      if (!top) return vscode.window.showWarningMessage("ревью: не git-репозиторий");
      let base = (await git(top, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])) || "main";
      const mb = await git(top, ["merge-base", base, "HEAD"]);
      const diff = await git(top, ["diff", mb || base]);
      if (!diff) return vscode.window.showWarningMessage("нет изменений относительно " + base);
      const r = await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: `Claude смотрит diff против ${base}…`, cancellable: false },
        () => run("claude", ["-p", prompt], { cwd: top, input: diff.slice(0, 150000), timeout: 600000 }));
      if (r.code !== 0) return vscode.window.showErrorMessage("claude: " + (r.err || "не запустился — нужен Claude Code (команда claude)"));
      diags.clear();
      const items = parse(r.out, top);
      if (!items.length) {
        return /NONE/.test(r.out) ? vscode.window.showInformationMessage("Claude проблем не нашёл ✓") : vscode.window.showWarningMessage("не понял ответ Claude:\n" + r.out.slice(0, 500));
      }
      const by = new Map<string, vscode.Diagnostic[]>();
      for (const it of items) {
        const d = new vscode.Diagnostic(new vscode.Range(it.line - 1, 0, it.line - 1, 1000), it.msg, sev[it.level]);
        d.source = "claude";
        by.set(it.file, [...(by.get(it.file) || []), d]);
      }
      for (const [f, ds] of by) diags.set(vscode.Uri.file(f), ds);
      vscode.commands.executeCommand("workbench.actions.view.problems");
      vscode.window.showWarningMessage(`ревью: замечаний ${items.length} — на строках в коде и в «Проблемах»; убрать — пробел a X`);
    }),
  );
}
