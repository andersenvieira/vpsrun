# Ansible — Monitoramento (Zabbix + Grafana) e Operações de TI

Automação do módulo de Monitoramento e das rotinas de SOC/NOC/TI do vpsrun.
**Nada aqui roda sozinho pela TUI sem sua confirmação** — instalar/alterar
sistemas é decisão do operador.

## Instalação por link
Veja [`../GET.md`](../GET.md). O `install.sh` (curl | bash) instala as
dependências, traz o kit e abre um **menu** com todas as instalações e funções.

## Pré-requisitos (uma vez)
```bash
sudo apt-get install -y ansible nmap
ansible-galaxy collection install -r ansible/requirements.yml
```

## Conteúdo
| Caminho | O que faz |
|---|---|
| `inventory.ini` | Inventário (grupos `zabbix_server`, `monitored`, `web`, `db`, `managed`). |
| `group_vars/all.yml` | Variáveis: versão do Zabbix, API, Grafana on/off, CIDR de descoberta, autoregistro. |
| `requirements.yml` | Coleções Ansible necessárias (community.zabbix, community.grafana, …). |
| `playbooks/zabbix-server.yml` | Instala Zabbix server+frontend+DB, importa schema, configura **autoregistro** e (opcional) Grafana provisionado. |
| `playbooks/discovery.yml` | Varre a(s) rede(s), detecta SO e instala o agente em **modo ativo** → hosts entram sozinhos no Zabbix. |
| `playbooks/zabbix-register-hosts.yml` | Cadastra hosts do grupo `[monitored]` via API (agentes passivos/SNMP). |
| `roles/zabbix_agent/` | Role do agente (ativo + `HostMetadata` para autoregistro). |
| `roles/grafana/` | Instala Grafana + plugin Zabbix + data source e dashboard já provisionados. |
| `playbooks/ops/` | Rotinas de SOC/NOC/TI (ver abaixo). |

## Fluxo típico numa empresa nova
```bash
cd ansible
# 1) sobe o monitoramento (single-node); senha da API via cofre/ambiente
ZABBIX_API_PASSWORD='...' ansible-playbook -i inventory.ini playbooks/zabbix-server.yml
# 2) mapeia a rede e instala agentes (entram sozinhos por autoregistro)
ansible-playbook -i inventory.ini playbooks/discovery.yml -e 'discovery_cidr=192.168.0.0/24'
# 3) (opcional) liga o Grafana com painel pronto
ansible-playbook -i inventory.ini playbooks/zabbix-server.yml -e 'grafana_enabled=true'
```

## Grafana é opcional
`grafana_enabled: false` instala **só o Zabbix** (dashboards nativos). Mude para
`true` e rode o playbook de novo para ganhar o Grafana com data source do Zabbix
e o dashboard **"vpsrun • Visão Geral"** já importado — nada é reinstalado.

## Segredos
As senhas geradas (banco do Zabbix, admin do Grafana) devem ir para o cofre:
```bash
vpsrun vault add --group Monitoramento --app Zabbix  --type db_password    --value '<senha>'
vpsrun vault add --group Monitoramento --app Grafana --type admin_password --value '<senha>'
```
Nunca versione senhas em `group_vars`. Injete via ambiente (`ZABBIX_API_PASSWORD`,
`ZABBIX_DB_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`) ou `-e`.

## Operações em massa (SOC/NOC/TI) — `playbooks/ops/`
Veja [`playbooks/ops/README.md`](playbooks/ops/README.md). Resumo:

| Playbook | Para quê |
|---|---|
| `update-all.yml` | Atualização de pacotes (safe/dist, só segurança, reboot opcional). |
| `install-package.yml` | Instala apps em massa (`-e packages=htop,tmux`). |
| `remove-package.yml` | Remove pacotes em massa. |
| `service.yml` | start/stop/restart/enable de serviços. |
| `reboot.yml` | Reboot em lotes (rolling). |
| `run-command.yml` | Comando ad-hoc no parque. |
| `harden-basic.yml` | UFW + fail2ban + auto-updates + SSH. |
| `inventory-report.yml` | Coleta CSV do parque (SO/CPU/RAM/disco). |

Todos aceitam `-e 'target=<grupo>'` para limitar o alcance (padrão: `all`).
