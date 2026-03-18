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

# ---- Generate secrets at runtime (never hardcode) ----
PG_PASSWORD=$(openssl rand -base64 32)
ADMIN_PASSWORD=$(openssl rand -base64 32)
DOCKER_GID=$(getent group docker | cut -d: -f3)

# ---- Create .env ----
cat > .env <<ENVEOF
CODER_ACCESS_URL=https://software.theagilemonkeys.com
POSTGRES_USER=coder
POSTGRES_PASSWORD=${PG_PASSWORD}
POSTGRES_DB=coder
DOCKER_GROUP_ID=${DOCKER_GID}
ENVEOF
chmod 600 .env

# ---- Start services ----
docker compose up -d

# ---- Wait for Coder to be healthy ----
echo "Waiting for Coder..."
HEALTHY=false
for i in $(seq 1 60); do
  if curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
    echo "Coder is healthy!"
    HEALTHY=true
    break
  fi
  sleep 3
done

if [ "$HEALTHY" != "true" ]; then
  echo "ERROR: Coder did not become healthy within 180 seconds."
  exit 1
fi

# ---- Create admin user ----
FIRST_CHECK=$(curl -sf http://localhost:8080/api/v2/users/first 2>&1 || true)
if echo "$FIRST_CHECK" | grep -q "initial user has not been created"; then
  curl -sf -X POST http://localhost:8080/api/v2/users/first \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"admin@theagilemonkeys.com\",\"username\":\"admin\",\"password\":\"${ADMIN_PASSWORD}\"}"
  echo "Admin user created."

  # Save credentials securely (root-only)
  cat > /root/.coder-admin-credentials <<CREDEOF
email=admin@theagilemonkeys.com
username=admin
password=${ADMIN_PASSWORD}
CREDEOF
  chmod 600 /root/.coder-admin-credentials
  echo "Credentials saved to /root/.coder-admin-credentials"
fi

# ---- Install Coder CLI and push template ----
curl -fsSL https://coder.com/install.sh | sh

SESSION_TOKEN=$(curl -sf -X POST http://localhost:8080/api/v2/users/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"admin@theagilemonkeys.com\",\"password\":\"${ADMIN_PASSWORD}\"}" | jq -r '.session_token')

echo "$SESSION_TOKEN" | coder login --use-token-as-session http://localhost:8080

coder templates push docker-claude-code \
  --directory /opt/coder/templates/docker-claude-code \
  --yes

# ---- Clean up sensitive data from logs ----
echo "=== Coder Setup Complete ==="
echo "Dashboard: https://software.theagilemonkeys.com"
echo "Admin credentials: /root/.coder-admin-credentials"

# Redact secrets from this log
sed -i "s/${PG_PASSWORD}/[REDACTED]/g" /var/log/coder-setup.log
sed -i "s/${ADMIN_PASSWORD}/[REDACTED]/g" /var/log/coder-setup.log
chmod 600 /var/log/coder-setup.log
