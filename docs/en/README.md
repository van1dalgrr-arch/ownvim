# ownvim documentation

🇷🇺 [Русская документация](../README.md)

ownvim is a Neovim build for backend development (Go, SQL, Docker, C/C++, Python, Rust) configured with a single
JSON file, no Lua. Everything is here, from installation to the internals.

## Start here

| | |
|---|---|
| [Getting started](getting-started.md) | install, first launch, 13 keys for day one, coming from VS Code |
| [Configuration](configuration.md) | how `defaults.jsonc` and `settings.jsonc` work, what applies immediately, every section |

## Features

| | |
|---|---|
| [Appearance](appearance.md) | themes (its own, from VS Code, 30+ ready-made), icons, font, status line, tabs, panels, animations |
| [Languages](languages.md) | language servers, formatting, linters, automatic setup for any language, inline errors |
| [Go](go.md) | ▶ next to main and tests, background tests, debugger, code generation, Gin endpoints, `.http` requests |
| [DevOps](devops.md) | Docker in your code (live compose, layer sizes, `${VAR}` ↔ `.env`), Kubernetes, databases, tasks |
| [Working with code](workflow.md) | search and navigation, editing, git, Claude, sessions, friction notes, Russian layout |
| [JSONC plugins](jsonc-plugins.md) ⭐ | no code: keys, tasks, your own checks (errors on lines), status line blocks — in one file |
| [Go extensions](go-extensions.md) ⭐ | your own commands, completion, K descriptions, fixes, panels — in Go: save and it works |
| [Extending](extending.md) | plugin store, your own plugins, your own Lua modules |
| [Script extensions](extensions.md) | your own commands in any language: stdin → stdout, no Lua |

## Reference

| | |
|---|---|
| [Keys](../keys.ru.md) | every default key (generated from `defaults.jsonc`; descriptions are in Russian) |
| [Modules](reference/modules.md) | all 51 modules: what they do, whether they are on, where their settings live |
| [Commands](reference/commands.md) | every ownvim `:command` |
| [Troubleshooting](troubleshooting.md) | health check, common problems and fixes |
| [Architecture](architecture.md) | startup order, settings layers, the module contract, how to add your own |

## About authorship

ownvim is my idea and my design: what the editor should have, how it should look and behave, what is inconvenient
and what to fix. But Lua and Neovim are not my stack, so **most of the code and this documentation was written by
an AI (Claude)** to my requirements, and I checked the result in real work.
