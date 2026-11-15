// Docker в запуске и отладке, как в ownvim:
//   задачи (пробел r t): compose up / up --build / down / логи — у проекта с compose-файлом
//   отладка (пробел r c): подключиться к dlv :2345, debugpy :5678, node --inspect :9229 в контейнере;
//   папка кода в контейнере — WORKDIR из Dockerfile проекта (нет — /app)
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { projectCompose } from "./docker";

/** WORKDIR последней стадии Dockerfile проекта */
function workdir(root: string): string {
  for (const name of ["Dockerfile", "build/Dockerfile", "docker/Dockerfile", "deploy/Dockerfile"]) {
    let text: string;
    try { text = fs.readFileSync(path.join(root, name), "utf8"); } catch { continue; }
    let wd = "";
    for (const l of text.split("\n")) {
      if (/^\s*FROM\s/i.test(l)) wd = "";
      const m = l.match(/^\s*WORKDIR\s+(\S+)/i);
      if (m) wd = m[1].startsWith("/") ? m[1] : path.posix.join(wd || "/", m[1]);
    }
    // многостадийная сборка: в итоговом образе часто только бинарник — код лежит там, где собирали
    const build = [...text.matchAll(/^\s*WORKDIR\s+(\S+)/gim)].map((m) => m[1]).find((w) => w.startsWith("/"));
    return build || wd || "/app";
  }
  return "/app";
}

function root(folder?: vscode.WorkspaceFolder) { return folder?.uri.fsPath || vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || ""; }

class Attach implements vscode.DebugConfigurationProvider {
  constructor(private kind: "go" | "debugpy" | "node") {}
  provideDebugConfigurations(folder?: vscode.WorkspaceFolder): vscode.DebugConfiguration[] {
    const wd = workdir(root(folder));
    if (this.kind === "go") return [{
      type: "go", request: "attach", mode: "remote", name: "Docker: подключиться к dlv (:2345)",
      host: "127.0.0.1", port: 2345, substitutePath: [{ from: "${workspaceFolder}", to: wd }],
    }];
    if (this.kind === "debugpy") return [{
      type: "debugpy", request: "attach", name: "Docker: подключиться к debugpy (:5678)",
      connect: { host: "127.0.0.1", port: 5678 }, pathMappings: [{ localRoot: "${workspaceFolder}", remoteRoot: wd }], justMyCode: false,
    }];
    return [{
      type: "node", request: "attach", name: "Docker: подключиться к node --inspect (:9229)",
      address: "127.0.0.1", port: 9229, localRoot: "${workspaceFolder}", remoteRoot: wd, restart: true, skipFiles: ["<node_internals>/**"],
    }];
  }
}

class Tasks implements vscode.TaskProvider {
  provideTasks(): vscode.Task[] {
    const file = projectCompose();
    if (!file) return [];
    const dir = path.dirname(file);
    const f = `-f '${path.basename(file)}'`;
    const task = (name: string, cmd: string, background = false) => {
      const t = new vscode.Task({ type: "ownvim", compose: name }, vscode.TaskScope.Workspace, name, "docker", new vscode.ShellExecution(`docker compose ${f} ${cmd}`, { cwd: dir }));
      t.isBackground = background;
      t.presentationOptions = { reveal: vscode.TaskRevealKind.Always, panel: vscode.TaskPanelKind.Dedicated, clear: true };
      return t;
    };
    return [
      task("compose up", "up", true),
      task("compose up --build", "up --build", true),
      task("compose up -d", "up -d"),
      task("compose down", "down"),
      task("compose логи", "logs -f --tail 200", true),
      task("compose ps", "ps -a"),
      task("compose pull", "pull"),
    ];
  }
  resolveTask() { return undefined; }
}

export function activate(ctx: vscode.ExtensionContext) {
  const dyn = vscode.DebugConfigurationProviderTriggerKind.Dynamic;
  ctx.subscriptions.push(
    vscode.debug.registerDebugConfigurationProvider("go", new Attach("go"), dyn),
    vscode.debug.registerDebugConfigurationProvider("debugpy", new Attach("debugpy"), dyn),
    vscode.debug.registerDebugConfigurationProvider("node", new Attach("node"), dyn),
    vscode.tasks.registerTaskProvider("ownvim", new Tasks()),
  );
}
