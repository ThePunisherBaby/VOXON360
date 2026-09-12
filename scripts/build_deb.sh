#!/usr/bin/env bash
# Empaqueta el build de Linux en un .deb para Debian/Ubuntu.
#
# Requisitos: Linux con dpkg-deb, y haber ejecutado antes
#   flutter build linux --release
# Uso:
#   scripts/build_deb.sh
set -euo pipefail

APP_NAME="voxon90"
APP_DISPLAY_NAME="VOXON90"
APP_ID="com.voxon90.voxon90"  # debe coincidir con APPLICATION_ID en linux/CMakeLists.txt
MAINTAINER="VOXON90 <contacto@example.com>"  # TODO: poner el contacto real
DESCRIPTION="VOXON90 - aplicación multiplataforma"

cd "$(dirname "$0")/.."

VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
DEB_ARCH="$(dpkg --print-architecture)"
case "$DEB_ARCH" in
  amd64) FLUTTER_ARCH="x64" ;;
  arm64) FLUTTER_ARCH="arm64" ;;
  *) echo "Arquitectura no soportada: $DEB_ARCH" >&2; exit 1 ;;
esac

BUNDLE_DIR="build/linux/${FLUTTER_ARCH}/release/bundle"
if [[ ! -x "${BUNDLE_DIR}/${APP_NAME}" ]]; then
  echo "No se encontró ${BUNDLE_DIR}/${APP_NAME}." >&2
  echo "Ejecuta primero: flutter build linux --release" >&2
  exit 1
fi

PKG_DIR="build/deb/${APP_NAME}_${VERSION}_${DEB_ARCH}"
rm -rf "$PKG_DIR"
mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/opt/$APP_NAME" \
  "$PKG_DIR/usr/bin" \
  "$PKG_DIR/usr/share/applications" \
  "$PKG_DIR/usr/share/icons/hicolor/256x256/apps"

# Binario, librerías y assets en /opt; enlace en /usr/bin para lanzarlo por nombre.
cp -r "$BUNDLE_DIR"/. "$PKG_DIR/opt/$APP_NAME/"
ln -s "/opt/$APP_NAME/$APP_NAME" "$PKG_DIR/usr/bin/$APP_NAME"

cp macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png \
  "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"

# El nombre del .desktop coincide con el APPLICATION_ID para que el escritorio
# asocie la ventana abierta con su icono.
cat > "$PKG_DIR/usr/share/applications/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_DISPLAY_NAME}
Exec=/opt/${APP_NAME}/${APP_NAME}
Icon=${APP_ID}
Categories=Utility;
Terminal=false
StartupWMClass=${APP_ID}
EOF

INSTALLED_SIZE="$(du -sk "$PKG_DIR" | cut -f1)"
cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: ${APP_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${DEB_ARCH}
Maintainer: ${MAINTAINER}
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0t64 | libgtk-3-0
Description: ${DESCRIPTION}
EOF

dpkg-deb --build --root-owner-group "$PKG_DIR"
echo "Paquete generado: ${PKG_DIR}.deb"
