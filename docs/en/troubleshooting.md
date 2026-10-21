# Troubleshooting

[← Documentation](README.md)

**Start with `:OwnHealth`** (`space uX`) — it checks settings, programs, servers, formatters, linters, parsers, the
font, the theme and startup time. Every problem comes with a fix.

## Settings

| symptom | what to do |
|---|---|
| a line in `settings.jsonc` is underlined | put the cursor on it — the message says what's wrong and how to fix it |
| "settings.jsonc не прочитан, работаю на умолчаниях" (not read, running on defaults) | the file has a JSON error, highlighted on its line; fix it and save |
| changed a setting — nothing happened | turning modules on, plugins and the start screen need `:restart` |
| everything is broken | rename `settings.jsonc` — ownvim starts on the defaults; bring lines back one by one |

## Languages

| symptom | what to do |
|---|---|
| no errors, navigation or completion | `space cl` — which servers are attached; `space cL` — restart them; `:Mason` — what's installed |
| a server won't install | `:OwnHealth` and `~/.local/state/ownvim/mason.log`; some servers need the language itself (Node, Java, Ruby…) |
| Rust: no rust-analyzer / rustfmt | `brew install rustup && rustup default stable` |
| automatic installation picked the wrong server | `:AutoTools language` — forget and decide again; or `"auto": { "languages": { "language": { "lsp": ["yours"] } } }` |
| a language needs nothing | `"auto": { "languages": { "language": false } }` |
| the file formats wrongly | `space cF` — what formats it; `space uf` — turn off for now; the list — the `format` section |
| errors flicker while typing | `"modules": { "error_lens": { "insert": false } }` |

## Appearance

| symptom | what to do |
|---|---|
| squares instead of icons | you need a Nerd Font (Ghostty has the icons built in) or `"icons": { "theme": "ascii" }` |
| wrong theme after a restart | `"theme"` in `settings.jsonc` beats the one picked in `alt-s`; `"theme": "auto"` — use alt-s |
| the font doesn't change | the terminal owns the font; `:Font` works in Ghostty |
| the side image doesn't show | needs a kitty-protocol terminal (Ghostty, kitty, WezTerm), not tmux; jpg/webp need ImageMagick |

## Docker

| symptom | what to do |
|---|---|
| no statuses in compose.yaml | check `docker ps` in a terminal; "docker не запущен" (docker isn't running) — start Docker / OrbStack; the file must be named `compose.yaml` / `docker-compose.yml` |
| no layer sizes in the Dockerfile | the image isn't built yet or has another name — `:DockerLayers` and pick it |
| layer sizes are outdated | rebuild the image |

## Plugins and speed

| symptom | what to do |
|---|---|
| a plugin didn't install | `:Lazy` (`space l`) — installation errors and an "update" button |
| slow startup | `:OwnHealth` shows the time; in detail — `NVIM_APPNAME=ownvim nvim --startuptime /tmp/st.txt +qa`; as a person sees it — `scripts/bench_paint.py` ([Architecture](architecture.md#checking-changes)) |

## Logs

`~/.local/state/ownvim/`: `lsp.log`, `mason.log`, `conform.log`, `dap.log`, `neotest.log`, `nvim.log`.
Notification history — `space n`.
