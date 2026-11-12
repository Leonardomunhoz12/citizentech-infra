#!/usr/bin/env bash
# =============================================================================
# 01-provision-infra.sh
# Provisiona a infraestrutura: hostname, rede/IP, DNS, usuários e diretórios.
# Idempotente. Funciona em VM (Azure/local) e WSL2 (aplica o que o ambiente permite).
# Uso: sudo ./scripts/01-provision-infra.sh
# =============================================================================
CT_SCRIPT="01-provision-infra"
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
CT_LOG_FILE="$LOG_DIR/provisionamento.log"
require_root
enable_error_trap

log INFO "===== Início do provisionamento de infraestrutura ====="
log INFO "Equipe: ${TEAM_MEMBERS:-não informada}"
audit "início provisionamento infra" "iniciado"

# --------------------------------------------------------------------------
# 1) Hostname
# --------------------------------------------------------------------------
set_hostname() {
  local fqdn="${HOSTNAME_FQDN}"
  if command -v hostnamectl >/dev/null 2>&1 && has_systemd; then
    hostnamectl set-hostname "$fqdn"
  else
    echo "$fqdn" > /etc/hostname
    hostname "$fqdn"
  fi
  # /etc/hosts: mapeia nome curto e FQDN para 127.0.1.1
  sed -i '/^127\.0\.1\.1 /d' /etc/hosts
  echo "127.0.1.1 ${fqdn}.${DOMAIN_NAME} ${fqdn}" >> /etc/hosts
  grep -q 'localhost' /etc/hosts || echo "127.0.0.1 localhost" >> /etc/hosts
  # WSL: persiste hostname entre reinícios
  if is_wsl; then wsl_conf_set network hostname "$fqdn"; fi
}
run_step "Configurar hostname (${HOSTNAME_FQDN})" set_hostname

# --------------------------------------------------------------------------
# 2) Rede / IP
# --------------------------------------------------------------------------
detect_iface() {
  if [ "${NET_IFACE}" != "auto" ]; then echo "$NET_IFACE"; return; fi
  ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}'
}

configure_network() {
  local iface; iface="$(detect_iface)"
  [ -n "$iface" ] || { log WARN "Interface de rede não detectada; pulando."; return 0; }
  log INFO "Interface: $iface | modo: ${NET_MODE}"

  if is_wsl; then
    log WARN "WSL2 detectado: IP é gerenciado pelo Windows (NAT). IP atual: $(hostname -I 2>/dev/null | awk '{print $1}')"
    return 0
  fi

  if [ "${NET_MODE}" = "static" ]; then
    if command -v netplan >/dev/null 2>&1; then
      local f=/etc/netplan/60-citizentech.yaml
      backup_file "$f"
      cat > "$f" <<EOF
# Gerado por 01-provision-infra.sh
network:
  version: 2
  ethernets:
    ${iface}:
      dhcp4: false
      addresses: [${STATIC_IP}]
      routes:
        - to: default
          via: ${STATIC_GATEWAY}
      nameservers:
        addresses: [$(echo "$DNS_SERVERS" | sed 's/ /, /g')]
EOF
      chmod 600 "$f"
      netplan generate
      log WARN "Netplan gerado. Aplique com 'sudo netplan apply' (pode derrubar sessão SSH)."
      [ "${APPLY_NETPLAN:-no}" = "yes" ] && netplan apply
    else
      log WARN "netplan indisponível; configure manualmente (ip addr add ${STATIC_IP} dev ${iface})."
    fi
  else
    log INFO "Modo DHCP mantido (recomendado em Azure/VirtualBox NAT)."
  fi
}
run_step "Configurar endereçamento IP/rede" configure_network

# --------------------------------------------------------------------------
# 3) DNS e resolução de nomes
# --------------------------------------------------------------------------
configure_dns() {
  if is_wsl; then
    wsl_conf_set network generateResolvConf false
    rm -f /etc/resolv.conf
    { echo "# Gerado por 01-provision-infra.sh"
      for s in $DNS_SERVERS; do echo "nameserver $s"; done
      echo "search ${DOMAIN_NAME}"; } > /etc/resolv.conf
  elif has_systemd && systemctl is-active --quiet systemd-resolved; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat > /etc/systemd/resolved.conf.d/citizentech.conf <<EOF
[Resolve]
DNS=${DNS_SERVERS}
Domains=${DOMAIN_NAME}
EOF
    systemctl restart systemd-resolved
  else
    backup_file /etc/resolv.conf
    { for s in $DNS_SERVERS; do echo "nameserver $s"; done
      echo "search ${DOMAIN_NAME}"; } > /etc/resolv.conf
  fi
  # Nome do próprio serviço resolvível localmente
  grep -q "app.${DOMAIN_NAME}" /etc/hosts || echo "127.0.0.1 app.${DOMAIN_NAME}" >> /etc/hosts
}
run_step "Configurar DNS (${DNS_SERVERS})" configure_dns

validate_dns() {
  getent hosts "app.${DOMAIN_NAME}" >/dev/null &&
  { getent hosts github.com >/dev/null || { log WARN "Sem resolução externa (offline?)"; return 0; }; }
}
run_step "Validar resolução de nomes" validate_dns

# --------------------------------------------------------------------------
# 4) Usuários, grupos e diretórios
# --------------------------------------------------------------------------
setup_users_dirs() {
  getent group "$APP_GROUP" >/dev/null || groupadd --system "$APP_GROUP"
  id "$APP_USER" >/dev/null 2>&1 || \
    useradd --system --gid "$APP_GROUP" --home-dir "$CT_INSTALL_DIR" --shell /usr/sbin/nologin "$APP_USER"

  mkdir -p "$CT_INSTALL_DIR" "$APP_DIR" "$CT_INSTALL_DIR/bin" "$LOG_DIR" /etc/citizentech
  chown -R "$APP_USER:$APP_GROUP" "$CT_INSTALL_DIR"
  chmod 755 "$CT_INSTALL_DIR"
  chmod 750 /etc/citizentech && chown root:"$APP_GROUP" /etc/citizentech
  # Logs: root escreve (monitor), grupo da app lê
  chown root:"$APP_GROUP" "$LOG_DIR"; chmod 775 "$LOG_DIR"
  find "$LOG_DIR" -type f -exec chmod 664 {} \; 2>/dev/null || true
}
run_step "Criar usuário '${APP_USER}', diretórios e permissões" setup_users_dirs

# Logrotate para os logs da infra
setup_logrotate() {
  cat > /etc/logrotate.d/citizentech <<EOF
${LOG_DIR}/*.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    copytruncate
}
EOF
}
run_step "Configurar rotação de logs" setup_logrotate

log INFO "===== Provisionamento de infraestrutura concluído ====="
audit "provisionamento infra" "CONCLUÍDO"
