# Operações Ansible — SOC / NOC / TI

Rotinas úteis de plantão e administração de parque. Todas são idempotentes e
aceitam `-e 'target=<grupo>'` (padrão `all`) para limitar o alcance a um grupo
do `inventory.ini` (`web`, `db`, `monitored`, `managed`, …).

> ⚠️ Rodam como root nos alvos. Comece por um grupo pequeno antes de `target=all`.
> Use `--check` para simular e `--limit host1` para um único host.

## Atualizações
```bash
# Atualização segura de tudo
ansible-playbook -i inventory.ini playbooks/ops/update-all.yml
# Só atualizações de segurança
ansible-playbook -i inventory.ini playbooks/ops/update-all.yml -e 'security_only=true'
# Upgrade completo + reboot se preciso, 1 host por vez
ansible-playbook -i inventory.ini playbooks/ops/update-all.yml -e 'upgrade_type=full auto_reboot=true batch=1'
```

## Instalar / remover apps em massa
```bash
ansible-playbook -i inventory.ini playbooks/ops/install-package.yml -e 'packages=htop,tmux,curl'
ansible-playbook -i inventory.ini playbooks/ops/install-package.yml -e 'packages=nginx state=latest target=web'
ansible-playbook -i inventory.ini playbooks/ops/remove-package.yml  -e 'packages=telnet,rsh-client'
```

## Serviços
```bash
ansible-playbook -i inventory.ini playbooks/ops/service.yml -e 'service=nginx action=restarted target=web'
ansible-playbook -i inventory.ini playbooks/ops/service.yml -e 'service=zabbix-agent2 action=started enabled=true'
```

## Reboot controlado (rolling)
```bash
ansible-playbook -i inventory.ini playbooks/ops/reboot.yml -e 'target=web batch=1'
```

## Comando ad-hoc de plantão
```bash
ansible-playbook -i inventory.ini playbooks/ops/run-command.yml -e 'cmd="df -h /"'
ansible-playbook -i inventory.ini playbooks/ops/run-command.yml -e 'cmd="systemctl is-active nginx" target=web'
```

## Hardening básico (SOC)
```bash
ansible-playbook -i inventory.ini playbooks/ops/harden-basic.yml -e 'target=all'
```

## Inventário do parque
```bash
ansible-playbook -i inventory.ini playbooks/ops/inventory-report.yml
# → gera ansible/inventory-report.csv
```
