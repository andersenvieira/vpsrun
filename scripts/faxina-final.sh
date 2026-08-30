#!/usr/bin/env bash
###############################################################################
# faxina-final.sh  -  Remove pacotes inuteis e limpa o nginx (UM comando)
#
# Deixa a maquina enxuta: so a stack de producao + desktop GNOME (via XRDP)
# + rotina de backup. Remove:
#   - NoMachine (substituido pelo XRDP)
#   - freerdp3-x11 (cliente instalado so para diagnostico)
#   - XFCE (nao usado; o desktop e o GNOME)
#   - dependencias orfas e cache do apt
# E remove os blocos .bak duplicados do nginx (com rollback).
#
# USO:  sudo bash ~/Documents/VPSRUN/faxina-final.sh
# Producao (nginx/php/mariadb/docker/queue) e o GNOME/XRDP NAO sao afetados.
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
export DEBIAN_FRONTEND=noninteractive

echo ">>> Espaco em disco ANTES:"; df -h / | tail -1

echo ">>> [1] Removendo NoMachine..."
systemctl disable --now nxserver 2>/dev/null || true
apt-get purge -y nomachine 2>/dev/null && echo "  nomachine removido" || \
    { [ -x /usr/NX/scripts/setup/nxserver ] && /usr/NX/scripts/setup/nxserver --uninstall 2>/dev/null; \
      rm -rf /usr/NX; echo "  NoMachine removido (manual)"; }

echo ">>> [2] Removendo cliente de diagnostico freerdp3-x11..."
apt-get purge -y freerdp3-x11 2>/dev/null && echo "  freerdp3-x11 removido" || true

echo ">>> [3] Removendo XFCE (desktop nao usado; o ativo e o GNOME)..."
# Confirma que o XRDP usa GNOME antes de remover o XFCE
if grep -q 'gnome-session' /etc/xrdp/startwm.sh 2>/dev/null; then
    apt-get purge -y 'xfce4*' 'libxfce4*' xfwm4 xfdesktop4 xfce4-* 2>/dev/null \
        && echo "  XFCE removido" || echo "  (XFCE ja ausente)"
else
    echo "  PULADO: o XRDP nao esta claramente em GNOME; XFCE mantido por seguranca."
fi

echo ">>> [4] Removendo dependencias orfas e limpando cache..."
apt-get autoremove --purge -y >/dev/null 2>&1 && echo "  orfas removidas"
apt-get clean && echo "  cache do apt limpo"

echo ">>> [5] Limpando blocos duplicados do nginx (com rollback)..."
if [[ -x "$SELF_DIR/corrigir-nginx.sh" ]]; then
    bash "$SELF_DIR/corrigir-nginx.sh" || echo "  (nginx inalterado; revise manualmente)"
fi

echo "============================================================"
echo ">>> Espaco em disco DEPOIS:"; df -h / | tail -1
echo ">>> Memoria:"; free -h | awk 'NR<=2'
echo ">>> Servicos de producao:"
for s in nginx php8.4-fpm mariadb docker xrdp xrdp-sesman vpsrun-backup.timer; do
    printf "   %-22s %s\n" "$s" "$(systemctl is-active "$s" 2>/dev/null)"
done
echo "============================================================"
echo " Maquina enxuta: producao + GNOME(XRDP) + backup diario."
