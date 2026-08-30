#!/usr/bin/env bash
###############################################################################
# setup-vps.sh  -  Personalizacao COMPLETA de uma VPS Debian 13 headless
#
# Roda numa instalacao limpa do Debian e deixa a maquina igual a esta:
#   - Stack de producao: nginx + PHP-FPM + MariaDB + Docker
#   - Acesso grafico via XRDP + GNOME (Xorg, render por software, headless)
#   - zram swap (lz4, 50% da RAM)
#   - Desativa servicos inuteis em VPS (bluetooth, cups, avahi, modem, wifi...)
#   - Sem login grafico local (GDM desligado) para economizar ~1 GB de RAM
#   - Instala a rotina de backup diario (vpsrun-backup.timer)
#   - (Opcional) Restaura dados a partir de /var/backups/vpsrun/latest
#
# USO:
#   sudo bash setup-vps.sh                 # configura tudo
#   sudo RESTORE=1 bash setup-vps.sh       # tambem restaura o ultimo backup
#   sudo DESKTOP=xfce bash setup-vps.sh    # usa XFCE (mais leve) em vez de GNOME
#
# EXECUTE VIA SSH OU CONSOLE (nunca de dentro do RDP).
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }

DESKTOP="${DESKTOP:-gnome}"
RESTORE="${RESTORE:-0}"
RDP_USER="${RDP_USER:-$(logname 2>/dev/null || echo adminvps)}"
USER_HOME="$(getent passwd "$RDP_USER" | cut -d: -f6)"
export DEBIAN_FRONTEND=noninteractive
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "### Alvo: usuario=$RDP_USER desktop=$DESKTOP restore=$RESTORE ###"

# ===========================================================================
# 1) PACOTES BASE
# ===========================================================================
echo ">>> [1] Instalando pacotes base..."
apt-get update -y
apt-get install -y --no-install-recommends \
    nginx mariadb-server \
    php8.4-fpm php8.4-cli php8.4-mysql php8.4-curl php8.4-mbstring \
    php8.4-xml php8.4-zip php8.4-gd php8.4-bcmath php8.4-intl \
    docker.io docker-compose-v2 \
    zram-tools \
    xrdp xorgxrdp dbus-x11 \
    git curl unzip rsync ca-certificates
# Desktop
if [[ "$DESKTOP" == "xfce" ]]; then
    apt-get install -y --no-install-recommends xfce4 xfce4-goodies
    SESSION_CMD="startxfce4"
else
    apt-get install -y --no-install-recommends \
        gnome-core gnome-session gnome-shell gnome-terminal nautilus gnome-session-xsession || true
    SESSION_CMD="gnome-session"
fi
systemctl enable --now docker mariadb nginx php8.4-fpm

# ===========================================================================
# 2) ZRAM (lz4, 50% da RAM, prioridade 100)  -- mesmo perfil desta maquina
# ===========================================================================
echo ">>> [2] Configurando zram..."
cat > /etc/default/zramswap <<'EOF'
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF
systemctl enable --now zramswap.service 2>/dev/null || true

# ===========================================================================
# 3) XRDP + sessao grafica (X11 + render por software p/ VPS sem GPU)
# ===========================================================================
echo ">>> [3] Configurando XRDP + $DESKTOP..."
# Libera a 3389 caso o gnome-remote-desktop exista (incompativel c/ app Microsoft)
if systemctl list-unit-files | grep -q gnome-remote-desktop; then
    systemctl disable --now gnome-remote-desktop.service 2>/dev/null || true
    systemctl mask gnome-remote-desktop.service 2>/dev/null || true
    sudo -u "$RDP_USER" systemctl --user disable --now gnome-remote-desktop.service 2>/dev/null || true
fi

cat > "$USER_HOME/.xsession" <<EOF
#!/bin/sh
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
export XDG_SESSION_DESKTOP=$DESKTOP
export DESKTOP_SESSION=$DESKTOP
exec $SESSION_CMD > "\$HOME/.session-xrdp.log" 2>&1
EOF
chown "$RDP_USER":"$RDP_USER" "$USER_HOME/.xsession"
chmod 755 "$USER_HOME/.xsession"

cat > /etc/xrdp/startwm.sh <<EOF
#!/bin/sh
[ -r /etc/profile ] && . /etc/profile
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
export XDG_SESSION_DESKTOP=$DESKTOP
export DESKTOP_SESSION=$DESKTOP
[ -r "\$HOME/.xsession" ] && . "\$HOME/.xsession"
exec dbus-launch --exit-with-session $SESSION_CMD
EOF
chmod 755 /etc/xrdp/startwm.sh

adduser xrdp ssl-cert 2>/dev/null || true
mkdir -p /etc/polkit-1/localauthority/50-local.d
cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<'EOF'
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF
# Persistencia de sessao (reconecta na mesma sessao entre aparelhos)
sed -i 's/^KillDisconnected=.*/KillDisconnected=false/' /etc/xrdp/sesman.ini 2>/dev/null || true
sed -i 's/^max_bpp=.*/max_bpp=32/'                      /etc/xrdp/xrdp.ini   2>/dev/null || true
systemctl enable xrdp xrdp-sesman
systemctl restart xrdp-sesman xrdp

# ===========================================================================
# 4) DESATIVAR servicos inuteis em VPS  +  GDM (login grafico local)
# ===========================================================================
echo ">>> [4] Desativando servicos desnecessarios..."
for svc in bluetooth cups cups-browsed avahi-daemon ModemManager \
           wpa_supplicant switcheroo-control nxserver; do
    systemctl disable --now "$svc" 2>/dev/null && echo "  desativado: $svc" || true
done
# Sem login grafico local: economiza ~1 GB. O XRDP NAO depende do GDM.
systemctl set-default multi-user.target
systemctl disable gdm 2>/dev/null || systemctl disable gdm3 2>/dev/null || true

# ===========================================================================
# 5) ROTINA DE BACKUP DIARIO (systemd timer)
# ===========================================================================
echo ">>> [5] Instalando rotina de backup diario..."
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
echo "  timer ativo: $(systemctl is-active vpsrun-backup.timer)"

# ===========================================================================
# 6) RESTAURACAO opcional a partir do ultimo backup
# ===========================================================================
# ===========================================================================
# 6) RESTAURACAO opcional a partir do ultimo backup (ou pacote da nuvem)
# ===========================================================================
if [[ "$RESTORE" == "1" ]]; then
    echo ">>> [6] Restaurando dados..."
    # Aceita RESTORE_FROM=/caminho/backup.tar.gz (ex.: baixado da nuvem)
    CONFIGS=1 bash "$SELF_DIR/restaurar.sh" "${RESTORE_FROM:-/var/backups/vpsrun/latest}"
else
    echo ">>> [6] Restauracao pulada. Para restaurar depois:"
    echo "     sudo CONFIGS=1 bash $SELF_DIR/restaurar.sh /caminho/backup.tar.gz"
fi

echo "============================================================"
echo " SETUP CONCLUIDO."
echo " Reinicie para aplicar o boot sem GDM:  sudo reboot"
echo " Itens MANUAIS (ver MANUAL.md): DNS, SSL (certbot), recriar"
echo " containers Docker e arquivos .env com segredos, instalar Ollama."
echo "============================================================"
