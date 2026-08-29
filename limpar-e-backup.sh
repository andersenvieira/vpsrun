#!/usr/bin/env bash
###############################################################################
# limpar-e-backup.sh  -  Faxina + backup de seguranca (nesta maquina)
#
# Ordem:
#   1) Remove Ollama (projeto parado) por completo
#   2) Remove lixo (core dumps, imagem docker de teste, cache apt, logs)
#   3) Desativa servicos inuteis em VPS + NoMachine + GDM (libera ~1 GB)
#   4) Faz o backup completo e VERIFICA
#   5) So apos backup OK: apaga os zips de backup antigos de /var/www
#   6) Instala a rotina de backup diario
#
# USO:  sudo bash ~/Documents/VPSRUN/limpar-e-backup.sh
# NAO reinicia o XRDP (sua sessao atual continua).
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ">>> [1/6] Removendo Ollama (projeto parado)..."
systemctl disable --now ollama.service 2>/dev/null || true
rm -f /etc/systemd/system/ollama.service
rm -f /etc/systemd/system/default.target.wants/ollama.service
rm -f /usr/local/bin/ollama
rm -rf /usr/share/ollama /root/.ollama /home/*/.ollama
systemctl daemon-reload
userdel ollama 2>/dev/null && echo "  usuario ollama removido" || true
echo "  Ollama removido (porta 11434 liberada)."

echo ">>> [2/6] Removendo lixo..."
rm -f /home/*/core.* && echo "  core dumps removidos" || true
docker rmi hello-world:latest 2>/dev/null && echo "  imagem hello-world removida" || true
apt-get autoremove -y >/dev/null 2>&1 && apt-get clean && echo "  apt limpo"
journalctl --vacuum-time=7d >/dev/null 2>&1 && echo "  journald reduzido a 7 dias"

echo ">>> [3/6] Desativando servicos inuteis + NoMachine + GDM..."
for svc in bluetooth cups cups-browsed avahi-daemon ModemManager \
           wpa_supplicant switcheroo-control nxserver; do
    systemctl disable --now "$svc" 2>/dev/null && echo "  desativado: $svc" || true
done
systemctl set-default multi-user.target
systemctl disable gdm 2>/dev/null || systemctl disable gdm3 2>/dev/null || true
systemctl stop gdm 2>/dev/null || systemctl stop gdm3 2>/dev/null || true
echo "  (desktop via XRDP NAO e afetado)"

echo ">>> [4/6] Backup completo em MODO CONSISTENTE (pausa fila/manutencao no dump)..."
CONSISTENT=1 bash "$SELF_DIR/backup-vps.sh"

# Verificacao: o backup mais novo precisa ter o tar de /var/www nao-vazio
LATEST="$(ls -1dt /var/backups/vpsrun/20*_* 2>/dev/null | head -1)"
WWW_TAR="$LATEST/www/var-www.tar.gz"
DB_DIR="$LATEST/databases"
BACKUP_OK=0
if [[ -s "$WWW_TAR" ]] && [[ -n "$(ls -A "$DB_DIR" 2>/dev/null)" ]]; then
    BACKUP_OK=1
    echo "  Backup verificado OK em: $LATEST"
    du -sh "$WWW_TAR" "$DB_DIR" 2>/dev/null
else
    echo "  !! ATENCAO: backup nao passou na verificacao. Zips antigos serao MANTIDOS."
fi

echo ">>> [5/6] Removendo backups antigos de /var/www..."
if [[ "$BACKUP_OK" == "1" ]]; then
    rm -f /var/www/*.zip && echo "  zips antigos removidos (espaco liberado)" || true
    # remove tambem a pasta legacy de execucoes anteriores, se existir
    rm -rf /var/backups/vpsrun/legacy-backups 2>/dev/null || true
else
    echo "  Pulado por seguranca (backup novo nao confirmado)."
fi

echo ">>> [6/6] Instalando backup diario (03:00)..."
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
echo " FAXINA + BACKUP CONCLUIDOS"
free -h | awk 'NR<=2'
echo " Backup em: ${LATEST:-/var/backups/vpsrun/}"
df -hT / | tail -1 | awk '{print " Disco /: usado "$6" de "$3}'
systemctl list-timers vpsrun-backup.timer --no-pager 2>/dev/null | head -2
echo "============================================================"
