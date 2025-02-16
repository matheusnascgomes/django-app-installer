#!/bin/bash

set -e  # Stop script on error

echo "🚀 Welcome to the Django VPS Deployment Script!"
echo "----------------------------------------------"

# Prompt user for project details
read -p "Enter your GitHub repository URL: " GITHUB_REPO
read -p "Enter the branch to deploy (default: main): " BRANCH
read -p "Enteder the django project name: " PROJECT_NAME
BRANCH=${BRANCH:-main}

# Extract project name from repository URL
PROJECT_DIR="/root/$PROJECT_NAME"
VENV_DIR="$PROJECT_DIR/venv"
GUNICORN_SERVICE="/etc/systemd/system/gunicorn.service"

# Prompt user for domain/IP
read -p "Enter your domain or server IP: " DOMAIN

# Prompt user for database details
read -p "Enter PostgreSQL database name: " DB_NAME
read -p "Enter PostgreSQL database username: " DB_USER
read -s -p "Enter PostgreSQL database password: " DB_PASS
echo ""

# Prompt user for email (for SSL certificate)
read -p "Enter your email for SSL certificate (Let's Encrypt): " EMAIL

echo "🚀 Updating and upgrading system..."
sudo apt update && sudo apt upgrade -y

echo "🔧 Installing required packages..."
sudo apt install -y python3-pip python3-venv nginx postgresql postgresql-contrib git certbot python3-certbot-nginx

echo "📂 Cloning GitHub repository..."
if [ -d "$PROJECT_DIR" ]; then
    echo "⚠️ Directory already exists. Pulling latest changes..."
    cd $PROJECT_DIR
    git pull origin $BRANCH
else
    git clone -b $BRANCH $GITHUB_REPO $PROJECT_DIR
fi
cd $PROJECT_DIR

echo "🐍 Creating and activating Python virtual environment..."
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

echo "📦 Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "💾 Setting up PostgreSQL database..."
sudo -u postgres psql <<EOF
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
ALTER ROLE $DB_USER SET client_encoding TO 'utf8';
ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';
ALTER ROLE $DB_USER SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

EOF

echo "⚙ Configuring Django settings..."
ENV_FILE="$PROJECT_DIR/.env"
cat <<EOL > $ENV_FILE
ENV=production
DEBUG=False
SECRET_KEY=$DB_PASS
DATABASE_URL=postgres://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME
ALLOWED_HOSTS=$DOMAIN
EOL

echo "📤 Running migrations..."
python manage.py migrate

echo "🎛 Collecting static files..."
python manage.py collectstatic --noinput

echo "🔥 Setting up Gunicorn systemd service..."
sudo tee $GUNICORN_SERVICE > /dev/null <<EOF
[Unit]
Description=Gunicorn instance to serve Django application
After=network.target

[Service]
User=root
Group=www-data
WorkingDirectory=$PROJECT_DIR
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --bind unix:$PROJECT_DIR/$PROJECT_NAME.sock $PROJECT_NAME.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 Enabling and starting Gunicorn..."
sudo systemctl daemon-reload
sudo systemctl start gunicorn
sudo systemctl enable gunicorn

echo "🌐 Setting up Nginx reverse proxy..."
NGINX_CONFIG="/etc/nginx/sites-available/$PROJECT_NAME"
sudo tee $NGINX_CONFIG > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        include proxy_params;
        proxy_pass http://unix:$PROJECT_DIR/$PROJECT_NAME.sock;
    }
}
EOF

echo "🔗 Enabling Nginx site..."
sudo ln -s $NGINX_CONFIG /etc/nginx/sites-enabled
sudo nginx -t
sudo systemctl restart nginx

echo "🔐 Setting up SSL with Certbot..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

echo "✅ Deployment complete! Your Django app is live at https://$DOMAIN"