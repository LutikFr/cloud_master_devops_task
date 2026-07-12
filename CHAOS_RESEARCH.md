# CHAOS_RESEARCH

Цель экспериментов — показать, как сбои сети и зависимостей влияют на приложение и Harbor Registry, а также какие архитектурные меры снижают эффект отказов. Сценарии реализованы через Istio fault injection в `VirtualService`.

## 1. Задержка между пользователем и приложением

Сценарий: `./scripts/run-chaos.sh user-delay` применяет `manifests/chaos/httpbin-delay-user.yaml`: 50% запросов к `httpbin` получают задержку 3s.

Как это бывает в реальности:

- перегружен ingress/API gateway;
- packet loss или высокий RTT между клиентом и edge-сегментом;
- TLS termination или WAF работает медленно;
- autoscaling не успел добавить реплики после всплеска трафика.

Что видно при проверке: baseline HTTP 200 быстро, после fault injection часть HTTP 200 приходит примерно через 3 секунды.

Защита:

- клиентские timeouts и retry с jitter/backoff;
- HPA/KEDA и лимиты на ingress;
- CDN/edge caching для статического контента;
- request hedging только для идемпотентных операций;
- SLO по latency и alerting на p95/p99.

## 2. HTTP 500 между компонентами приложения

Сценарий: `./scripts/run-chaos.sh component-500` применяет `httpbin-abort-component.yaml`: 40% запросов к сервису возвращают HTTP 500.

Как это бывает в реальности:

- новый релиз содержит ошибку;
- downstream сервис недоступен или падает по OOM;
- неверная конфигурация feature flag;
- сервис исчерпал пул соединений к БД/очереди.

Что видно: несколько запросов возвращают 500, остальные 200.

Защита:

- readiness/liveness probes и быстрый rollback;
- circuit breaker и outlier detection в service mesh;
- retry только для безопасных операций;
- canary/blue-green deployment;
- graceful degradation и fallback-ответы.

## 3. Задержка между БД и остальными компонентами

Сценарий: `./scripts/run-chaos.sh db-delay` применяет `httpbin-db-delay.yaml` к service `fake-db`. В тестовом стенде БД имитируется отдельным Kubernetes Service, чтобы показать сетевую задержку зависимости без тяжелой СУБД.

Как это бывает в реальности:

- медленные SQL-запросы и блокировки;
- saturating IOPS на диске;
- сетевые проблемы между app и DB subnet;
- checkpoint/vacuum/backup создает latency spike.

Что видно: запросы к DB-like service начинают занимать около 5 секунд.

Защита:

- connection pooling с лимитами;
- query timeout и cancelation;
- индексы, профилирование slow queries;
- read replicas/cache для чтения;
- bulkhead isolation, чтобы медленная БД не заняла все worker threads.

## 4. Harbor registry delay

Сценарий: `./scripts/run-chaos.sh harbor-registry-delay` добавляет 4s задержку до `harbor-registry`.

Как это бывает:

- registry storage backend отвечает медленно;
- большой concurrent pull/push образов;
- проблемы сети между core/jobservice и registry;
- деградация диска PV.

Влияние: push/pull образов и обращения к `/v2/` становятся медленнее.

Защита:

- достаточный storage IOPS и мониторинг latency;
- локальные pull-through caches на кластерах;
- pre-pull критичных образов;
- лимиты concurrent jobs и отдельный storage class для registry.

## 5. Harbor portal HTTP 500

Сценарий: `./scripts/run-chaos.sh harbor-portal-500` возвращает HTTP 500 для 50% запросов к `harbor-portal`.

Как это бывает:

- ошибка UI после обновления;
- неправильный config/nginx location;
- pod portal рестартует или не проходит readiness;
- frontend не может получить статические файлы.

Влияние: web UI нестабилен, но API/core/registry могут оставаться работоспособными.

Защита:

- отделять проверку UI от API health;
- canary для portal;
- readinessProbe на реальные статические ресурсы;
- runbook: пользоваться API/CLI, если UI недоступен.

## 6. Свой сценарий: задержка Harbor core API

Сценарий: `./scripts/run-chaos.sh harbor-core-delay` добавляет 5s задержку до `harbor-core`.

Почему важен: `core` — центральный компонент Harbor. Он обслуживает API, аутентификацию, проекты, политики, взаимодействие с jobservice/registry.

Реальные причины:

- БД Harbor медленно отвечает core;
- внешний OIDC/LDAP недоступен;
- core перегружен API-запросами CI/CD;
- блокировки при массовом garbage collection/replication.

Влияние: UI и API становятся медленными, CI/CD может получать timeout при docker login/push/pull metadata.

Защита:

- отдельные timeout budgets для CI/CD;
- масштабирование core больше 1 реплики в production;
- rate limiting API;
- мониторинг p95/p99 latency core и ошибок авторизации;
- отдельные окна для GC/replication.

## Общие выводы

Istio fault injection позволяет безопасно проверить устойчивость без изменения кода приложения. Для production важны: наблюдаемость, корректные timeouts, retries с backoff, circuit breakers, readiness probes, canary rollout, capacity planning и runbook для ручного восстановления.


## Покрытие сценариев

Для демонстрации выбраны три стандартных сценария из разных категорий: задержка между пользователем и приложением, HTTP 500 между компонентами приложения, задержка между DB-like зависимостью и остальными компонентами. Дополнительно реализован собственный сценарий деградации Harbor core API.

## Мониторинг

В стенд добавлены Prometheus и Grafana. Prometheus собирает метрики Kubernetes и Envoy sidecar на порту `15090`. Grafana доступна через `scripts/monitoring.sh grafana`, URL `http://127.0.0.1:3000`, логин `admin`, пароль `admin`. Смотреть Grafana нужно во время паузы после применения fault injection: на delay-сценариях ожидается рост latency, на abort-сценариях — рост HTTP 5xx/error rate.
