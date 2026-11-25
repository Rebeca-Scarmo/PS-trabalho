#!/usr/bin/env bash
# Uso: ./criar_banco.sh [nome_do_banco]   — cria o banco com esquema, gatilhos e carga de exemplo (sem rodar os testes)
set -euo pipefail
DB="${1:-sgf_u2}"
cd "$(dirname "$0")"
dropdb --if-exists "$DB" && createdb "$DB"
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f 01_schema.sql
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f 02_triggers.sql
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f 03_seed.sql
echo "Banco $DB pronto."
