# Implementation Plan — vpsrun

## Overview

Plano incremental. A base Go/Charm e o cofre vêm primeiro (fundação de UI + segurança), depois os módulos passam a orquestrar os Executores Bash/Ansible que já existem. Cada tarefa referencia requisitos para rastreabilidade.

## Estado de implementação (v0.1.0)

Funcional e publicado no repositório privado. Resumo:

- **Fundação Go/Charm** — TUI com menu em árvore, navegação por teclado. ✅
- **Cofre** — argon2id + AES-256-GCM, static/dynamic, troca de master, CLI `vpsrun vault`. Testes passando. ✅
- **Resolvers dinâmicos** — dotenv/nginx/docker/file/command (allowlist+timeout). Testes passando. ✅
- **Runner** — executor Bash seguro (args em slice). ✅
- **Tuning** — scripts idempotentes rede/ram/cpu (show/apply/revert), CLI `vpsrun tuning`. ✅
- **Limpeza** — relatório read-only. ✅
- **Monitoramento** — Zabbix (install + schema + autoregistro via API), discovery multi-CIDR com agente ativo, Grafana provisionado (data source + dashboard), registro por API. Ligado na TUI com confirmação. ✅ (código) / ⏳ (execução no cliente)
- **Operações SOC/NOC/TI** — catálogo Ansible em `playbooks/ops/` (update em massa, install/remove, serviços, reboot rolling, comando ad-hoc, hardening, inventário CSV). ✅
- **Instalador por link (Linux)** — `install.sh` (curl|bash): instala deps + coleções, traz o kit e abre um **menu** com todas as instalações e funções. Link curto via GitHub Pages (`docs/get`). Doc em `GET.md`. ✅
- **Standalone `vpsrun-audit`** — gate de escopo + scan TCP + trilha. Testes passando. ✅
- **Empacotamento** — `build.sh` cross-compila Linux/Windows e gera Kit `.tar.zst`. ✅

Pendências conhecidas: sync automático do cofre p/ Drive (2.4), módulos de instalação Meta/Chatwoot (5.2), backup via restic (7.3), updates guiados (8.2), validação de provisionamento em Debian limpo (11).

## Tasks

- [x] 1. Fundação do projeto Go
  - [ ] 1.1 Inicializar módulo Go, layout de diretórios (cmd/, internal/, scripts/, ansible/, templates/) e build tags para as edições server e audit
    - _Requirements: 6.4, 6.5, 7.1_
  - [ ] 1.2 Esqueleto da TUI com Bubble Tea: pilha de telas, navegação por teclado, menu raiz do rascunho
    - _Requirements: NF-Usabilidade 1, 2_
  - [ ] 1.3 Core: config.yaml (não-sensível), logging sem segredos, inventário de componentes
    - _Requirements: 5.4, 5.5, NF-Segurança 1_

- [x] 2. Cofre de Credenciais
  - [ ] 2.1 KDF argon2id + cifra AES-256-GCM; Senha_Master só em memória; criação e abertura do cofre
    - _Requirements: 2.1, 2.2, NF-Segurança 1_
  - [ ] 2.2 Schema de entries (grupo/app/tipo), CRUD, navegação e busca; mascaramento e revelar/copiar sob ação
    - _Requirements: 2.3, 2.7_
  - [ ] 2.3 Resolvers dinâmicos (dotenv, docker, nginx, file, command allowlisted) e modo dynamic vs static
    - _Requirements: 2.4, 2.5_
  - [ ] 2.4 Alterar Senha_Master (re-cifragem) e sync do cofre cifrado para o Drive
    - _Requirements: 2.6, 2.8_
  - [ ] 2.5 Checkpoint — testes de vault e resolvers passando

- [ ] 3. Orquestração e Executores
  - [ ] 3.1 Wrapper exec (args em array, streaming de progresso, captura de erro) integrando os scripts Bash existentes
    - _Requirements: NF-Segurança 3, NF-Confiabilidade 1, 2_
  - [ ] 3.2 Tornar os Executores idempotentes e parametrizáveis por env
    - _Requirements: 1.3, NF-Confiabilidade 1_

- [ ] 4. Módulo Limpeza & Otimização
  - [ ] 4.1 Relatório de ocupação (caches, logs, Docker órfão, backups duplicados) antes de remover
    - _Requirements: 1.1, 1.5_
  - [ ] 4.2 Ações de limpeza com confirmação e arquivar-antes-de-remover; rotação de logs idempotente
    - _Requirements: 1.2, 1.3, 1.4_

- [ ] 5. Módulo Instalação & Provisionamento
  - [ ] 5.1 Stack base + XRDP (perfis mobile/PC, tempos) via setup-vps.sh
    - _Requirements: 6.2_
  - [ ] 5.2 WhatsApp API Oficial Meta (tokens no cofre) e Chatwoot opcional
    - _Requirements: 3.1, 3.2, 3.5_
  - [ ] 5.3 Evolution em modo depreciação + decomissionamento controlado sob confirmação
    - _Requirements: 3.3, 3.4_
  - [ ] 5.4 Replicação: gerar Kit_Portátil e provisionar Debian limpo + restaurar
    - _Requirements: 6.1, 6.2, 6.3_

- [x] 6. Módulo Monitoramento (Zabbix + Ansible)
  - [x] 6.1 Instalação autoconfigurável do Zabbix (server/frontend/db + import de schema + senha do banco gerada) com registro no cofre
    - _Requirements: 4.1_
  - [x] 6.2 Grafana como módulo opcional (role dedicada: plugin Zabbix + data source e dashboard provisionados; liga/desliga sem reinstalar)
    - _Requirements: 4.3, 4.6_
  - [x] 6.3 Dashboards nativos do Zabbix + dashboard "Visão Geral" do Grafana (CPU/RAM/disco/rede/problemas)
    - _Requirements: 4.4, 4.5_
  - [x] 6.4 Ansible: descoberta multi-CIDR, detecção de SO, agente em modo ativo + autoregistro (ação na API) e registro via API para hosts passivos
    - _Requirements: 4.2_
  - [x] 6.5 Instalador por link (`install.sh`) com menu, e wiring da TUI para executar os playbooks com confirmação
    - _Requirements: 4.1, 4.2, NF-Usabilidade_

- [x] 12. Operações Ansible (SOC/NOC/TI) — `ansible/playbooks/ops/`
  - [x] 12.1 Atualização em massa (safe/dist, só segurança, reboot opcional, rolling)
  - [x] 12.2 Instalar/remover apps em massa; gerência de serviços
  - [x] 12.3 Reboot controlado, comando ad-hoc de plantão, coleta de inventário (CSV)
  - [x] 12.4 Hardening básico (UFW + fail2ban + auto-updates + SSH)

- [ ] 7. Módulo Backup & Restauração
  - [ ] 7.1 Rodar/agendar, retenção e sync rclone para o Drive
    - _Requirements: 6.3_
  - [ ] 7.2 Restauração com teste em schema temporário
    - _Requirements: 6.2_
  - [ ] 7.3 Avaliar/integrar restic (dedup + cifra + incremental)
    - _Requirements: 6.1, 6.3_

- [ ] 8. Módulo Tuning & Updates
  - [ ] 8.1 Tuning RAM/CPU/rede/logs com antes-depois e reversão
    - _Requirements: 5.1, 5.2, 5.3, 5.6_
  - [ ] 8.2 Updates guiados sobre o inventário do que o vpsrun instalou, com histórico
    - _Requirements: 5.4, 5.5_

- [x] 9. Edição Standalone (vpsrun-audit)
  - [ ] 9.1 Build separado por tags, sem módulos de servidor
    - _Requirements: 7.1, 7.5_
  - [ ] 9.2 Gate de Escopo_Autorizado + trilha de auditoria
    - _Requirements: 7.2, 7.4_
  - [ ] 9.3 Discovery, diagnóstico e varredura de vulnerabilidades com relatório
    - _Requirements: 7.3_

- [x] 10. Empacotamento e Multiplataforma
  - [ ] 10.1 Kit_Portátil (.tar.zst / makeself) separando código (GitHub) de segredos (Drive)
    - _Requirements: 6.1, 6.3_
  - [ ] 10.2 Preparar cross-compile Windows (interfaces por plataforma para ações de SO)
    - _Requirements: 6.5_

- [ ] 11. Checkpoint final — provisionar Debian limpo e validar equivalência com a origem

## Notes
- Preservar e reutilizar os scripts Bash já existentes em VPSRUN como Executores.
- Nenhum segredo em log ou no Git; cofre e backups só cifrados no Drive.
- Menus profissionais navegáveis por teclado; toda ação destrutiva confirmada e reversível quando possível.
- Ação imediata pendente do Operador: rotacionar a Senha_Master e a senha de sudo (expostas em chat).
