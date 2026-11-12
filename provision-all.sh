#!/usr/bin/env bash
# =============================================================================
# provision-all.sh - executa TODO o provisionamento em ordem, com um comando.
# Uso: sudo ./provision-all.sh
# =============================================================================
set -Eeuo pipefail
cd "$(dirname "$(readlink -f "$0")")"
[ "$(id -u)" -eq 0 ] || { echo "Execute com sudo."; exit 1; }
chmod +x scripts/*.sh
./scripts/01-provision-infra.sh
./scripts/02-provision-app.sh
./scripts/03-install-monitor-service.sh
echo
echo "Ambiente pronto. Acesse http://localhost/  |  Teste de falhas: sudo ./scripts/04-failure-tests.sh"
