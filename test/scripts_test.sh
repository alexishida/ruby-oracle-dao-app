#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"
cp "$PROJECT_DIR"/test/fixtures/bin/* "$TEST_DIR/bin/"
chmod +x "$TEST_DIR"/bin/*
SOURCE_DIR="$PROJECT_DIR"
PROJECT_DIR="$TEST_DIR/app with 100% spaces"
mkdir -p "$PROJECT_DIR"
cp "$SOURCE_DIR/run.sh" "$SOURCE_DIR/start.sh" "$SOURCE_DIR/app.rb" "$PROJECT_DIR/"
export PATH="$TEST_DIR/bin:$PATH"
export TEST_BIN="$TEST_DIR/bin"
export TEST_CALLS="$TEST_DIR/calls"
export TEST_CRONTAB="$TEST_DIR/crontab"
export ORACLE_CLIENT_DIR="$TEST_DIR/oracle"
export LD_LIBRARY_PATH='/existing/library'
unset APP_RUBY_ENV

assert_contains() {
  if ! grep -Fq -- "$2" "$1"; then
    printf 'Expected %s to contain: %s\n' "$1" "$2" >&2
    exit 1
  fi
}

# Executa fora do diretório do projeto, preservando o caminho de bibliotecas.
cd "$TEST_DIR"
bash "$PROJECT_DIR/run.sh"
assert_contains "$TEST_CALLS" "cwd=$PROJECT_DIR"
assert_contains "$TEST_CALLS" "ld=$ORACLE_CLIENT_DIR:/existing/library"
assert_contains "$TEST_CALLS" ' -e producao'
export APP_RUBY_ENV=desenvolvimento
bash "$PROJECT_DIR/run.sh"
assert_contains "$TEST_CALLS" ' -e desenvolvimento'

# Falha na verificação das gems interrompe a execução da aplicação.
: > "$TEST_CALLS"
if TEST_BUNDLE_STATUS=1 bash "$PROJECT_DIR/run.sh"; then
  printf 'run.sh should fail when dependencies are missing\n' >&2
  exit 1
fi
if grep -Fq 'bundle exec' "$TEST_CALLS"; then
  printf 'Application ran after dependency failure\n' >&2
  exit 1
fi

# Cron é substituído apenas para a entrada identificada deste projeto.
printf '15 * * * * echo keep-me\n' > "$TEST_CRONTAB"
bash "$PROJECT_DIR/start.sh"
bash "$PROJECT_DIR/start.sh"
assert_contains "$TEST_CRONTAB" '15 * * * * echo keep-me'
[[ "$(grep -Fc '# ruby-oracle-dao-app' "$TEST_CRONTAB")" == 1 ]]
assert_contains "$TEST_CRONTAB" ' >> '
assert_contains "$TEST_CRONTAB" ' 2>&1 '
assert_contains "$TEST_CALLS" 'cron -f'

# Primeiro uso sem crontab e erro de permissão são tratados separadamente.
TEST_CRONTAB_ERROR='no crontab for test-user' bash "$PROJECT_DIR/start.sh"
[[ "$(grep -Fc '# ruby-oracle-dao-app' "$TEST_CRONTAB")" == 1 ]]
printf '15 * * * * echo keep-me\n' > "$TEST_CRONTAB"
if TEST_CRONTAB_ERROR='permission denied' bash "$PROJECT_DIR/start.sh" 2>/dev/null; then
  printf 'start.sh should fail on crontab permission errors\n' >&2
  exit 1
fi
[[ "$(cat "$TEST_CRONTAB")" == '15 * * * * echo keep-me' ]]

# A execução agendada parte de um ambiente vazio, como ocorre no cron.
export ORACLE_HOST='fake host with spaces and 100%'
export TEST_EXPECT_ORACLE_HOST="$ORACLE_HOST"
export TEST_RUN_SCHEDULED=1
bash "$PROJECT_DIR/start.sh"
[[ -f "$PROJECT_DIR/tmp/cron.env" ]]
[[ "$(stat -c '%a' "$PROJECT_DIR/tmp/cron.env")" == 600 ]]
[[ -f "$PROJECT_DIR/log.txt" ]]

printf 'Shell regressions: OK (no real cron or database used)\n'
