#!/usr/bin/env bash
# =============================================================================
# 04-failure-tests.sh
# Testes de falha com evidências gravadas em evidencias/falhas-<data>.log
#   T1  Interromper o serviço de monitoramento (kill -9) e verificar recuperação
#   T2  Parar a aplicação (kill -9) e verificar recuperação automática
#   T3  Simular consumo elevado de CPU e verificar alerta
#   T4  Simular consumo elevado de memória e verificar alerta
#   T5  Falha controlada em script e verificação no erros.log
#   T6  Parada/início manual do serviço (stop/start/restart)
#   (Reboot da VM: veja README, seção "Teste de reinicialização")
# Uso: sudo ./scripts/04-failure-tests.sh [--all|T1|T2|...]
# =============================================================================
CT_SCRIPT="04-failure-tests"
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
require_root
mkdir -p "$CT_ROOT/evidencias"
EVID="$CT_ROOT/evidencias/falhas-$(date +%Y%m%d-%H%M%S).log"
CT_LOG_FILE="$LOG_DIR/testes-falha.log"
has_systemd || die "systemd é necessário para os testes de recuperação."

say() { echo "$*" | tee -a "$EVID"; }
section() { say ""; say "================ $* ================"; }
wait_active() { local s=$1 i; for i in $(seq 1 "${2:-30}"); do systemctl is-active --quiet "$s" && return 0; sleep 1; done; return 1; }
PASS=0; FAIL=0
result() { if [ "$1" = ok ]; then say "RESULTADO: PASS - $2"; PASS=$((PASS+1)); audit "teste falha: $2" "PASS"
           else say "RESULTADO: FAIL - $2"; FAIL=$((FAIL+1)); audit "teste falha: $2" "FAIL"; fi; }

t1() {
  section "T1 - Matar o serviço de monitoramento (SIGKILL) e verificar recuperação"
  local old new
  old=$(systemctl show -p MainPID --value citizentech-monitor); say "PID antes: $old"
  kill -9 "$old"; say "$(date +%T) SIGKILL enviado ao PID $old"
  sleep 1; say "Estado imediatamente após: $(systemctl is-active citizentech-monitor)"
  if wait_active citizentech-monitor 30; then
    new=$(systemctl show -p MainPID --value citizentech-monitor)
    say "$(date +%T) Serviço recuperado. PID novo: $new (NRestarts=$(systemctl show -p NRestarts --value citizentech-monitor))"
    [ "$old" != "$new" ] && result ok "monitor recuperado automaticamente (Restart=always)" || result fail "PID não mudou"
  else result fail "monitor não voltou"; fi
  journalctl -u citizentech-monitor --no-pager -n 8 2>&1 | tee -a "$EVID"
}

t2() {
  section "T2 - Matar a aplicação (SIGKILL) e verificar recuperação"
  systemctl is-active --quiet citizentech-app || { result fail "citizentech-app não está ativo (rode 02-provision-app.sh)"; return; }
  local old; old=$(systemctl show -p MainPID --value citizentech-app); say "PID antes: $old"
  kill -9 "$old"; sleep 1
  if wait_active citizentech-app 30; then
    sleep 2; local code; code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/health)
    say "HTTP /health após recuperação: $code"
    [ "$code" = 200 ] && result ok "aplicação recuperada e respondendo" || result fail "app voltou mas /health=$code"
  else result fail "aplicação não voltou"; fi
}

t3() {
  section "T3 - Consumo elevado de CPU (gera alerta)"
  local before; before=$(wc -l < "$LOG_DIR/alertas.log" 2>/dev/null || echo 0)
  local n; n=$(nproc)
  stress_cpu() { if command -v stress-ng >/dev/null; then stress-ng --cpu "$n" --timeout 12s >/dev/null 2>&1 &
                 else for _ in $(seq "$n"); do timeout 12 sh -c 'while :; do :; done' & done; fi; }
  stress_cpu; sleep 3
  CPU_THRESHOLD=50 "$CT_ROOT/scripts/monitor.sh" --once 2>&1 | tee -a "$EVID" || true
  wait 2>/dev/null
  local after; after=$(wc -l < "$LOG_DIR/alertas.log" 2>/dev/null || echo 0)
  say "Últimos alertas:"; tail -n 3 "$LOG_DIR/alertas.log" 2>/dev/null | tee -a "$EVID"
  [ "$after" -gt "$before" ] && result ok "alerta de CPU registrado em alertas.log" || result fail "nenhum alerta de CPU"
}

t4() {
  section "T4 - Consumo elevado de memória (gera alerta)"
  local before; before=$(wc -l < "$LOG_DIR/alertas.log" 2>/dev/null || echo 0)
  local used; used=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{print int((t-a)*100/t)}' /proc/meminfo)
  # Limiar logo abaixo do uso atual força o alerta sem estressar a máquina
  if command -v stress-ng >/dev/null; then stress-ng --vm 1 --vm-bytes 25% --timeout 10s >/dev/null 2>&1 & sleep 3; fi
  MEM_THRESHOLD=$(( used > 1 ? used - 1 : 1 )) "$CT_ROOT/scripts/monitor.sh" --once 2>&1 | tee -a "$EVID" || true
  wait 2>/dev/null
  local after; after=$(wc -l < "$LOG_DIR/alertas.log" 2>/dev/null || echo 0)
  say "Últimos alertas:"; tail -n 3 "$LOG_DIR/alertas.log" 2>/dev/null | tee -a "$EVID"
  [ "$after" -gt "$before" ] && result ok "alerta de RAM registrado" || result fail "nenhum alerta de RAM"
}

t5() {
  section "T5 - Falha controlada em script (deve aparecer em erros.log)"
  local before; before=$(wc -l < "$LOG_DIR/erros.log" 2>/dev/null || echo 0)
  "$CT_ROOT/scripts/monitor.sh" --fail-test 2>&1 | tee -a "$EVID" || true
  local after; after=$(wc -l < "$LOG_DIR/erros.log" 2>/dev/null || echo 0)
  say "Últimas linhas de erros.log:"; tail -n 3 "$LOG_DIR/erros.log" | tee -a "$EVID"
  [ "$after" -gt "$before" ] && result ok "erro registrado em erros.log" || result fail "erro não registrado"
}

t6() {
  section "T6 - Parar, iniciar e reiniciar o serviço de monitoramento"
  systemctl stop citizentech-monitor; say "stop  -> $(systemctl is-active citizentech-monitor)"
  systemctl start citizentech-monitor; sleep 2; say "start -> $(systemctl is-active citizentech-monitor)"
  systemctl restart citizentech-monitor; sleep 2; say "restart-> $(systemctl is-active citizentech-monitor)"
  systemctl is-active --quiet citizentech-monitor && result ok "controle manual do serviço funciona" || result fail "serviço inativo"
  say "systemctl status:"; systemctl status citizentech-monitor --no-pager -n 5 2>&1 | tee -a "$EVID"
}

say "Testes de falha - $(date -Is) - host $(hostname)"
audit "testes de falha" "iniciado"
sel="${1:---all}"
if [ "$sel" = "--all" ]; then t1; t2; t3; t4; t5; t6
else for t in "$@"; do "$(echo "$t" | tr 'A-Z' 'a-z')"; done; fi

section "RESUMO"
say "PASS=$PASS FAIL=$FAIL  | evidência: $EVID"
audit "testes de falha" "concluído PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
