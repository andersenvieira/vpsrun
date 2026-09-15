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
log "Instalando dependências (ansible, nmap, git, curl)… (pode levar 1-2 min)"
if [ "$FAMILY" = "debian" ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ansible nmap git curl ca-certificates
else
  dnf install -y ansible nmap git curl || yum install -y ansible nmap git curl
fi
ok "Dependências prontas."

# ── obter o kit ─────────────────────────────────────────────────────────────
# 1) Rodando de dentro de um checkout (tem build.sh + ansible/)? Usa no lugar.
#    Nunca mexe no git desse diretório — só o utiliza como está.
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo '')"
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/build.sh" ] && [ -d "$SELF_DIR/ansible" ]; then
  DIR="$SELF_DIR"
  log "Usando o kit local em $DIR (nenhuma alteração no git)."
elif [ -d "$DIR/.git" ]; then
  # 2) Já existe um clone gerenciado pelo instalador → atualiza sem destruir.
  #    'pull --ff-only' NUNCA descarta trabalho local; se houver divergência ou
  #    mudanças não commitadas, ele falha de propósito e seguimos com o que há.
  log "Atualizando kit em $DIR (pull --ff-only, sem descartar nada)…"
  if ! git -C "$DIR" pull --ff-only -q origin "$REF"; then
    warn "Não deu para atualizar via fast-forward (mudanças locais?). Seguindo com o conteúdo atual."
  fi
else
  # 3) Nada ainda → clona limpo.
  log "Clonando $REPO ($REF) em $DIR…"
  git clone --depth 1 --branch "$REF" "$REPO" "$DIR" -q
fi
ok "Kit em $DIR"

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
pause() { read -r -p "  (enter para voltar ao menu) " _ <"$TTY" || true; }

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
    1) run_playbook playbooks/zabbix-server.yml; pause;;
    2) run_playbook playbooks/zabbix-server.yml -e grafana_enabled=true; pause;;
    3) c="$(ask 'CIDR [enter=usar group_vars]:')"; if [ -n "$c" ]; then run_playbook playbooks/discovery.yml -e "discovery_cidr=$c"; else run_playbook playbooks/discovery.yml; fi; pause;;
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
