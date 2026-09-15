#!/usr/bin/env bash
# vpsrun — instalador por link.
#
#   curl -fsSL https://raw.githubusercontent.com/andersenvieira/vpsrun/main/install.sh | sudo bash
#
# Opções (flags ou variáveis de ambiente):
#   --repo URL         Origem do kit           (VPSRUN_REPO,  padrão: repositório oficial)
#   --ref BRANCH       Branch/tag a usar       (VPSRUN_REF,   padrão: main)
#   --dir PATH         Onde instalar o kit     (VPSRUN_DIR,   padrão: /opt/vpsrun)
#   --monitor          Instala o Zabbix ao final
#   --grafana          Junto com --monitor, liga o Grafana com painel pronto
#   --discovery CIDR   Após o Zabbix, mapeia a rede e instala agentes
#   --no-build         Não compila o binário Go (usa só os playbooks)
#   --menu             Só mostra o menu de funções (não instala nada antes)
#   --yes              Não pergunta nada (modo desatendido)
#   --help             Mostra esta ajuda
#
# Sem nenhuma flag de ação, abre um MENU com as instalações e funções do vpsrun.
#
# Exemplos:
#   curl -fsSL <link>/install.sh | sudo bash                       # menu interativo
#   curl -fsSL <link>/install.sh | sudo bash -s -- --monitor --grafana --yes
set -euo pipefail

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
case "${1:-}" in --help|-h) usage;; esac

# ── parâmetros ──────────────────────────────────────────────────────────────
REPO="${VPSRUN_REPO:-https://github.com/andersenvieira/vpsrun.git}"
REF="${VPSRUN_REF:-main}"
DIR="${VPSRUN_DIR:-/opt/vpsrun}"
DO_MONITOR=0 DO_GRAFANA=0 DO_BUILD=1 ASSUME_YES=0 DISCOVERY_CIDR="" FORCE_MENU=0
ACTION_GIVEN=0
ORIG_ARGS=("$@")   # guardado para re-exec na versão do kit
# Fonte de input interativo (sobrescrevível para testes: VPSRUN_TTY=arquivo).
TTY="${VPSRUN_TTY:-/dev/tty}"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --ref) REF="$2"; shift 2;;
    --dir) DIR="$2"; shift 2;;
    --monitor) DO_MONITOR=1; ACTION_GIVEN=1; shift;;
    --grafana) DO_GRAFANA=1; ACTION_GIVEN=1; shift;;
    --discovery) DISCOVERY_CIDR="$2"; ACTION_GIVEN=1; shift 2;;
    --menu) FORCE_MENU=1; shift;;
    --no-build) DO_BUILD=0; shift;;
    --yes|-y) ASSUME_YES=1; shift;;
    *) echo "opção desconhecida: $1" >&2; exit 2;;
  esac
done
# Sem flag de ação (e sem --yes) → abre o menu de funções.
[ "$ACTION_GIVEN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ] && FORCE_MENU=1

log()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Rode como root (sudo)."

# ── detecção de distro ──────────────────────────────────────────────────────
. /etc/os-release 2>/dev/null || true
FAMILY="debian"
case "${ID_LIKE:-$ID}" in
  *rhel*|*fedora*|*centos*) FAMILY="rhel";;
esac
log "Distro: ${PRETTY_NAME:-desconhecida} (família $FAMILY)"

# ── dependências base ───────────────────────────────────────────────────────
# ansible-core >= 2.15? (as coleções modernas do Zabbix exigem)
_ansible_ok() {
  command -v ansible-playbook >/dev/null 2>&1 || return 1
  local v a b
  v="$(ansible-playbook --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
  [ -n "$v" ] || return 1
  a="${v%%.*}"; b="${v#*.}"
  [ "$a" -gt 2 ] || { [ "$a" -eq 2 ] && [ "$b" -ge 15 ]; }
}

if [ "${VPSRUN_REEXEC:-0}" != "1" ]; then
  log "Instalando dependências (nmap, git, curl, python)… (pode levar 1-2 min)"
  if [ "$FAMILY" = "debian" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y nmap git curl ca-certificates python3-pip python3-venv
  else
    (dnf install -y nmap git curl python3-pip || yum install -y nmap git curl python3-pip)
  fi

  if _ansible_ok; then
    ok "Ansible compatível: $(ansible-playbook --version | head -1)."
  else
    log "Ansible do sistema é antigo/ausente — instalando ansible-core moderno via pip…"
    python3 -m pip install --break-system-packages --upgrade 'ansible-core>=2.16' \
      || python3 -m pip install --upgrade 'ansible-core>=2.16'
    hash -r
    _ansible_ok && ok "Ansible instalado: $(ansible-playbook --version | head -1)." \
      || warn "ansible-playbook ainda parece antigo — confira se /usr/local/bin vem antes de /usr/bin no PATH."
  fi
fi

# ── obter o kit ─────────────────────────────────────────────────────────────
# 1) Rodando de dentro de um checkout (tem build.sh + ansible/)? Usa no lugar.
#    Nunca mexe no git desse diretório — só o utiliza como está.
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo '')"
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/build.sh" ] && [ -d "$SELF_DIR/ansible" ]; then
  DIR="$SELF_DIR"
  log "Usando o kit local em $DIR (nenhuma alteração no git)."
elif [ -d "$DIR/.git" ]; then
  # 2) Clone GERENCIADO pelo instalador (ex.: /opt/vpsrun) → sincroniza com o
  #    remoto de forma garantida (fetch + reset --hard). É seguro porque este
  #    diretório é só a instalação, não um checkout de trabalho (esse caso é
  #    tratado no ramo 1 acima, que nunca toca no git).
  log "Atualizando kit em $DIR (sincronizando com origin/$REF)…"
  git -C "$DIR" fetch -q origin "$REF" 2>/dev/null || git -C "$DIR" fetch -q --unshallow origin "$REF" 2>/dev/null || true
  git -C "$DIR" reset --hard -q FETCH_HEAD 2>/dev/null || warn "não consegui sincronizar; seguindo com o conteúdo atual."
else
  # 3) Nada ainda → clona limpo.
  log "Clonando $REPO ($REF) em $DIR…"
  git clone --depth 1 --branch "$REF" "$REPO" "$DIR" -q
fi
ok "Kit em $DIR"

# Re-executa a versão do KIT (garante o menu mais novo, mesmo que o script tenha
# vindo do cache do curl). Só quando ainda não estamos rodando o script do kit.
SELF_REAL="$(readlink -f "$0" 2>/dev/null || echo "$0")"
if [ "${VPSRUN_REEXEC:-0}" != "1" ] && [ -f "$DIR/install.sh" ] && [ "$SELF_REAL" != "$DIR/install.sh" ]; then
  export VPSRUN_REEXEC=1
  exec bash "$DIR/install.sh" "${ORIG_ARGS[@]}"
fi

# ── coleções Ansible ────────────────────────────────────────────────────────
if [ -f "$DIR/ansible/requirements.yml" ]; then
  log "Instalando coleções Ansible… (baixa alguns MB)"
  ansible-galaxy collection install -r "$DIR/ansible/requirements.yml"
  ok "Coleções instaladas."
fi

# ── binário Go (TUI/CLI) ────────────────────────────────────────────────────
install_binary() {
  if command -v go >/dev/null 2>&1 && [ "$DO_BUILD" -eq 1 ]; then
    log "Compilando o binário vpsrun…"
    ( cd "$DIR" && go build -o /usr/local/bin/vpsrun ./cmd/vpsrun \
        && go build -o /usr/local/bin/vpsrun-audit ./cmd/vpsrun-audit )
    ok "Binários em /usr/local/bin (vpsrun, vpsrun-audit)."
  elif ls "$DIR"/dist/vpsrun-kit-*-linux-amd64.tar.zst >/dev/null 2>&1; then
    log "Extraindo binário pré-compilado do Kit…"
    local kit; kit="$(ls -1 "$DIR"/dist/vpsrun-kit-*-linux-amd64.tar.zst | head -1)"
    tar --use-compress-program=unzstd -xf "$kit" -C "$DIR/dist" 2>/dev/null || true
    [ -f "$DIR/dist/vpsrun" ] && install -m0755 "$DIR/dist/vpsrun" /usr/local/bin/vpsrun && ok "Binário instalado."
  else
    warn "Go não encontrado e sem binário no Kit — seguindo só com os playbooks."
  fi
}
install_binary

# ── execução de playbooks ───────────────────────────────────────────────────
run_playbook() { ( cd "$DIR/ansible" && ansible-playbook -i inventory.ini "$@" ); }

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  read -r -p "$1 [s/N] " r <"$TTY" || return 1
  case "$r" in s|S|y|Y) return 0;; *) return 1;; esac
}
ask() { local __v; read -r -p "$1 " __v <"$TTY" || __v=""; printf '%s' "$__v"; }
askpass() { local __v; read -rs -p "$1 " __v <"$TTY" || __v=""; echo >&2; printf '%s' "$__v"; }
pause() { echo; read -r -p "  ▸ Pressione ENTER para voltar ao menu " _ <"$TTY" || true; }

# Mostra o painel de acessos (URLs + credenciais) gravado pelos playbooks.
show_access() {
  [ -f /root/vpsrun-zabbix.txt ] || return 0
  echo
  ok "════════ ACESSOS — anote ou recupere depois ════════"
  sed 's/^/   /' /root/vpsrun-zabbix.txt
  echo "   ──────────────────────────────────────────────────"
  echo "   Recupere quando quiser:  sudo cat /root/vpsrun-zabbix.txt"
}

# ── modo direto (flags de ação) ─────────────────────────────────────────────
if [ "$FORCE_MENU" -eq 0 ]; then
  if [ "$DO_MONITOR" -eq 1 ]; then
    extra=""; [ "$DO_GRAFANA" -eq 1 ] && extra="-e grafana_enabled=true"
    if confirm "Instalar o Zabbix agora neste host${extra:+ + Grafana}?"; then
      log "Instalando Zabbix${extra:+ + Grafana}…"
      # shellcheck disable=SC2086
      run_playbook playbooks/zabbix-server.yml $extra
      ok "Monitoramento instalado. Acesse http://<IP>/zabbix (Admin/zabbix — troque)."
    fi
    if [ -n "$DISCOVERY_CIDR" ] && confirm "Mapear a rede $DISCOVERY_CIDR e instalar agentes?"; then
      log "Descobrindo $DISCOVERY_CIDR…"
      run_playbook playbooks/discovery.yml -e "discovery_cidr=$DISCOVERY_CIDR"
      ok "Descoberta concluída — hosts entram sozinhos por autoregistro."
    fi
  fi
  exit 0
fi

# ── MENU de instalações e funções ───────────────────────────────────────────
menu_ops() {
  while :; do
    cat <<MENU

  ── Operações Ansible (SOC · NOC · TI) ─────────────────────
   a) Atualizar tudo (safe) no parque
   b) Atualizar só segurança
   c) Instalar apps em massa (pergunta os pacotes)
   d) Remover apps em massa
   e) Gerenciar serviço (start/stop/restart)
   f) Reboot controlado (rolling)
   g) Hardening básico (UFW + fail2ban + auto-updates)
   h) Inventário do parque (gera CSV)
   i) Comando ad-hoc no parque
   0) Voltar
MENU
    case "$(ask 'ops>')" in
      a) run_playbook playbooks/ops/update-all.yml; pause;;
      b) run_playbook playbooks/ops/update-all.yml -e security_only=true; pause;;
      c) p="$(ask 'pacotes (ex: htop,tmux):')"; [ -n "$p" ] && run_playbook playbooks/ops/install-package.yml -e "packages=$p"; pause;;
      d) p="$(ask 'pacotes a remover:')"; [ -n "$p" ] && run_playbook playbooks/ops/remove-package.yml -e "packages=$p"; pause;;
      e) s="$(ask 'serviço:')"; a="$(ask 'ação [restarted]:')"; run_playbook playbooks/ops/service.yml -e "service=$s action=${a:-restarted}"; pause;;
      f) run_playbook playbooks/ops/reboot.yml; pause;;
      g) run_playbook playbooks/ops/harden-basic.yml; pause;;
      h) run_playbook playbooks/ops/inventory-report.yml; pause;;
      i) c="$(ask 'comando:')"; [ -n "$c" ] && run_playbook playbooks/ops/run-command.yml -e "cmd=$c"; pause;;
      0|"") return;;
      *) warn "opção inválida";;
    esac
  done
}

# Assistente guiado de descoberta de rede (opções prontas, dados pré-preenchidos).
menu_discovery() {
  local myip pfx alvo scan exc ini fim r x2 ea
  myip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  pfx="$(printf '%s' "$myip" | awk -F. 'NF>=3{print $1"."$2"."$3}')"
  [ -n "$pfx" ] || pfx="192.168.0"

  echo
  cat <<PASSO1

  ── Descoberta · passo 1 de 2: QUAL faixa escanear? ─────────
   1) Minha rede local inteira        ($pfx.0/24)
   2) Uma faixa de IPs desta rede      (ex.: de $pfx.2 até $pfx.50)
   3) Outra rede (digitar)            (ex.: 10.0.0.0/24)
   4) Um único computador             (ex.: $pfx.10)
   0) Cancelar
PASSO1
  case "$(ask 'faixa>')" in
    1) alvo="$pfx.0/24";;
    2) ini="$(ask "  Número inicial (só o final, ex.: 2):")"
       fim="$(ask "  Número final   (só o final, ex.: 50):")"
       [ -n "$ini" ] && [ -n "$fim" ] && alvo="$pfx.$ini-$fim";;
    3) alvo="$(ask '  Digite a rede/CIDR (ex.: 10.0.0.0/24):')";;
    4) alvo="$(ask "  Digite o IP (ex.: $pfx.10):")";;
    *) return;;
  esac
  [ -n "$alvo" ] || { warn "faixa não informada"; return; }

  echo
  cat <<PASSO2

  ── Descoberta · passo 2 de 2: O QUE fazer com o que achar? ──
   1) Só MAPEAR a rede (não instala nada)      ← recomendado p/ começar
   2) MONITORAR: instalar o agente Zabbix nos hosts encontrados
PASSO2
  local strat suser skey
  case "$(ask 'estratégia>')" in
    2) strat="agent"
       suser="$(ask '  Usuário SSH dos servidores [root]:')"; suser="${suser:-root}"
       skey="$(ask "  Caminho da chave SSH [$HOME/.ssh/id_ed25519]:")"; skey="${skey:-$HOME/.ssh/id_ed25519}";;
    *) strat="map";;
  esac

  # Por padrão pula o gateway/firewall (.1) — a causa mais comum de problema.
  exc="$pfx.1"
  r="$(ask "  Pular o firewall/gateway ($pfx.1)? [S/n]:")"
  case "$r" in n|N) exc="";; esac
  x2="$(ask '  Excluir mais algum IP? (separe por vírgula, vazio=não):')"
  [ -n "$x2" ] && exc="${exc:+$exc,}$x2"

  echo
  ok "Resumo → faixa: $alvo  ·  $([ "$strat" = map ] && echo 'só mapear' || echo "monitorar por chave SSH ($suser)")  ·  excluir: ${exc:-nenhum}"
  confirm "Pode mapear a rede agora?" || { warn "cancelado"; return; }

  # 1) SEMPRE mapeia primeiro (sem tocar em ninguém) e mostra a lista.
  ea="-e discovery_cidr=$alvo -e discovery_scan_only=true"
  [ -n "$exc" ] && ea="$ea -e discovery_exclude=$exc"
  # shellcheck disable=SC2086
  run_playbook playbooks/discovery.yml $ea
  [ -f "$DIR/ansible/discovery-report.txt" ] && { echo; ok "Rede mapeada (salvo em $DIR/ansible/discovery-report.txt):"; sed 's/^/   /' "$DIR/ansible/discovery-report.txt"; }

  # 2) Se for monitorar, faz o onboarding por chave: testa → copia se preciso → instala nos que conectam.
  [ "$strat" = agent ] && onboard_and_install "$suser" "$skey"
  return 0
}

# Testa SSH por chave, oferece copiar a chave nos que faltam e instala o agente
# só nos hosts que realmente conectam. Nunca "pede senha e falha no meio".
onboard_and_install() {
  local suser="$1" skey="$2" rep="$DIR/ansible/discovery-report.txt"
  local ips ip reach="" unreach="" pw
  ips="$(grep -oE '^- [0-9.]+' "$rep" 2>/dev/null | awk '{print $2}')"
  [ -n "$ips" ] || { warn "nenhum host encontrado para instalar."; return; }

  # Garante a chave (gera se não existir).
  if [ ! -f "$skey" ]; then
    if confirm "A chave $skey não existe. Criar agora (sem senha)?"; then
      ssh-keygen -t ed25519 -N '' -f "$skey" -q && ok "Chave criada: $skey (.pub ao lado)."
    else warn "Sem chave não dá para seguir pelo modelo de chave."; return; fi
  fi

  echo; log "Testando quais servidores já aceitam sua chave…"
  for ip in $ips; do
    if ssh -i "$skey" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$suser@$ip" true 2>/dev/null; then
      reach="${reach:+$reach,}$ip"; echo "   ✔ $ip conecta"
    else
      unreach="${unreach:+$unreach }$ip"; echo "   ✖ $ip sem acesso ainda"
    fi
  done

  # Oferece copiar a chave nos que faltam (aí sim pede a senha, uma vez).
  if [ -n "$unreach" ] && confirm "Copiar sua chave para os hosts sem acesso? (pede a senha 1x)"; then
    command -v sshpass >/dev/null 2>&1 || { log "instalando sshpass…"; { [ "$FAMILY" = debian ] && apt-get install -y sshpass; } >/dev/null 2>&1 || true; }
    pw="$(askpass '  Senha SSH (a mesma nos servidores):')"
    for ip in $unreach; do
      if sshpass -p "$pw" ssh-copy-id -i "$skey.pub" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$suser@$ip" >/dev/null 2>&1; then
        ok "   chave copiada → $ip"; reach="${reach:+$reach,}$ip"
      else warn "   falhou em $ip (senha errada, sem acesso ou host recusou)"; fi
    done
    unset pw
  fi

  [ -n "$reach" ] || { warn "Nenhum servidor acessível por chave — nada a instalar."; return; }
  echo; ok "Vou instalar o agente Zabbix em: $reach"
  confirm "Confirma a instalação nesses hosts?" || { warn "cancelado"; return; }
  run_playbook playbooks/install-agents.yml -e "agent_hosts=$reach" -e "ansible_user=$suser" -e "ansible_ssh_private_key_file=$skey"
  ok "Feito. Os hosts que instalaram entram sozinhos no Zabbix (autoregistro)."
}

# A partir daqui é o menu interativo: uma tarefa que falha NÃO deve derrubar o
# menu (o usuário volta e tenta outra). A fase de preparação acima seguiu estrita.
set +e

while :; do
  cat <<MENU

  ┌─ vpsrun ─ instalações & funções ──────────────────────────┐
   Kit: $DIR   ·   distro: ${PRETTY_NAME:-?}

   1) Instalar Zabbix (server + frontend + DB)
   2) Instalar Zabbix + Grafana (painel pronto)
   3) Descobrir rede + instalar agentes (autoregistro)
   4) Registrar hosts do inventário via API
   5) Operações Ansible (SOC/NOC/TI) »
   6) Backup agora
   7) Saúde do sistema
   8) Abrir a TUI completa (vpsrun)
   9) Editar inventário / variáveis (nano)
   0) Sair
  └───────────────────────────────────────────────────────────┘
MENU
  case "$(ask 'vpsrun>')" in
    1) run_playbook playbooks/zabbix-server.yml; show_access; pause;;
    2) run_playbook playbooks/zabbix-server.yml -e grafana_enabled=true; show_access; pause;;
    3) menu_discovery; pause;;
    4) run_playbook playbooks/zabbix-register-hosts.yml; pause;;
    5) menu_ops;;
    6) ( cd "$DIR/scripts" 2>/dev/null && bash backup-vps.sh ) || warn "scripts/backup-vps.sh não encontrado"; pause;;
    7) ( cd "$DIR/scripts" 2>/dev/null && bash verificar-saude.sh ) || warn "scripts/verificar-saude.sh não encontrado"; pause;;
    8) if command -v vpsrun >/dev/null 2>&1; then vpsrun <"$TTY"; else warn "binário 'vpsrun' não instalado (rode com Go disponível)"; pause; fi;;
    9) ${EDITOR:-nano} "$DIR/ansible/inventory.ini" "$DIR/ansible/group_vars/all.yml" <"$TTY" || true;;
    0|"") ok "Até logo."; break;;
    *) warn "opção inválida";;
  esac
done
