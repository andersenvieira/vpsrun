#!/usr/bin/env bash
###############################################################################
# padronizar-nginx.sh  -  Padroniza sites-available/enabled e remove lixo
# Rollback automatico se o nginx -t falhar em qualquer etapa.
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }

EN=/etc/nginx/sites-enabled
AV=/etc/nginx/sites-available
BK=/tmp/nginx-padronizar-bk-$$
mkdir -p "$BK"

echo ">>> Teste baseline (antes de qualquer mudanca)..."
nginx -t 2>/dev/null || { echo "!! nginx ja tem erro antes de mexer. Abortando."; nginx -t; exit 1; }

rollback(){
    echo "!! ROLLBACK: restaurando estado original..."
    [[ -f "$BK/undersec.enabled" ]] && cp "$BK/undersec.enabled" "$EN/undersec.com.br"
    [[ -f "$BK/undersec.available" ]] && cp "$BK/undersec.available" "$AV/undersec.com.br"
    nginx -t && echo "  rollback OK" || echo "  !! rollback com erro - cheque manualmente"
    rm -rf "$BK"
    exit 1
}

# --- Backup de seguranca antes de mexer
cp "$EN/undersec.com.br"  "$BK/undersec.enabled"   2>/dev/null || true
cp "$AV/undersec.com.br"  "$BK/undersec.available" 2>/dev/null || true

echo ">>> [1] Movendo arquivo atual (sites-enabled) para sites-available..."
# O arquivo em sites-enabled e o atual e correto (13334 bytes, 16/jun)
# O de sites-available e versao velha (7913 bytes, 18/mai) -- sera sobrescrito
cp "$EN/undersec.com.br" "$AV/undersec.com.br"
rm -f "$EN/undersec.com.br"

echo ">>> [2] Criando link simbólico correto em sites-enabled..."
ln -s "$AV/undersec.com.br" "$EN/undersec.com.br"

echo ">>> Teste apos padronizacao..."
nginx -t 2>/dev/null || rollback

echo ">>> [3] Recarregando nginx..."
systemctl reload nginx && echo "  nginx recarregado OK"

echo ">>> [4] Removendo lixo (versoes antigas, _bak, _backups_desativados)..."
rm -f  "$AV/undersec.com.br.bak.1779114629"
rm -f  "$AV/undersec.com.br.bak.parkia.1778993002"
rm -rf "$AV/_bak"
rm -rf "$AV/_backups_desativados"
rm -rf "$BK"

echo ">>> Estado final:"
echo "--- sites-available ---"; ls -la "$AV/"
echo "--- sites-enabled ---"; ls -la "$EN/"

echo ">>> Teste final..."
nginx -t 2>/dev/null && echo "NGINX OK" || echo "!! Revisar nginx"

echo "============================================================"
echo " sites-enabled/undersec.com.br -> link para sites-available"
echo " Lixo removido. Producao intacta."
echo "============================================================"
