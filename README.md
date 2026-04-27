# Claude in the Cloud

Self-hosted [Coder](https://coder.com) instance on AWS Lightsail that gives every member of the `theam` GitHub organisation a cloud-based development workspace with **Claude Code** pre-installed.

**Live at:** https://software.theagilemonkeys.com

---

## Architecture

```
Browser → Caddy (HTTPS/TLS) → Coder → Docker workspace containers
                                    ↓
                               PostgreSQL
```

- **Caddy** — reverse proxy, auto-manages Let's Encrypt TLS certificates
- **Coder** — workspace orchestrator, GitHub OAuth login (theam org only)
- **PostgreSQL** — Coder's database (isolated on an internal Docker network)
- **Workspace containers** — one per user, built from `templates/docker-claude-code/`

---

## What's in each workspace

| Tool | Details |
|---|---|
| Claude Code | Pre-installed globally (`claude` command) |
| VS Code | Browser-based via code-server (port 13337) |
| Terminal | One-click terminal in the Coder dashboard |
| Node.js 22 LTS | + npm |
| Python 3 | + pip, venv |
| GitHub CLI | `gh` |
| Docker CLI | `docker` (connects to host Docker) |
| Chromium | Headless browser for Claude Code web search |
| ripgrep, fd, fzf, bat | Fast search tools |
| make, cmake, tmux, shellcheck | Build and dev utilities |
| Full sudo | Passwordless for installing anything else |
| 8 GB RAM | Per workspace |
| Persistent home | Survives workspace restarts |

---

## Deploy from scratch

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [AWS CLI](https://aws.amazon.com/cli/) configured with SSO
- An AWS SSO profile for the `innovation` account:

```bash
aws configure sso --profile innovation
aws sso login --profile innovation
```

### 1. Deploy infrastructure

```bash
cd infra/
terraform init
terraform apply
```

This creates:
- A Lightsail instance (Ubuntu 24.04, 2 vCPU, 8 GB RAM, ~$40/mo)
- A static IP attached to the instance
- Firewall rules for ports 22, 80, 443

Note the `static_ip` output.

### 2. Point DNS

Add (or update) an **A record** for `software.theagilemonkeys.com` pointing to the static IP from step 1.

> Terraform will also print: `dns_instruction = "Point an A record for software.theagilemonkeys.com → <ip>"`

### 3. Wait for cloud-init (~5 minutes)

`cloud-init.sh` runs automatically on first boot. It:

1. Installs Docker
2. Installs a systemd service to keep SSH accessible through Docker's iptables rules
3. Clones this repo to `/opt/coder`
4. Generates random secrets for PostgreSQL and the admin user
5. Starts Coder + Caddy + PostgreSQL via Docker Compose
6. Creates the `admin@theagilemonkeys.com` admin account
7. Installs the Coder CLI and pushes the `docker-claude-code` workspace template
8. Starts a background watcher that auto-promotes the first GitHub OAuth user to **owner**

You can monitor progress via:
```bash
ssh ubuntu@<static-ip> "sudo tail -f /var/log/coder-setup.log"
```

Coder is ready when `https://software.theagilemonkeys.com/healthz` returns `OK`.

### 4. First login

1. Go to **https://software.theagilemonkeys.com**
2. Log in with a GitHub account that belongs to the **theam** org
3. The background watcher from cloud-init will automatically promote you to **owner** within ~30 seconds

### 5. Set your Anthropic API key

Claude Code needs an API key. Set it in each workspace terminal:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

To make it permanent, add it to `~/.bashrc` inside the workspace.

---

## Tear down (stop all costs)

```bash
cd infra/
terraform destroy
```

Or manually via AWS CLI:
```bash
aws lightsail detach-static-ip --static-ip-name coder-claude-ip --region us-east-1
aws lightsail delete-instance --instance-name coder-claude --region us-east-1
aws lightsail release-static-ip --static-ip-name coder-claude-ip --region us-east-1
```

> **Note:** Lightsail charges for stopped instances. You must **delete** to stop billing.

---

## Repo structure

```
.
├── cloud-init.sh                          # Runs on first boot — full server setup
├── docker-compose.yml                     # Coder + Caddy + PostgreSQL
├── Caddyfile                              # Reverse proxy + TLS + security headers
├── setup.sh                              # Local Docker Compose setup (for development)
├── infra/
│   ├── main.tf                           # Lightsail instance, static IP, firewall
│   ├── variables.tf                      # Region, bundle size, domain
│   └── outputs.tf                        # Static IP, dashboard URL, DNS instruction
└── templates/
    └── docker-claude-code/
        ├── main.tf                       # Coder workspace template (Terraform)
        └── build/
            └── Dockerfile                # Workspace container image
```

---

## Access control

- Login is restricted to members of the **`theam` GitHub organisation**
- Password auth is disabled — GitHub OAuth is the only way in
- The GitHub OAuth app is registered at: https://github.com/organizations/theam/settings/applications
  - **Client ID:** `Ov23lilBUrSxGdEqfofN`
  - **Client Secret:** stored in `cloud-init.sh` (rotate via the GitHub app settings if compromised)

---

## SSH access (for maintenance)

The SSH key is managed by Lightsail. Download it via:

```bash
aws lightsail download-default-key-pair --region us-east-1 \
  | jq -r '.privateKeyBase64' > /tmp/lightsail-key.pem
chmod 600 /tmp/lightsail-key.pem
ssh -i /tmp/lightsail-key.pem ubuntu@<static-ip>
```

---

## Costs

| Resource | Cost |
|---|---|
| Lightsail `large_3_0` (2 vCPU, 8 GB) | ~$40/mo |
| Static IP (when attached to running instance) | Free |
| Static IP (when detached / instance deleted) | ~$3.60/mo |
| **Total while running** | **~$40/mo** |
| **Total when destroyed** | **$0/mo** |
