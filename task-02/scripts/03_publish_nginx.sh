#!/usr/bin/env bash
# Настройка nginx
source "$(dirname "$0")/common.sh"

if ! command -v nginx >/dev/null; then
    log "Устанавливаем nginx..."
    sudo apt-get update && sudo apt-get install -y nginx
fi

SNIPPET=/etc/nginx/snippets/hadoop-rewrite.conf
SITE=/etc/nginx/sites-available/hadoop-ui

log "Генерируем конфиги nginx..."

# Пишем настройки замены ссылок
sudo bash -c "cat > $SNIPPET" <<EOF
proxy_set_header Accept-Encoding "";
sub_filter_once off;
sub_filter_types text/html text/css text/javascript application/javascript application/json;
sub_filter '//${NN_HOST}:8088'  '//\$host:${RM_PUBLIC_PORT}';
sub_filter '//${NN_HOST}:19888' '//\$host:${JHS_PUBLIC_PORT}';
sub_filter '//${NN_HOST}:9870'  '//\$host:${NN_PUBLIC_PORT}';
EOF

port=$NM_PUBLIC_PORT_BASE
for h in $NM_HOSTS; do
  sudo bash -c "cat >> $SNIPPET" <<EOF
sub_filter '//${h}:8042' '//\$host:${port}';
EOF
  port=$((port + 1))
done

# Пишем основной конфиг виртуального хоста
sudo bash -c "cat > $SITE" <<EOF
server {
    listen $RM_PUBLIC_PORT;
    location / {
        proxy_pass http://$NN_HOST:8088;
        proxy_set_header Host \$http_host;
        proxy_redirect http://$NN_HOST:8088/ http://\$host:$RM_PUBLIC_PORT/;
        proxy_redirect http://$NN_HOST:19888/ http://\$host:$JHS_PUBLIC_PORT/;
        include $SNIPPET;
    }
}

server {
    listen $JHS_PUBLIC_PORT;
    location / {
        proxy_pass http://$NN_HOST:19888;
        proxy_set_header Host \$http_host;
        proxy_redirect http://$NN_HOST:19888/ http://\$host:$JHS_PUBLIC_PORT/;
        include $SNIPPET;
    }
}
EOF

port=$NM_PUBLIC_PORT_BASE
for h in $NM_HOSTS; do
  sudo bash -c "cat >> $SITE" <<EOF
server {
    listen $port;
    location / {
        proxy_pass http://$h:8042;
        proxy_set_header Host \$http_host;
        proxy_redirect http://$h:8042/ http://\$host:$port/;
        include $SNIPPET;
    }
}
EOF
  port=$((port + 1))
done

sudo ln -sf $SITE /etc/nginx/sites-enabled/hadoop-ui
sudo systemctl restart nginx
log "Nginx перезапущен, интерфейсы опубликованы"