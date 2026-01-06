# Usage

## Prerequisites
- AWS account with Route53 hosted zone for your root domain.
- AWS CLI configured (`aws configure` or exported credentials).
- Terraform >= 1.5, bash, jq, ssh, and a key pair available in AWS (or a public key to import).
- Domain delegation for the hosted zone you plan to use.

## Configure environment
1. `cp .env.example .env`
2. Edit `.env`:
   - `AWS_REGION` and optional `AWS_PROFILE`
   - `TF_VAR_project_name`, `TF_VAR_env`
   - `TF_VAR_key_name` (existing key pair) and optional `TF_VAR_public_key_path` (imports the public key)
   - `TF_VAR_allowed_ssh_cidr` (lock this down)
   - `TF_VAR_root_domain`, `TF_VAR_jenkins_subdomain`, `TF_VAR_hosted_zone_id`
   - `TF_VAR_auto_shutdown_hours` (default 6)
   - Optional `TF_VAR_enable_ssm_aws_creds` + `TF_VAR_ssm_aws_creds_param_name`
   - Optional `TF_VAR_jenkins_admin_email` to enable certbot for TLS
3. `source .env` to export the variables for Terraform and the scripts.

## Deploy
```bash
./scripts/jenkinsctl.sh init
./scripts/jenkinsctl.sh deploy
./scripts/jenkinsctl.sh status
./scripts/jenkinsctl.sh password   # fetch initial admin password over SSH
```
The Route53 A record `jenkins.<root_domain>` is created automatically against the Elastic IP. Use the EIP until DNS propagates.

## Daily operations
- `./scripts/jenkinsctl.sh start|stop|reboot`
- `./scripts/jenkinsctl.sh status`
- `./scripts/jenkinsctl.sh ssh [cmd]` (set `SSH_KEY_PATH` if your key is not the default)
- `./scripts/jenkinsctl.sh url`
- `./scripts/jenkinsctl.sh password`

## Change instance type
Update `TF_VAR_instance_type` in `.env` (or `infra/terraform/auto.tfvars`) and run:
```bash
source .env
./scripts/jenkinsctl.sh deploy
```
Terraform will replace the instance to apply the new type.

## Adjust auto-shutdown hours
```bash
./scripts/jenkinsctl.sh set-auto-shutdown 8
```
This writes `infra/terraform/auto.tfvars` with the new `auto_shutdown_hours`, reapplies, updates the instance tag, and reschedules the shutdown on the instance immediately. The cron job runs at every reboot and reads `/etc/jenkins/auto_shutdown_hours`. To cancel a pending shutdown on the instance itself, SSH in and run `sudo shutdown -c`.

## Optional AWS creds via SSM
The IAM role `jenkins-user` is always attached. To also expose key-based creds to Jenkins jobs:
1. Create a SecureString parameter matching `TF_VAR_ssm_aws_creds_param_name` (default `/jenkins/aws-creds`).
2. Value can be JSON:
   ```json
   {
     "AWS_ACCESS_KEY_ID": "AKIA...",
     "AWS_SECRET_ACCESS_KEY": "******",
     "AWS_DEFAULT_REGION": "ap-south-1"
   }
   ```
   or KEY=VALUE lines.
3. Set `TF_VAR_enable_ssm_aws_creds=true` and redeploy. User data writes `/etc/profile.d/jenkins_aws_creds.sh` and a systemd drop-in to load it for Jenkins.

## Optional TLS
If `TF_VAR_jenkins_admin_email` is set, user data installs certbot and runs `certbot --nginx` for `jenkins.<root_domain>`. Ensure DNS already points to the Elastic IP and port 80 is reachable; otherwise certbot will be retried manually after fixing DNS (`sudo certbot --nginx -d <fqdn> -m <email> --agree-tos --redirect`).

## Remote backend
Remote backend (S3 + DynamoDB) is **required** via env vars and `jenkinsctl init`:
```bash
export TF_BACKEND_BUCKET=rdhcloudlab-jenkins-tfstate   # use a globally-unique bucket you created
export TF_BACKEND_DYNAMODB_TABLE=rdhcloudlab-jenkins-tflock  # existing DynamoDB table for locks
# optional overrides:
# export TF_BACKEND_KEY=jenkins/dev/terraform.tfstate
# export TF_BACKEND_REGION=ap-south-1
./scripts/jenkinsctl.sh init
```
Both `TF_BACKEND_BUCKET` and `TF_BACKEND_DYNAMODB_TABLE` must be set; otherwise init will fail. `init` passes the backend configs; `deploy` assumes init already ran.

## Troubleshooting
- **Missing outputs**: run `terraform output` or ensure `terraform apply` has succeeded.
- **Cannot SSH**: verify `TF_VAR_allowed_ssh_cidr`, key pair matches, and `SSH_KEY_PATH` is correct.
- **Certbot failures**: confirm DNS and port 80 reach the instance; rerun certbot manually after DNS propagates.
- **SSM creds not loading**: ensure the parameter value is valid JSON or KEY=VALUE format and the IAM role has read access to that path.
- **Auto-shutdown not updated**: check `/etc/jenkins/auto_shutdown_hours` on the instance and rerun `set-auto-shutdown`.
