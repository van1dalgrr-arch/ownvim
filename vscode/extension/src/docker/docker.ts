// Docker прямо в коде (как core/extensions/docker):
//   compose.yaml — справа от каждого сервиса статус: ● работает · здоров · :8080, ○ остановлен (код 1);
//     обновляется сам, пока файл на экране. Над сервисом — up / собрать / restart / stop / логи / shell.
//     ${VAR} без значения в .env и без умолчания — предупреждение; F12 на ${VAR} — к .env (нет — допишет).
//   Dockerfile — справа от RUN / COPY / ADD вес слоя в собранном образе, на FROM — итог и база.
import { execFile } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";
import { readEnv } from "../sql/db";
import * as run from "./run";

process.env.PATH = [path.join(os.homedir(), ".orbstack/bin"), "/opt/homebrew/bin", "/usr/local/bin", process.env.PATH].join(":");

const cfg = () => vscode.workspace.getConfiguration("ownvim.docker");
export const isCompose = (f: string) => /^(docker-)?compose.*\.ya?ml$/.test(path.basename(f));
export const isDockerfile = (f: string) => /^(Dockerfile(\..*)?|.*\.[Dd]ockerfile|Containerfile)$/.test(path.basename(f));

function docker(args: string[], cwd?: string, timeout = 8000): Promise<{ out: string; err: string; code: number }> {
  return new Promise((res) => {
    execFile("docker", args, { cwd, timeout, maxBuffer: 16 << 20 }, (e, out, err) =>
      res({ out: String(out), err: String(err || (e as any)?.message || ""), code: e ? ((e as any).code ?? 1) : 0 }));
  });
}

// ── compose ──────────────────────────────────────────────────────────────────

interface Service { name: string; line: number } // строка — с 0

/** Сервисы файла по отступам: работает и с недописанным YAML */
export function services(doc: vscode.TextDocument): Service[] {
  const out: Service[] = [];
  let inside = false, indent = -1;
  for (let i = 0; i < doc.lineCount; i++) {
    const l = doc.lineAt(i).text;
    if (/^\S/.test(l)) { inside = /^services:\s*(#.*)?$/.test(l); indent = -1; continue; }
    if (!inside || /^\s*(#|$)/.test(l)) continue;
    const m = l.match(/^(\s+)["']?([\w.-]+)["']?:\s*(#.*)?$/);
    const ind = l.match(/^\s*/)![0].length;
    if (indent < 0 && m) indent = ind;
    if (m && ind === indent) out.push({ name: m[2], line: i });
  }
  return out;
}

interface Container { Service: string; State: string; Health?: string; Status?: string; ExitCode?: number; Publishers?: { PublishedPort: number }[] }
interface Status { down: boolean; list: Map<string, Container>; at: number }
const status = new Map<string, Status>();

function jsonLines<T>(s: string): T[] {
  s = s.trim();
  if (!s) return [];
  if (s.startsWith("[")) { try { return JSON.parse(s); } catch { return []; } }
  return s.split("\n").flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
}

async function fetch(dir: string): Promise<Status> {
  const r = await docker(["compose", "ps", "-a", "--format", "json"], dir);
  const st: Status = { down: /Cannot connect|failed to connect|Is the docker daemon/.test(r.err), list: new Map(), at: Date.now() };
  for (const c of jsonLines<Container>(r.out)) {
    const prev = st.list.get(c.Service);
    if (c.Service && (!prev || (prev.State !== "running" && c.State === "running"))) st.list.set(c.Service, c);
  }
  status.set(dir, st);
  return st;
}

const STATE: Record<string, [string, string, string]> = {
  running: ["●", "testing.iconPassed", "работает"], restarting: ["↻", "editorWarning.foreground", "перезапускается"],
  paused: ["⏸", "editorInfo.foreground", "на паузе"], exited: ["○", "errorForeground", "остановлен"],
  created: ["○", "disabledForeground", "создан"], dead: ["✗", "errorForeground", "мёртв"],
};
const HEALTH: Record<string, [string, string]> = { healthy: ["здоров", "testing.iconPassed"], unhealthy: ["нездоров", "errorForeground"], starting: ["проверка…", "editorWarning.foreground"] };

function label(c?: Container): { text: string; color: string } {
  if (!c) return { text: "○ не запущен", color: "disabledForeground" };
  let [icon, color, word] = STATE[c.State] || ["•", "disabledForeground", c.State];
  if (c.State === "exited") {
    let code = c.ExitCode || 0;
    const m = c.Status?.match(/Exited \((\d+)\)/);
    if (m && !code) code = Number(m[1]);
    if (!code) color = "disabledForeground";
    word += ` (код ${code})`;
  }
  let text = `${icon} ${word}`;
  const h = c.Health && HEALTH[c.Health];
  if (h) { text += " · " + h[0]; if (c.State === "running") color = h[1]; }
  const ports = [...new Set((c.Publishers || []).map((p) => p.PublishedPort).filter((p) => p > 0))];
  if (ports.length) text += " · " + ports.map((p) => ":" + p).join(" ");
  return { text, color };
}

const decoTypes = new Map<string, vscode.TextEditorDecorationType>(); // цвет → тип
function deco(color: string) {
  let t = decoTypes.get(color);
  if (!t) {
    t = vscode.window.createTextEditorDecorationType({ after: { color: new vscode.ThemeColor(color), margin: "0 0 0 2em", fontStyle: "italic" } });
    decoTypes.set(color, t);
  }
  return t;
}

function render(ed: vscode.TextEditor) {
  const st = status.get(path.dirname(ed.document.uri.fsPath));
  const by = new Map<string, vscode.DecorationOptions[]>();
  const put = (line: number, text: string, color: string) => {
    const end = ed.document.lineAt(line).range.end;
    by.set(color, [...(by.get(color) || []), { range: new vscode.Range(end, end), renderOptions: { after: { contentText: text } } }]);
  };
  if (st && cfg().get("composeStatus") !== false) {
    const cur = ed.selection.active.line;
    for (const s of services(ed.document)) {
      const l = st.down ? { text: "○ docker не запущен", color: "disabledForeground" } : label(st.list.get(s.name));
      put(s.line, l.text, l.color);
      if (s.line === cur) put(s.line, "⏎ действия", "disabledForeground");
    }
  }
  for (const [color, t] of decoTypes) ed.setDecorations(t, by.get(color) || []);
  for (const [color, list] of by) ed.setDecorations(deco(color), list);
}

// compose-файл проекта (для статус-бара): в корне открытой папки
const COMPOSE = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"];
export function projectCompose(): string | undefined {
  const ws = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!ws) return undefined;
  const f = COMPOSE.find((n) => fs.existsSync(path.join(ws, n)));
  return f && path.join(ws, f);
}

let bar: vscode.StatusBarItem | undefined;

function renderBar() {
  if (!bar) return;
  const file = projectCompose();
  const st = file && status.get(path.dirname(file));
  if (!file || !st || cfg().get("statusBar") === false) return bar.hide();
  const names = fileServices(file);
  if (st.down) {
    bar.text = "$(vm-outline) docker не запущен";
    bar.color = new vscode.ThemeColor("disabledForeground");
  } else {
    const up = names.filter((n) => st.list.get(n)?.State === "running").length;
    const bad = names.some((n) => { const c = st.list.get(n); return c?.Health === "unhealthy" || (c?.State === "exited" && (c.ExitCode || 0) !== 0); });
    bar.text = `$(vm${up ? "-running" : "-outline"}) ${up}/${names.length}`;
    bar.color = bad ? new vscode.ThemeColor("errorForeground") : up ? undefined : new vscode.ThemeColor("disabledForeground");
  }
  const md = new vscode.MarkdownString(names.map((n) => `${label(st.down ? undefined : st.list.get(n)).text} — **${n}**`).join("\n\n"));
  bar.tooltip = md;
  bar.show();
}

async function refresh(force = false) {
  const eds = vscode.window.visibleTextEditors.filter((e) => isCompose(e.document.uri.fsPath));
  const dirs = new Set(eds.map((e) => path.dirname(e.document.uri.fsPath)));
  const proj = projectCompose();
  if (proj) dirs.add(path.dirname(proj));
  const every = Math.max(500, cfg().get<number>("intervalMs") || 3000);
  for (const d of dirs) {
    const st = status.get(d);
    // compose-файла на экране нет — для статус-бара хватает раза в 10 с
    const shown = eds.some((e) => path.dirname(e.document.uri.fsPath) === d);
    if (force || !st || Date.now() - st.at >= (shown ? every : Math.max(every, 10_000))) await fetch(d);
  }
  for (const e of eds) render(e);
  renderBar();
}

// длинное (сборка, логи, shell) — в терминале
function terminal(cwd: string, cmd: string, name = "docker") {
  const t = vscode.window.terminals.find((x) => x.name === name) || vscode.window.createTerminal({ name, cwd });
  t.show();
  t.sendText(`cd '${cwd}' && ${cmd}`);
  setTimeout(() => refresh(true), 1500);
}

// короткое (up, restart, stop) — тихо, с уведомлением, как в ownvim
async function quiet(cwd: string, args: string[], title: string) {
  await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: title + "…" }, async () => {
    const r = await docker(args, cwd, 180_000);
    if (r.code !== 0) vscode.window.showErrorMessage(`${title} — ошибка: ${(r.err || r.out).trim().split("\n").slice(-6).join("\n")}`);
    else vscode.window.setStatusBarMessage(`$(check) ${title} — готово`, 3000);
  });
  await refresh(true);
}

/** Сервисы compose-файла с диска (или из открытого документа) */
function fileServices(file: string): string[] {
  const doc = vscode.workspace.textDocuments.find((d) => d.uri.fsPath === file);
  if (doc) return services(doc).map((s) => s.name);
  let lines: string[];
  try { lines = fs.readFileSync(file, "utf8").split("\n"); } catch { return []; }
  const fake = { lineCount: lines.length, lineAt: (i: number) => ({ text: lines[i] }) } as unknown as vscode.TextDocument;
  return services(fake).map((s) => s.name);
}

/** Меню сервиса; без аргументов — сервис под курсором в compose-файле, иначе выбрать из compose проекта */
export async function serviceMenu(file?: string, service?: string) {
  const ed = vscode.window.activeTextEditor;
  if (!file && ed && isCompose(ed.document.uri.fsPath)) {
    file = ed.document.uri.fsPath;
    service ??= [...services(ed.document)].reverse().find((s) => s.line <= ed.selection.active.line)?.name;
  }
  file ??= projectCompose();
  if (!file) return vscode.window.showInformationMessage("compose-файла в проекте нет");
  const dir = path.dirname(file), f = ["-f", path.basename(file)];
  if (!status.get(dir)) await fetch(dir);
  if (!service) {
    const st = status.get(dir)!;
    const pick = await vscode.window.showQuickPick(fileServices(file).map((n) => ({ label: n, description: label(st.down ? undefined : st.list.get(n)).text })),
      { title: "Сервис · " + path.basename(file) });
    if (!pick) return;
    service = pick.label;
  }
  const s = service;
  const st = status.get(dir)?.list.get(s);
  const running = st?.State === "running";
  const ff = `-f '${path.basename(file)}'`;
  const items: { label: string; run: () => unknown }[] = [
    { label: `$(play) up`, run: () => quiet(dir, ["compose", ...f, "up", "-d", s], `${s}: up`) },
    { label: "$(package) собрать и up", run: () => terminal(dir, `docker compose ${ff} up -d --build ${s}`) },
    ...(running ? [
      { label: "$(debug-restart) restart", run: () => quiet(dir, ["compose", ...f, "restart", s], `${s}: restart`) },
      { label: "$(debug-stop) stop", run: () => quiet(dir, ["compose", ...f, "stop", s], `${s}: stop`) },
      { label: "$(terminal) shell", run: () => terminal(dir, `docker compose ${ff} exec ${s} sh -c 'command -v bash >/dev/null && exec bash || exec sh'`, "shell " + s) },
    ] : []),
    { label: "$(output) логи", run: () => terminal(dir, `docker compose ${ff} logs -f --tail 200 ${s}`, "логи " + s) },
    { label: "$(layers) up — все сервисы", run: () => quiet(dir, ["compose", ...f, "up", "-d"], "compose up") },
    { label: "$(circle-slash) down — все", run: () => quiet(dir, ["compose", ...f, "down"], "compose down") },
  ];
  const pick = await vscode.window.showQuickPick(items, { title: `${s} · ${label(st).text}` });
  pick?.run();
}

/** Enter в обычном режиме: на сервисе compose — меню, иначе как в Vim — на строку ниже, к первому символу */
export async function enter() {
  const ed = vscode.window.activeTextEditor;
  if (ed && isCompose(ed.document.uri.fsPath)) {
    const line = ed.selection.active.line;
    const s = services(ed.document).find((x) => x.line === line);
    if (s) return serviceMenu(ed.document.uri.fsPath, s.name);
  }
  if (!ed) return;
  const n = Math.min(ed.selection.active.line + 1, ed.document.lineCount - 1);
  const c = ed.document.lineAt(n).firstNonWhitespaceCharacterIndex;
  ed.selection = new vscode.Selection(n, c, n, c);
  ed.revealRange(ed.selection);
}

/** alt-o: все контейнеры (docker ps -a) — логи, shell, restart, stop, удалить */
export async function containers() {
  const r = await docker(["ps", "-a", "--format", "json"]);
  if (r.code !== 0) return vscode.window.showWarningMessage("docker не отвечает: " + r.err.trim().split("\n")[0]);
  type Ps = { ID: string; Names: string; Image: string; State: string; Status: string; Ports: string; Labels?: string };
  const list = jsonLines<Ps>(r.out);
  const proj = (c: Ps) => c.Labels?.match(/com\.docker\.compose\.project=([^,]+)/)?.[1] || "";
  list.sort((a, b) => proj(a).localeCompare(proj(b)) || a.Names.localeCompare(b.Names));
  const pick = await vscode.window.showQuickPick(list.map((c) => ({
    label: `${c.State === "running" ? "$(circle-filled)" : "$(circle-outline)"} ${c.Names}`,
    description: `${proj(c) ? proj(c) + " · " : ""}${c.Image}`, detail: `${c.Status}${c.Ports ? " · " + c.Ports.replace(/0\.0\.0\.0:|\[::\]:/g, "").split(", ").filter((p, i, a) => a.indexOf(p) === i).join(", ") : ""}`, c,
  })), { title: "Контейнеры", matchOnDescription: true, matchOnDetail: true });
  if (!pick) return;
  const c = pick.c, on = c.State === "running";
  const acts: { label: string; run: () => unknown }[] = [
    { label: "$(output) логи", run: () => terminal(os.homedir(), `docker logs -f --tail 200 ${c.Names}`, "логи " + c.Names) },
    ...(on ? [
      { label: "$(terminal) shell", run: () => terminal(os.homedir(), `docker exec -it ${c.Names} sh -c 'command -v bash >/dev/null && exec bash || exec sh'`, "shell " + c.Names) },
      { label: "$(debug-restart) restart", run: () => quiet(os.homedir(), ["restart", c.ID], `${c.Names}: restart`) },
      { label: "$(debug-stop) stop", run: () => quiet(os.homedir(), ["stop", c.ID], `${c.Names}: stop`) },
    ] : [{ label: "$(play) start", run: () => quiet(os.homedir(), ["start", c.ID], `${c.Names}: start`) }]),
    { label: "$(info) inspect", run: async () => {
      const i = await docker(["inspect", c.ID]);
      vscode.window.showTextDocument(await vscode.workspace.openTextDocument({ language: "json", content: i.out }));
    } },
    { label: "$(trash) удалить", run: async () => {
      if (await vscode.window.showWarningMessage(`Удалить контейнер ${c.Names}?`, { modal: true }, "Удалить")) quiet(os.homedir(), ["rm", "-f", c.ID], `${c.Names}: удалить`);
    } },
  ];
  (await vscode.window.showQuickPick(acts, { title: `${c.Names} · ${c.Status}` }))?.run();
}

// ── ${VAR} и .env ────────────────────────────────────────────────────────────

const VAR = /\$\{(\w+)(:?[-?+][^}]*)?\}|\$(\w+)/g;

function envFor(file: string) {
  const dir = path.dirname(file);
  return { path: path.join(dir, ".env"), vars: readEnv(path.join(dir, ".env")) };
}

function checkEnv(doc: vscode.TextDocument, diags: vscode.DiagnosticCollection) {
  if (!isCompose(doc.uri.fsPath) || cfg().get("envCheck") === false) return diags.delete(doc.uri);
  const env = envFor(doc.uri.fsPath).vars;
  const out: vscode.Diagnostic[] = [];
  for (let i = 0; i < doc.lineCount; i++) {
    const l = doc.lineAt(i).text;
    if (/^\s*#/.test(l)) continue;
    for (const m of l.matchAll(VAR)) {
      const name = m[1] || m[3];
      if (l[m.index! - 1] === "$" || m[2] || name in env || name in process.env) continue;
      const d = new vscode.Diagnostic(new vscode.Range(i, m.index!, i, m.index! + m[0].length),
        `${name} нет в .env и нет умолчания (\${${name}:-…}) — compose подставит пустую строку`, vscode.DiagnosticSeverity.Warning);
      d.source = "ownvim";
      out.push(d);
    }
  }
  diags.set(doc.uri, out);
}

class EnvDefinition implements vscode.DefinitionProvider {
  async provideDefinition(doc: vscode.TextDocument, pos: vscode.Position) {
    const r = doc.getWordRangeAtPosition(pos, /\$\{?\w+[^}\s]*\}?/);
    const name = r && doc.getText(r).match(/\$\{?(\w+)/)?.[1];
    if (!name) return undefined;
    const env = envFor(doc.uri.fsPath);
    let text = fs.existsSync(env.path) ? fs.readFileSync(env.path, "utf8") : "";
    let line = text.split("\n").findIndex((l) => new RegExp(`^\\s*(export\\s+)?${name}\\s*=`).test(l));
    if (line < 0) {
      if (text && !text.endsWith("\n")) text += "\n";
      text += `${name}=\n`;
      fs.writeFileSync(env.path, text);
      line = text.split("\n").length - 2;
    }
    return new vscode.Location(vscode.Uri.file(env.path), new vscode.Position(line, name.length + 1));
  }
}

// ── Dockerfile: вес слоёв ────────────────────────────────────────────────────

interface Instr { kw: string; args: string; line: number }
const norm = (s: string) => s.replace(/\s+/g, " ").trim();

function lastStage(doc: vscode.TextDocument): Instr[] {
  const all: Instr[] = [];
  for (let i = 0; i < doc.lineCount; i++) {
    const l = doc.lineAt(i).text;
    if (/^\s*#/.test(l)) continue;
    const m = l.match(/^\s*([A-Za-z]+)\s+(.*)$/);
    if (!m) continue;
    const start = i;
    let text = m[2];
    while (/\\\s*$/.test(text) && i + 1 < doc.lineCount) {
      i++;
      text = text.replace(/\\\s*$/, " ");
      if (!/^\s*#/.test(doc.lineAt(i).text)) text += doc.lineAt(i).text;
    }
    all.push({ kw: m[1].toUpperCase(), args: norm(text), line: start });
  }
  let from = 0;
  all.forEach((x, k) => { if (x.kw === "FROM") from = k; });
  return all.slice(from);
}

function historyStep(created: string): [string, string] {
  let s = norm(created).replace(/ # buildkit$/, "").replace(/^\/bin\/sh -c #\(nop\) /, "");
  const m = s.match(/^([A-Z]+)\s*(.*)$/);
  if (!m) return ["RUN", s];
  let rest = m[2];
  if (m[1] === "RUN") rest = rest.replace(/^\|\d+ .*?\/bin\/sh -c /, "").replace(/^\/bin\/sh -c /, "");
  return [m[1], rest];
}

function matches(i: Instr, kw: string, text: string) {
  if (i.kw !== kw) return false;
  if (kw !== "RUN") return true;
  const a = norm(i.args.replace(/--(mount|network)=\S+/g, ""));
  const n = Math.min(30, a.length, text.length);
  return n === 0 || a.slice(0, n) === text.slice(0, n) || text.includes(a.slice(0, n));
}

export function human(b: number) {
  const u = ["B", "kB", "MB", "GB"];
  let n = b, i = 0;
  while (n >= 1000 && i < u.length - 1) { n /= 1000; i++; }
  return i === 0 ? `${b} B` : n < 10 ? `${n.toFixed(1)} ${u[i]}` : `${Math.round(n)} ${u[i]}`;
}
const sizeColor = (b: number) => b >= 500e6 ? "errorForeground" : b >= 100e6 ? "editorWarning.foreground" : b >= 10e6 ? "editorInfo.foreground" : "disabledForeground";

const chosen = new Map<string, string>(); // Dockerfile → образ

async function guessImage(file: string): Promise<string | undefined> {
  if (chosen.has(file)) return chosen.get(file);
  const root = vscode.workspace.getWorkspaceFolder(vscode.Uri.file(file))?.uri.fsPath || path.dirname(file);
  const project = path.basename(root).toLowerCase().replace(/[^a-z0-9_-]/g, "");
  const r = await docker(["images", "--format", "json"]);
  const names = jsonLines<{ Repository: string; Tag: string }>(r.out).filter((i) => i.Repository && i.Repository !== "<none>").map((i) => `${i.Repository}:${i.Tag}`);
  return names.find((n) => n === project + ":dev") || names.find((n) => n.startsWith(project + "-") || n.startsWith(project + ":"));
}

async function layers(ed: vscode.TextEditor) {
  const file = ed.document.uri.fsPath;
  for (const t of decoTypes.values()) ed.setDecorations(t, []);
  if (cfg().get("layers") === false) return;
  const image = await guessImage(file);
  if (!image) return;
  const r = await docker(["history", "--no-trunc", "--human=false", "--format", "json", image]);
  const hist = jsonLines<{ CreatedBy: string; Size: number | string }>(r.out);
  const ins = lastStage(ed.document);
  const bytes = (x: { Size: number | string }) => Number(x.Size) || 0;
  let j = 0, matched = 0, total = 0;
  const by = new Map<string, vscode.DecorationOptions[]>();
  const put = (line: number, text: string, color: string) => {
    const end = ed.document.lineAt(line).range.end;
    by.set(color, [...(by.get(color) || []), { range: new vscode.Range(end, end), renderOptions: { after: { contentText: text } } }]);
  };
  for (let k = ins.length - 1; k >= 1; k--) {
    for (let look = j; look < Math.min(j + 5, hist.length); look++) {
      const [kw, text] = historyStep(hist[look].CreatedBy);
      if (matches(ins[k], kw, text)) {
        const b = bytes(hist[look]);
        total += b; matched++;
        if (b > 0) put(ins[k].line, human(b), sizeColor(b));
        j = look + 1;
        break;
      }
    }
  }
  if (!matched || !ins.length) return;
  let base = 0;
  for (let k = j; k < hist.length; k++) base += bytes(hist[k]);
  put(ins[0].line, `${image} · ${human(total + base)} (база ${human(base)})`, "disabledForeground");
  for (const [color, list] of by) ed.setDecorations(deco(color), list);
}

export async function pickImage() {
  const ed = vscode.window.activeTextEditor;
  if (!ed || !isDockerfile(ed.document.uri.fsPath)) return vscode.window.showInformationMessage("Открой Dockerfile");
  const r = await docker(["images", "--format", "json"]);
  const names = jsonLines<{ Repository: string; Tag: string; Size: string }>(r.out).filter((i) => i.Repository !== "<none>")
    .map((i) => ({ label: `${i.Repository}:${i.Tag}`, description: i.Size }));
  const pick = await vscode.window.showQuickPick(names, { title: "Образ, вес слоёв которого показывать" });
  if (!pick) return;
  chosen.set(ed.document.uri.fsPath, pick.label);
  layers(ed);
}

// ── подключение ─────────────────────────────────────────────────────────────

export function activate(ctx: vscode.ExtensionContext) {
  run.activate(ctx);
  bar = vscode.window.createStatusBarItem("ownvim.docker", vscode.StatusBarAlignment.Left, 50);
  bar.name = "Docker: сервисы проекта";
  bar.command = "ownvim.docker.service";
  ctx.subscriptions.push(bar);
  const diags = vscode.languages.createDiagnosticCollection("ownvim.docker");
  const composeSel = [{ pattern: "**/{compose,docker-compose}*.{yml,yaml}" }];
  ctx.subscriptions.push(
    diags,
    vscode.languages.registerDefinitionProvider(composeSel, new EnvDefinition()),
    vscode.commands.registerCommand("ownvim.docker.service", serviceMenu),
    vscode.commands.registerCommand("ownvim.docker.enter", enter),
    vscode.commands.registerCommand("ownvim.docker.containers", containers),
    vscode.window.onDidChangeTextEditorSelection((e) => { if (isCompose(e.textEditor.document.uri.fsPath)) render(e.textEditor); }),
    vscode.commands.registerCommand("ownvim.docker.layers", pickImage),
    vscode.window.onDidChangeVisibleTextEditors((eds) => {
      refresh();
      for (const e of eds) if (isDockerfile(e.document.uri.fsPath)) layers(e);
    }),
    vscode.workspace.onDidOpenTextDocument((d) => checkEnv(d, diags)),
    vscode.workspace.onDidChangeTextDocument((e) => {
      checkEnv(e.document, diags);
      for (const ed of vscode.window.visibleTextEditors) if (ed.document === e.document && isCompose(ed.document.uri.fsPath)) render(ed);
    }),
    vscode.workspace.onDidSaveTextDocument((d) => {
      if (isCompose(d.uri.fsPath)) refresh(true);
      for (const e of vscode.window.visibleTextEditors) if (e.document === d && isDockerfile(d.uri.fsPath)) layers(e);
    }),
    vscode.window.onDidChangeWindowState((s) => s.focused && refresh(true)),
  );
  for (const d of vscode.workspace.textDocuments) checkEnv(d, diags);
  for (const e of vscode.window.visibleTextEditors) if (isDockerfile(e.document.uri.fsPath)) layers(e);
  const timer = setInterval(() => { if (vscode.window.state.focused) refresh(); }, 1000);
  ctx.subscriptions.push({ dispose: () => clearInterval(timer) });
  refresh(true);
}
