# Jenkins EC2 deployment notes (rdhcloudlab-jenkins-infra)

Chronological notes from deploying this repo on an EC2 host, including issues encountered, fixes applied, and validation steps.

## Environment prep
- Copy `.env.example` to `.env` and fill values. To export and validate required variables in your shell, run:
  ```bash
  source ./scripts/export-env.sh
  ```
  The helper prints missing vars without closing your shell.
- If creating a new EC2 key pair from the host:
  ```bash
  ./scripts/jenkinsctl.sh create-keypair jenkins-key
  sed -i 's/^TF_VAR_key_name=.*/TF_VAR_key_name=jenkins-key/' .env
  grep -q '^SSH_KEY_PATH=' .env || echo 'SSH_KEY_PATH=~/.ssh/jenkins-key.pem' >> .env
  source ./scripts/export-env.sh
  ```

## Backend init
- `./scripts/jenkinsctl.sh init`
- Behavior: auto-creates the S3 bucket and DynamoDB lock table if they do not exist, then runs `terraform init`.
- Validations: init completes, no errors about missing bucket/table.

## Deploy
- `./scripts/jenkinsctl.sh deploy`
- Expected outputs: `instance_id`, `elastic_ip`, `jenkins_fqdn`, `ssh_command`, `initial_password_command`.
- Validation commands:
  ```bash
  ./scripts/jenkinsctl.sh status
  dig +short jenkins.<root_domain>
  ./scripts/jenkinsctl.sh url
  ./scripts/jenkinsctl.sh password   # uses SSH_KEY_PATH if set
  ```

## Known issues and fixes
- **Missing .env values at deploy:** Terraform prompted for `allowed_ssh_cidr`. Fix by setting required vars in `.env` and exporting via `source ./scripts/export-env.sh`.
- **Key pair import failed (missing public key file):**
  - Error: `Invalid value for "path" parameter: no file exists at "/home/ubuntu/.ssh/jenkins.pub"`.
  - Fix: Terraform now only imports the key pair if `TF_VAR_public_key_path` is non-empty *and* the file exists (`fileexists`). Otherwise it uses the existing key name.
  - If you already created a key pair via `create-keypair.sh`, leave `TF_VAR_public_key_path` empty.
- **export-env.sh closed shell:** Updated to detect when sourced and return without exiting the session; still validates required vars.

## Post-deploy ops
- Access Jenkins: `./scripts/jenkinsctl.sh url` (HTTPS if certbot enabled). Use the initial admin password from `./scripts/jenkinsctl.sh password`.
- Auto-shutdown update: `./scripts/jenkinsctl.sh set-auto-shutdown <hours>`
- Stop/start/reboot: `./scripts/jenkinsctl.sh stop|start|reboot`
- Destroy: `./scripts/jenkinsctl.sh destroy`

## Validation checklist (quick)
- `source ./scripts/export-env.sh` shows no missing vars.
- `./scripts/jenkinsctl.sh init` completes (creates backend if needed).
- `./scripts/jenkinsctl.sh deploy` succeeds.
- `./scripts/jenkinsctl.sh status` shows running instance and IP/FQDN.
- `dig +short jenkins.<root_domain>` resolves to the elastic IP.
- `./scripts/jenkinsctl.sh password` returns the initial admin password.

## After rebooting your management EC2
- The Jenkins server keeps its Elastic IP and DNS, so you can still connect after a reboot of the management host.
- Ensure your PEM (`~/.ssh/jenkins-key.pem`) still exists and `SSH_KEY_PATH` points to it; EBS root persists across reboots.
- Reload env when needed:
  ```bash
  cd ~/poc/rdhcloudlab-jenkins-infra
  git pull
  source ./scripts/export-env.sh
  ./scripts/jenkinsctl.sh status
  ```
- Connect directly: `ssh -i ~/.ssh/jenkins-key.pem ubuntu@jenkins.<root_domain>` or use `./scripts/jenkinsctl.sh ssh`.
- If your public IP changed and SSH is CIDR-restricted, update `TF_VAR_allowed_ssh_cidr` in `.env` and run `./scripts/jenkinsctl.sh deploy` to refresh the security group.
- If the Jenkins EC2 is stopped, start it: `./scripts/jenkinsctl.sh start` (EIP and DNS remain the same).
