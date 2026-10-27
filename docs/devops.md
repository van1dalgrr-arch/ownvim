# DevOps

[← Документация](README.md)

- [Docker в коде](#docker-в-коде): [живой compose.yaml](#живой-composeyaml) · [вес слоёв Dockerfile](#вес-слоёв-dockerfile) · [`${VAR}` ↔ `.env`](#var--env)
- [Контейнеры, GitHub, Kubernetes](#контейнеры-github-kubernetes)
- [Базы данных](#базы-данных)
- [Задачи](#задачи)

## Docker в коде

Модуль `docker`: статус и цифры — прямо в файлах, без отдельных окон. Нужен `docker` (Docker Desktop, OrbStack…).

### Живой compose.yaml

Справа от каждого сервиса — его состояние:

```yaml
services:
  api:          ● работает · здоров · :8080
  worker:       ○ остановлен (код 1)
  migrate:      ○ остановлен (код 0)
  cache:        ○ не запущен
```

- Цвет: зелёный — работает, красный — упал (ненулевой код или `unhealthy`), серый — завершился нормально или не
  запускался. Видны здоровье (healthcheck) и опубликованные порты.
- Обновляется сам раз в 3 секунды — только пока compose-файл на экране.
- **`enter` на сервисе** — меню: ▶ up, ⇪ собрать и up, ⟳ restart, ■ stop, ≡ логи, ❯ shell (логи и shell — в
  терминале снизу). На остальных строках `enter` работает как обычно.

Работает для стандартных имён файлов: `compose.yaml`, `compose.yml`, `docker-compose.yml`, `docker-compose.yaml`.

### Вес слоёв Dockerfile

После сборки образа справа от каждой инструкции — сколько она добавила; на `FROM` — итог и вес базового образа:

```dockerfile
FROM golang:1.25-alpine                        app:dev · 412 MB · база 245 MB
RUN apk add --no-cache git make                                       +18 MB
COPY . .                                                             +4.1 MB
RUN go build -o /app ./cmd/api                                       +145 MB
```

- Цвет по весу: до 10 MB — серый, от 10 MB — синий, от 100 MB — жёлтый, от 500 MB — красный.
- Цифры — из `docker history` собранного образа. Образ ownvim ищет сам: `<папка проекта>:dev` (как собирает задача
  «docker build»), затем `<папка>-<сервис>` (как называет compose). Не тот — **`:DockerLayers`** и выбрать.
- Считается последняя стадия multi-stage сборки — только она попадает в итоговый образ. Поменяли Dockerfile —
  цифры обновятся после пересборки.

### `${VAR}` ↔ `.env`

- Переменная в compose-файле без значения в `.env` (рядом с compose-файлом), без значения в окружении и без умолчания
  (`${VAR:-…}`) — **предупреждение на строке**: compose подставил бы пустую строку.
- **`gd` на `${VAR}`** — к её строке в `.env`. Её там нет — ownvim допишет `VAR=` в конец `.env` и поставит туда курсор.
- Секреты в `.env` — под звёздочками (модуль `cloak`), строка под курсором видна; `пробел ue` — показать все.

```jsonc
"modules": {
  "docker": { "interval_ms": 3000, "compose_status": true, "layers": true, "env_check": true },
},
```

## Контейнеры, GitHub, Kubernetes

| клавиша | что |
|---|---|
| `alt-o` / `пробел rc` | контейнеры: OrbStack или lazydocker в окне (ещё раз — спрятать) |
| `пробел rd` | lazydocker |
| `alt-w` / `пробел gw` | GitHub: PR, Actions, логи (gw или `gh dash`) |
| `пробел k` | Kubernetes (kubectl.nvim): поды, деплойменты, логи, describe — если есть `kubectl` |

```jsonc
"modules": { "system": { "containers": "orbstack", "github": "gw" } },  // или "lazydocker", "gh dash"
```

Задачи для Docker уже есть в списке (`пробел rr`): `docker compose up -d / down / ps / logs`, сборка образа проекта,
hadolint текущего Dockerfile, trivy — уязвимости образа. Отладка Go в контейнере — [Go → Отладчик](go.md#отладчик).

## Базы данных

`пробел D` / `alt-d` — подключения и таблицы (vim-dadbod). Запрос — в файле: `enter` или `пробел S` выполняет,
результат — таблицей. В `.sql` — дополнение по таблицам и колонкам настоящей базы.

```jsonc
"database": {
  "connections": { "local": "postgres://postgres:postgres@localhost:5432/app" },
  "project_env": true,   // подключение проекта само: DATABASE_URL из .env, иначе postgres://postgres:<DB_PASSWORD>@localhost:5432/<папка>
},
```

### SQL и миграции

Модуль `sql`. Подключение к базе проекта находится само: `DATABASE_URL` из `.env`, иначе сервис postgres из
compose-файла (`POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` и порт).

- **Дополнение.** `FROM |` — таблицы, `u.|` — колонки таблицы или псевдонима, `SELECT | FROM users` — колонки
  запроса, `INSERT INTO t (|`, `REFERENCES t(|` — колонки `t`, `role = '|` — значения enum. В `CREATE TABLE` и
  `ADD COLUMN` после имени — типы Postgres, после типа — `NOT NULL`, `DEFAULT`, `REFERENCES`… Схема берётся из
  файлов миграций — работает без запущенной базы и знает ещё не применённые миграции; с базой добавляется сервер SQL
  (функции, системные таблицы, ошибки в запросах, опасные миграции).
- **Миграции** — `пробел rm`: новая, up, down (с подтверждением), redo, статус. Или `:Migrate new add_phone_to_users`.
  Имя `create_orders` даёт заготовку `CREATE TABLE`, `add_x_to_y` — `ALTER TABLE y ADD COLUMN x`.
- **down пишется сам** при сохранении up (`DROP TABLE`, `DROP COLUMN`, `RENAME` обратно…), пока его не правили руками.
- В первой строке миграции: `✓ применена`, `○ ждёт применения`, `✗ dirty`. `cmd-shift-t` — up ↔ down.
- Сниппеты: `tbl`, `col`, `fk`, `ts`, `idx`, `idxc`, `uidx`, `enum`, `addcol`, `dropcol`, `rencol`, `notnull`,
  `retype`, `addfk`, `trgupd`, `upsert`, `cte`, `page`, `tx`, `goose`.
- golang-migrate (`000001_x.up.sql` / `.down.sql`) и goose (`-- +goose Up`) различаются сами.

```jsonc
"modules": { "sql": { "migrations": "", "tool": "auto", "auto_down": true, "status": true, "lsp_db": true } },
```

## Задачи

Как Run Configurations в GoLand или `ctrl-r` в Zed: `пробел rr` (или `alt-t`) — выбрать и запустить, `пробел rl` —
что запущено, вывод последней — нижняя панель (`пробел jo`).

```jsonc
"tasks": {
  "list": [
    { "name": "миграции вверх", "cmd": "migrate -path migrations -database $DATABASE_URL up", "when": ["migrations"] },
    { "name": "тест пакета", "cmd": "go test -count=1 ${file_dir}", "when": ["go.mod"] },
    { "name": "собрать C++", "cmd": "clang++ -g -o /tmp/a.out ${file}", "ft": ["cpp"] },
  ]
},
```

- `when` — задача видна, если в корне проекта есть хоть один из этих файлов или папок (нет `when` — всегда).
- `ft` — только когда открыт файл этого языка. `cwd`: `"root"` (по умолчанию) или `"file"`.
- В `cmd` подставляются `${root}`, `${file}`, `${file_dir}`, `${image}` (= `<папка проекта>:dev`).
- Свой `list` в `settings.jsonc` **заменяет** список по умолчанию целиком — скопируйте нужные задачи из `defaults.jsonc`.

Из коробки: `up` (зависимости compose + приложение), air, `go run ./cmd/api`, gotestsum, покрытие, бенчмарки + pprof,
golangci-lint, `go mod tidy`, govulncheck, `curl /health`, команды compose, `docker build`, hadolint, trivy,
cmake / ctest / make.
