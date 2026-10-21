-- Rust: всё, что сверх rust-analyzer (lsp), rustfmt (format) и codelldb (debug):
--   Cargo.toml — справа от зависимости её последняя версия (устаревшие — подсвечены), K — описание крейта,
--   пробел ca — обновить версию, дополнение версий и фич (crates.nvim, без cargo — прямо с crates.io).
--   Отладка: F9 → «Rust: собрать и отладить» — cargo build и запуск бинарника под codelldb, путь вводить не нужно.
--   Задачи (пробел r r): cargo run / test / clippy / build --release — когда в корне Cargo.toml.
-- Сам Rust: brew install rustup && rustup default stable (rust-analyzer и clippy — rustup component add).
local M = {}

function M.plugins()
  return {
    {
      "saecki/crates.nvim",
      tag = "stable",
      event = { "BufRead Cargo.toml" },
      opts = {
        completion = { crates = { enabled = true } },
        lsp = { enabled = true, actions = true, completion = true, hover = true },
      },
    },
  }
end

return M
