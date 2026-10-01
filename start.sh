#!/bin/bash
set -euo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$PATH:/usr/local/bundle/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
cd -- "$APP_DIR"

command -v crontab >/dev/null
command -v cron >/dev/null
bundle check

# Cron não herda todas as variáveis do processo que inicia o serviço.
# Gere um arquivo privado, sem colocar credenciais no comando do crontab.
mkdir -p -- "$APP_DIR/tmp"
CRON_ENV_FILE="$APP_DIR/tmp/cron.env"
CRON_ENV_TEMP="$(mktemp "$APP_DIR/tmp/cron.env.XXXXXX")"
trap 'rm -f -- "$CRON_ENV_TEMP"' EXIT
while IFS= read -r ENV_NAME; do
  case "$ENV_NAME" in
    APP_RUBY_ENV|ORACLE_*|NLS_LANG|TNS_ADMIN|PATH|LD_LIBRARY_PATH|GEM_HOME|GEM_PATH|RUBYOPT|RUBYLIB|BUNDLE_*)
      declare -px "$ENV_NAME"
      ;;
  esac
done < <(compgen -e) > "$CRON_ENV_TEMP"
mv -f -- "$CRON_ENV_TEMP" "$CRON_ENV_FILE"
trap - EXIT

# Preserve as demais tarefas e substitua somente a entrada deste projeto.
EXISTING_CRONTAB="$(LC_ALL=C crontab -l 2>&1)" || {
  if [[ "$EXISTING_CRONTAB" == *'no crontab for'* ]]; then
    EXISTING_CRONTAB=''
  else
    printf '%s\n' "$EXISTING_CRONTAB" >&2
    exit 1
  fi
}

printf -v CRON_JOB '0 * * * * /bin/bash %q %q >> %q 2>&1 # ruby-oracle-dao-app' \
  "$APP_DIR/run.sh" "$CRON_ENV_FILE" "$APP_DIR/log.txt"
# Cron trata percentuais como separadores mesmo dentro de aspas.
CRON_JOB="${CRON_JOB//%/\\%}"
{
  printf '%s\n' "$EXISTING_CRONTAB" | awk '!/ # ruby-oracle-dao-app$/ && NF'
  printf '%s\n' "$CRON_JOB"
} | crontab -

/bin/bash "$APP_DIR/run.sh" "$CRON_ENV_FILE"
# Script destinado a contêiner dedicado com cron instalado.
exec cron -f
