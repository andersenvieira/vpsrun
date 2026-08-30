#!/usr/bin/env bash
###############################################################################
# verificar-saude.sh  -  Checagem pos-boot da VPS (producao + dev + backup)
#
# Mostra um relatorio com OK/FALHA de cada item. Pode rodar a qualquer momento:
#   sudo bash ~/Documents/VPSRUN/verificar-saude.sh
# Tambem roda sozinho no boot (servico vpsrun-healthcheck) gravando em:
#   /var/log/vpsrun-healthcheck.log
###############################################################################
PASS=0; FAIL=0
ok(){ echo "  [ OK ] $1"; PASS=$((PASS+1)); }
bad(){ echo "  [FALHA] $1"; FAIL=$((FAIL+1)); }
chk_active(){ systemctl is-active "$1" >/dev/null 2>&1 && ok "servico ativo: $1" || bad "servico INATIVO: $1"; }
chk_off(){ systemctl is-active "$1" >/dev/null 2>&1 && bad "deveria estar DESLIGADO: $1" || ok "desligado (correto): $1"; }
chk_port(){ ss -tlnH "( sport = :$1 )" 2>/dev/null | grep -q . && ok "porta escutando: $1 ($2)" || bad "porta FECHADA: $1 ($2)"; }

echo "==================================================================="
echo " VPSRUN - Checagem de saude  |  $(date)  |  uptime:$(uptime -p 2>/dev/null)"
echo "==================================================================="

echo "[ Servicos de PRODUCAO ]"
for s in nginx php8.4-fpm mariadb docker xrdp xrdp-sesman parkia-queue vpsrun-backup.timer; do
    chk_active "$s"
done

echo "[ Servicos que devem estar DESLIGADOS ]"
for s in gdm nxserver bluetooth cups avahi-daemon ModemManager wpa_supplicant; do
    chk_off "$s"
done

echo "[ Portas ]"
chk_port 22 ssh; chk_port 80 http; chk_port 443 https
chk_port 3306 mariadb; chk_port 3389 xrdp

echo "[ Docker ]"
if docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -q '^evo'; then
    ok "container evo rodando: $(docker ps --format '{{.Status}}' -f name=evo)"
else
    bad "container evo NAO esta rodando"
fi

echo "[ Sites (resposta HTTP local) ]"
code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 https://localhost/ 2>/dev/null)
[[ "$code" =~ ^(200|301|302|403)$ ]] && ok "nginx responde HTTPS (HTTP $code)" || bad "nginx HTTPS retornou: ${code:-sem resposta}"
nginx -t >/dev/null 2>&1 && ok "config do nginx valida" || bad "nginx -t com ERRO"

echo "[ Sistema ]"
[[ "$(systemctl get-default)" == "multi-user.target" ]] && ok "boot sem GDM (multi-user.target)" || bad "default target: $(systemctl get-default)"
swapon --show=NAME --noheadings 2>/dev/null | grep -q zram && ok "zram ativo" || bad "zram inativo"

echo "[ Backup ]"
LAST=$(ls -1dt /var/backups/vpsrun/20*_*/ 2>/dev/null | head -1)
[[ -n "$LAST" ]] && ok "ultimo backup: $(basename "$LAST")" || bad "nenhum backup encontrado"
systemctl is-enabled vpsrun-backup.timer >/dev/null 2>&1 && ok "timer de backup habilitado" || bad "timer de backup NAO habilitado"
NEXT=$(systemctl list-timers vpsrun-backup.timer --no-pager 2>/dev/null | awk 'NR==2{print $1,$2}')
echo "  proximo backup: ${NEXT:-?}"

echo "[ Recursos ]"
free -h | awk 'NR==2{print "  RAM: usada "$3" / disponivel "$7}'
df -h / | awk 'NR==2{print "  Disco /: usado "$3" de "$2" ("$5")"}'

echo "==================================================================="
echo " RESULTADO: $PASS OK, $FAIL falha(s)."
[[ "$FAIL" -eq 0 ]] && echo " >>> TUDO CERTO. Maquina saudavel apos o boot." \
                    || echo " >>> Ha itens a revisar (FALHA acima)."
echo "==================================================================="
