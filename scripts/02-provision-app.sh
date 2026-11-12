#!/usr/bin/env bash
# =============================================================================
# 02-provision-app.sh
# Instala dependências, publica a aplicação CitizenTech, cria variáveis de
# ambiente, serviço systemd (citizentech-app) e proxy reverso nginx.
# Uso: sudo ./scripts/02-provision-app.sh
# =============================================================================
CT_SCRIPT="02-provision-app"
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
CT_LOG_FILE="$LOG_DIR/provisionamento.log"
require_root
enable_error_trap

REPO_DIR="$CT_ROOT"
log INFO "===== Início do provisionamento da aplicação ====="
audit "início provisionamento app" "iniciado"

# --------------------------------------------------------------------------
# 1) Dependências
# --------------------------------------------------------------------------
install_deps() {
  apt_update
  # shellcheck disable=SC2086
  apt_install curl ca-certificates git python3 nginx procps sysstat stress-ng $EXTRA_PACKAGES
}
run_step "Instalar pacotes e dependências (apt)" install_deps
for p in python3 nginx git curl; do
  command -v "$p" >/dev/null && audit "pacote verificado: $p" "OK" || die "Pacote ausente: $p"
done

# --------------------------------------------------------------------------
# 2) Publicação da aplicação
# --------------------------------------------------------------------------
deploy_app() {
  mkdir -p "$APP_DIR"
  if [ -n "${APP_REPO_URL:-}" ]; then
    log INFO "Clonando aplicação de $APP_REPO_URL (branch $APP_REPO_BRANCH)"
    if [ -d "$APP_DIR/.git" ]; then
      git -C "$APP_DIR" fetch --all -q && git -C "$APP_DIR" reset --hard "origin/$APP_REPO_BRANCH" -q
    else
      rm -rf "${APP_DIR:?}"/* "$APP_DIR"/.[!.]* 2>/dev/null || true
      git clone -q --branch "$APP_REPO_BRANCH" "$APP_REPO_URL" "$APP_DIR"
    fi
  else
    log INFO "APP_REPO_URL vazio: usando aplicação de exemplo (app-sample/)"
    cp -a "$REPO_DIR/app-sample/." "$APP_DIR/"
  fi
  chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
  find "$APP_DIR" -type d -exec chmod 755 {} \;
  find "$APP_DIR" -type f -exec chmod 644 {} \;
}
run_step "Publicar aplicação em $APP_DIR" deploy_app

# Dependências específicas da app (se existirem)
install_app_deps() {
  cd "$APP_DIR"
  if [ -f package.json ]; then
    command -v npm >/dev/null || { apt_update; apt_install nodejs npm; }
    sudo -u "$APP_USER" npm install --omit=dev --no-audit --no-fund
  fi
  if [ -f requirements.txt ]; then
    apt_install python3-venv python3-pip
    sudo -u "$APP_USER" python3 -m venv .venv
    sudo -u "$APP_USER" .venv/bin/pip install -q -r requirements.txt
  fi
}
run_step "Instalar dependências da aplicação" install_app_deps

# --------------------------------------------------------------------------
# 3) Variáveis de ambiente
# --------------------------------------------------------------------------
write_app_env() {
  mkdir -p "$(dirname "$APP_ENV_FILE")"
  cat > "$APP_ENV_FILE" <<EOF
# Gerado por 02-provision-app.sh em $(date -Is)
APP_NAME=${APP_NAME}
APP_PORT=${APP_PORT}
APP_ENV=production
HOST=127.0.0.1
PORT=${APP_PORT}
ASPNETCORE_URLS=http://127.0.0.1:${APP_PORT}
NODE_ENV=production
EOF
  chown root:"$APP_GROUP" "$APP_ENV_FILE"; chmod 640 "$APP_ENV_FILE"
}
run_step "Gerar variáveis de ambiente ($APP_ENV_FILE)" write_app_env

# --------------------------------------------------------------------------
# 4) Serviço systemd da aplicação
# --------------------------------------------------------------------------
install_app_service() {
  # .venv, se existir, tem prioridade no PATH
  APP_PATH="$APP_DIR/.venv/bin:/usr/local/bin:/usr/bin:/bin"
  render_template "$REPO_DIR/systemd/citizentech-app.service.tpl" \
    /etc/systemd/system/citizentech-app.service \
    APP_USER APP_GROUP APP_DIR APP_ENV_FILE APP_START_CMD APP_PATH
  chmod 644 /etc/systemd/system/citizentech-app.service
  if has_systemd; then
    systemctl daemon-reload
    systemctl enable citizentech-app.service
    systemctl restart citizentech-app.service
  else
    log WARN "systemd ausente (WSL sem systemd?). Veja README: habilite [boot] systemd=true."
    return 1
  fi
}
run_step "Instalar e iniciar serviço citizentech-app" install_app_service

# --------------------------------------------------------------------------
# 5) Nginx (proxy reverso :80 -> app)
# --------------------------------------------------------------------------
setup_nginx() {
  render_template "$REPO_DIR/config/nginx-citizentech.conf.tpl" \
    /etc/nginx/sites-available/citizentech DOMAIN_NAME APP_PORT
  ln -sf /etc/nginx/sites-available/citizentech /etc/nginx/sites-enabled/citizentech
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl enable nginx
  systemctl restart nginx
}
run_step "Configurar nginx como proxy reverso" setup_nginx

# --------------------------------------------------------------------------
# 6) Validação final
# --------------------------------------------------------------------------
wait_http() {
  local url="$1" i
  for i in $(seq 1 20); do
    curl -fsS -o /dev/null "$url" && return 0
    sleep 1
  done
  return 1
}
check "serviço citizentech-app ativo" systemctl is-active --quiet citizentech-app
check "serviço nginx ativo" systemctl is-active --quiet nginx
check "app responde em :${APP_PORT}" wait_http "http://127.0.0.1:${APP_PORT}/health"
check "nginx responde em :80" wait_http "http://127.0.0.1/health"

if [ "$CHECK_FAILS" -gt 0 ]; then
  die "Provisionamento terminou com $CHECK_FAILS verificação(ões) falha(s). Veja $LOG_DIR/execucao.log"
fi
log INFO "Aplicação disponível em http://$(hostname -I 2>/dev/null | awk '{print $1}')/ (ou http://localhost/)"
log INFO "===== Provisionamento da aplicação concluído ====="
audit "provisionamento app" "CONCLUÍDO"
