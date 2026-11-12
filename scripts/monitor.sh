#!/usr/bin/env bash
# =============================================================================
# monitor.sh - monitoramento de CPU, memória RAM e disco com alertas.
#
# Uso:
#   monitor.sh --once          # uma verificação e sai (código 0=OK, 2=alerta)
#   monitor.sh --daemon        # loop contínuo a cada CHECK_INTERVAL s (usado pelo systemd)
#   monitor.sh --fail-test     # provoca uma falha controlada e verifica o log de erros
#
# Limites (CPU_THRESHOLD, MEM_THRESHOLD, DISK_THRESHOLD, CHECK_INTERVAL) vêm de
# config/citizentech.env e podem ser sobrescritos por variáveis de ambiente.
# Logs: $LOG_DIR/monitor.log (todas as verificações), alertas.log, erros.log,
#       auditoria.log
# =============================================================================
CT_SCRIPT="monitor"
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
CT_LOG_FILE="$LOG_DIR/monitor.log"
ALERT_LOG="$LOG_DIR/alertas.log"

: "${CPU_THRESHOLD:=80}" "${MEM_THRESHOLD:=80}" "${DISK_THRESHOLD:=85}"
: "${CHECK_INTERVAL:=30}" "${CPU_SAMPLE_SECONDS:=2}" "${MONITOR_DISK_PATH:=/}"

# --------------------------------------------------------------------------
# Coletas (retornam inteiro 0-100)
# --------------------------------------------------------------------------
get_cpu() {
  local u1 n1 s1 i1 w1 q1 sq1 st1 u2 n2 s2 i2 w2 q2 sq2 st2 t1 t2 dt di
  read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
  sleep "$CPU_SAMPLE_SECONDS"
  read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
  t1=$((u1+n1+s1+i1+w1+q1+sq1+st1)); t2=$((u2+n2+s2+i2+w2+q2+sq2+st2))
  dt=$((t2-t1)); di=$(( (i2+w2) - (i1+w1) ))
  [ "$dt" -gt 0 ] || { echo 0; return; }
  echo $(( (100 * (dt - di)) / dt ))
}

get_mem() {  # imprime: pct_usado total_MB disponivel_MB
  awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{
    if (t==0) {print "0 0 0"; exit}
    printf "%d %d %d\n", (t-a)*100/t, t/1024, a/1024 }' /proc/meminfo
}

get_disk() {  # imprime: pct_usado usado total
  df -P -h "$MONITOR_DISK_PATH" | awk 'NR==2{gsub("%","",$5); print $5, $3, $2}'
}

# --------------------------------------------------------------------------
# Alertas
# --------------------------------------------------------------------------
alert() {  # alert RECURSO VALOR LIMITE
  local msg="ALERTA: consumo elevado de $1 = $2% (limite $3%)"
  printf '%s [ALERTA] %s\n' "$(_ts)" "$msg" >> "$ALERT_LOG"
  log WARN "$msg"
  audit "alerta $1" "$2% > $3%"
}

# --------------------------------------------------------------------------
# Uma verificação completa
# --------------------------------------------------------------------------
check_once() {
  local cpu mem_pct mem_tot mem_av disk_pct disk_used disk_tot alerts=0
  cpu="$(get_cpu)"
  read -r mem_pct mem_tot mem_av <<<"$(get_mem)"
  read -r disk_pct disk_used disk_tot <<<"$(get_disk)"

  log INFO "CHECK cpu=${cpu}% mem=${mem_pct}% (livre ${mem_av}MB de ${mem_tot}MB) disco=${disk_pct}% (${disk_used}/${disk_tot}) load=$(cut -d' ' -f1-3 /proc/loadavg)"

  [ "$cpu"      -ge "$CPU_THRESHOLD"  ] && { alert CPU  "$cpu"      "$CPU_THRESHOLD";  alerts=$((alerts+1)); }
  [ "$mem_pct"  -ge "$MEM_THRESHOLD"  ] && { alert RAM  "$mem_pct"  "$MEM_THRESHOLD";  alerts=$((alerts+1)); }
  [ "$disk_pct" -ge "$DISK_THRESHOLD" ] && { alert DISCO "$disk_pct" "$DISK_THRESHOLD"; alerts=$((alerts+1)); }

  # Saúde dos serviços da aplicação
  if has_systemd; then
    local s
    for s in citizentech-app nginx; do
      if systemctl list-unit-files "$s.service" >/dev/null 2>&1 && \
         systemctl cat "$s.service" >/dev/null 2>&1; then
        if ! systemctl is-active --quiet "$s"; then
          log ERROR "Serviço $s INATIVO"
          alerts=$((alerts+1))
        fi
      fi
    done
  fi
  [ "$alerts" -eq 0 ] && return 0 || return 2
}

# --------------------------------------------------------------------------
# Teste de falha controlada (comprova registro de erros nos logs)
# --------------------------------------------------------------------------
fail_test() {
  log INFO "Iniciando falha controlada (comando inexistente)"
  enable_error_trap
  this_command_does_not_exist_ct_test
}

# --------------------------------------------------------------------------
# Notificações systemd (watchdog) - ignoradas fora do systemd
# --------------------------------------------------------------------------
notify() { command -v systemd-notify >/dev/null 2>&1 && [ -n "${NOTIFY_SOCKET:-}" ] && systemd-notify "$@" || true; }

daemon_loop() {
  log INFO "Daemon iniciado (intervalo=${CHECK_INTERVAL}s cpu>=${CPU_THRESHOLD} mem>=${MEM_THRESHOLD} disco>=${DISK_THRESHOLD})"
  audit "monitor iniciado" "daemon pid=$$"
  trap 'log INFO "SIGTERM recebido: encerrando monitor"; audit "monitor parado" "SIGTERM"; exit 0' TERM INT
  notify --ready --status="monitorando"
  while true; do
    check_once || true
    notify WATCHDOG=1 --status="última verificação $(date +%T)"
    sleep "$CHECK_INTERVAL" & wait $!
  done
}

case "${1:---once}" in
  --once)      check_once; rc=$?; exit $rc ;;
  --daemon)    daemon_loop ;;
  --fail-test) fail_test ;;
  -h|--help)   sed -n '2,13p' "$0" ;;
  *)           echo "Uso: $0 [--once|--daemon|--fail-test]" >&2; exit 64 ;;
esac
