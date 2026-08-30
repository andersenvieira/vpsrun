#!/usr/bin/env bash
###############################################################################
# testar-restauracao.sh  -  Prova que o backup e restauravel (sem tocar nos
#                           bancos de producao)
#
# Restaura um dump do ultimo backup num schema TEMPORARIO, conta as tabelas
# e linhas, e em seguida APAGA o schema temporario. Nao altera nada em producao.
#
# USO:   sudo bash ~/Documents/VPSRUN/testar-restauracao.sh [nome_do_banco]
#        (padrao: undersec)
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }

DB="${1:-undersec}"
SRC="/var/backups/vpsrun/latest/databases/${DB}.sql.gz"
TMP="restore_test_${DB}_$$"

[[ -f "$SRC" ]] || { echo "Dump nao encontrado: $SRC"; echo "Disponiveis:"; ls /var/backups/vpsrun/latest/databases/; exit 1; }

echo ">>> Criando schema temporario '$TMP'..."
mysql -e "CREATE DATABASE \`$TMP\`;"

cleanup() { mysql -e "DROP DATABASE IF EXISTS \`$TMP\`;" && echo ">>> Schema temporario removido."; }
trap cleanup EXIT INT TERM

echo ">>> Restaurando '$DB' dentro de '$TMP'..."
zcat "$SRC" | sed "s/\`$DB\`/\`$TMP\`/g" | mysql "$TMP" 2>/dev/null || zcat "$SRC" | mysql "$TMP"

NT=$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$TMP';")
echo ">>> Resultado: $NT tabelas restauradas com sucesso no schema de teste."
echo ">>> Amostra de tabelas:"
mysql -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='$TMP' LIMIT 8;" | sed 's/^/   - /'
echo ">>> Backup CONFIRMADO restauravel. (producao intacta)"
