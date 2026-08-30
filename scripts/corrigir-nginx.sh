#!/usr/bin/env bash
###############################################################################
# corrigir-nginx.sh  -  Remove blocos 'server' duplicados de sites-enabled
#
# Os arquivos undersec.com.br.bak e .bak2 sao copias com o MESMO server_name
# do site ativo. O nginx carrega tudo de sites-enabled, gerando conflito.
# Este script move os .bak para sites-available (viram backup inofensivo),
# testa a config e, se falhar, DESFAZ tudo automaticamente (rollback).
#
# USO:  sudo bash ~/Documents/VPSRUN/corrigir-nginx.sh
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }

EN=/etc/nginx/sites-enabled
AV=/etc/nginx/sites-available
BKDIR="$AV/_backups_desativados"
FILES=(undersec.com.br.bak undersec.com.br.bak2)

echo ">>> Teste inicial do nginx (baseline)..."
if ! nginx -t 2>/dev/null; then
    echo "!! O nginx JA esta com erro antes de mexer. Abortando para nao piorar."
    nginx -t
    exit 1
fi

mkdir -p "$BKDIR"
MOVED=()
for f in "${FILES[@]}"; do
    if [[ -e "$EN/$f" ]]; then
        mv "$EN/$f" "$BKDIR/$f"
        MOVED+=("$f")
        echo "  movido: $EN/$f -> $BKDIR/$f"
    fi
done

echo ">>> Testando nginx apos a limpeza..."
if nginx -t 2>/dev/null; then
    systemctl reload nginx
    echo ">>> OK: nginx recarregado sem os duplicados."
    echo "    Backups guardados (inativos) em: $BKDIR"
else
    echo "!! Falhou. Fazendo ROLLBACK..."
    for f in "${MOVED[@]}"; do mv "$BKDIR/$f" "$EN/$f"; echo "  restaurado: $f"; done
    nginx -t
    echo "!! Config voltou ao estado anterior. Nada foi alterado em producao."
    exit 1
fi

echo ">>> sites-enabled agora:"
ls -1 "$EN"
