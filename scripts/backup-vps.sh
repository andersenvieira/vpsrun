#!/usr/bin/env bash
###############################################################################
# backup-vps.sh  -  Backup completo da VPS (apps + bancos + configs)
#
# Destino (padrao Debian para backups):  /var/backups/vpsrun/
# Estrutura:  /var/backups/vpsrun/AAAA-MM-DD_HHMMSS/{databases,www,docker,configs}
# Mantem os ultimos RETENTION backups (rotacao automatica).
# Cria/atualiza o link  /var/backups/vpsrun/latest  apontando para o mais novo.
#
# MODOS:
#   sudo bash backup-vps.sh                 -> a quente (sem downtime)
#   sudo CONSISTENT=1 bash backup-vps.sh    -> modo consistente:
#        pausa fila + poe apps Laravel em manutencao durante o dump e
#        RELIGA tudo automaticamente ao final (mesmo se houver erro).
#
# Diario: instalado em /usr/local/bin e disparado por vpsrun-backup.timer.
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }

DEST="/var/backups/vpsrun"
RETENTION="${RETENTION:-7}"
CONSISTENT="${CONSISTENT:-0}"
WWW_ROOT="/var/www/undersec.com.br"
QUEUE_SVC="parkia-queue.service"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
DIR="$DEST/$STAMP"
LOG="/var/log/vpsrun-backup.log"
mkdir -p "$DIR"/{databases,www,docker,configs}
exec > >(tee -a "$LOG") 2>&1
echo "==================================================================="
echo "[$(date)] Iniciando backup em $DIR (CONSISTENT=$CONSISTENT)"

# --- Descobre apps Laravel (diretorios com arquivo 'artisan')
LARAVEL_APPS=()
if [[ -d "$WWW_ROOT" ]]; then
    while IFS= read -r a; do LARAVEL_APPS+=("$(dirname "$a")"); done \
        < <(find "$WWW_ROOT" -maxdepth 2 -name artisan 2>/dev/null)
fi

# --- Funcao que RELIGA tudo (chamada no fim e tambem em qualquer erro/saida)
MAINT_ON=0
restore_services() {
    [[ "$MAINT_ON" == "1" ]] || return 0
    echo "[*] Religando servicos/apps..."
    for app in "${LARAVEL_APPS[@]}"; do
        owner="$(stat -c %U "$app/artisan" 2>/dev/null || echo www-data)"
        sudo -u "$owner" php "$app/artisan" up --no-interaction 2>/dev/null \
            && echo "  up: $app" || true
    done
    systemctl start "$QUEUE_SVC" 2>/dev/null && echo "  fila religada" || true
    MAINT_ON=0
}
trap restore_services EXIT INT TERM

# --- MODO CONSISTENTE: pausa fila + manutencao antes do dump
if [[ "$CONSISTENT" == "1" ]]; then
    echo "[*] Modo consistente: pausando fila e colocando apps em manutencao..."
    MAINT_ON=1
    systemctl stop "$QUEUE_SVC" 2>/dev/null && echo "  fila pausada" || true
    for app in "${LARAVEL_APPS[@]}"; do
        owner="$(stat -c %U "$app/artisan" 2>/dev/null || echo www-data)"
        sudo -u "$owner" php "$app/artisan" down --no-interaction 2>/dev/null \
            && echo "  manutencao: $app" || true
    done
    sleep 1
fi

# --- 1) Bancos de dados MariaDB
echo "[*] MariaDB..."
if command -v mysqldump >/dev/null; then
    mysqldump --single-transaction --quick --all-databases 2>/dev/null \
        | gzip > "$DIR/databases/all-databases.sql.gz" || echo "  (falha no dump geral)"
    for db in $(mysql -N -e 'SHOW DATABASES;' 2>/dev/null \
                | grep -Ev '^(information_schema|performance_schema|sys|mysql)$'); do
        mysqldump --single-transaction --quick "$db" 2>/dev/null \
            | gzip > "$DIR/databases/${db}.sql.gz" && echo "  banco: $db"
    done
    # Registra o engine de cada tabela (auditoria InnoDB x MyISAM)
    mysql -N -e "SELECT table_schema,table_name,engine FROM information_schema.tables \
        WHERE table_schema NOT IN ('information_schema','performance_schema','sys','mysql');" \
        2>/dev/null > "$DIR/databases/_engines.txt"
    MYISAM=$(grep -ic 'MyISAM' "$DIR/databases/_engines.txt" 2>/dev/null || echo 0)
    echo "  tabelas MyISAM encontradas: $MYISAM (0 = tudo InnoDB, ideal)"
else
    echo "  mysqldump ausente, pulando."
fi

# --- 2) Aplicacoes web (/var/www) -- exclui zips antigos e caches pesados
echo "[*] /var/www..."
tar --exclude='*.zip' --exclude='node_modules' \
    -czf "$DIR/www/var-www.tar.gz" -C / var/www 2>/dev/null \
    && echo "  /var/www arquivado" || echo "  (aviso ao arquivar /var/www)"

# --- MODO CONSISTENTE: religa imediatamente apos os dados criticos
if [[ "$CONSISTENT" == "1" ]]; then restore_services; fi

# --- 3) Docker
echo "[*] Docker..."
if command -v docker >/dev/null; then
    docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}' > "$DIR/docker/containers.txt" 2>/dev/null
    docker images --format '{{.Repository}}:{{.Tag}}'          > "$DIR/docker/images.txt"     2>/dev/null
    for c in $(docker ps -a --format '{{.Names}}'); do
        docker inspect "$c" > "$DIR/docker/${c}.inspect.json" 2>/dev/null && echo "  container: $c"
    done
    for f in /opt/*/docker-compose.yml /root/*/docker-compose.yml /home/*/*/docker-compose.yml; do
        [[ -f "$f" ]] && cp "$f" "$DIR/docker/compose_$(echo "$f"|tr / _)" 2>/dev/null
    done
fi

# --- 4) Configuracoes do sistema
echo "[*] Configs do sistema..."
cp -a /etc/xrdp                 "$DIR/configs/xrdp"            2>/dev/null
cp -a /etc/nginx                "$DIR/configs/nginx"           2>/dev/null
cp -a /etc/php                  "$DIR/configs/php"             2>/dev/null
cp    /etc/default/zramswap     "$DIR/configs/"                2>/dev/null
cp    /etc/fstab                "$DIR/configs/"                2>/dev/null
crontab -l                    > "$DIR/configs/root-crontab.txt" 2>/dev/null
apt-mark showmanual           > "$DIR/configs/apt-manual.txt" 2>/dev/null
systemctl list-unit-files --state=enabled > "$DIR/configs/enabled-services.txt" 2>/dev/null
cp -a /home/*/Documents/VPSRUN  "$DIR/configs/VPSRUN-kit"      2>/dev/null

# --- 5) Tamanho, link 'latest' e rotacao
du -sh "$DIR" | awk '{print "[*] Tamanho do backup: "$1}'
ln -sfn "$DIR" "$DEST/latest"

# --- 5b) Empacota o snapshot num unico .tar.gz (facil de subir p/ nuvem)
if [[ "${PACKAGE:-1}" == "1" ]]; then
    echo "[*] Empacotando snapshot para nuvem..."
    tar -czf "$DEST/$STAMP.tar.gz" -C "$DEST" "$STAMP" 2>/dev/null \
        && du -sh "$DEST/$STAMP.tar.gz" | awk '{print "  pacote: "$2" ("$1")"}'
    ln -sfn "$DEST/$STAMP.tar.gz" "$DEST/latest.tar.gz"
fi

# --- 5c) Upload opcional para a nuvem via rclone (se REMOTE estiver definido)
# Configure antes:  rclone config   (crie um remote, ex.: gdrive)
# E rode com:        REMOTE=gdrive:vpsrun  sudo backup-vps.sh
if [[ -n "${REMOTE:-}" ]] && command -v rclone >/dev/null; then
    echo "[*] Enviando pacote para a nuvem ($REMOTE)..."
    rclone copy "$DEST/$STAMP.tar.gz" "$REMOTE/" 2>&1 | tail -2 \
        && echo "  upload concluido" || echo "  (falha no upload - verifique 'rclone config')"
fi

echo "[*] Rotacao: mantendo os ultimos $RETENTION backups..."
ls -1dt "$DEST"/20*_*/ 2>/dev/null | tail -n +$((RETENTION+1)) | while read -r old; do
    rm -rf "$old" && echo "  removida pasta antiga: $old"
done
ls -1t "$DEST"/20*_*.tar.gz 2>/dev/null | tail -n +$((RETENTION+1)) | while read -r old; do
    rm -f "$old" && echo "  removido pacote antigo: $old"
done

restore_services   # garantia final
echo "[$(date)] Backup concluido com sucesso."
echo "==================================================================="
