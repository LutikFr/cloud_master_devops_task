#!/usr/bin/env bash
set -euo pipefail
SCENARIO="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO_NS="${DEMO_NS:-demo}"
HARBOR_NS="${HARBOR_NS:-harbor}"

pause(){ echo; read -r -p "Press Enter to continue..." _; }
section(){ printf '\n\033[1;33m### %s\033[0m\n' "$*"; }
inside_curl(){ kubectl -n "$DEMO_NS" exec deploy/sleep -c sleep -- curl -sS -o /dev/null -w 'HTTP %{http_code}, time %{time_total}s\n' "$@"; }
show_vs(){ kubectl get virtualservice -A | grep -E 'httpbin|harbor|fake-db' || true; }

demo_before(){
  section "Baseline demo app checks"
  for i in 1 2 3; do inside_curl "http://httpbin.$DEMO_NS.svc.cluster.local:8000/status/200"; done
}
core_before(){
  section "Baseline Harbor core API checks"
  for i in 1 2 3; do inside_curl "http://harbor-core.$HARBOR_NS.svc.cluster.local/api/v2.0/ping" || true; done
}
apply_and_test(){
  local manifest="$1" ns="$2" testcmd="$3" vsname="$4"
  section "Apply chaos manifest: $manifest"
  kubectl apply -f "$ROOT_DIR/$manifest"
  show_vs
  section "After fault injection"
  bash -c "$testcmd"
  pause
  section "Rollback"
  kubectl -n "$ns" delete virtualservice "$vsname" --ignore-not-found
  show_vs
}

demo_status_loop='for i in 1 2 3 4 5; do kubectl -n demo exec deploy/sleep -c sleep -- curl -sS -o /dev/null -w "HTTP %{http_code}, time %{time_total}s\n" http://httpbin.demo.svc.cluster.local:8000/status/200 || true; done'
core_loop='for i in 1 2 3 4 5; do kubectl -n demo exec deploy/sleep -c sleep -- curl -sS -o /dev/null -w "HTTP %{http_code}, time %{time_total}s\n" http://harbor-core.harbor.svc.cluster.local/api/v2.0/ping || true; done'

case "$SCENARIO" in
  user-delay)
    demo_before; pause
    apply_and_test manifests/chaos/httpbin-delay-user.yaml demo "$demo_status_loop" httpbin-delay-user ;;
  component-500)
    demo_before; pause
    apply_and_test manifests/chaos/httpbin-abort-component.yaml demo "$demo_status_loop" httpbin-abort-component ;;
  db-delay)
    section "Baseline DB-like dependency checks"; for i in 1 2 3; do inside_curl "http://fake-db.$DEMO_NS.svc.cluster.local:8000/status/200"; done; pause
    apply_and_test manifests/chaos/httpbin-db-delay.yaml demo \
      'for i in 1 2 3; do kubectl -n demo exec deploy/sleep -c sleep -- curl -sS -o /dev/null -w "HTTP %{http_code}, time %{time_total}s\n" http://fake-db.demo.svc.cluster.local:8000/status/200; done' \
      httpbin-db-delay ;;
  harbor-core-delay)
    core_before; pause
    apply_and_test manifests/chaos/harbor-core-delay.yaml harbor "$core_loop" harbor-core-delay ;;
  all)
    for s in user-delay component-500 db-delay harbor-core-delay; do "$0" "$s"; done ;;
  *)
    cat <<USAGE
Usage: $0 <scenario>
Scenarios:
  user-delay          standard: delay between user and application
  component-500       standard: HTTP 500 between application components
  db-delay            standard: delay between DB-like dependency and other components
  harbor-core-delay   custom: delay of Harbor core API
  all                 run all scenarios sequentially
USAGE
    exit 1 ;;
esac
