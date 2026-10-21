# DevOps

[← Documentation](README.md)

- [Docker in your code](#docker-in-your-code): [live compose.yaml](#live-composeyaml) · [Dockerfile layer sizes](#dockerfile-layer-sizes) · [`${VAR}` ↔ `.env`](#var--env)
- [Containers, GitHub, Kubernetes](#containers-github-kubernetes)
- [Databases](#databases)
- [Tasks](#tasks)

## Docker in your code

The `docker` module puts status and numbers right in the files, with no extra windows. Needs `docker` (Docker
Desktop, OrbStack…).

### Live compose.yaml

Each service shows its state on the right:

```yaml
services:
  api:          ● работает · здоров · :8080
  worker:       ○ остановлен (код 1)
  migrate:      ○ остановлен (код 0)
  cache:        ○ не запущен
```

(Labels are in Russian: running · healthy, stopped (exit code), not started.)

- Color: green — running, red — failed (non-zero exit or `unhealthy`), grey — exited normally or never started.
  Health (healthcheck) and published ports are shown.
- Refreshes every 3 seconds — only while the compose file is on screen.
- **`enter` on a service** — a menu: ▶ up, ⇪ build and up, ⟳ restart, ■ stop, ≡ logs, ❯ shell (logs and shell open in
  a terminal below). On other lines `enter` works as usual.

Works with the standard file names: `compose.yaml`, `compose.yml`, `docker-compose.yml`, `docker-compose.yaml`.

### Dockerfile layer sizes

After the image is built, each instruction shows how much it added; `FROM` shows the total and the base image size:

```dockerfile
FROM golang:1.25-alpine                        app:dev · 412 MB · база 245 MB
RUN apk add --no-cache git make                                       +18 MB
COPY . .                                                             +4.1 MB
RUN go build -o /app ./cmd/api                                       +145 MB
```

- Color by size: under 10 MB — grey, from 10 MB — blue, from 100 MB — yellow, from 500 MB — red.
- The numbers come from `docker history` of the built image. ownvim finds the image itself: `<project folder>:dev`
  (as the "docker build" task names it), then `<folder>-<service>` (as compose names it). Wrong one —
  **`:DockerLayers`** and pick it.
- Only the last stage of a multi-stage build counts — it's the only one in the final image. After changing the
  Dockerfile, the numbers update once you rebuild.

### `${VAR}` ↔ `.env`

- A variable in a compose file with no value in `.env` (next to the compose file), none in the environment and no
  default (`${VAR:-…}`) gets **a warning on its line**: compose would substitute an empty string.
- **`gd` on `${VAR}`** — jumps to its line in `.env`. If it isn't there, ownvim appends `VAR=` to `.env` and puts the
  cursor on it.
- Secrets in `.env` are masked with asterisks (the `cloak` module); the line under the cursor is visible; `space ue` —
  show all.

```jsonc
"modules": {
  "docker": { "interval_ms": 3000, "compose_status": true, "layers": true, "env_check": true },
},
```

## Containers, GitHub, Kubernetes

| key | what |
|---|---|
| `alt-o` / `space rc` | containers: OrbStack or lazydocker in a window (press again to hide) |
| `space rd` | lazydocker |
| `alt-w` / `space gw` | GitHub: PRs, Actions, logs (gw or `gh dash`) |
| `space k` | Kubernetes (kubectl.nvim): pods, deployments, logs, describe — when `kubectl` is installed |

```jsonc
"modules": { "system": { "containers": "orbstack", "github": "gw" } },  // or "lazydocker", "gh dash"
```

Docker tasks are already in the list (`space rr`): `docker compose up -d / down / ps / logs`, building the project
image, hadolint on the current Dockerfile, trivy image vulnerabilities. Debugging Go in a container —
[Go → Debugger](go.md#debugger).

## Databases

`space D` / `alt-d` — connections and tables (vim-dadbod). Queries live in a file: `enter` or `space S` runs one, the
result is a table. In `.sql` files, completion knows the tables and columns of the real database.

```jsonc
"database": {
  "connections": { "local": "postgres://postgres:postgres@localhost:5432/app" },
  "project_env": true,   // the project connection by itself: DATABASE_URL from .env, else postgres://postgres:<DB_PASSWORD>@localhost:5432/<folder>
},
```

## Tasks

Like Run Configurations in GoLand or `ctrl-r` in Zed: `space rr` (or `alt-t`) — pick and run, `space rl` — what's
running, the last task's output — the bottom panel (`space jo`).

```jsonc
"tasks": {
  "list": [
    { "name": "migrate up", "cmd": "migrate -path migrations -database $DATABASE_URL up", "when": ["migrations"] },
    { "name": "package tests", "cmd": "go test -count=1 ${file_dir}", "when": ["go.mod"] },
    { "name": "build C++", "cmd": "clang++ -g -o /tmp/a.out ${file}", "ft": ["cpp"] },
  ]
},
```

- `when` — the task is visible if the project root has at least one of these files or folders (no `when` — always).
- `ft` — only while a file of that language is open. `cwd`: `"root"` (default) or `"file"`.
- `cmd` gets `${root}`, `${file}`, `${file_dir}`, `${image}` (= `<project folder>:dev`) substituted.
- Your own `list` in `settings.jsonc` **replaces** the default list entirely — copy the tasks you need from `defaults.jsonc`.

Included: `up` (compose dependencies + the app), air, `go run ./cmd/api`, gotestsum, coverage, benchmarks + pprof,
golangci-lint, `go mod tidy`, govulncheck, `curl /health`, compose commands, `docker build`, hadolint, trivy,
cmake / ctest / make.
