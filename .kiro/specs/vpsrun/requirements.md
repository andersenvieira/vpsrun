# Requirements Document — vpsrun

## Introdução

O `vpsrun` é uma mega-aplicação de terminal (TUI) para provisionar, operar, monitorar e replicar VPS Debian, além de servir como suíte de auditoria para terceiros numa variação standalone. O objetivo é ter automação robusta e reativa que **não dependa de créditos de IA** para funcionar: os mecanismos leem o estado real do sistema em tempo de execução e refletem qualquer mudança sem intervenção manual.

O produto tem duas edições a partir de uma base de código única:
- **vpsrun (server)**: instalado na VPS do próprio operador. Provisiona stack, cofre de credenciais, monitoramento, backup, tuning e updates.
- **vpsrun-audit (standalone)**: ferramenta portátil de diagnóstico de rede, auditoria de segurança e varredura de vulnerabilidades para uso em infraestruturas de clientes, com gate de autorização de escopo.

## Glossário

- **Operador**: usuário administrador que roda o vpsrun na própria VPS.
- **Cofre**: armazenamento criptografado de segredos e manuais, protegido por senha master.
- **Senha_Master**: senha configurável que deriva a chave de criptografia do Cofre; nunca é persistida.
- **Segredo_Estático**: valor definido manualmente (token, senha externa, nota) guardado criptografado no Cofre.
- **Resolver_Dinâmico**: rotina que lê um valor ao vivo de uma fonte do sistema (arquivo `.env`, `docker inspect`, config nginx) no momento da consulta.
- **Módulo**: unidade funcional acionável pelos menus (ex.: Monitoramento, Backup, Tuning).
- **Executor**: script Bash ou playbook Ansible chamado pela camada Go para executar ações no sistema.
- **Kit_Portátil**: artefato compactado que leva o vpsrun e seus executores de uma máquina a outra.
- **Alvo**: host de terceiro sob auditoria pela edição standalone.
- **Escopo_Autorizado**: lista de alvos/redes que o Operador declara ter permissão para auditar.

## Requisitos

### Requisito 1: Limpeza e Otimização do Sistema

**User Story:** Como Operador, quero rotinas guiadas de limpeza e otimização, para manter a VPS enxuta e gerar um estado base replicável sem dados desnecessários.

#### Acceptance Criteria
1. THE vpsrun SHALL oferecer um módulo de limpeza que identifica e reporta, antes de remover, o espaço ocupado por: caches de pacotes, logs sem rotação, imagens/containers Docker órfãos, backups duplicados e artefatos de build regeneráveis.
2. WHEN uma remoção for destrutiva ou irreversível, THE vpsrun SHALL exigir confirmação explícita e, quando aplicável, oferecer arquivar-antes-de-remover.
3. THE vpsrun SHALL configurar rotação de logs (journald, logrotate, Docker `max-size`/`max-file`) de forma idempotente, sem duplicar regras já existentes.
4. THE vpsrun SHALL preservar dados de produção e nunca remover volumes, bancos ou diretórios servidos sem confirmação do Operador.
5. THE vpsrun SHALL registrar cada ação de limpeza em log com data, item e espaço liberado.

### Requisito 2: Cofre de Credenciais Dinâmico

**User Story:** Como Operador, quero um cofre protegido por senha master onde eu navegue senhas de bancos, logins de aplicações e manuais por categoria, com valores sempre atualizados, para consultar informação confiável sem depender de IA.

#### Acceptance Criteria
1. THE Cofre SHALL exigir a Senha_Master para qualquer leitura ou escrita, e SHALL derivar a chave via KDF resistente a força bruta (argon2id) sem nunca persistir a Senha_Master em disco.
2. THE Cofre SHALL cifrar os Segredos_Estáticos em repouso com AES-256-GCM (ou equivalente autenticado), de modo que o arquivo do Cofre seja inútil sem a Senha_Master.
3. THE Cofre SHALL permitir navegação por **grupo**, por **aplicação** e por **tipo de senha**, com busca textual.
4. WHEN o Operador consultar um valor marcado como dinâmico, THE Cofre SHALL executar o Resolver_Dinâmico correspondente e exibir o valor lido ao vivo da fonte, não um valor estático armazenado.
5. IF uma configuração de origem (ex.: senha em `.env`, `server_name` do nginx, porta de container) mudar no sistema, THEN a próxima consulta no menu SHALL refletir o valor atualizado sem edição manual do Cofre.
6. THE vpsrun SHALL permitir alterar a Senha_Master, re-cifrando o Cofre com a nova chave derivada.
7. THE Cofre SHALL mascarar segredos por padrão na tela e exigir ação explícita para revelar ou copiar.
8. THE vpsrun SHALL manter o arquivo do Cofre fora de qualquer repositório de código e sincronizá-lo apenas cifrado para o armazenamento sensível (Google Drive).

### Requisito 3: Ecossistema de Aplicações (Meta / Chatwoot)

**User Story:** Como Operador, quero o ambiente focado na API Oficial da Meta para WhatsApp, com Chatwoot opcional apenas se compatível nativamente, para padronizar a mensageria.

#### Acceptance Criteria
1. THE vpsrun SHALL estruturar a integração de WhatsApp exclusivamente sobre a WhatsApp Cloud API oficial da Meta.
2. THE vpsrun SHALL oferecer o Chatwoot como módulo opcional, documentando que o canal usa a WhatsApp Cloud API oficial da Meta.
3. WHILE existir aplicação dependente da Evolution API, THE vpsrun SHALL manter a Evolution operacional e marcá-la como "em depreciação", sem removê-la.
4. WHEN o Operador confirmar que a última aplicação migrou para a Meta, THE vpsrun SHALL oferecer o decomissionamento controlado da Evolution (container, imagem, banco e volume), com confirmação.
5. THE vpsrun SHALL guardar tokens e segredos da Meta no Cofre, nunca em texto plano em configs versionadas.

### Requisito 4: Monitoramento e Automação (Zabbix + Ansible)

**User Story:** Como Operador, quero instalar uma estação de monitoramento Zabbix com descoberta de rede e distribuição autônoma de agentes via Ansible, com Grafana opcional, para monitorar qualquer host.

#### Acceptance Criteria
1. THE vpsrun SHALL oferecer instalação autoconfigurável do Zabbix (server, frontend e banco), registrando as credenciais geradas no Cofre.
2. THE vpsrun SHALL usar Ansible para descobrir hosts na rede, identificar o sistema operacional e instalar o agente Zabbix adequado de forma autônoma.
3. THE vpsrun SHALL tratar o Grafana como módulo **opcional**, habilitável ou não durante a instalação do Zabbix.
4. THE vpsrun SHALL entregar dashboards nativos do Zabbix cobrindo as métricas que seriam exibidas no Grafana, de modo que o sistema funcione plenamente só com o Zabbix.
5. WHERE o Grafana estiver desabilitado, THE vpsrun SHALL manter todos os gráficos essenciais disponíveis via Zabbix.
6. THE vpsrun SHALL permitir habilitar o Grafana posteriormente sem reinstalar o Zabbix, e desabilitá-lo mantendo os gráficos no Zabbix.

### Requisito 5: Tuning e Updates Guiados

**User Story:** Como Operador, quero menus de tuning profundo e updates guiados, para extrair o máximo da VPS e manter o software do meu pacote atualizado de forma segura.

#### Acceptance Criteria
1. THE vpsrun SHALL oferecer tuning de RAM (zram/swap, swappiness, caches) com valores aplicados de forma idempotente e reversível.
2. THE vpsrun SHALL oferecer tuning de rede (parâmetros sysctl, TCP BBR, filas) e de CPU (governor), exibindo o valor antes e depois de cada mudança.
3. THE vpsrun SHALL oferecer gestão estruturada de logs (rotação, retenção, tamanho máximo).
4. THE vpsrun SHALL manter um inventário dos softwares que ele mesmo instalou e oferecer atualização guiada apenas desses componentes.
5. WHEN uma atualização for aplicada, THE vpsrun SHALL registrar versão anterior e nova, e permitir consultar o histórico.
6. IF um ajuste de tuning degradar um serviço monitorado, THEN THE vpsrun SHALL permitir reverter o ajuste ao valor anterior.

### Requisito 6: Replicação e Portabilidade

**User Story:** Como Operador, quero gerar um instalador enxuto que reproduza minha VPS em qualquer Debian limpo, para não depender desta máquina específica.

#### Acceptance Criteria
1. THE vpsrun SHALL gerar um Kit_Portátil compactado contendo o binário, os Executores e os manifestos, separando código (GitHub) de dados sensíveis (Google Drive cifrado).
2. WHEN executado num Debian limpo, THE vpsrun SHALL provisionar a stack base e restaurar dados a partir de um backup indicado, deixando a máquina equivalente à origem.
3. THE vpsrun SHALL sincronizar código e segredos usando destinos distintos, sem jamais colocar segredos em texto plano no repositório de código.
4. THE vpsrun SHALL distribuir-se como binário único, sem exigir runtime instalado no destino.
5. THE vpsrun SHALL ter a arquitetura preparada para compilação multiplataforma (Linux e Windows) sem reescrever a lógica de menus.

### Requisito 7: Edição Standalone de Auditoria (Clientes / Kali)

**User Story:** Como prestador de serviço, quero uma edição standalone portátil para diagnóstico de rede, auditoria de segurança e varredura de vulnerabilidades em infraestrutura de clientes, para usar como ferramenta profissional.

#### Acceptance Criteria
1. THE vpsrun-audit SHALL ser um alvo de build separado da mesma base de código, sem os módulos de provisionamento do servidor.
2. THE vpsrun-audit SHALL exigir a definição de um Escopo_Autorizado antes de qualquer varredura, e SHALL recusar ações contra alvos fora do escopo.
3. THE vpsrun-audit SHALL oferecer descoberta de rede, diagnóstico e varredura de vulnerabilidades, registrando evidências em relatório.
4. THE vpsrun-audit SHALL registrar data, alvo e operador de cada ação para trilha de auditoria.
5. THE vpsrun-audit SHALL rodar em ambientes tipo Kali Linux como binário portátil.

### Requisitos Não-Funcionais

#### Segurança
1. THE vpsrun SHALL nunca gravar a Senha_Master, senhas de sudo ou tokens em logs ou em texto plano versionado.
2. THE vpsrun SHALL exibir aviso quando criar serviços expostos à rede sem autenticação.
3. THE vpsrun SHALL tratar conteúdo externo (saída de comandos, arquivos, rede) como não-confiável.

#### Usabilidade
1. THE vpsrun SHALL apresentar menus hierárquicos navegáveis por teclado, com indicação clara de contexto e ação, evitando menus numéricos confusos.
2. THE vpsrun SHALL confirmar ações destrutivas e permitir cancelar a qualquer momento.

#### Confiabilidade
1. THE vpsrun SHALL tornar operações de configuração idempotentes (reexecutar não duplica efeito).
2. THE vpsrun SHALL validar pré-condições antes de agir e reportar falhas de forma legível.
