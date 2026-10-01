#!/bin/bash
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if (( $# > 1 )); then
  printf 'Uso: bash run.sh [arquivo de ambiente do agendamento]\n' >&2
  exit 1
fi
if (( $# == 1 )); then
  # Arquivo privado gerado por start.sh para a execução via cron.
  # shellcheck disable=SC1090
  source "$1"
fi
ORACLE_CLIENT_DIR="${ORACLE_CLIENT_DIR:-/opt/oracle/instantclient}"
export LD_LIBRARY_PATH="$ORACLE_CLIENT_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$ORACLE_CLIENT_DIR:$PATH:/usr/local/bundle/bin:/usr/local/bin:/usr/bin:/bin"
cd -- "$APP_DIR"

# Instale as dependências uma vez, durante a preparação do ambiente.
bundle check
exec bundle exec ruby "$APP_DIR/app.rb" -e "${APP_RUBY_ENV:-producao}"
