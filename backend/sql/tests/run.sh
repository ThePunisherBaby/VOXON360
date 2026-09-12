#!/usr/bin/env bash
# Pruebas del esquema SQL con el cliente sqlite3 (sin compilar nada).
#
#   backend/sql/tests/run.sh            usa el sqlite3 del sistema
#   SQLITE3=/ruta/sqlite3 run.sh        usa otro binario
#
# 1. Carga migraciones + datos de ejemplo.
# 2. assertions.sql: resultados que deben cumplirse.
# 3. expected_errors.sql: operaciones que la base debe rechazar.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MIGRATIONS="$HERE/../migrations"
SQLITE="${SQLITE3:-sqlite3}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

run_sql() { # run_sql <db> < sql
  { echo "PRAGMA foreign_keys = ON;"; cat; } | "$SQLITE" -bail "$1"
}

failures=0
base="$WORK/base.db"
cat "$MIGRATIONS"/*.sql "$HERE/fixtures.sql" | run_sql "$base"

echo "== Resultados esperados"
cp "$base" "$WORK/assertions.db"
report="$(run_sql "$WORK/assertions.db" < "$HERE/assertions.sql")"
echo "$report"
if grep -q '^FALLA' <<< "$report"; then
  failures=$((failures + 1))
fi

echo "== Operaciones que deben rechazarse"
awk -v dir="$WORK" '
  /^-- case: / {
    count++
    file = sprintf("%s/case_%03d.sql", dir, count)
    meta = $0
    sub(/^-- case: /, "", meta)
    print meta > (file ".meta")
    next
  }
  count > 0 { print > file }
' "$HERE/expected_errors.sql"

for case_file in "$WORK"/case_*.sql; do
  meta="$(cat "$case_file.meta")"
  name="${meta%% => *}"
  expected="${meta##* => }"
  cp "$base" "$WORK/case.db"
  if error="$(run_sql "$WORK/case.db" < "$case_file" 2>&1 >/dev/null)"; then
    echo "FALLA  $name: no dio error (esperaba '$expected')"
    failures=$((failures + 1))
  elif [[ "$error" != *"$expected"* ]]; then
    echo "FALLA  $name: $error"
    failures=$((failures + 1))
  else
    echo "ok     $name"
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "$failures grupo(s) con fallas"
  exit 1
fi
echo "Todas las pruebas SQL pasaron"
