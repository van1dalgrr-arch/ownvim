// Связь с ownvim: Go-ядро (ownvimd) и общие настройки (settings.jsonc + defaults.jsonc).
//   ownvimd собирается сам из core/ репозитория в папку расширения — нужен go; сборка заново, когда core/ новее.
//   Настройки — те же, что у nvim: ownvimd settings load (кэш ~/.local/share/ownvim/own-settings.cache.json),
//   поэтому задачи, свои команды и музыка в статусе берутся из одного места.
import * as cp from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";

/** корень репозитория ownvim: расширение лежит в vscode/extension */
export const repo = path.resolve(__dirname, "..", "..", "..");
export const data = path.join(os.homedir(), ".local", "share", "ownvim");

let storage = "";
export function init(ctx: vscode.ExtensionContext) {
  storage = ctx.globalStorageUri.fsPath;
}

/** корень проекта: папка с .git / go.mod / package.json / pyproject.toml над файлом, иначе папка окна */
export function root(file?: string): string {
  const ws = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || "";
  file = file ?? vscode.window.activeTextEditor?.document.uri.fsPath;
  if (!file) return ws;
  let d = path.dirname(file);
  for (let i = 0; i < 12; i++) {
    for (const m of [".git", "go.mod", "package.json", "pyproject.toml", "Cargo.toml"]) if (fs.existsSync(path.join(d, m))) return d;
    const up = path.dirname(d);
    if (up === d || d === ws) break;
    d = up;
  }
  return ws || path.dirname(file);
}

function newest(dir: string): number {
  let t = 0;
  const walk = (d: string) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".go") || e.name === "go.mod") t = Math.max(t, fs.statSync(p).mtimeMs);
    }
  };
  try { walk(dir); } catch { /* нет core/ */ }
  return t;
}

let building: Promise<string> | undefined;
/** путь к ownvimd (собирается при первом вызове и когда core/ поменялся) */
export function ownvimd(): Promise<string> {
  if (building) return building;
  building = new Promise<string>((resolve, reject) => {
    const bin = path.join(storage || os.tmpdir(), "ownvimd");
    const core = path.join(repo, "core");
    let have = 0;
    try { have = fs.statSync(bin).mtimeMs; } catch { /* нет */ }
    if (have && have >= newest(core)) return resolve(bin);
    fs.mkdirSync(path.dirname(bin), { recursive: true });
    vscode.window.setStatusBarMessage("$(sync~spin) ownvim: собираю ownvimd…", 10000);
    cp.execFile("go", ["build", "-trimpath", "-o", bin, "./cmd/ownvimd"], { cwd: core, env: { ...process.env, PATH: pathEnv() } }, (err, _o, e) => {
      if (err) reject(new Error("go build ownvimd: " + (e || err.message)));
      else resolve(bin);
    });
  }).finally(() => { building = undefined; });
  return building;
}

/** PATH с brew и go — у приложения из Launchpad он короткий */
export function pathEnv(): string {
  const extra = ["/opt/homebrew/bin", "/usr/local/bin", path.join(os.homedir(), "go", "bin"), path.join(os.homedir(), ".local", "bin")];
  return [...new Set([...(process.env.PATH || "").split(":"), ...extra])].filter(Boolean).join(":");
}

export function run(cmd: string, args: string[], opts: { cwd?: string; input?: string; env?: Record<string, string>; timeout?: number } = {}): Promise<{ code: number; out: string; err: string }> {
  return new Promise((resolve) => {
    const p = cp.spawn(cmd, args, { cwd: opts.cwd, env: { ...process.env, PATH: pathEnv(), ...opts.env } });
    let out = "", err = "";
    const timer = opts.timeout ? setTimeout(() => p.kill(), opts.timeout) : undefined;
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    p.on("error", (e) => { clearTimeout(timer); resolve({ code: -1, out, err: e.message }); });
    p.on("close", (code) => { clearTimeout(timer); resolve({ code: code ?? -1, out, err }); });
    if (opts.input !== undefined) p.stdin.end(opts.input);
    else p.stdin.end();
  });
}

// ── настройки ownvim ─────────────────────────────────────────────────────────

let cached: { at: number; s: any } | undefined;
/** собранные настройки ownvim (defaults + settings.jsonc + extensions/*.jsonc); {} — если не вышло */
export async function settings(): Promise<any> {
  if (cached && Date.now() - cached.at < 5000) return cached.s;
  let s: any;
  try {
    const bin = await ownvimd();
    const r = await run(bin, ["settings", "load", "--config", repo, "--data", data], { timeout: 10000 });
    s = JSON.parse(r.out).settings;
  } catch {
    try { s = JSON.parse(fs.readFileSync(path.join(data, "own-settings.cache.json"), "utf8")).settings; } catch { s = {}; }
  }
  cached = { at: Date.now(), s: s || {} };
  return cached.s;
}

/** .env → переменные: KEY=value, export KEY=value, кавычки снимаются, # — комментарий */
export function readEnv(file: string): Record<string, string> {
  const out: Record<string, string> = {};
  let text = "";
  try { text = fs.readFileSync(file, "utf8"); } catch { return out; }
  for (const l of text.split("\n")) {
    const m = l.match(/^\s*(?:export\s+)?(\w+)\s*=\s*(.*?)\s*$/);
    if (!m) continue;
    let v = m[2];
    const q = v[0];
    if ((q === '"' || q === "'") && v.endsWith(q) && v.length > 1) v = v.slice(1, -1);
    else v = v.replace(/\s+#.*$/, "");
    out[m[1]] = v;
  }
  return out;
}
