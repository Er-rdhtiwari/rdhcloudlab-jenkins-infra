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

## Runbook: deploy from an existing EC2 host
Follow these steps on the EC2 box that already has Terraform, AWS CLI, and admin credentials configured.

### Prep
- Verify tools and identity: `aws sts get-caller-identity && terraform -version && jq --version`.
- Confirm your Route53 hosted zone exists for the root domain and note its hosted zone ID.
- Ensure you have an EC2 key pair. Put the key pair name in `TF_VAR_key_name`; set `TF_VAR_public_key_path` if you want Terraform to import a public key file.

### 1) Create remote state (required)
- Pick unique names: `TF_BACKEND_BUCKET`, `TF_BACKEND_DYNAMODB_TABLE`, and (optionally) `TF_BACKEND_KEY`.
- You can let `./scripts/jenkinsctl.sh init` create them automatically now, or pre-create once per region:
  ```bash
  aws s3api create-bucket --bucket <bucket> --create-bucket-configuration LocationConstraint=<region>
  aws dynamodb create-table --table-name <lock-table> --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
  ```
- Checkpoint: `aws s3api head-bucket --bucket <bucket>` and `aws dynamodb describe-table --table-name <lock-table>` both succeed.

### 2) Configure environment
- Copy and edit: `cp .env.example .env`
- Set at minimum: `AWS_REGION`, optional `AWS_PROFILE`; `TF_VAR_project_name`, `TF_VAR_env`, `TF_VAR_instance_type`, `TF_VAR_key_name`, `TF_VAR_allowed_ssh_cidr`, `TF_VAR_root_domain`, `TF_VAR_jenkins_subdomain`, `TF_VAR_hosted_zone_id`, `TF_VAR_auto_shutdown_hours`, optional `TF_VAR_public_key_path`, optional `TF_VAR_jenkins_admin_email` (for TLS), `TF_BACKEND_BUCKET`, `TF_BACKEND_KEY`, `TF_BACKEND_REGION`, `TF_BACKEND_DYNAMODB_TABLE`.
- Checkpoint: `cat .env` shows your values (no secrets beyond AWS profile).

### 3) Load environment
- Run `source .env`
- Checkpoint: `env | grep TF_VAR_ | sort` prints your Terraform variables; `echo $TF_BACKEND_BUCKET $TF_BACKEND_DYNAMODB_TABLE` is non-empty.

### 4) Initialize Terraform via helper
- Run `./scripts/jenkinsctl.sh init`
- Checkpoint: Terraform init completes with the remote backend configured (S3 bucket + DynamoDB lock).

### 5) Deploy
- Run `./scripts/jenkinsctl.sh deploy`
- Expected resources: EC2 with IAM role `jenkins-user`, EIP, SG (22/80/443), Route53 A record `jenkins.<root_domain>`, user data installs Jenkins + Nginx, optional certbot, auto-shutdown cron.
- Checkpoint: apply ends with outputs `instance_id`, `elastic_ip`, `jenkins_fqdn`, `ssh_command`.

### 6) Verify status and DNS
- Run `./scripts/jenkinsctl.sh status`
- Ensure state is `running` and IP/FQDN are present.
- DNS: `dig +short jenkins.<root_domain>` should resolve to the EIP (may take a minute).

### 7) Access Jenkins
- URL: `./scripts/jenkinsctl.sh url` (use IP until DNS propagates).
- Initial admin password: `./scripts/jenkinsctl.sh password` (set `SSH_KEY_PATH` if your private key is not default).
- Complete the Jenkins setup wizard in the browser.

### 8) Operations
- Stop/start/reboot: `./scripts/jenkinsctl.sh stop|start|reboot`
- Update auto-shutdown hours: `./scripts/jenkinsctl.sh set-auto-shutdown <hours>`
- Destroy everything: `./scripts/jenkinsctl.sh destroy`

### 9) Troubleshooting tips
- Check status first: `./scripts/jenkinsctl.sh status`
- Inspect user data logs: `./scripts/jenkinsctl.sh ssh 'sudo journalctl -u cloud-final -n 200'`
- Re-run DNS/certbot only after DNS points to the EIP.

## Generate and use a new EC2 key pair (helper)
Use this if you need to create the EC2 key pair for Jenkins from the EC2 host:
- Make the helper executable (once): `chmod +x scripts/create-keypair.sh`
- Optional AWS context: `export AWS_PROFILE=<profile>` and/or `export AWS_REGION=<region>`
- Create the key pair and save the PEM locally (default `~/.ssh/jenkins-key.pem`): `./scripts/jenkinsctl.sh create-keypair jenkins-key`
- Verify the PEM: `ls -l ~/.ssh/jenkins-key.pem`
- Update `.env` to use it:
  ```bash
  sed -i 's/^TF_VAR_key_name=.*/TF_VAR_key_name=jenkins-key/' .env
  grep -q '^SSH_KEY_PATH=' .env || echo 'SSH_KEY_PATH=~/.ssh/jenkins-key.pem' >> .env
  ```
- Reload env before deploy: `source .env`

The helper refuses to overwrite an existing AWS key pair with the same name. `jenkinsctl.sh ssh/password` will use `SSH_KEY_PATH` when set.

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
