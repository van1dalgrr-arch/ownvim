-- Docker прямо в коде — теперь на Go: core/extensions/docker (написан на sdk, как любое своё расширение).
--   compose.yaml — статус сервисов справа, enter — действия, ${VAR} ↔ .env; Dockerfile — вес слоёв (:DockerLayers).
-- Настройки — там же: { "interval_ms": 3000, "compose_status": true, "layers": true, "env_check": true }.
-- Здесь — то, что нужно редактору до Go: compose.yml, docker-compose.*.yml, compose.override.yaml… — тип
-- yaml.docker-compose (на нём работает Docker-сервер: ключи compose, описание по K, проверка), подсветка YAML,
-- отступы в YAML без сюрпризов (lua/own/yaml.lua) и форматирование yamlfmt (раздел format).
local M = {}

local function is_compose(path)
  local name = vim.fs.basename(path)
  return name:match("^compose%.ya?ml$") or name:match("^compose%..+%.ya?ml$")
    or name:match("^docker%-compose%.ya?ml$") or name:match("^docker%-compose%..+%.ya?ml$")
end

function M.setup()
  vim.filetype.add({
    pattern = {
      [".*%.ya?ml"] = { function(path) return is_compose(path) and "yaml.docker-compose" or nil end, { priority = 10 } },
    },
  })
  vim.treesitter.language.register("yaml", "yaml.docker-compose")
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("own.docker.yaml", { clear = true }),
    pattern = { "yaml", "yaml.*" },
    callback = function(ev)
      local yaml = require("own.yaml")
      yaml.attach(ev.buf)
      -- treesitter ставит свой indentexpr на том же событии — вернуть свой после него
      vim.schedule(function() if vim.api.nvim_buf_is_valid(ev.buf) then yaml.attach(ev.buf) end end)
    end,
  })
  -- файл открыли раньше, чем модуль загрузился (ownvim compose.yml)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "yaml" and is_compose(vim.api.nvim_buf_get_name(buf)) then
      vim.bo[buf].filetype = "yaml.docker-compose"
    end
  end
end

return M
