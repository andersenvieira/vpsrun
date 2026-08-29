#!/usr/bin/env bash
###############################################################################
# tuning-ram.sh — otimização de memória (idempotente e reversível)
#
#   show    : mostra RAM, swap, zram e swappiness [padrão]
#   apply   : swappiness=10, vfs_cache_pressure=50 (backup antes)
#   revert  : restaura o backup
#
# Observação: a config de zram já é tratada por setup-vps.sh (zramswap).
###############################################################################
set -uo pipefail
export PATH="/usr/sbin:/sbin:$PATH"   # sysctl/zramctl/swapon ficam em /usr/sbin

CONF=/etc/sysctl.d/60-vpsrun-ram.conf
BACKUP=/var/backups/vpsrun-tuning/ram.pre-apply.txt
ACTION="${1:-show}"
KEYS=( vm.swappiness vm.vfs_cache_pressure )

show() {
  echo "== Memória =="
  free -h
  echo
  echo "== zram / swap =="
  if command -v zramctl >/dev/null 2>&1; then zramctl 2>/dev/null || true; fi
  swapon --show 2>/dev/null || true
  echo
  echo "== parâmetros =="
  for k in "${KEYS[@]}"; do printf "  %-24s = %s\n" "$k" "$(sysctl -n "$k" 2>/dev/null || echo '?')"; done
  if [ -f "$CONF" ]; then echo "perfil vpsrun aplicado: SIM"; else echo "perfil vpsrun aplicado: nao"; fi
}

apply() {
  [ "$(id -u)" -eq 0 ] || { echo "apply requer root"; exit 1; }
  mkdir -p "$(dirname "$BACKUP")"
  if [ ! -f "$BACKUP" ]; then
    { for k in "${KEYS[@]}"; do echo "$k = $(sysctl -n "$k" 2>/dev/null)"; done; } > "$BACKUP"
    echo "backup em $BACKUP"
  fi
  cat > "$CONF" <<'EOF'
# Perfil de memória vpsrun. 'revert' desfaz.
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
  sysctl -p "$CONF"
  echo "perfil de memória aplicado."
}

revert() {
  [ "$(id -u)" -eq 0 ] || { echo "revert requer root"; exit 1; }
  rm -f "$CONF"
  if [ -f "$BACKUP" ]; then
    while IFS= read -r line; do
      key="${line%% = *}"; val="${line#* = }"
      [ -n "$key" ] && [ -n "$val" ] && sysctl -w "$key=$val" >/dev/null 2>&1
    done < "$BACKUP"
    echo "valores restaurados de $BACKUP"
  else
    echo "sem backup; removido apenas $CONF"
  fi
}

case "$ACTION" in
  show) show ;; apply) apply ;; revert) revert ;;
  *) echo "uso: $0 [show|apply|revert]"; exit 2 ;;
esac
