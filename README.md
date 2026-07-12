# cloud_master_devops_task

Автоматизация разворачивает однонодовый Kubernetes на Minikube, устанавливает Istio, Harbor Registry и demo-приложение, затем запускает Chaos Engineering сценарии через Istio `VirtualService` fault injection.

## Состав стенда

- Docker как драйвер Minikube;
- Minikube single-node Kubernetes;
- kubectl и Helm;
- Istio ingress gateway и control plane;
- Harbor Registry в namespace `harbor`, все компоненты по 1 реплике;
- demo-приложение `httpbin` и pod `sleep` в namespace `demo`;
- Istio-манифесты для задержек и HTTP 500;
- Prometheus и Grafana для просмотра метрик.

## Требования

Ubuntu 22.04 amd64, пользователь с `sudo`, доступ в интернет, минимум 2 CPU, рекомендуется 4 CPU, 6-8 GB RAM и 30 GB диска.

## Установка

```bash
cd cloud_master_devops_task
git checkout solution/devops-chaos-task
./scripts/setup.sh
```

Если sudo требует пароль, `setup.sh` запросит его на этапе проверки sudo и запустит локальный playbook через `sudo`. Minikube при этом создаётся от обычного пользователя, заданного переменной `minikube_user`.

Локальный запуск playbook на самой VM:

```bash
cd ansible
ansible-playbook -i inventory.local.ini site.yml
```

`inventory.local.ini` использует `ansible_connection=local`; Minikube и kubectl запускаются от пользователя, заданного переменной `minikube_user`.

Запуск Ansible из Docker-контейнера для удалённой VM:

```bash
cp ansible/inventory.remote.example.ini ansible/inventory.remote.ini
vi ansible/inventory.remote.ini
./scripts/run-ansible-container.sh
```

В удалённом inventory нужно указать IP/hostname VM и SSH-пользователя с sudo-доступом:

```ini
[vm]
vm1 ansible_host=192.0.2.10 ansible_user=ubuntu ansible_become=true
```

В этом режиме контейнер является только control node для Ansible, а Docker, Minikube, Istio, Harbor и monitoring устанавливаются на удалённую VM по SSH. Playbook копирует на VM директории `manifests` и `scripts` в `remote_repo_dir` (`/home/<user>/cloud_master_devops_task` по умолчанию), поэтому chaos-скрипты и манифесты доступны на целевой VM после установки.

Для SSH-аутентификации рекомендуется ключ из `~/.ssh`; он монтируется в Ansible-контейнер read-only. Если используется пароль SSH, запустить с `--ask-pass`. Если sudo требует пароль, добавить `--ask-become-pass` или коротко `-K`:

```bash
./scripts/run-ansible-container.sh --ask-pass --ask-become-pass
```

Проверку после удалённой установки выполнять на целевой VM:

```bash
ssh ubuntu@192.0.2.10
cd ~/cloud_master_devops_task
kubectl get nodes
kubectl get pods -A
```

Параметры можно переопределить через `--extra-vars`:

```bash
./scripts/setup.sh --extra-vars "minikube_cpus=4 minikube_memory=8192 harbor_admin_password=Harbor12345"
```

Основные значения находятся в `ansible/group_vars/all.yml`.

## Роли Ansible

```text
ansible/inventory.local.ini          # локальный запуск на VM
ansible/inventory.remote.example.ini # пример inventory для удалённой VM
ansible/roles/workspace   # копирование scripts/manifests на целевую VM
ansible/roles/common      # системные пакеты, Docker, Python-библиотеки
ansible/roles/minikube    # minikube, kubectl, single-node cluster
ansible/roles/helm        # Helm repositories
ansible/roles/istio       # Istio base, istiod, ingress gateway
ansible/roles/demo_app    # demo namespace, httpbin, sleep, Istio route
ansible/roles/harbor      # Harbor Helm release, Istio route
ansible/roles/monitoring  # Prometheus и Grafana
```

## Проверка установки

```bash
kubectl get nodes
kubectl get pods -A
kubectl get gateways,virtualservices -A
```

Demo-приложение:

```bash
kubectl -n demo exec deploy/sleep -c sleep -- \
  curl -sS -o /dev/null -w 'HTTP %{http_code}, time %{time_total}s\n' \
  http://httpbin.demo.svc.cluster.local:8000/status/200
```

Harbor API:

```bash
kubectl -n demo exec deploy/sleep -c sleep -- \
  curl -sS -o /dev/null -w 'HTTP %{http_code}, time %{time_total}s\n' \
  http://harbor-core.harbor.svc.cluster.local/api/v2.0/ping
```

Метрики:

```bash
./scripts/monitoring.sh prometheus   # http://127.0.0.1:9090
./scripts/monitoring.sh grafana      # http://127.0.0.1:3000, admin/admin
```

Grafana стоит в namespace `monitoring`. Открывать её удобно во время паузы в `run-chaos.sh`: сначала запустить сценарий, дождаться применения fault injection, затем в отдельном терминале выполнить `./scripts/monitoring.sh grafana` и открыть `http://127.0.0.1:3000`. В Grafana подключён datasource Prometheus; для проверки деградации использовать метрики Istio/Envoy по latency, request rate и HTTP 5xx.

## Chaos-сценарии

Каждый сценарий показывает baseline, делает паузу, применяет Istio fault injection, показывает эффект и откатывает изменения.

```bash
./scripts/run-chaos.sh user-delay
./scripts/run-chaos.sh component-500
./scripts/run-chaos.sh db-delay
./scripts/run-chaos.sh harbor-core-delay
```

Выбраны три стандартных сценария из разных категорий и один дополнительный собственный сценарий:

| Сценарий | Тип |
|---|---|
| `user-delay` | стандартный, задержка между пользователем и приложением |
| `component-500` | стандартный, HTTP 500 между компонентами приложения |
| `db-delay` | стандартный, задержка между БД и остальными компонентами |
| `harbor-core-delay` | дополнительный, задержка Harbor core API |

Все сценарии последовательно:

```bash
./scripts/run-chaos.sh all
```

Откат fault injection правил:

```bash
./scripts/reset-chaos.sh
```

## Ожидаемый результат

- `kubectl get nodes` показывает 1 Ready node;
- `kubectl get pods -A` показывает запущенные pod'ы Istio, Harbor и demo;
- baseline-запросы возвращают HTTP 200 с малым временем ответа;
- delay-сценарии увеличивают время ответа на 3-5 секунд;
- abort-сценарии возвращают HTTP 500 для части запросов;
- после rollback поведение возвращается к baseline.

## Структура

```text
scripts/setup.sh                 # запуск установки через ansible-playbook
scripts/run-chaos.sh             # запуск сценариев отказа
scripts/reset-chaos.sh           # удаление fault-injection VirtualService
scripts/monitoring.sh            # port-forward к Prometheus/Grafana
scripts/run-ansible-container.sh # запуск Ansible из Docker-контейнера
docker/Dockerfile                # образ с Ansible и коллекциями
ansible/                         # playbook, inventory, group_vars, roles
manifests/apps/demo/*.yaml      # namespace demo, httpbin, sleep, fake-db service
manifests/harbor/values.yaml     # values Harbor Helm chart
manifests/istio/*/*.yaml         # gateways/routes
manifests/chaos/*.yaml           # Istio fault-injection сценарии
CHAOS_RESEARCH.md                # описание сценариев и защитных мер
```

## Очистка

```bash
./scripts/reset-chaos.sh
helm -n monitoring uninstall grafana prometheus || true
helm -n harbor uninstall harbor || true
kubectl delete ns monitoring harbor demo || true
helm -n istio-system uninstall istio-ingressgateway istiod istio-base || true
kubectl delete ns istio-system || true
minikube delete
```
