#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# build.sh  —  Compila + empacota vcamoverlay + vcamrootless em um único .deb
# Pré-requisitos: Theos instalado em $THEOS (default: ~/theos)
# Uso:  chmod +x build.sh && ./build.sh
# ─────────────────────────────────────────────────────────────────────────────
set -e

THEOS="${THEOS:-$HOME/theos}"

if [ ! -d "$THEOS" ]; then
    echo "❌ Theos não encontrado em $THEOS"
    echo "   Instale: https://theos.dev/docs/installation"
    exit 1
fi

echo "► Limpando builds anteriores..."
make clean 2>/dev/null || true

echo "► Compilando tweak..."
make package FINALPACKAGE=1 PACKAGE_FORMAT=deb

echo ""
echo "✅ .deb gerado em: packages/"
ls -lh packages/*.deb 2>/dev/null || ls -lh *.deb 2>/dev/null
