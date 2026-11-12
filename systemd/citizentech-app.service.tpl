[Unit]
Description=Aplicacao CitizenTech (servico web)
Documentation=file://@APP_DIR@/README.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=@APP_USER@
Group=@APP_GROUP@
WorkingDirectory=@APP_DIR@
EnvironmentFile=@APP_ENV_FILE@
Environment=PATH=@APP_PATH@
ExecStart=/bin/bash -lc 'exec @APP_START_CMD@'
# Tolerancia a falhas: reinicia sempre que o processo cair
Restart=always
RestartSec=3
StartLimitIntervalSec=60
StartLimitBurst=10
# Endurecimento basico
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
StandardOutput=journal
StandardError=journal
SyslogIdentifier=citizentech-app

[Install]
WantedBy=multi-user.target
