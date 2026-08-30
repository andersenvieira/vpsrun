#!/usr/bin/env bash
###############################################################################
# reboot-e-verificar.sh  -  Instala a checagem de saude no boot e REINICIA
#
# Apos o reboot, o relatorio fica pronto em /var/log/vpsrun-healthcheck.log
# (legivel sem sudo). Reconecte e rode:   cat /var/log/vpsrun-healthcheck.log
# A checagem passa a rodar a cada boot (util como diagnostico permanente).
#
# USO:  sudo bash ~/Documents/VPSRUN/reboot-e-verificar.sh
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ">>> Instalando a checagem de saude..."
install -m 755 "$SELF_DIR/verificar-saude.sh" /usr/local/bin/verificar-saude.sh

cat > /etc/systemd/system/vpsrun-healthcheck.service <<'EOF'
[Unit]
Description=VPSRUN - Checagem de saude pos-boot
After=network-online.target nginx.service mariadb.service docker.service xrdp.service
Wants=network-online.target

[Service]
Type=oneshot
# Espera os servicos assentarem antes de checar
ExecStartPre=/bin/sleep 15
ExecStart=/bin/bash -c '/usr/local/bin/verificar-saude.sh | tee /var/log/vpsrun-healthcheck.log; chmod 644 /var/log/vpsrun-healthcheck.log'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpsrun-healthcheck.service
echo ">>> Check instalado e habilitado para rodar no boot."

echo ">>> Reiniciando em 5 segundos... (sua sessao RDP/SSH vai cair; reconecte depois)"
echo "    Ao voltar:  cat /var/log/vpsrun-healthcheck.log"
sleep 5
systemctl reboot
