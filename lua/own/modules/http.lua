-- Postman в файле и эндпоинты — теперь на Go (написаны на sdk, как любое своё расширение):
--   core/extensions/http       — .http-файлы: enter на запросе — ответ справа, esc — закрыть, пробел R s/r/c/n/p
--   core/extensions/endpoints  — :Endpoints (пробел r e, alt-a) — все маршруты Gin; :ApiHttp (пробел r h, alt-p) — api.http
-- Этот файл оставлен, чтобы модуль включался и выключался как раньше: "modules": { "http": false }.
return {}
