#!/usr/bin/env bash
###############################################################################
# INSTALAR-TUDO.sh  -  MAESTRO: reconstroi a VPS inteira com UM comando
#
# Numa instalacao NOVA do Debian, este script executa, na ordem:
#   1) setup-vps.sh   -> instala stack + configura XRDP/GNOME + zram +
#                        desativa servicos inuteis/GDM + backup diario
#                        + RESTAURA os dados do backup (www, bancos, configs)
#   2) corrigir-nginx.sh    -> remove blocos duplicados (com rollback)
#   3) testar-restauracao.sh -> prova que os bancos restaurados estao integros
#
# USO (na maquina nova, apos extrair a pasta VPSRUN do pacote):
#   sudo bash INSTALAR-TUDO.sh /caminho/VPSRUN-completo-XXXX.tar.gz
#   # ou, se o pacote estiver ao lado, ele se acha sozinho:
#   sudo bash INSTALAR-TUDO.sh
#
# Variaveis opcionais:  DESKTOP=xfce  (desktop leve)   |  SKIP_RESTORE=1
###############################################################################
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo bash $0"; exit 1; }
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- Localiza o pacote (.tar.gz) com o backup -----------------------------
BUNDLE="${1:-}"
if [[ -z "$BUNDLE" ]]; then
    BUNDLE="$(ls -1t "$SELF_DIR"/../VPSRUN-completo-*.tar.gz \
                     "$SELF_DIR"/VPSRUN-completo-*.tar.gz \
                     "$SELF_DIR"/PARA-NUVEM/VPSRUN-completo-*.tar.gz \
                     ./VPSRUN-completo-*.tar.gz 2>/dev/null | head -1 || true)"
fi
if [[ "${SKIP_RESTORE:-0}" != "1" ]]; then
    if [[ -z "$BUNDLE" || ! -f "$BUNDLE" ]]; then
        echo "!! Pacote de backup nao encontrado."
        echo "   Informe o caminho:  sudo bash $0 /caminho/VPSRUN-completo-XXXX.tar.gz"
        echo "   (ou use SKIP_RESTORE=1 para so instalar/configurar, sem restaurar dados)"
        exit 1
    fi
    echo ">>> Pacote de backup: $BUNDLE"
fi

echo ""
echo "############################################################"
echo "# ETAPA 1/3 - Instalacao + configuracao + restauracao      #"
echo "############################################################"
if [[ "${SKIP_RESTORE:-0}" == "1" ]]; then
    bash "$SELF_DIR/setup-vps.sh"
else
    RESTORE=1 RESTORE_FROM="$BUNDLE" bash "$SELF_DIR/setup-vps.sh"
fi

echo ""
echo "############################################################"
echo "# ETAPA 2/3 - Limpeza do nginx (com rollback)              #"
echo "############################################################"
bash "$SELF_DIR/corrigir-nginx.sh" || echo "(nginx: revise manualmente se necessario)"

echo ""
echo "############################################################"
echo "# ETAPA 3/3 - Validacao da restauracao dos bancos          #"
echo "############################################################"
if [[ "${SKIP_RESTORE:-0}" != "1" ]]; then
    bash "$SELF_DIR/testar-restauracao.sh" || echo "(validacao: verifique manualmente)"
fi

echo ""
echo "============================================================"
echo " TUDO PRONTO. A maquina foi reconstruida."
echo " Pendencias manuais (segredos/decisoes - ver MANUAL.md sec.5):"
echo "   - Recriar container Docker (config em .../docker/*.inspect.json)"
echo "   - SSL/HTTPS (certbot) e apontamento de DNS"
echo " Recomendado:  sudo reboot"
echo "============================================================"
