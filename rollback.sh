#!/bin/bash

set +e  # Continue script on error

echo "🚀 Starting rollback process..."
echo "--------------------------------"

# Prompt user for project details
read -p "Enter the django project name: " PROJECT_NAME
PROJECT_DIR="/root/$PROJECT_NAME"
VENV_DIR="$PROJECT_DIR/venv"
GUNICORN_SERVICE="/etc/systemd/system/gunicorn.service"
NGINX_CONFIG="/etc/nginx/sites-available/$PROJECT_NAME"

# Prompt user for domain/IP
read -p "Enter your domain or server IP: " DOMAIN

echo "🛑 Stopping Gunicorn service..."
sudo systemctl stop gunicorn || true
sudo systemctl disable gunicorn || true

echo "🗑 Removing Gunicorn systemd service file..."
sudo rm -f $GUNICORN_SERVICE || true
sudo systemctl daemon-reload || true

echo "🛑 Stopping Nginx service..."
sudo systemctl stop nginx || true

echo "🗑 Removing Nginx site configuration..."
sudo rm -f $NGINX_CONFIG || true
sudo rm -f /etc/nginx/sites-enabled/$PROJECT_NAME || true
sudo nginx -t || true

echo "🗑 Removing SSL certificate..."
sudo certbot delete --cert-name $DOMAIN || true

echo "🗑 Removing project directory..."
sudo rm -rf $PROJECT_DIR || true

echo "🗑 Dropping PostgreSQL database and user..."
read -p "Enter PostgreSQL database name: " DB_NAME
read -p "Enter PostgreSQL database username: " DB_USER
sudo -u postgres psql <<EOF || true
DROP DATABASE IF EXISTS $DB_NAME;
DROP USER IF EXISTS $DB_USER;
EOF

echo "✅ Rollback complete!"