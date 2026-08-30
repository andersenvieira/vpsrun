#!/usr/bin/env bash
###############################################################################
# aplicar-agora.sh  -  Aplica as mudancas NESTA maquina (ja configurada)
#
# Faz: 1o backup completo + remove NoMachine + desativa servicos inuteis +
#      desliga GDM (libera ~1GB) + instala backup diario.
# NAO reinstala pacotes e NAO reinicia o XRDP (sua sessao atual continua).
#
# USO:  sudo bash ~/Documents/VPSRUN/aplicar-agora.sh
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ">>> [1/4] Primeiro backup completo (pode demorar p/ /var/www e bancos)..."
bash "$SELF_DIR/backup-vps.sh"

echo ">>> [2/4] Desativando servicos inuteis em VPS + NoMachine..."
for svc in bluetooth cups cups-browsed avahi-daemon ModemManager \
           wpa_supplicant switcheroo-control nxserver; do
    systemctl disable --now "$svc" 2>/dev/null && echo "  desativado: $svc" || true
done

echo ">>> [3/4] Desligando login grafico local (GDM) - libera ~1GB de RAM..."
systemctl set-default multi-user.target
systemctl disable gdm 2>/dev/null || systemctl disable gdm3 2>/dev/null || true
systemctl stop gdm 2>/dev/null || systemctl stop gdm3 2>/dev/null || true
echo "  (seu desktop via XRDP NAO e afetado)"

echo ">>> [4/4] Instalando rotina de backup diario (03:00)..."
install -m 755 "$SELF_DIR/backup-vps.sh" /usr/local/bin/backup-vps.sh
cat > /etc/systemd/system/vpsrun-backup.service <<'EOF'
[Unit]
Description=VPSRUN - Backup completo (apps, bancos, configs)
[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-vps.sh
EOF
cat > /etc/systemd/system/vpsrun-backup.timer <<'EOF'
[Unit]
Description=VPSRUN - Backup diario as 03:00
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now vpsrun-backup.timer

echo "============================================================"
echo " Concluido nesta maquina."
free -h | awk 'NR<=2'
echo " Backups em: /var/backups/vpsrun/   (latest -> mais recente)"
echo " Proximo backup automatico:"; systemctl list-timers vpsrun-backup.timer --no-pager 2>/dev/null | head -2
echo "============================================================"
