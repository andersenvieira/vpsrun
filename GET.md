# vpsrun — instalação por link (Linux)

Um comando traz o seu código para a máquina e abre um **menu** com todas as
instalações e funções. Rode como root:

```bash
curl -fsSL https://raw.githubusercontent.com/andersenvieira/vpsrun/main/install.sh | sudo bash
```

Sem nenhuma flag ele instala as dependências, clona o kit em `/opt/vpsrun` e
mostra o menu. Para rodar direto sem menu (desatendido):

```bash
curl -fsSL <link>/install.sh | sudo bash -s -- --monitor --grafana --yes
```

## Como deixar o link curto e fácil de digitar

O `raw.githubusercontent.com/...` é comprido. Do mais simples ao mais bonito:

### 1) GitHub Pages (recomendado, grátis, sem depender de terceiros)
Ative o Pages do repositório (Settings → Pages → Branch: `main`, pasta `/docs`).
Já deixei pronto o arquivo [`docs/get`](docs/get) — um bootstrap mínimo que
baixa e executa o `install.sh` atual. Depois de ativar, o link vira:

```bash
curl -fsSL https://andersenvieira.github.io/vpsrun/get | sudo bash
```

> Dica: como o Pages serve o `docs/get`, você mantém a lógica só no `install.sh`
> (o `get` é só um "atalho" estável que aponta pra ele).

### 2) Domínio próprio (o mais curto de todos)
Se um dia tiver um domínio (ex.: `andersen.dev`), aponte um CNAME para o Pages e
o link fica algo como `curl -fsSL andersen.dev/vps | sudo bash`. É assim que o
rustup/Deno/Bun/MassGrave conseguem links curtos: domínio + redirecionador.

### 3) Encurtador (rápido, mas depende de terceiro)
Cole o link do Pages (ou do raw) num encurtador de sua confiança. Fácil, porém
some se o serviço cair — por isso prefiro a opção 1.

## O que o menu oferece
```
 1) Instalar Zabbix (server + frontend + DB)
 2) Instalar Zabbix + Grafana (painel pronto)
 3) Descobrir rede + instalar agentes (autoregistro)
 4) Registrar hosts do inventário via API
 5) Operações Ansible (SOC/NOC/TI) »   (update, install/remove, serviço,
                                         reboot, hardening, inventário, ad-hoc)
 6) Backup agora
 7) Saúde do sistema
 8) Abrir a TUI completa (vpsrun)
 9) Editar inventário / variáveis
 0) Sair
```
