# Manual VPSRUN — Configuração, Backup e Recuperação da VPS

Debian 13 (headless) · AMD Ryzen 9 7950X3D (7 vCPU) · 7,6 GB RAM · disco 64 GB
Gerado em 22/06/2026. Usuário principal: `adminvps`.

---

## 1. Onde está cada coisa (mapa do sistema)

| O quê | Localização |
|---|---|
| **Kit VPSRUN** (scripts + este manual) | `~/Documents/VPSRUN/` |
| **MAESTRO** (roda tudo com um comando) | `~/Documents/VPSRUN/INSTALAR-TUDO.sh` |
| Script mestre de instalação | `~/Documents/VPSRUN/setup-vps.sh` |
| Aplicar mudanças nesta máquina (já configurada) | `~/Documents/VPSRUN/aplicar-agora.sh` |
| Script de backup | `~/Documents/VPSRUN/backup-vps.sh` (instalado em `/usr/local/bin/backup-vps.sh`) |
| Corrigir nginx (remover .bak duplicados, com rollback) | `~/Documents/VPSRUN/corrigir-nginx.sh` |
| Testar restauração do backup (schema temporário) | `~/Documents/VPSRUN/testar-restauracao.sh` |
| **Backups** (destino padrão Debian) | `/var/backups/vpsrun/AAAA-MM-DD_HHMMSS/` |
| Atalho para o backup mais recente | `/var/backups/vpsrun/latest` |
| Backups antigos recolhidos de /var/www | `/var/backups/vpsrun/legacy-backups/` |
| Log dos backups | `/var/log/vpsrun-backup.log` |
| **Aplicações web (produção)** | `/var/www/undersec.com.br` |
| Raiz servida pelo nginx | `/var/www/undersec.com.br/site1/public` |
| **Bancos MariaDB** (dados) | `/var/lib/mysql/` (acesso só via root/socket) |
| Config nginx | `/etc/nginx/` (sites em `/etc/nginx/sites-available` e `sites-enabled`) |
| Config PHP-FPM | `/etc/php/8.4/fpm/` |
| **Config XRDP** | `/etc/xrdp/` → `xrdp.ini`, `sesman.ini`, `startwm.sh` |
| Sessão gráfica do usuário | `~/.xsession` (log em `~/.session-xrdp.log`) |
| Config zram | `/etc/default/zramswap` |
| Container Docker (Evolution API) | imagem `atendai/evolution-api:latest` (restart unless-stopped) |
| Ollama (IA local) | binário `/usr/local/bin/ollama`, porta 11434 |
| Timer de backup | `/etc/systemd/system/vpsrun-backup.{service,timer}` |

---

## 2. O que foi feito nesta máquina (e por quê)

### 2.1 Acesso remoto RDP (porta 3389)
- **Problema original:** o `gnome-remote-desktop` (nativo) ocupava a 3389 em modo
  headless e exigia NLA/TLS que o app oficial da Microsoft no Android não fecha
  (erro `BIO_do_handshake failed`) → tela preta.
- **Solução:** trocado pelo **XRDP + xorgxrdp**, que cria uma sessão Xorg nova a
  cada login e fala o protocolo que o cliente Microsoft espera.
- **Desktop:** GNOME (visual padrão Debian) rodando em **Xorg** com **render por
  software** (`LIBGL_ALWAYS_SOFTWARE=1`, llvmpipe) — necessário porque a VPS não
  tem GPU; sem isso o GNOME Shell mostra "Algo deu errado".
- **Persistência:** `KillDisconnected=false` (mantém a sessão viva ao desconectar)
  + `max_bpp=32` (celular e notebook usam a mesma profundidade de cor e por isso
  reconectam na MESMA sessão). Resultado: você continua de onde parou ao trocar
  de aparelho. Obs.: a sessão não aparece em dois aparelhos ao mesmo tempo — o
  segundo "assume" e o primeiro é desconectado.

### 2.2 Otimizações de recurso
| Ação | Função / motivo |
|---|---|
| `systemctl set-default multi-user.target` | Não inicia login gráfico local (GDM). Economiza ~1,17 GB de RAM. O XRDP **não** depende do GDM. |
| `systemctl disable gdm` | Garante que o GDM não suba no boot. |
| Desativar `bluetooth` | VPS não tem Bluetooth. |
| Desativar `cups` + `cups-browsed` | Impressão; fecha a porta 631. |
| Desativar `avahi-daemon` | Descoberta mDNS de rede local, inútil em VPS. |
| Desativar `ModemManager` | Gerência de modems 3G/4G inexistentes. |
| Desativar `wpa_supplicant` | WiFi inexistente. |
| Desativar `switcheroo-control` | Troca entre GPUs, inexistente. |
| Desativar `nxserver` (NoMachine) | Segundo servidor de desktop remoto, redundante com o XRDP (fecha a porta 4000). |

### 2.3 Memória / swap
- **zram** via `zram-tools`: algoritmo lz4, 50% da RAM, prioridade 100 (usado antes
  do `/swapfile` em disco). Mantido como está — é uma boa configuração.

---

## 3. Comandos do dia a dia

```bash
# Rodar um backup manual agora
sudo /usr/local/bin/backup-vps.sh

# Ver quando o backup automático roda e o histórico
systemctl status vpsrun-backup.timer
systemctl list-timers vpsrun-backup.timer
tail -n 40 /var/log/vpsrun-backup.log

# Listar backups disponíveis
ls -lt /var/backups/vpsrun/

# Reiniciar o acesso remoto
sudo systemctl restart xrdp xrdp-sesman

# Ver memória e swap
free -h ; zramctl ; swapon --show
```

---

## 4. Backups: o que é salvo e como restaurar

Cada backup em `/var/backups/vpsrun/AAAA-MM-DD_HHMMSS/` contém:
- `databases/` — dump de cada banco MariaDB (`.sql.gz`) + `all-databases.sql.gz`.
- `www/var-www.tar.gz` — aplicações de `/var/www` (sem os zips antigos).
- `docker/` — config dos containers (`*.inspect.json`), lista de imagens e compose.
- `configs/` — cópia de `xrdp`, `nginx`, `php`, `zramswap`, `fstab`, crontab,
  lista de pacotes instalados, serviços habilitados e o próprio kit VPSRUN.

Rotação: mantém os últimos **7** backups (ajuste com `RETENTION=N`).

**Modos de backup:**
- A quente (padrão): `sudo /usr/local/bin/backup-vps.sh` — sem downtime.
- Consistente: `sudo CONSISTENT=1 /usr/local/bin/backup-vps.sh` — pausa o worker de
  fila e põe os apps Laravel em manutenção (`artisan down`) só durante o dump, e
  **religa tudo automaticamente** ao final, mesmo se houver erro (via `trap`).
  O backup diário automático roda no modo a quente; o backup da faxina inicial
  roda no modo consistente. O dump também grava `databases/_engines.txt` com o
  engine de cada tabela (auditoria InnoDB x MyISAM).

### Restaurar tudo numa instalação nova do Debian
```bash
# 1) Copie a pasta VPSRUN (ou o backup) para a nova máquina, ex. em ~/Documents
# 2) Restaure os dados a partir de um backup colocado em /var/backups/vpsrun/latest
sudo RESTORE=1 bash ~/Documents/VPSRUN/setup-vps.sh
sudo reboot
```

### Restaurar só um banco
```bash
zcat /var/backups/vpsrun/latest/databases/NOMEDOBANCO.sql.gz | sudo mysql NOMEDOBANCO
```

### Restaurar só os arquivos web
```bash
sudo tar -xzf /var/backups/vpsrun/latest/www/var-www.tar.gz -C /
```

---

## 5. Passos MANUAIS (não automatizados — exigem decisão/segredos)

1. **Segredos / .env**: o container Evolution API e apps Laravel usam chaves
   (`AUTHENTICATION_API_KEY`, `DATABASE_CONNECTION_URI`, etc.). Guarde os arquivos
   `.env` / variáveis em local seguro e recoloque-os após restaurar.
2. **Recriar o container Docker** (ex.: Evolution API):
   ```bash
   docker run -d --name evo --restart unless-stopped \
     --env-file /caminho/evo.env atendai/evolution-api:latest
   ```
   (confira a config exata em `/var/backups/vpsrun/latest/docker/evo.inspect.json`)
3. **Ollama** (IA local):
   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ```
4. **SSL / HTTPS**: reemitir certificados (ex.: `certbot --nginx`).
5. **DNS**: apontar os domínios para o IP da nova VPS.
6. **nginx — limpeza pendente**: remover `undersec.com.br.bak` e `.bak2` de
   `/etc/nginx/sites-enabled/` (o nginx carrega tudo dessa pasta e isso gera
   blocos `server` duplicados). Mantenha backups em `sites-available`. Sempre
   teste com `sudo nginx -t` antes de `sudo systemctl reload nginx`.

---

## 6. Ordem recomendada numa instalação nova

### Jeito mais fácil — UM comando só (recomendado)
Extraia a pasta `VPSRUN` do pacote e rode o maestro, que executa todos os
outros scripts na ordem certa (instala, configura, otimiza, restaura, corrige
nginx e valida):
```bash
tar -xzf VPSRUN-completo-XXXX.tar.gz VPSRUN
sudo bash VPSRUN/INSTALAR-TUDO.sh VPSRUN-completo-XXXX.tar.gz
sudo reboot
```

### Jeito manual (passo a passo), se preferir controle
```bash
sudo bash ~/Documents/VPSRUN/setup-vps.sh
sudo RESTORE=1 bash ~/Documents/VPSRUN/setup-vps.sh
sudo reboot
```
