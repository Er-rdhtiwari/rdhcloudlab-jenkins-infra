# rdhcloudlab-jenkins-infra
# Jenkins on AWS EC2 (Terraform)

Provision an independent Jenkins server on AWS EC2 with Terraform, an IAM instance profile, and a small management script to operate start/stop/reboot, DNS, and auto-shutdown.

## Why this exists
- Single EC2 with Elastic IP and Route53 A record (no ALB).
- Jenkins is behind Nginx on Ubuntu 22.04; only 80/443 exposed.
- IAM role **jenkins-user** plus optional SSM-based AWS creds for jobs.
- Auto-shutdown after N hours to save cost; reschedules every boot.
- Simple CLI (`scripts/jenkinsctl.sh`) for deploy/destroy/start/stop/status/ssh/password/auto-shutdown.

## Architecture
```
                 +-------------------+
                 | Route53 HostedZone|
                 |  A: jenkins.<root>|
                 +---------+---------+
                           |
                     +-----v------+
                     | Elastic IP |
                     +-----+------+
                           |
        +------------------v-------------------+
        |  EC2 (Ubuntu 22.04, t3.medium default)|
        |  - IAM role: jenkins-user             |
        |  - User data installs Jenkins         |
        |  - Auto-shutdown cron (@reboot)       |
        |  - Optional: fetch SSM creds          |
        +------------------+--------------------+
                           |
                 +---------v----------+
                 | Nginx reverse proxy|
                 | :80/443 -> :8080   |
                 +---------+----------+
                           |
                 +---------v----------+
                 |  Jenkins service   |
                 |  localhost:8080    |
                 +--------------------+
```

## Key pieces
- **Terraform** in `infra/terraform`: EC2 + EIP + SG + Route53 + IAM role/instance profile `jenkins-user`.
- **User data** installs Jenkins, Nginx reverse proxy, optional certbot (if `TF_VAR_jenkins_admin_email`), auto-shutdown cron, and optional SSM AWS creds.
- **Scripts** in `scripts/`: `jenkinsctl.sh` driver plus `lib.sh` helpers.
- **Outputs**: `instance_id`, `elastic_ip`, `jenkins_fqdn`, `ssh_command`, `initial_password_command`.

## Quickstart
1. Copy `.env.example` to `.env` and fill values (AWS region/profile, Route53 zone, key pair, allowed SSH CIDR, domain, etc.).
2. `source .env`
3. `./scripts/jenkinsctl.sh init`
4. `./scripts/jenkinsctl.sh deploy`
5. Browse `http://jenkins.<root_domain>` (or the EIP if DNS not ready). Grab the initial admin password with `./scripts/jenkinsctl.sh password`.

## Operations (via jenkinsctl.sh)
- `status` show instance id/state/IP/FQDN/URL
- `start` / `stop` / `reboot`
- `ssh [args]` (set `SSH_KEY_PATH` if needed)
- `url` prints Jenkins URL
- `password` fetches initial admin password over SSH
- `set-auto-shutdown HOURS` updates `auto.tfvars` and reapplies
- `destroy` tears everything down

## Notes & decisions
- Default Ubuntu 22.04 ami (Canonical owner id 099720109477).
- Instance-initiated shutdown behavior is `stop`, so cron `shutdown -h +N*60` stops EC2 instead of terminating.
- EIP keeps DNS stable across stops/starts.
- Key pair: Terraform can import a public key if `TF_VAR_public_key_path` is provided; otherwise an existing key is assumed.
- Optional AWS creds from SSM SecureString (JSON or KEY=VALUE lines) are written to `/etc/profile.d/jenkins_aws_creds.sh` and loaded via systemd drop-in.
- Optional TLS: set `TF_VAR_jenkins_admin_email` to have user data run certbot against Nginx (requires DNS pointing at the EIP).
- Auto-shutdown hours are stored as an instance tag; `set-auto-shutdown` updates the tag and reschedules on the host without rebuilding the instance.
- Remote backend: backend `s3` block is present and required. Set `TF_BACKEND_BUCKET` (unique bucket, e.g., `rdhcloudlab-jenkins-tfstate`) and `TF_BACKEND_DYNAMODB_TABLE` (e.g., `rdhcloudlab-jenkins-tflock`) before `jenkinsctl.sh init`.
