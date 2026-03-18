#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Coder on Railway — Automated Setup
#
# Prerequisites:
#   - Railway CLI installed and authenticated (railway login)
#   - A domain you control (for OIDC callback URLs)
#
# This script:
#   1. Creates a Railway project with PostgreSQL + Coder services
#   2. Configures OIDC authentication restricted to @theagilemonkeys.com
#   3. Deploys the Coder control plane
#
# After deployment, you'll need to:
#   - Push the workspace template via the Coder CLI
#   - Set up a provisioner daemon on a Docker host (for workspace containers)
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

# ---- Pre-flight checks ----
command -v railway >/dev/null 2>&1 || err "Railway CLI not found. Install: https://docs.railway.com/guides/cli"

echo ""
echo "========================================"
echo "  Coder on Railway — Setup"
echo "========================================"
echo ""

# ---- Step 1: Create Railway project ----
info "Creating Railway project 'coder'..."
railway init --name coder 2>/dev/null || warn "Project may already exist, linking instead..."
ok "Railway project ready."

# ---- Step 2: Add PostgreSQL ----
info "Adding PostgreSQL database..."
echo ""
echo "  Go to your Railway dashboard and add a PostgreSQL plugin to the project."
echo "  Then copy the DATABASE_URL and paste it below."
echo ""
read -rp "  PostgreSQL connection URL (DATABASE_URL): " PG_URL

if [[ -z "$PG_URL" ]]; then
  err "PostgreSQL URL is required."
fi

# ---- Step 3: Configure OIDC ----
echo ""
info "Configuring OIDC authentication for @theagilemonkeys.com"
echo ""
echo "  Choose your OIDC provider:"
echo "  1) Google Workspace"
echo "  2) GitHub OAuth"
echo "  3) Skip (configure manually later)"
echo ""
read -rp "  Selection [1/2/3]: " AUTH_CHOICE

case "$AUTH_CHOICE" in
  1)
    echo ""
    echo "  Create a Google OAuth 2.0 Client:"
    echo "  1. Go to https://console.cloud.google.com/apis/credentials"
    echo "  2. Create OAuth 2.0 Client ID (Web application)"
    echo "  3. Add authorized redirect URI: https://<your-coder-url>/api/v2/users/oidc/callback"
    echo ""
    read -rp "  Google OAuth Client ID: " OIDC_CLIENT_ID
    read -rp "  Google OAuth Client Secret: " OIDC_CLIENT_SECRET

    railway variables set \
      CODER_OIDC_ISSUER_URL="https://accounts.google.com" \
      CODER_OIDC_CLIENT_ID="$OIDC_CLIENT_ID" \
      CODER_OIDC_CLIENT_SECRET="$OIDC_CLIENT_SECRET" \
      CODER_OIDC_EMAIL_DOMAIN="theagilemonkeys.com" \
      CODER_OIDC_ALLOW_SIGNUPS="true" \
      CODER_OIDC_SCOPES="openid,profile,email"

    ok "Google OIDC configured — only @theagilemonkeys.com emails allowed."
    ;;
  2)
    echo ""
    echo "  Create a GitHub OAuth App:"
    echo "  1. Go to https://github.com/settings/developers"
    echo "  2. New OAuth App"
    echo "  3. Set callback URL: https://<your-coder-url>/api/v2/users/oauth2/github/callback"
    echo ""
    read -rp "  GitHub OAuth Client ID: " GH_CLIENT_ID
    read -rp "  GitHub OAuth Client Secret: " GH_CLIENT_SECRET
    read -rp "  GitHub Org to allow (e.g. TheAgileMonkeys): " GH_ORG

    railway variables set \
      CODER_OAUTH2_GITHUB_CLIENT_ID="$GH_CLIENT_ID" \
      CODER_OAUTH2_GITHUB_CLIENT_SECRET="$GH_CLIENT_SECRET" \
      CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS="true" \
      CODER_OAUTH2_GITHUB_ALLOWED_ORGS="$GH_ORG"

    ok "GitHub OAuth configured — restricted to org: $GH_ORG"
    ;;
  3)
    warn "Skipping auth config. Set OIDC variables manually before going to production."
    ;;
  *)
    warn "Invalid selection, skipping auth config."
    ;;
esac

# ---- Step 4: Set core environment variables ----
info "Setting Coder environment variables..."

railway variables set \
  CODER_PG_CONNECTION_URL="$PG_URL" \
  CODER_HTTP_ADDRESS="0.0.0.0:${PORT:-8080}" \
  PORT="8080"

ok "Environment variables set."

# ---- Step 5: Deploy ----
info "Deploying Coder to Railway..."
railway up --detach

echo ""
ok "Deployment started!"
echo ""

# ---- Step 6: Post-deploy instructions ----
echo "========================================"
echo "  Next Steps"
echo "========================================"
echo ""
echo "  1. CODER_ACCESS_URL"
echo "     Once deployed, get your Railway URL from the dashboard and set:"
echo "     railway variables set CODER_ACCESS_URL=https://<your-app>.up.railway.app"
echo ""
echo "  2. FIRST USER"
echo "     Visit your Coder URL to create the admin account."
echo ""
echo "  3. OIDC CALLBACK"
echo "     Update your OAuth provider's redirect URI with the actual URL:"
echo "     - Google: https://<url>/api/v2/users/oidc/callback"
echo "     - GitHub: https://<url>/api/v2/users/oauth2/github/callback"
echo ""
echo "  4. DISABLE PASSWORD AUTH (after verifying OIDC works)"
echo "     railway variables set CODER_DISABLE_PASSWORD_AUTH=true"
echo ""
echo "  5. WORKSPACE TEMPLATE"
echo "     Install the Coder CLI and push the workspace template:"
echo ""
echo "     curl -fsSL https://coder.com/install.sh | sh"
echo "     coder login https://<your-coder-url>"
echo "     coder templates push docker-claude-code \\"
echo "       --directory ./templates/docker-claude-code"
echo ""
echo "  6. PROVISIONER DAEMON (for Docker workspaces)"
echo "     Coder on Railway runs the control plane only."
echo "     Workspaces need a Docker host. On a VM with Docker:"
echo ""
echo "     coder provisionerd start --tag scope=organization"
echo ""
echo "  7. CLAUDE CODE AUTH"
echo "     Users authenticate Claude Code inside their workspace:"
echo "     - Run 'claude' and follow the browser OAuth flow, or"
echo "     - Set ANTHROPIC_API_KEY in workspace environment"
echo ""
echo "========================================"
echo ""
