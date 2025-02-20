#!/bin/bash

set -e  # Para execução se algum comando falhar

echo "⚠️  Iniciando rollback completo da aplicação Django..."

# Solicita a confirmação do usuário antes de continuar
read -p "Tem certeza que deseja remover completamente a aplicação? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "❌ Rollback cancelado."
    exit 1
fi

# Solicita detalhes do projeto
read -p "Informe o nome do projeto Django: " PROJECT_NAME
read -p "Informe o domínio usado no Nginx: " DOMAIN
read -p "Informe o nome do banco de dados PostgreSQL: " DB_NAME
read -p "Informe o nome do usuário do banco de dados PostgreSQL: " DB_USER

PROJECT_DIR="/root/$PROJECT_NAME"
GUNICORN_SERVICE="/etc/systemd/system/gunicorn.service"
NGINX_CONFIG="/etc/nginx/sites-available/$PROJECT_NAME"
NGINX_ENABLED="/etc/nginx/sites-enabled/$PROJECT_NAME"

echo "🛑 Parando serviços..."
sudo systemctl stop gunicorn || true
sudo systemctl disable gunicorn || true
sudo systemctl stop nginx || true

echo "🗑 Removendo serviço Gunicorn..."
sudo rm -f "$GUNICORN_SERVICE"
sudo systemctl daemon-reload

echo "🗑 Removendo configuração do Nginx..."
sudo rm -f "$NGINX_CONFIG"
sudo rm -f "$NGINX_ENABLED"
sudo nginx -t
sudo systemctl restart nginx

echo "🛑 Removendo certificados SSL (Let's Encrypt)..."
sudo certbot revoke --cert-name "$DOMAIN" --delete-after-revoke || true
sudo rm -rf /etc/letsencrypt/live/"$DOMAIN"
sudo rm -rf /etc/letsencrypt/archive/"$DOMAIN"
sudo rm -rf /etc/letsencrypt/renewal/"$DOMAIN".conf

echo "🗑 Removendo diretório do projeto..."
sudo rm -rf "$PROJECT_DIR"

echo "🗄 Removendo banco de dados e usuário PostgreSQL..."
sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;
EOF

echo "📦 Removendo pacotes desnecessários..."
sudo apt remove -y nginx postgresql python3-pip python3-venv certbot python3-certbot-nginx
sudo apt autoremove -y

echo "✅ Rollback completo! O servidor foi limpo com sucesso."
