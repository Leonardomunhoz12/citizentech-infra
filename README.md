# CitizenTech – Infraestrutura Linux automatizada (Operating Systems · GS 2026.2)

> **Integrantes da equipe** (preencher antes de entregar):
> - Arthur Silva – RM553320
> - Eduardo Escudero – RM556527
> - Leonardo Prado – RM556824
> - Davi Vieira – RM556798
> - Luca Monteiro – RM556906

## Ficha da CitizenTech

| Campo | Preenchimento |
|---|---|
| Nome da CitizenTech | _(nome do projeto da equipe)_ |
| Cidade e bairro | _(ex.: São Paulo – Liberdade)_ |
| Cidadão beneficiado | _(quem usa)_ |
| Problema, em uma frase | _(...)_ |
| Como funciona | Aplicação web hospedada nesta infraestrutura Linux, atrás de nginx, com monitoramento contínuo |
| O que cada parte faz | Esta pasta: infraestrutura (rede, DNS, usuários, serviços, monitoramento, logs, testes de falha). Demais disciplinas: backend, app, IoT, IA etc. |
| Link do repositório | _(URL do GitHub)_ |
| Indicador de impacto | Disponibilidade da aplicação (uptime) e tempo de recuperação após falhas |
| ODS conectados | ODS 9 (Indústria, inovação e infraestrutura) e ODS 11 (Cidades e comunidades sustentáveis) |

**Contribuição para os ODS:** uma infraestrutura reproduzível e monitorada mantém a solução cidadã disponível com baixo custo (ODS 9) e sustenta serviços digitais urbanos confiáveis (ODS 11).

---

## O que este repositório entrega

| Requisito da disciplina | Onde está |
|---|---|
| Provisionamento de rede, hostname, DNS, IP, usuários | `scripts/01-provision-infra.sh` |
| Provisionamento da aplicação (dependências, variáveis, permissões, serviço, boot) | `scripts/02-provision-app.sh`, `systemd/citizentech-app.service.tpl`, `config/nginx-citizentech.conf.tpl` |
| Monitoramento de CPU, RAM e disco com alertas | `scripts/monitor.sh` |
| Monitoramento como serviço systemd tolerante a falhas | `systemd/citizentech-monitor.service`, `systemd/citizentech-monitor-failure.service`, `scripts/03-install-monitor-service.sh` |
| Logs e auditoria | `scripts/lib/common.sh` → `/var/log/citizentech/*.log` |
| Testes de falha | `scripts/04-failure-tests.sh` |
| Evidências | `evidencias/` |

```
citizentech-infra/
├── provision-all.sh              # executa tudo em ordem
├── config/
│   ├── citizentech.env           # TODAS as configurações (hostname, IP, DNS, limites...)
│   └── nginx-citizentech.conf.tpl
├── scripts/
│   ├── lib/common.sh             # log(), audit(), run_step(), trap de erro
│   ├── 01-provision-infra.sh
│   ├── 02-provision-app.sh
│   ├── 03-install-monitor-service.sh
│   ├── 04-failure-tests.sh
│   └── monitor.sh
├── systemd/                      # units (app, monitor, handler de falha)
├── app-sample/                   # app de exemplo (usada se APP_REPO_URL estiver vazio)
└── evidencias/                   # prints e logs dos testes
```

## Pré-requisitos

Ubuntu 22.04/24.04 (ou Debian) com **systemd ativo** e acesso à internet, em uma destas opções:

- **VM Azure / VirtualBox / VMware** (opção recomendada)
- **WSL2** com systemd habilitado:
  ```bash
  # dentro do Ubuntu/WSL
  sudo tee /etc/wsl.conf <<'EOF'
  [boot]
  systemd=true
  EOF
  # no PowerShell do Windows:  wsl --shutdown   (e abra o Ubuntu de novo)
  ```

## Instalação e execução (reprodução do ambiente)

```bash
git clone <URL_DO_REPOSITORIO> citizentech-infra
cd citizentech-infra

# 1) Edite os nomes da equipe, hostname, DNS, portas e limites:
nano config/citizentech.env

# 2) (Opcional) Use a SUA aplicação em vez da de exemplo:
#    APP_REPO_URL=https://github.com/<org>/<repo>.git
#    APP_START_CMD="node server.js"    # ou: dotnet App.dll / python3 app.py / npm start
#    EXTRA_PACKAGES="nodejs npm"

# 3) Provisione tudo com um comando:
sudo ./provision-all.sh
```

Ou etapa por etapa:

```bash
sudo ./scripts/01-provision-infra.sh          # hostname, rede, DNS, usuário, diretórios
sudo ./scripts/02-provision-app.sh            # pacotes, app, env, systemd, nginx
sudo ./scripts/03-install-monitor-service.sh  # serviço de monitoramento
```

Verificação rápida:

```bash
hostnamectl                                   # hostname configurado
curl -i http://localhost/health               # aplicação (via nginx)
systemctl status citizentech-app citizentech-monitor nginx
sudo ./scripts/monitor.sh --once              # uma checagem manual
```

### Configuração de rede
- `NET_MODE=dhcp` (padrão): mantém o IP fornecido pelo ambiente (Azure e WSL2 gerenciam o IP).
- `NET_MODE=static`: gera `/etc/netplan/60-citizentech.yaml` com `STATIC_IP`, `STATIC_GATEWAY` e `DNS_SERVERS`; aplique com `APPLY_NETPLAN=yes sudo ./scripts/01-provision-infra.sh` (cuidado em sessões SSH).
- No **WSL2** o IP é do Windows (NAT); hostname e DNS são persistidos via `/etc/wsl.conf`.

## Monitoramento

`scripts/monitor.sh` mede CPU (amostragem de `/proc/stat`), RAM (`MemAvailable`) e disco (`df`) e compara com `CPU_THRESHOLD`, `MEM_THRESHOLD` e `DISK_THRESHOLD`. Também verifica se `citizentech-app` e `nginx` estão ativos.

| Modo | Descrição |
|---|---|
| `--once` | Uma verificação; sai com 0 (OK) ou 2 (alerta) |
| `--daemon` | Loop a cada `CHECK_INTERVAL` s (usado pelo systemd) |
| `--fail-test` | Gera uma falha controlada para validar o registro de erros |

Os limites podem ser alterados na hora: `CPU_THRESHOLD=10 sudo -E ./scripts/monitor.sh --once`.

### Serviço systemd tolerante a falhas
- `WantedBy=multi-user.target` → **inicia com o sistema**.
- Loop periódico dentro do serviço → **execução periódica**.
- `Restart=always` + `RestartSec=5` → **recupera após interrupção** (inclusive `kill -9`).
- `Type=notify` + `WatchdogSec=120` → se o loop travar, o systemd reinicia o serviço.
- `OnFailure=citizentech-monitor-failure.service` → registra a falha definitiva em `erros.log`/`auditoria.log`.
- Controle: `sudo systemctl start|stop|restart|status citizentech-monitor`.

## Logs e auditoria (`/var/log/citizentech/`)

| Arquivo | Conteúdo |
|---|---|
| `provisionamento.log` | Instalações e configurações (início/OK/FALHA de cada etapa, com tempo) |
| `monitor.log` | Cada verificação de CPU/RAM/disco |
| `alertas.log` | Alertas de consumo elevado |
| `erros.log` | Erros e falhas de scripts e serviços |
| `auditoria.log` | Trilha: **quando**, **quem**, **o quê** e **resultado** |
| `testes-falha.log` | Execução dos testes de falha |
| `saida_comandos.log` | Saída bruta dos comandos (apt, nginx etc.) |

Também vão para o syslog/journal (`journalctl -t citizentech`, `journalctl -u citizentech-monitor`).

Consultas úteis:
```bash
sudo tail -f /var/log/citizentech/monitor.log
sudo cat /var/log/citizentech/alertas.log
sudo grep FALHA /var/log/citizentech/provisionamento.log
journalctl -u citizentech-monitor --since "10 min ago"
```

## Testes de falha

```bash
sudo ./scripts/04-failure-tests.sh        # todos (T1–T6); grava evidencias/falhas-<data>.log
sudo ./scripts/04-failure-tests.sh t1     # apenas um
```

| Teste | Ação | Resultado esperado |
|---|---|---|
| T1 | `kill -9` no monitor | systemd reinicia com novo PID |
| T2 | `kill -9` na aplicação | app volta e `/health` responde 200 |
| T3 | Carga de CPU (stress-ng) | alerta em `alertas.log` |
| T4 | Carga/limiar de RAM | alerta em `alertas.log` |
| T5 | Comando inexistente no script | erro em `erros.log` + `auditoria.log` |
| T6 | `stop` / `start` / `restart` | serviço controlável |

### Teste de reinicialização
```bash
systemctl is-enabled citizentech-app citizentech-monitor nginx   # enabled
sudo reboot                                                       # (WSL: wsl --shutdown e reabrir)
# após voltar:
systemctl is-active citizentech-app citizentech-monitor nginx
curl http://localhost/health
sudo tail -n 5 /var/log/citizentech/monitor.log                  # logs retomados
```

## Evidências técnicas
Salve prints em `evidencias/` com estes nomes sugeridos:

1. `01-provisionamento-infra.png` – saída de `01-provision-infra.sh`
2. `02-provisionamento-app.png` – saída de `02-provision-app.sh`
3. `03-app-no-ar.png` – navegador em `http://localhost/` + `curl /health`
4. `04-systemctl-status.png` – app, monitor e nginx ativos
5. `05-monitor-log.png` – `tail monitor.log`
6. `06-alerta-cpu.png` – `alertas.log` após o T3
7. `07-recuperacao-servico.png` – T1/T2 (PID mudou)
8. `08-erro-controlado.png` – T5 em `erros.log`
9. `09-auditoria.png` – `auditoria.log`
10. `10-pos-reboot.png` – serviços ativos após reinicialização

Os logs `evidencias/falhas-*.log` são gerados automaticamente pelo script de testes.

## Roteiro do vídeo (≤ 7 min)

| Tempo | Conteúdo |
|---|---|
| 0:00–0:30 | Apresentação da equipe e do ambiente (`hostnamectl`, `uname -a`) |
| 0:30–2:30 | `sudo ./provision-all.sh` (acelere trechos longos do `apt`) |
| 2:30–3:15 | Aplicação funcionando no navegador + `/health` |
| 3:15–4:15 | `monitor.sh --once`, `systemctl status`, `tail monitor.log` |
| 4:15–6:15 | `04-failure-tests.sh`: kill do monitor → recuperação; carga de CPU → alerta; erro controlado |
| 6:15–7:00 | Consulta de `auditoria.log`, reboot/conclusão |

## Solução de problemas
- **"systemd não está ativo"** → habilite `[boot] systemd=true` no WSL e reinicie o WSL.
- **Porta 80 ocupada** → pare o serviço em conflito (`sudo ss -ltnp | grep :80`).
- **App real não sobe** → ajuste `APP_START_CMD`/`EXTRA_PACKAGES` e rode `journalctl -u citizentech-app -n 50`.
- **Sem permissão em `/var/log/citizentech`** → execute com `sudo`.
