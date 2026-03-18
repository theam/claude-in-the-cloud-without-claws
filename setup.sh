#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Coder with Claude Code — Docker Compose Setup
#
# Deploys:
#   - Coder server (control plane + workspace provisioner)
#   - PostgreSQL database
#   - Docker workspace template with Claude Code pre-installed
#
# Auth: GitHub OAuth restricted to theam org (@theagilemonkeys.com)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "========================================"
echo "  Coder + Claude Code — Setup"
echo "========================================"
echo ""

# ---- Pre-flight checks ----
command -v docker >/dev/null 2>&1 || err "Docker not found. Install: https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 || err "Docker daemon not running."
command -v docker compose >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 || err "Docker Compose not found."

ok "Docker is running."

# ---- Create .env if missing ----
if [[ ! -f .env ]]; then
  info "Creating .env file..."

  PG_PASSWORD=$(openssl rand -base64 24)
  DOCKER_GID=$(getent group docker 2>/dev/null | cut -d: -f3 || stat -f '%g' /var/run/docker.sock 2>/dev/null || echo "999")

  # Detect access URL
  if [[ -n "${CODER_ACCESS_URL:-}" ]]; then
    ACCESS_URL="$CODER_ACCESS_URL"
  else
    ACCESS_URL="http://localhost"
    warn "Using CODER_ACCESS_URL=$ACCESS_URL (set to your public URL for remote access)"
  fi

  cat > .env <<EOF
CODER_ACCESS_URL=$ACCESS_URL
POSTGRES_USER=coder
POSTGRES_PASSWORD=$PG_PASSWORD
POSTGRES_DB=coder
DOCKER_GROUP_ID=$DOCKER_GID
EOF

  ok "Created .env with generated credentials."
else
  ok ".env file already exists."
fi

# ---- Start services ----
info "Starting Coder + PostgreSQL..."
docker compose up -d

echo ""
info "Waiting for Coder to be healthy..."
for i in $(seq 1 30); do
  if curl -sf http://localhost/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -sf http://localhost/healthz >/dev/null 2>&1; then
  err "Coder did not become healthy within 60 seconds. Check: docker compose logs coder"
fi
ok "Coder is running!"

# ---- Create first user ----
info "Checking if first user exists..."
FIRST_USER_CHECK=$(curl -sf http://localhost/api/v2/users/first 2>&1 || true)

if echo "$FIRST_USER_CHECK" | grep -q "initial user has not been created"; then
  info "Creating admin user..."
  ADMIN_PASSWORD=$(openssl rand -base64 24)

  curl -sf -X POST http://localhost/api/v2/users/first \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"admin@theagilemonkeys.com\", \"username\": \"admin\", \"password\": \"$ADMIN_PASSWORD\"}" >/dev/null

  ok "Admin user created."
  echo ""
  echo -e "  ${YELLOW}Save these credentials:${NC}"
  echo "  Username: admin"
  echo "  Email:    admin@theagilemonkeys.com"
  echo "  Password: $ADMIN_PASSWORD"
  echo ""
else
  ok "Admin user already exists."
  ADMIN_PASSWORD=""
fi

# ---- Install Coder CLI if needed ----
if ! command -v coder >/dev/null 2>&1; then
  info "Installing Coder CLI..."
  curl -fsSL https://coder.com/install.sh | sh 2>/dev/null
fi

# ---- Login to Coder CLI ----
if [[ -n "$ADMIN_PASSWORD" ]]; then
  info "Logging into Coder CLI..."
  SESSION_TOKEN=$(curl -sf -X POST http://localhost/api/v2/users/login \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"admin@theagilemonkeys.com\", \"password\": \"$ADMIN_PASSWORD\"}" | jq -r '.session_token')

  echo "$SESSION_TOKEN" | coder login --use-token-as-session http://localhost 2>/dev/null
  ok "Coder CLI authenticated."
fi

# ---- Push workspace template ----
info "Pushing Claude Code workspace template..."
coder templates push docker-claude-code \
  --directory ./templates/docker-claude-code \
  --yes 2>&1

ok "Workspace template 'docker-claude-code' pushed!"

# ---- Done ----
ACCESS_URL=$(grep CODER_ACCESS_URL .env | cut -d= -f2-)

echo ""
echo "========================================"
echo -e "  ${GREEN}Deployment complete!${NC}"
echo "========================================"
echo ""
echo "  Dashboard:  $ACCESS_URL"
echo ""
echo "  Auth:       GitHub OAuth (theam org members only)"
echo "  Template:   docker-claude-code (Ubuntu 24.04 + Claude Code)"
echo ""
echo "  Next steps:"
echo "  1. Visit $ACCESS_URL and sign in"
echo "  2. Create a workspace from the 'docker-claude-code' template"
echo "  3. Open the terminal and run 'claude' to authenticate Claude Code"
echo ""
echo "  To set a public URL (for remote access):"
echo "    1. Edit .env and set CODER_ACCESS_URL to your domain"
echo "    2. Run: docker compose up -d"
echo ""
echo "========================================"
echo ""
