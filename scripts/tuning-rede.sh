#!/usr/bin/env bash
###############################################################################
# tuning-rede.sh — otimização de rede (idempotente e reversível)
#
#   show    : mostra os valores atuais (não altera nada) [padrão]
#   apply   : aplica o perfil recomendado (backup automático antes)
#   revert  : restaura o backup do último apply
#
# Perfil: TCP BBR + fq, buffers maiores, backlog e somaxconn ampliados.
# Requer root para apply/revert.
###############################################################################
set -uo pipefail
export PATH="/usr/sbin:/sbin:$PATH"   # sysctl fica em /usr/sbin

CONF=/etc/sysctl.d/60-vpsrun-rede.conf
BACKUP=/var/backups/vpsrun-tuning/rede.pre-apply.txt
ACTION="${1:-show}"

KEYS=(
  net.core.default_qdisc
  net.ipv4.tcp_congestion_control
  net.core.rmem_max
  net.core.wmem_max
  net.ipv4.tcp_rmem
  net.ipv4.tcp_wmem
  net.core.somaxconn
  net.ipv4.tcp_max_syn_backlog
  net.ipv4.tcp_fastopen
)

show() {
  echo "== Rede: valores atuais =="
  for k in "${KEYS[@]}"; do
    printf "  %-32s = %s\n" "$k" "$(sysctl -n "$k" 2>/dev/null || echo '?')"
  done
  echo
  if [ -f "$CONF" ]; then echo "perfil vpsrun aplicado: SIM ($CONF)"; else echo "perfil vpsrun aplicado: nao"; fi
}

apply() {
  [ "$(id -u)" -eq 0 ] || { echo "apply requer root"; exit 1; }
  mkdir -p "$(dirname "$BACKUP")"
  if [ ! -f "$BACKUP" ]; then
    { for k in "${KEYS[@]}"; do echo "$k = $(sysctl -n "$k" 2>/dev/null)"; done; } > "$BACKUP"
    echo "backup dos valores atuais em $BACKUP"
  fi
  cat > "$CONF" <<'EOF'
# Perfil de rede vpsrun (idempotente). Remova este arquivo e rode 'revert' para desfazer.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fastopen = 3
EOF
  sysctl -p "$CONF"
  echo "perfil de rede aplicado."
}

revert() {
  [ "$(id -u)" -eq 0 ] || { echo "revert requer root"; exit 1; }
  rm -f "$CONF"
  if [ -f "$BACKUP" ]; then
    while IFS= read -r line; do
      key="${line%% = *}"; val="${line#* = }"
      [ -n "$key" ] && [ -n "$val" ] && sysctl -w "$key=$val" >/dev/null 2>&1
    done < "$BACKUP"
    echo "valores restaurados a partir de $BACKUP"
  else
    echo "sem backup; removido apenas $CONF (reinicie para valores de boot)"
  fi
}

case "$ACTION" in
  show) show ;;
  apply) apply ;;
  revert) revert ;;
  *) echo "uso: $0 [show|apply|revert]"; exit 2 ;;
esac
