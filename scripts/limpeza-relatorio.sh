#!/usr/bin/env bash
###############################################################################
# limpeza-relatorio.sh — relatório READ-ONLY de ocupação de disco.
#
# NÃO remove nada. Aponta os candidatos típicos a limpeza para o operador
# decidir. Itens que exigem root são marcados quando indisponíveis.
###############################################################################
set -uo pipefail
export PATH="/usr/sbin:/sbin:$PATH"

hr() { printf '%s\n' "-------------------------------------------------------------"; }

echo "== Uso de disco =="
df -h / 2>/dev/null | sed -n '1p;/\/$/p'
hr

echo "== Maiores diretórios em / (nível 1) =="
du -sh --exclude=/proc --exclude=/sys --exclude=/dev /* 2>/dev/null | sort -rh | head -8
hr

echo "== Docker =="
if command -v docker >/dev/null 2>&1; then
  docker system df 2>/dev/null || echo "  (docker sem permissão para este usuário)"
  echo "  imagens penduradas (dangling):"
  docker images -f dangling=true -q 2>/dev/null | wc -l | sed 's/^/    /'
else
  echo "  docker não instalado"
fi
hr

echo "== Journald (systemd) =="
journalctl --disk-usage 2>/dev/null || echo "  (requer root para medir)"
hr

echo "== Cache APT =="
if [ -d /var/cache/apt/archives ]; then
  du -sh /var/cache/apt/archives 2>/dev/null || echo "  (requer root)"
else
  echo "  (n/d)"
fi
hr

echo "== Logs grandes em /var/log (>20M) =="
find /var/log -type f -size +20M 2>/dev/null -exec ls -lh {} \; | awk '{print "    "$5"\t"$9}' | sort -rh | head -10
[ -z "$(find /var/log -type f -size +20M 2>/dev/null)" ] && echo "    (nenhum acima de 20M ou sem permissão)"
hr

echo "== Artefatos regeneráveis em /var/www (node_modules) =="
find /var/www -maxdepth 4 -type d -name node_modules -prune 2>/dev/null | head -12 | while read -r d; do
  echo "    $(du -sh "$d" 2>/dev/null | cut -f1)  $d"
done
hr

echo "Relatório gerado em $(date '+%Y-%m-%d %H:%M:%S'). Nada foi removido."
echo "Dica: rotação de log do Docker e limpeza guiada entram como ações confirmáveis."
