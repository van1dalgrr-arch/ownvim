-- Docker прямо в коде — теперь на Go: core/extensions/docker (написан на sdk, как любое своё расширение).
--   compose.yaml — статус сервисов справа, enter — действия, ${VAR} ↔ .env; Dockerfile — вес слоёв (:DockerLayers).
-- Этот файл оставлен, чтобы модуль включался и выключался как раньше: "modules": { "docker": false }.
-- Настройки — там же: { "interval_ms": 3000, "compose_status": true, "layers": true, "env_check": true }.
return {}
