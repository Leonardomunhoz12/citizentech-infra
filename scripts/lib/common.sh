#!/usr/bin/env bash
# =============================================================================
# lib/common.sh - funções compartilhadas: log, auditoria, validações, templates
# Uso: source "$(dirname "$0")/lib/common.sh"
# =============================================================================
shopt -u patsub_replacement 2>/dev/null || true
set -o pipefail

CT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CT_ROOT="${CT_ROOT:-$(cd "$CT_LIB_DIR/../.." && pwd)}"
ENV_FILE="${ENV_FILE:-$CT_ROOT/config/citizentech.env}"

# Carrega o arquivo de configuração SEM sobrescrever variáveis já definidas no
# ambiente (permite: sudo CPU_THRESHOLD=10 ./monitor.sh --once).
if [ -f "$ENV_FILE" ]; then
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in ''|'#'*|';'*) continue ;; esac
    _key="${_line%%=*}"
    if [[ "$_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ -z "${!_key+x}" ]; then
      eval "export $_line"
    fi
  done < "$ENV_FILE"
  unset _line _key
fi

: "${LOG_DIR:=/var/log/citizentech}"
: "${CT_INSTALL_DIR:=/opt/citizentech}"

# Se não for possível escrever em LOG_DIR (execução sem root), usa ./logs
if ! mkdir -p "$LOG_DIR" 2>/dev/null || [ ! -w "$LOG_DIR" ]; then
  LOG_DIR="$CT_ROOT/logs"
  mkdir -p "$LOG_DIR"
fi
AUDIT_LOG="$LOG_DIR/auditoria.log"
RAW_LOG="$LOG_DIR/saida_comandos.log"

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
_ts() { date '+%Y-%m-%d %H:%M:%S%z'; }
_prio() { case "$1" in ERROR) echo err ;; WARN) echo warning ;; *) echo info ;; esac; }

# log NIVEL mensagem...   (NIVEL: INFO | WARN | ERROR)
log() {
  local level="$1"; shift
  local who="${CT_SCRIPT:-$(basename "$0")}"
  local line
  line="$(_ts) [$level] [$who] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "${CT_LOG_FILE:-$LOG_DIR/execucao.log}" 2>/dev/null || true
  if [ "$level" = "ERROR" ]; then
    printf '%s\n' "$line" >> "$LOG_DIR/erros.log" 2>/dev/null || true
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t citizentech -p "user.$(_prio "$level")" -- "[$who] $*" 2>/dev/null || true
  fi
}

# audit "ação" "resultado"  -> o que foi feito, por quem, quando e com que resultado
audit() {
  printf '%s user=%s host=%s script=%s acao="%s" resultado="%s"\n' \
    "$(_ts)" "$(id -un 2>/dev/null || echo '?')" "$(hostname 2>/dev/null || echo '?')" \
    "${CT_SCRIPT:-$(basename "$0")}" "$1" "$2" >> "$AUDIT_LOG" 2>/dev/null || true
}

die() { log ERROR "$*"; audit "abortado" "ERRO: $*"; exit 1; }

# run_step "descrição" comando args...  -> executa, mede, registra OK/FALHA + auditoria
run_step() {
  local desc="$1"; shift
  local t0=$SECONDS
  log INFO "INÍCIO: $desc"
  if "$@" 2>&1 | tee -a "$RAW_LOG"; then
    log INFO "OK: $desc ($((SECONDS - t0))s)"
    audit "$desc" "OK"
    return 0
  else
    log ERROR "FALHA: $desc ($((SECONDS - t0))s)"
    audit "$desc" "FALHA"
    return 1
  fi
}

# Trap de erro: registra linha, comando e código de saída nos logs
_on_err() {
  local rc=$1 line=$2 cmd=$3
  trap - ERR
  log ERROR "Falha (exit=$rc) na linha $line: $cmd"
  audit "falha em ${CT_SCRIPT:-script}" "ERRO exit=$rc linha=$line"
  exit "$rc"
}
enable_error_trap() {
  set -Eeuo pipefail
  trap '_on_err $? $LINENO "$BASH_COMMAND"' ERR
}

# check "descrição" comando... -> PASS/FAIL (usado em validações)
CHECK_FAILS=0
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    log INFO "PASS: $desc"
  else
    log WARN "FAIL: $desc"
    CHECK_FAILS=$((CHECK_FAILS + 1))
  fi
}

# ----------------------------------------------------------------------------
# Utilidades
# ----------------------------------------------------------------------------
require_root() { [ "$(id -u)" -eq 0 ] || die "Execute como root (use sudo)."; }
is_wsl() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }
has_systemd() { [ -d /run/systemd/system ]; }
is_cloud_vm() { [ -d /var/lib/waagent ] || command -v cloud-init >/dev/null 2>&1; }

backup_file() { [ -e "$1" ] && cp -a "$1" "$1.bak.$(date +%Y%m%d%H%M%S)" || true; }

apt_update()  { DEBIAN_FRONTEND=noninteractive apt-get update -qq; }
apt_install() { DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"; }

# render_template TEMPLATE DESTINO VAR1 VAR2 ...  (substitui @VAR@ pelo valor)
render_template() {
  local tpl="$1" dest="$2"; shift 2
  local content v
  content="$(cat "$tpl")"
  for v in "$@"; do
    content="${content//@${v}@/${!v}}"
  done
  printf '%s\n' "$content" > "$dest"
}

# wsl_conf_set SECAO CHAVE VALOR  (edita /etc/wsl.conf)
wsl_conf_set() {
  local sec="$1" key="$2" val="$3" f=/etc/wsl.conf
  touch "$f"
  grep -q "^\[$sec\]" "$f" || printf '\n[%s]\n' "$sec" >> "$f"
  if sed -n "/^\[$sec\]/,/^\[/p" "$f" | grep -q "^$key *="; then
    sed -i "/^\[$sec\]/,/^\[/ s|^$key *=.*|$key=$val|" "$f"
  else
    sed -i "/^\[$sec\]/a $key=$val" "$f"
  fi
}
