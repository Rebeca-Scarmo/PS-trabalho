#!/usr/bin/env bash
# Uso: ./run_tests.sh [nome_do_banco]    (requer PostgreSQL 16 em execução e usuário com permissão de criar banco)
set -euo pipefail
DB="${1:-sgf_u2}"
cd "$(dirname "$0")"
# descarte de saída: NUL no Windows (Git Bash), /dev/null nos demais
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) NULO=NUL ;; *) NULO=/dev/null ;; esac
dropdb --if-exists "$DB" && createdb "$DB"
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f 01_schema.sql
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f 02_triggers.sql
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f 03_seed.sql
echo "=== Testes de componente e de sistema ==="
psql -q -v nulo="$NULO" -d "$DB" -f tests/01_testes.sql
echo "=== DECIMAL x FLOAT ==="
psql -q -d "$DB" -f tests/02_decimal_vs_float.sql
