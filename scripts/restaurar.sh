#!/usr/bin/env bash
###############################################################################
# restaurar.sh  -  Restaura um backup VPSRUN nos locais corretos de producao
#
# Aceita um snapshot em PASTA ou em arquivo unico .tar.gz (ex.: baixado da
# nuvem). Descompacta e aloca tudo: /var/www, bancos MariaDB e (opcional) as
# configuracoes de nginx/php/xrdp. Ao final, sobe os apps Laravel.
#
# USO:
#   sudo bash restaurar.sh                         # usa /var/backups/vpsrun/latest
#   sudo bash restaurar.sh /caminho/backup.tar.gz  # usa um pacote (ex.: da nuvem)
#   sudo bash restaurar.sh /var/backups/vpsrun/2026-06-22_205015
#   sudo CONFIGS=1 bash restaurar.sh ...           # tambem restaura configs do sistema
#
# Cada backup e COMPLETO: restaurar 1 snapshot = aquela versao inteira.
# Para a producao atual, restaure o snapshot mais recente.
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }

SRC="${1:-/var/backups/vpsrun/latest}"
WORK=""; CLEAN_WORK=0

# Se for um .tar.gz, extrai para uma pasta temporaria
if [[ -f "$SRC" && "$SRC" == *.tar.gz ]]; then
    echo ">>> Pacote detectado. Extraindo $SRC ..."
    WORK="$(mktemp -d)"; CLEAN_WORK=1
    tar -xzf "$SRC" -C "$WORK"
    SNAP="$(find "$WORK" -maxdepth 1 -mindepth 1 -type d | head -1)"
else
    SNAP="$SRC"
fi
[[ -d "$SNAP" ]] || { echo "Backup invalido: $SRC"; exit 1; }
echo ">>> Restaurando a partir de: $SNAP"
trap '[[ "$CLEAN_WORK" == "1" ]] && rm -rf "$WORK"' EXIT

# --- 1) Arquivos das aplicacoes (/var/www)
if [[ -f "$SNAP/www/var-www.tar.gz" ]]; then
    echo ">>> [1] Restaurando /var/www ..."
    tar -xzf "$SNAP/www/var-www.tar.gz" -C / && echo "  /var/www restaurado"
fi

# --- 2) Bancos de dados (cada banco no seu schema, sem tocar no 'mysql' do sistema)
echo ">>> [2] Restaurando bancos MariaDB ..."
for f in "$SNAP"/databases/*.sql.gz; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f" .sql.gz)"
    [[ "$name" == "all-databases" ]] && continue   # usamos os dumps por banco
    echo "  banco: $name"
    mysql -e "CREATE DATABASE IF NOT EXISTS \`$name\` CHARACTER SET utf8mb4;"
    zcat "$f" | mysql "$name"
done

# --- 3) Configuracoes do sistema (opcional: CONFIGS=1)
if [[ "${CONFIGS:-0}" == "1" ]]; then
    echo ">>> [3] Restaurando configs (nginx/php/xrdp) ..."
    [[ -d "$SNAP/configs/nginx" ]] && cp -a "$SNAP/configs/nginx/." /etc/nginx/ && echo "  nginx"
    [[ -d "$SNAP/configs/php"   ]] && cp -a "$SNAP/configs/php/."   /etc/php/   && echo "  php"
    [[ -d "$SNAP/configs/xrdp"  ]] && cp -a "$SNAP/configs/xrdp/."  /etc/xrdp/  && echo "  xrdp"
    [[ -f "$SNAP/configs/zramswap" ]] && cp "$SNAP/configs/zramswap" /etc/default/ && echo "  zramswap"
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || echo "  (revise o nginx manualmente: nginx -t)"
else
    echo ">>> [3] Configs do sistema NAO restauradas (use CONFIGS=1 se quiser)."
fi

# --- 4) Sobe os apps Laravel (caso tenham vindo em manutencao)
echo ">>> [4] Subindo apps Laravel ..."
while IFS= read -r art; do
    app="$(dirname "$art")"; owner="$(stat -c %U "$art" 2>/dev/null || echo www-data)"
    sudo -u "$owner" php "$art" up --no-interaction 2>/dev/null && echo "  up: $app" || true
done < <(find /var/www -maxdepth 3 -name artisan 2>/dev/null)

echo "============================================================"
echo " RESTAURACAO CONCLUIDA."
echo " Pendencias manuais (segredos/decisoes):"
echo "  - Recriar container Docker (ver $SNAP/docker/*.inspect.json)"
echo "  - SSL/HTTPS (certbot) e apontamento de DNS"
echo "  - Conferir os .env restaurados em /var/www"
echo "============================================================"
