#!/usr/bin/env bash
# =============================================================================
# 03-install-monitor-service.sh
# Instala o monitoramento como serviço systemd tolerante a falhas.
# Uso: sudo ./scripts/03-install-monitor-service.sh
# =============================================================================
CT_SCRIPT="03-install-monitor-service"
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
CT_LOG_FILE="$LOG_DIR/provisionamento.log"
require_root
enable_error_trap

log INFO "===== Instalação do serviço de monitoramento ====="
has_systemd || die "systemd não está ativo. No WSL2, adicione em /etc/wsl.conf: [boot] systemd=true e rode 'wsl --shutdown' no Windows."

# O serviço roda a partir de /opt/citizentech (cópia estável do repositório)
install_files() {
  mkdir -p "$CT_INSTALL_DIR/scripts/lib" "$CT_INSTALL_DIR/config"
  install -m 755 "$CT_ROOT/scripts/monitor.sh"      "$CT_INSTALL_DIR/scripts/monitor.sh"
  install -m 644 "$CT_ROOT/scripts/lib/common.sh"   "$CT_INSTALL_DIR/scripts/lib/common.sh"
  install -m 644 "$CT_ROOT/config/citizentech.env"  "$CT_INSTALL_DIR/config/citizentech.env"
  install -m 644 "$CT_ROOT/systemd/citizentech-monitor.service"         /etc/systemd/system/
  install -m 644 "$CT_ROOT/systemd/citizentech-monitor-failure.service" /etc/systemd/system/
}
run_step "Copiar scripts e units systemd" install_files

enable_service() {
  systemctl daemon-reload
  systemctl enable citizentech-monitor.service
  systemctl restart citizentech-monitor.service
}
run_step "Habilitar e iniciar citizentech-monitor.service" enable_service

sleep 3
check "serviço de monitoramento ativo" systemctl is-active --quiet citizentech-monitor
check "serviço habilitado no boot"     systemctl is-enabled --quiet citizentech-monitor
check "monitor.log gerado"             test -s "$LOG_DIR/monitor.log"
[ "$CHECK_FAILS" -eq 0 ] || die "Falha na instalação do serviço de monitoramento"

log INFO "Gerenciar: systemctl {start|stop|restart|status} citizentech-monitor"
log INFO "Logs:      journalctl -u citizentech-monitor -f   |   tail -f $LOG_DIR/monitor.log"
audit "instalação serviço monitor" "CONCLUÍDO"
