# Coder Infrastructure

Terraform configuration for deploying the Coder instance on AWS Lightsail.

## Prerequisites

- Terraform >= 1.3
- AWS CLI with the `innovation` SSO profile configured and logged in

## Deploy

```bash
# Authenticate
aws sso login --profile innovation

# Deploy
cd infra/
terraform init
terraform apply
```

Terraform will create:
- A Lightsail instance (Ubuntu 24.04, `large_3_0` ~$40/mo) with `cloud-init.sh` as user data
- A static IP attached to the instance
- Firewall rules for ports 22, 80, 443

Cloud-init takes ~5 minutes to complete (installs Docker, starts Coder, pushes the workspace template).

## Tear down

```bash
terraform destroy
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `aws_profile` | `innovation` | AWS CLI profile |
| `instance_name` | `coder-claude` | Resource name prefix |
| `bundle_id` | `large_3_0` | Instance size (~$40/mo) |
