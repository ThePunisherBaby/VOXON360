#!/usr/bin/env bash
# Compila y prueba el backend local completo: SQL, motor C++, servidor Java y
# cliente web. Funciona en Linux (Debian/Ubuntu) y macOS; en Windows usa
# scripts/build-backend.ps1.
#
#   scripts/build-backend.sh                 Release y todas las pruebas
#   BUILD_TYPE=Debug scripts/build-backend.sh
#   SKIP_WEB_TESTS=1 scripts/build-backend.sh  sin Node.js
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
BUILD_TYPE="${BUILD_TYPE:-Release}"
CORE_BUILD="$BACKEND/core/build"

step() {
  printf '\n== %s\n' "$1"
}

step "Pruebas del esquema SQL"
if command -v sqlite3 >/dev/null 2>&1; then
  "$BACKEND/sql/tests/run.sh"
else
  echo "sqlite3 no está instalado; se omiten (el motor C++ las cubre igual)"
fi

step "Motor C++ ($BUILD_TYPE)"
generator=()
if command -v ninja >/dev/null 2>&1 && [[ ! -f "$CORE_BUILD/CMakeCache.txt" ]]; then
  generator=(-G Ninja)
fi
cmake -S "$BACKEND/core" -B "$CORE_BUILD" ${generator[@]+"${generator[@]}"} -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
cmake --build "$CORE_BUILD" --config "$BUILD_TYPE" --parallel
ctest --test-dir "$CORE_BUILD" --build-config "$BUILD_TYPE" --output-on-failure

step "Servidor Java"
(cd "$BACKEND/server" && ./gradlew test installDist --console=plain -PvoxonCoreDir="$CORE_BUILD")

step "Cliente web"
if [[ -z "${SKIP_WEB_TESTS:-}" ]] && command -v node >/dev/null 2>&1; then
  (cd "$BACKEND/web" && npm test)
else
  echo "Node.js no está disponible; se omiten las pruebas web"
fi

step "Listo"
echo "Inicia el servidor con:"
echo "  $BACKEND/server/build/install/voxon-server/bin/voxon-server"
