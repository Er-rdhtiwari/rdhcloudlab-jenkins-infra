You are an expert Cloud/DevOps engineer. Generate a complete, simple, easy-to-understand Git repository that provisions and manages an independent Jenkins server on AWS EC2 using Terraform + scripts.

====
GOAL (what repo must do)
====
Create a repo that:
1) Deploys Jenkins on AWS EC2 (default instance type t3.medium) using Terraform.
   - Instance type must be changeable anytime via Terraform variables (upgrade/downgrade).
   - Jenkins instance must be start/stop/reboot cost-effectively (not 24x7).
2) Maps Jenkins to my domain (Route53 record).
   - Use Elastic IP so DNS doesn’t change after stop/start.
   - Jenkins must be reachable at a configurable FQDN like: jenkins.<ROOT_DOMAIN>.
3) Attaches an AWS “jenkins-user” credential to the instance via environment.
   - Prefer secure approach: IAM role + instance profile named “jenkins-user” (least privilege).
   - Additionally support optional access-key style credentials via SSM Parameter Store:
     - If enabled, instance reads SecureString parameter (path provided as variable) and exports AWS_* env vars.
     - This MUST NOT put secrets into repo or terraform state. (User will create SSM param manually.)
4) Cost saving auto-stop:
   - Install a cron job that automatically schedules instance shutdown after N hours (default 6).
   - It must re-apply on every boot/restart automatically.
   - Use EC2 “instance-initiated shutdown behavior” = STOP so “shutdown -h” results in EC2 STOP (cost saving).
   - The N hours must be configurable via Terraform variable and also adjustable via management script command.
5) Docs:
   - README.md: architecture overview + decisions + ASCII diagram.
   - docs/USAGE.md: step-by-step how to deploy, connect domain, manage start/stop, change instance type, troubleshoot.
6) No hardcoded important variables:
   - All important config must come from env or Terraform variables (TF_VAR_*).
   - Provide .env.example with placeholders and explain usage.
7) Provide a well-documented management script:
   - One script capable of: deploy/apply, destroy, start instance, stop instance, reboot instance,
     show status (instance id, state, public dns/ip), open ssh, show Jenkins URL, fetch initial admin password.
   - Script must also support: set-auto-shutdown HOURS (update a tfvars file and apply).
   - Script must be readable with comments and safe defaults.

====
SCOPE / SIMPLICITY RULES
====
- Keep it “simple but production-minded”.
- Use Ubuntu 22.04 LTS AMI (data source).
- Jenkins install should happen via user_data (cloud-init):
  - install Java + Jenkins (official Jenkins repo) + enable service
  - install Nginx OR Caddy reverse proxy
  - do NOT expose port 8080 publicly; only allow 80/443 from internet; Jenkins listens on localhost:8080
- Domain mapping: Route53 A record to Elastic IP.
- Security group:
  - inbound: 22 from ALLOWED_SSH_CIDR, 80/443 from 0.0.0.0/0
  - outbound: allow all
- Tag resources consistently.
- Terraform should output:
  - instance_id, elastic_ip, jenkins_fqdn, ssh_command, initial_password_command
- Repo must be runnable by a user with AWS CLI configured.
- Avoid paid extras (no ALB required). Keep to EC2 + EIP + Route53.

====
REPO STRUCTURE (REQUIRED)
====
Generate similar structure (you may add small helper files, but keep it minimal):

.
├── README.md
├── docs
│   └── USAGE.md
├── infra
│   └── terraform
│       ├── versions.tf
│       ├── provider.tf
│       ├── variables.tf
│       ├── main.tf
│       ├── outputs.tf
│       ├── userdata.sh.tftpl
│       └── auto.tfvars.example
├── scripts
│   ├── jenkinsctl.sh
│   └── lib.sh
├── .env.example
├── .gitignore
└── Makefile

=======
CONFIG (ENV + TF VARS)
=======
Use these environment variables (with examples in .env.example):
- AWS_REGION (default ap-south-1)
- AWS_PROFILE (optional)
- TF_VAR_project_name (e.g., "jenkins-ec2")
- TF_VAR_env (e.g., "dev")
- TF_VAR_instance_type (default "t3.medium")
- TF_VAR_key_name (existing EC2 keypair name)
- TF_VAR_public_key_path (path to public key file to import OR if key already exists, allow skip)
- TF_VAR_allowed_ssh_cidr (e.g., "x.x.x.x/32")
- TF_VAR_root_domain (e.g., "rdhcloudlab.com")
- TF_VAR_jenkins_subdomain (e.g., "jenkins")
- TF_VAR_hosted_zone_id (Route53 hosted zone id)
- TF_VAR_auto_shutdown_hours (default 6)
- TF_VAR_enable_ssm_aws_creds (default false)
- TF_VAR_ssm_aws_creds_param_name (e.g., "/jenkins/aws-creds")
- TF_VAR_jenkins_admin_email (optional for TLS proxy config; default to errdhtiwari@gmail.com)
- Remote backend is REQUIRED (S3 + DynamoDB):
  - TF_BACKEND_BUCKET (use unique bucket, e.g., rdhcloudlab-jenkins-tfstate)
  - TF_BACKEND_DYNAMODB_TABLE (locks table, e.g., rdhcloudlab-jenkins-tflock)
  - Optional TF_BACKEND_KEY (default project-env/terraform.tfstate) and TF_BACKEND_REGION (default AWS_REGION)
- Backend: configure S3 backend block and require remote backend env vars; bucket/table must be created beforehand.

Terraform must be written so it works with TF_VAR_* variables without hardcoding.

=======
AUTO-SHUTDOWN IMPLEMENTATION (IMPORTANT)
=======
In user_data, set up:
- EC2 instance-initiated shutdown behavior = STOP (Terraform setting).
- Cron job that runs on every boot (@reboot) and schedules a shutdown after AUTO_SHUTDOWN_HOURS:
  - simplest acceptable: `shutdown -h +MINUTES`
  - ensure MINUTES = AUTO_SHUTDOWN_HOURS * 60
  - ensure it schedules only once per boot (idempotent enough)
- Provide a way to cancel/reschedule if user changes hours (document steps).

========
AWS CREDENTIAL ATTACHMENT (IMPORTANT)
========
Implement BOTH:
A) Recommended: IAM role + instance profile named “jenkins-user”
   - Minimal policy: allow SSM get parameter if enabled; allow CloudWatch logs optional; keep small.
B) Optional: read SSM SecureString for AWS creds and export as environment for Jenkins service:
   - User_data should:
     - if enable_ssm_aws_creds=true:
       - install awscli
       - read parameter from SSM with `aws ssm get-parameter --with-decryption`
       - write to /etc/profile.d/jenkins_aws_creds.sh (chmod 600)
       - create systemd override for Jenkins to load EnvironmentFile if needed
   - DO NOT create the parameter in Terraform (avoid secrets in state).

========
MANAGEMENT SCRIPT (IMPORTANT)
========
scripts/jenkinsctl.sh must:
- load .env if present (and/or rely on exported env)
- validate required env vars
- commands:
  - init        -> terraform init
  - deploy      -> terraform apply -auto-approve
  - destroy     -> terraform destroy -auto-approve
  - status      -> show instance state, instance id, public ip, EIP, url
  - start       -> start instance (aws ec2 start-instances)
  - stop        -> stop instance (aws ec2 stop-instances)
  - reboot      -> reboot instance (aws ec2 reboot-instances)
  - ssh         -> ssh into instance
  - url         -> print Jenkins URL
  - password    -> print command to fetch Jenkins initial admin password (via ssh)
  - set-auto-shutdown HOURS -> write infra/terraform/auto.tfvars with auto_shutdown_hours and apply
- It should discover instance id using terraform output (preferred) and fallback to tags.
- Use scripts/lib.sh for shared functions (colors, require_cmd, aws_profile args, terraform wrapper, jq helpers).
- Add clear help output: `jenkinsctl.sh help`.

========
OUTPUT FORMAT (CRITICAL)
========
Return:
1) The complete file tree.
2) Then for EACH file, output its full content in a fenced code block with the file path as a heading.
Example:
### infra/terraform/main.tf
```hcl
...
````

Do NOT omit any file content.

========
QUALITY / STYLE
========

* Keep code readable, commented, and minimal.
* Use Terraform best practices (variables, locals, tags).
* Avoid exposing sensitive data in outputs.
* Make docs beginner-friendly but production-minded (trade-offs, pitfalls, troubleshooting).
* Include an ASCII architecture diagram in README.md.

Now generate the repository exactly as specified.


