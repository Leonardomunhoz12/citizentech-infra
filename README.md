# CitizenTech AlertaEnchente - Infraestrutura Linux automatizada

Entrega de **Operating Systems** · FIAP · Engenharia de Software (3º ano) · Global Solution 2026.2

## Equipe

| Integrante | RM |
|---|---|
| Arthur Silva | RM553320 |
| Eduardo Escudero | RM556527 |
| Leonardo Prado | RM556824 |
| Davi Vieira | RM556798 |
| Luca Monteiro | RM556906 |

**Nome do grupo:** _(preencher)_

## Ficha da CitizenTech

| Campo | Preenchimento |
|---|---|
| Nome da CitizenTech | AlertaEnchente |
| Cidade e bairro | São Paulo, Jardim Helena (Zona Leste) |
| Cidadão beneficiado | Moradores e pequenos comerciantes de áreas alagáveis |
| Problema, em uma frase | Moradores de áreas alagáveis recebem os avisos de enchente tarde demais para proteger pessoas e bens. |
| Como funciona | Uma aplicação web mostra o nível dos córregos e o risco de alagamento por região, e avisa os moradores antes da cheia. Ela roda em um servidor Linux provisionado e monitorado por scripts, que se recupera sozinho de falhas para o aviso nunca ficar fora do ar. |
| O que cada parte faz | Operating Systems (este repositório): infraestrutura Linux, monitoramento, logs e testes de falha. Web Services e C#: API e regras de negócio. Mobile: app do morador. IoT: sensores de nível dos córregos. IA: previsão de risco. Cybersecurity: proteção de acessos e dados. Testing: qualidade e testes. |
| Link do repositório | https://github.com/Leonardomunhoz12/citizentech-infra |
| Indicador de impacto | Disponibilidade do serviço acima de 99% e recuperação automática de falhas em menos de 30 segundos (medido nos testes de falha) |
| ODS conectados | ODS 9, ODS 11 e ODS 13 |

### Como contribuímos para os ODS

- **ODS 9 (Indústria, inovação e infraestrutura):** uma infraestrutura resiliente, reproduzível por scripts e de baixo custo mantém o serviço disponível sem equipe de plantão.
- **ODS 11 (Cidades e comunidades sustentáveis):** o aviso confiável reduz o impacto das enchentes sobre quem vive em áreas de risco.
- **ODS 13 (Ação contra a mudança global do clima):** eventos extremos de chuva ficam mais frequentes, e um serviço de alerta sempre ativo ajuda as comunidades a se adaptarem.

## O que este repositório entrega

| Requisito | Onde está |
|---|---|
| Hostname, rede, DNS, usuários e diretórios | `scripts/01-provision-infra.sh` |
| Dependências, aplicação, variáveis de ambiente, permissões, serviço e nginx | `scripts/02-provision-app.sh`, `systemd/citizentech-app.service.tpl`, `config/nginx-citizentech.conf.tpl` |
| Monitoramento de CPU, RAM e disco com alertas | `scripts/monitor.sh` |
| Monitoramento como serviço systemd tolerante a falhas | `systemd/citizentech-monitor.service`, `systemd/citizentech-monitor-failure.service`, `scripts/03-install-monitor-service.sh` |
| Logs de execução e auditoria | `scripts/lib/common.sh` (grava em `/var/log/citizentech/`) |
| Testes de falha | `scripts/04-failure-tests.sh` |
| Evidências | `evidencias/` |

```
citizentech-infra/
├── provision-all.sh              # executa todo o provisionamento em ordem
├── config/
│   ├── citizentech.env           # todas as configurações (hostname, IP, DNS, limites...)
│   └── nginx-citizentech.conf.tpl
├── scripts/
│   ├── lib/common.sh             # log(), audit(), run_step(), trap de erro
│   ├── 01-provision-infra.sh
│   ├── 02-provision-app.sh
│   ├── 03-install-monitor-service.sh
│   ├── 04-failure-tests.sh
│   └── monitor.sh
├── systemd/                      # units do app, do monitor e do tratamento de falha
├── app-sample/                   # aplicação de exemplo (usada se APP_REPO_URL estiver vazio)
└── evidencias/                   # prints e logs dos testes
```

## Pré-requisitos

Ubuntu 22.04 ou 24.04 (ou Debian) com **systemd ativo** e acesso à internet. O ambiente foi testado em **Ubuntu no WSL2**. Uma VM (Azure, VirtualBox ou VMware) também funciona.

Para ligar o systemd no WSL2:

```bash
sudo tee /etc/wsl.conf <<'EOF'
[boot]
systemd=true
EOF
```

Depois, no PowerShell do Windows, rode `wsl --shutdown` e abra o Ubuntu de novo.

## Como reproduzir o ambiente

```bash
git clone https://github.com/Leonardomunhoz12/citizentech-infra.git
cd citizentech-infra

# 1) Revise as configurações (hostname, DNS, portas, limites de alerta):
nano config/citizentech.env

# 2) Provisione tudo com um comando:
sudo ./provision-all.sh
```

Também é possível rodar etapa por etapa:

```bash
sudo ./scripts/01-provision-infra.sh          # hostname, rede, DNS, usuário, diretórios
sudo ./scripts/02-provision-app.sh            # pacotes, app, variáveis, systemd, nginx
sudo ./scripts/03-install-monitor-service.sh  # serviço de monitoramento
```

Verificação rápida:

```bash
hostnamectl                                   # hostname configurado
curl -i http://localhost/health               # aplicação, via nginx
systemctl status citizentech-app citizentech-monitor nginx
sudo ./scripts/monitor.sh --once              # uma checagem manual
```

### Usar a aplicação real em vez da de exemplo

Em `config/citizentech.env`, preencha antes de provisionar:

```bash
APP_REPO_URL=https://github.com/<org>/<repo>.git
APP_START_CMD="node server.js"      # ou: python3 app.py / dotnet App.dll / npm start
EXTRA_PACKAGES="nodejs npm"
```

### Configuração de rede

- `NET_MODE=dhcp` (padrão): mantém o IP do ambiente. É o recomendado em WSL2 e Azure.
- `NET_MODE=static`: gera `/etc/netplan/60-citizentech.yaml` com `STATIC_IP`, `STATIC_GATEWAY` e `DNS_SERVERS`. Aplique com `APPLY_NETPLAN=yes sudo ./scripts/01-provision-infra.sh` (cuidado em sessão SSH).
- No WSL2 o IP é do Windows (NAT). Hostname e DNS ficam persistidos em `/etc/wsl.conf`.

## Monitoramento

`scripts/monitor.sh` mede CPU (amostra de `/proc/stat`), RAM (`MemAvailable`) e disco (`df`) e compara com `CPU_THRESHOLD=80`, `MEM_THRESHOLD=80` e `DISK_THRESHOLD=85`. Também confere se `citizentech-app` e `nginx` estão ativos.

| Modo | Descrição |
|---|---|
| `--once` | Uma verificação. Sai com 0 (tudo certo) ou 2 (alerta) |
| `--daemon` | Repete a cada `CHECK_INTERVAL` segundos (30 por padrão). É o modo do serviço systemd |
| `--fail-test` | Provoca uma falha controlada para validar o registro de erros |

Os limites podem ser trocados na hora: `CPU_THRESHOLD=10 sudo -E ./scripts/monitor.sh --once`.

### Serviço systemd tolerante a falhas

- `WantedBy=multi-user.target`: inicia junto com o sistema.
- Loop periódico dentro do serviço: executa o monitoramento continuamente.
- `Restart=always` e `RestartSec=5`: reinicia após qualquer interrupção, inclusive `kill -9`.
- `Type=notify` e `WatchdogSec=120`: se o loop travar, o systemd reinicia o serviço.
- `OnFailure=citizentech-monitor-failure.service`: registra cada falha do serviço em `erros.log` e `auditoria.log`.
- Controle manual: `sudo systemctl start|stop|restart|status citizentech-monitor`.

## Logs e auditoria

Ficam em `/var/log/citizentech/` e também vão para o journal (`journalctl -t citizentech`).

| Arquivo | Conteúdo |
|---|---|
| `provisionamento.log` | Instalações e configurações (início, OK ou FALHA de cada etapa, com tempo) |
| `monitor.log` | Cada verificação de CPU, RAM e disco |
| `alertas.log` | Alertas de consumo elevado |
| `erros.log` | Erros e falhas de scripts e serviços |
| `auditoria.log` | Quando, quem, em qual máquina, o que foi feito e o resultado |
| `testes-falha.log` | Execução dos testes de falha |
| `saida_comandos.log` | Saída bruta dos comandos (apt, nginx etc.) |

Consultas úteis:

```bash
sudo tail -f /var/log/citizentech/monitor.log
sudo cat /var/log/citizentech/alertas.log
sudo grep FALHA /var/log/citizentech/provisionamento.log
journalctl -u citizentech-monitor --since "10 min ago"
```

## Testes de falha

```bash
sudo ./scripts/04-failure-tests.sh        # todos (T1 a T6); grava evidencias/falhas-<data>.log
sudo ./scripts/04-failure-tests.sh t1     # apenas um
```

| Teste | Ação | Resultado obtido |
|---|---|---|
| T1 | `kill -9` no monitor | PASS: o systemd reiniciou com novo PID |
| T2 | `kill -9` na aplicação | PASS: voltou e `/health` respondeu 200 |
| T3 | Carga de CPU | PASS: alerta em `alertas.log` |
| T4 | Uso de memória | PASS: alerta em `alertas.log` |
| T5 | Erro controlado no script | PASS: erro em `erros.log` e `auditoria.log` |
| T6 | `stop`, `start` e `restart` | PASS: serviço controlável |

Resultado final da execução: **PASS=6 FAIL=0**. Os logs completos estão em [`evidencias/`](evidencias/).

### Teste de reinicialização

```bash
systemctl is-enabled citizentech-app citizentech-monitor nginx   # enabled
# WSL: no PowerShell rode "wsl --shutdown" e abra o Ubuntu de novo. VM: sudo reboot
systemctl is-active citizentech-app citizentech-monitor nginx    # active
curl http://localhost/health
```

## Evidências técnicas

Capturas de tela da execução real, na pasta `evidencias/`:

**1. Aplicação CitizenTech no ar**

![Aplicação no ar](evidencias/evidencia-01.jpeg)

**2. Resumo dos testes de falha (PASS=6 FAIL=0)**

![Resumo dos testes de falha](evidencias/evidencia-02.jpeg)

**3. Serviços ativos (app, monitor e nginx)**

![Status dos serviços](evidencias/evidencia-03.jpeg)

**4. monitor.log: verificações, alertas e recuperação**

![monitor.log](evidencias/evidencia-04.jpeg)

**5. alertas.log: alertas de CPU e RAM**

![alertas.log](evidencias/evidencia-05.jpeg)

**6. erros.log: falhas registradas**

![erros.log](evidencias/evidencia-06.jpeg)

**7. auditoria.log: trilha de auditoria**

![auditoria.log](evidencias/evidencia-07.jpeg)

**8. provisionamento.log: instalações e configurações**

![provisionamento.log](evidencias/evidencia-08.jpeg)

Logs gerados automaticamente pelos testes: `evidencias/falhas-20261111-201833.log` e `evidencias/falhas-20261111-205121.log`.

## Vídeo de demonstração

Link: _(inserir o link do vídeo)_

## Uso de IA

A IA foi usada como copiloto para estruturar e revisar os scripts. Os prompts estão registrados em [`prompts.md`](prompts.md).

## Solução de problemas

- **"systemd não está ativo"**: habilite `[boot] systemd=true` no WSL e reinicie o WSL.
- **Porta 80 ocupada**: veja quem usa com `sudo ss -ltnp | grep :80` e pare o serviço em conflito.
- **App real não sobe**: ajuste `APP_START_CMD` e `EXTRA_PACKAGES` e consulte `journalctl -u citizentech-app -n 50`.
- **Sem permissão em `/var/log/citizentech`**: execute com `sudo`.
