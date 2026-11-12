# Gerado por 02-provision-app.sh - proxy reverso para a aplicação CitizenTech
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name app.@DOMAIN_NAME@ _;

    access_log /var/log/nginx/citizentech.access.log;
    error_log  /var/log/nginx/citizentech.error.log;

    location / {
        proxy_pass http://127.0.0.1:@APP_PORT@;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }
}
