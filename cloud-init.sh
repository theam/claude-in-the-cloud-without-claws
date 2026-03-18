#!/bin/bash
set -euo pipefail
exec > /var/log/coder-setup.log 2>&1

echo "=== Coder Setup Starting ==="

# ---- Install Docker ----
apt-get update
apt-get install -y ca-certificates curl gnupg jq
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker

# ---- Clone repo ----
cd /opt
git clone https://github.com/theam/claude-in-the-cloud-without-claws.git coder
cd /opt/coder

# ---- Get public IP for access URL ----
PUBLIC_IP=$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -sf https://ifconfig.me)

# ---- Create .env ----
DOCKER_GID=$(getent group docker | cut -d: -f3)
cat > .env <<ENVEOF
CODER_ACCESS_URL=http://${PUBLIC_IP}
POSTGRES_USER=coder
POSTGRES_PASSWORD=zlmyHWXo+GWg4odGlCJzy8F/PWzHCM2s
POSTGRES_DB=coder
DOCKER_GROUP_ID=${DOCKER_GID}
ENVEOF

# ---- Start services ----
docker compose up -d

# ---- Wait for Coder to be healthy ----
echo "Waiting for Coder..."
for i in $(seq 1 60); do
  if curl -sf http://localhost/healthz >/dev/null 2>&1; then
    echo "Coder is healthy!"
    break
  fi
  sleep 3
done

# ---- Create admin user ----
FIRST_CHECK=$(curl -sf http://localhost/api/v2/users/first 2>&1 || true)
if echo "$FIRST_CHECK" | grep -q "initial user has not been created"; then
  curl -sf -X POST http://localhost/api/v2/users/first \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@theagilemonkeys.com","username":"admin","password":"RTMLPVL9rJesnPnYBzoH7imrquHr3wDG"}'
  echo "Admin user created."
fi

# ---- Install Coder CLI and push template ----
curl -fsSL https://coder.com/install.sh | sh

SESSION_TOKEN=$(curl -sf -X POST http://localhost/api/v2/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@theagilemonkeys.com","password":"RTMLPVL9rJesnPnYBzoH7imrquHr3wDG"}' | jq -r '.session_token')

echo "$SESSION_TOKEN" | coder login --use-token-as-session http://localhost

coder templates push docker-claude-code \
  --directory /opt/coder/templates/docker-claude-code \
  --yes

echo "=== Coder Setup Complete ==="
echo "Dashboard: http://${PUBLIC_IP}"
