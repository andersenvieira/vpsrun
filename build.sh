#!/usr/bin/env bash
###############################################################################
# build.sh — compila os binários e monta o Kit Portátil do vpsrun.
#
#   ./build.sh              compila para o SO atual (linux/amd64) + kit
#   ./build.sh all          cross-compila linux e windows (amd64)
#   ./build.sh clean        remove dist/
#
# Saídas em dist/:
#   vpsrun / vpsrun-audit (e .exe para windows)
#   vpsrun-kit-<versao>-<os>-<arch>.tar.zst  (binários + scripts + ansible + spec)
#
# O Kit contém APENAS código/artefatos — NUNCA segredos. Cofre e backups vão
# cifrados para o Google Drive, separados do repositório (ver design.md).
###############################################################################
set -euo pipefail
cd "$(dirname "$0")"
export GOTOOLCHAIN=local

VERSION="$(grep -oE 'Version = "[^"]+"' internal/core/paths.go | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "$VERSION" ] || VERSION="dev"
DIST="dist"

pack() { # $1=os $2=arch $3=ext
  local os="$1" arch="$2" ext="${3:-}"
  echo ">> compilando $os/$arch"
  GOOS="$os" GOARCH="$arch" go build -trimpath -ldflags "-s -w" -o "$DIST/vpsrun$ext" ./cmd/vpsrun
  GOOS="$os" GOARCH="$arch" go build -trimpath -ldflags "-s -w" -o "$DIST/vpsrun-audit$ext" ./cmd/vpsrun-audit

  local staging="$DIST/kit-$os-$arch"
  rm -rf "$staging"; mkdir -p "$staging"
  cp "$DIST/vpsrun$ext" "$DIST/vpsrun-audit$ext" "$staging/"
  cp -r scripts ansible "$staging/" 2>/dev/null || true
  mkdir -p "$staging/docs"; cp MANUAL.md "$staging/docs/" 2>/dev/null || true
  cp -r .kiro "$staging/" 2>/dev/null || true

  local kit="$DIST/vpsrun-kit-$VERSION-$os-$arch.tar.zst"
  if command -v zstd >/dev/null 2>&1; then
    tar -C "$staging" -cf - . | zstd -19 -q -f -o "$kit"
  else
    kit="${kit%.zst}.gz"; echo "   (zstd ausente — usando gzip)"
    tar -C "$staging" -czf "$kit" .
  fi
  rm -rf "$staging"
  echo "   kit: $kit ($(du -h "$kit" | cut -f1))"
}

case "${1:-current}" in
  clean) rm -rf "$DIST"; echo "dist/ removido"; exit 0 ;;
  all)
    mkdir -p "$DIST"
    pack linux amd64 ""
    pack windows amd64 ".exe"
    ;;
  current|*)
    mkdir -p "$DIST"
    pack "$(go env GOOS)" "$(go env GOARCH)" ""
    ;;
esac

echo
echo "== artefatos em $DIST/ =="
ls -lh "$DIST" | awk 'NR>1{print "  "$5"  "$9}'
echo "versao: $VERSION"
