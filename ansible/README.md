# Ansible — Monitoramento (Zabbix) e Descoberta de Rede

Automação do módulo de Monitoramento do vpsrun. **Nada aqui é executado
automaticamente pela TUI** — instalar Zabbix/agentes é mudança de sistema e roda
somente sob comando explícito do operador.

## Conteúdo
- `inventory.ini` — inventário de exemplo (edite com seus hosts).
- `playbooks/zabbix-server.yml` — instala Zabbix Server + frontend + DB.
- `playbooks/discovery.yml` — varre a rede, detecta SO e instala o agente Zabbix.
- `roles/zabbix_agent/` — role idempotente do agente.
- `group_vars/all.yml` — variáveis (versão do Zabbix, Grafana on/off, servidor).

## Grafana é opcional
`grafana_enabled: false` em `group_vars/all.yml` instala **só o Zabbix**, com os
dashboards nativos. Para habilitar depois, mude para `true` e rode o playbook de
novo — nada precisa ser reinstalado. Para desabilitar, volte a `false`; os
gráficos continuam no Zabbix.

## Como executar (manual, sob sua decisão)
```bash
# pré-requisito: ansible instalado (sudo apt-get install -y ansible)
cd ansible
ansible-playbook -i inventory.ini playbooks/zabbix-server.yml            # servidor
ansible-playbook -i inventory.ini playbooks/discovery.yml                # descobrir + agentes
```

## Credenciais
As senhas geradas na instalação devem ser guardadas no cofre do vpsrun:
```bash
vpsrun vault add --group Monitoramento --app Zabbix --type db_password --label "Zabbix DB" --value '<senha>'
```
