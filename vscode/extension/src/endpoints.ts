// Эндпоинты, как окно Endpoints в GoLand (core/extensions/endpoints): все маршруты Gin проекта с полным путём.
//   пробел r e (alt-a) — список с поиском: enter — к хендлеру, ▷ справа — отправить запрос на запущенный API
//     (ответ — JSON справа; access_token из ответа запоминается для следующих запросов), ⧉ — скопировать curl.
//   пробел r h — api.http проекта из маршрутов (REST Client: «Send Request» над запросом; готовый не перезаписывается).
// Маршруты — настоящим разбором Go-кода (go/ast, ownvimd routes): группы по цепочке и группы, переданные в функции.
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { ownvimd, root, run } from "./core";

type Route = { Method: string; Path: string; Handler: string; File: string; Line: number; Col: number };

let token = "";
const icon: Record<string, string> = { GET: "🟢", POST: "🟡", PUT: "🔵", PATCH: "🔵", DELETE: "🔴" };

export const examplePath = (p: string) => ("/" + p.split("/").map((s) => s.startsWith(":") ? "1" : s.startsWith("*") ? "" : s).filter(Boolean).join("/")).replace(/\/+/g, "/");
const method = (r: Route) => (r.Method === "ANY" || r.Method === "Any" ? "GET" : r.Method);

async function collect(dir: string): Promise<{ port: string; routes: Route[] } | undefined> {
  try {
    const bin = await ownvimd();
    const r = await run(bin, ["routes", dir], { timeout: 30000 });
    if (r.code !== 0) throw new Error(r.err);
    const v = JSON.parse(r.out);
    for (const x of v.routes as Route[]) x.File = path.resolve(dir, x.File);
    return v;
  } catch (e: any) {
    vscode.window.showErrorMessage("эндпоинты: " + e.message);
  }
}

function tokenOf(v: any): string {
  if (!v || typeof v !== "object") return "";
  for (const k of ["access_token", "accessToken", "token"]) if (typeof v[k] === "string" && v[k]) return v[k];
  return tokenOf(v.data);
}

async function send(ctx: vscode.ExtensionContext, r: Route, port: string) {
  const m = method(r);
  let body: string | undefined;
  if (["POST", "PUT", "PATCH"].includes(m)) {
    const key = "body:" + m + r.Path;
    body = await vscode.window.showInputBox({ title: `${m} ${r.Path}`, prompt: "тело JSON", value: ctx.workspaceState.get<string>(key) || "{}" });
    if (body === undefined) return;
    await ctx.workspaceState.update(key, body);
  }
  const url = `http://localhost:${port}${examplePath(r.Path)}`;
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = "Bearer " + token;
  if (body) headers["Content-Type"] = "application/json";
  const t0 = Date.now();
  let res: Response;
  try {
    res = await fetch(url, { method: m, headers, body });
  } catch (e: any) {
    return vscode.window.showErrorMessage(`${url}: ${e.cause?.code || e.message} — API запущен? пробел r r`);
  }
  const text = await res.text();
  let pretty = text;
  try {
    const json = JSON.parse(text);
    pretty = JSON.stringify(json, null, 2);
    const t = tokenOf(json);
    if (t) { token = t; vscode.window.setStatusBarMessage("токен запомнен для следующих запросов", 4000); }
  } catch { /* не JSON */ }
  const head = `// ${m} ${examplePath(r.Path)} → ${res.status} ${res.statusText} · ${Date.now() - t0} мс\n`;
  const doc = await vscode.workspace.openTextDocument({ language: "jsonc", content: head + pretty });
  await vscode.window.showTextDocument(doc, { viewColumn: vscode.ViewColumn.Beside, preview: true, preserveFocus: true });
}

export async function pick(ctx: vscode.ExtensionContext) {
  const dir = root();
  const v = await vscode.window.withProgress({ location: vscode.ProgressLocation.Window, title: "эндпоинты…" }, () => collect(dir));
  if (!v) return;
  if (!v.routes.length) return vscode.window.showWarningMessage("маршрутов Gin не нашёл в " + dir);
  const sendBtn = { iconPath: new vscode.ThemeIcon("play"), tooltip: "отправить запрос" };
  const curlBtn = { iconPath: new vscode.ThemeIcon("copy"), tooltip: "скопировать curl" };
  type Item = vscode.QuickPickItem & { r: Route };
  const qp = vscode.window.createQuickPick<Item>();
  qp.title = `Эндпоинты · :${v.port} · enter — хендлер · ▷ — запрос · ⧉ — curl`;
  qp.matchOnDescription = true;
  qp.items = v.routes.map((r) => ({
    label: `${icon[r.Method] || "⚪"} ${r.Method.padEnd(6)} ${r.Path}`,
    description: "→ " + r.Handler,
    detail: `${vscode.workspace.asRelativePath(r.File)}:${r.Line}`,
    buttons: [sendBtn, curlBtn], r,
  }));
  qp.onDidTriggerItemButton(async (e) => {
    const r = e.item.r;
    if (e.button === curlBtn) {
      await vscode.env.clipboard.writeText(`curl -s -X ${method(r)} localhost:${v.port}${examplePath(r.Path)} | jq .`);
      vscode.window.setStatusBarMessage("curl скопирован", 3000);
    } else { qp.hide(); await send(ctx, r, v.port); }
  });
  qp.onDidAccept(async () => {
    const r = qp.selectedItems[0]?.r;
    qp.hide();
    if (!r) return;
    const ed = await vscode.window.showTextDocument(vscode.Uri.file(r.File));
    const pos = new vscode.Position(r.Line - 1, r.Col - 1);
    ed.selection = new vscode.Selection(pos, pos);
    ed.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.InCenter);
  });
  qp.onDidHide(() => qp.dispose());
  qp.show();
}

/** api.http: логин получает имя login, остальные берут его access_token в Authorization */
export async function apiHttp() {
  const dir = root();
  const dest = path.join(dir, "api.http");
  if (fs.existsSync(dest)) {
    vscode.window.setStatusBarMessage("api.http уже есть — открываю (новый: удалите файл)", 4000);
    return vscode.window.showTextDocument(vscode.Uri.file(dest));
  }
  const v = await collect(dir);
  if (!v) return;
  if (!v.routes.length) return vscode.window.showWarningMessage("маршрутов Gin не нашёл в " + dir);
  const login = v.routes.find((r) => r.Method === "POST" && r.Path.endsWith("login"));
  const lines = [
    "# Как пользоваться: «Send Request» над запросом (или alt-p) — ответ справа.",
    "# Сгенерировано из маршрутов (пробел r h); дальше файл ваш — правьте тела и параметры.",
    `@host = http://localhost:${v.port}`,
  ];
  const add = (r: Route) => {
    lines.push("", `### ${r.Method} ${r.Path} → ${r.Handler}`);
    if (r === login) lines.push("# @name login");
    lines.push(`${method(r)} {{host}}${examplePath(r.Path)}`);
    if (login && r !== login && !/(register|refresh)$/.test(r.Path)) lines.push("Authorization: Bearer {{login.response.body.$.access_token}}");
    if (["POST", "PUT", "PATCH"].includes(r.Method)) lines.push("Content-Type: application/json", "", "{}");
  };
  if (login) add(login);
  for (const r of v.routes) if (r !== login) add(r);
  fs.writeFileSync(dest, lines.join("\n") + "\n");
  vscode.window.setStatusBarMessage(`api.http: ${v.routes.length} запросов`, 4000);
  return vscode.window.showTextDocument(vscode.Uri.file(dest));
}

export function activate(ctx: vscode.ExtensionContext) {
  ctx.subscriptions.push(
    vscode.commands.registerCommand("ownvim.endpoints", () => pick(ctx)),
    vscode.commands.registerCommand("ownvim.apiHttp", apiHttp),
  );
}
