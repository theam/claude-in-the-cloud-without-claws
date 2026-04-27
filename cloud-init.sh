#!/bin/bash
set -eu
export HOME=/root
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

# ---- Ensure SSH stays accessible ----
# Docker's iptables rules can interfere with SSH. Create a systemd service
# that inserts an ACCEPT rule for port 22 in DOCKER-USER after Docker starts.
# (DOCKER-USER chain only exists once Docker is running, so we can't insert now.)
cat > /etc/systemd/system/ssh-iptables-fix.service <<'SSHFIX'
[Unit]
Description=Ensure SSH is allowed through Docker iptables
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/sbin/iptables -I DOCKER-USER -p tcp --dport 22 -j ACCEPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SSHFIX
systemctl daemon-reload
systemctl enable ssh-iptables-fix.service
systemctl start ssh-iptables-fix.service || true
echo "SSH iptables fix installed."

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
GITHUB_OAUTH_CLIENT_ID=Ov23lilBUrSxGdEqfofN
GITHUB_OAUTH_CLIENT_SECRET=f0b9a66e01878e007907908dae1845030762ce4d
ENVEOF
chmod 600 .env

# ---- Start services ----
docker compose up -d

# ---- Wait for Coder to be healthy ----
# Coder port 8080 is not mapped to the host; check via docker exec.
echo "Waiting for Coder..."
HEALTHY=false
for i in $(seq 1 60); do
  if docker exec coder-coder-1 curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
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

# Helper: get Coder's internal IP for API calls from the host
CODER_IP=$(docker inspect coder-coder-1 | jq -r '.[0].NetworkSettings.Networks["coder_frontend"].IPAddress')
echo "Coder internal IP: ${CODER_IP}"

# ---- Create admin user ----
FIRST_CHECK=$(curl -sf http://${CODER_IP}:8080/api/v2/users/first 2>&1 || true)
if echo "$FIRST_CHECK" | grep -q "initial user has not been created"; then
  curl -sf -X POST http://${CODER_IP}:8080/api/v2/users/first \
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

SESSION_TOKEN=$(curl -sf -X POST http://${CODER_IP}:8080/api/v2/users/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"admin@theagilemonkeys.com\",\"password\":\"${ADMIN_PASSWORD}\"}" | jq -r '.session_token')

echo "$SESSION_TOKEN" | coder login --use-token-as-session http://${CODER_IP}:8080

coder templates push docker-claude-code \
  --directory /opt/coder/templates/docker-claude-code \
  --yes

# ---- Promote first GitHub OAuth user to owner (convenience) ----
# Wait for the first GitHub user to sign up, then promote them.
# Runs in the background so it doesn't block setup completion.
nohup bash -c "
for i in \$(seq 1 120); do
  USERS=\$(curl -sf http://${CODER_IP}:8080/api/v2/users \
    -H \"Coder-Session-Token: ${SESSION_TOKEN}\" | jq -r '.users[] | select(.username != \"admin\") | .username')
  if [ -n \"\$USERS\" ]; then
    for u in \$USERS; do
      curl -sf -X PUT \"http://${CODER_IP}:8080/api/v2/users/\${u}/roles\" \
        -H \"Content-Type: application/json\" \
        -H \"Coder-Session-Token: ${SESSION_TOKEN}\" \
        -d '{\"roles\":[\"owner\"]}'
      echo \"Promoted \${u} to owner\"
    done
    break
  fi
  sleep 10
done
" > /var/log/coder-promote.log 2>&1 &

# ---- Clean up sensitive data from logs ----
echo "=== Coder Setup Complete ==="
echo "Dashboard: https://software.theagilemonkeys.com"
echo "Admin credentials: /root/.coder-admin-credentials"

# Redact secrets from this log
sed -i "s/${PG_PASSWORD}/[REDACTED]/g" /var/log/coder-setup.log
sed -i "s/${ADMIN_PASSWORD}/[REDACTED]/g" /var/log/coder-setup.log
chmod 600 /var/log/coder-setup.log
