# Jenkins UI setup choices and next steps

## Plugins selected (custom install)
- Folders
- OWASP Markup Formatter
- Build Timeout
- Credentials Binding
- Timestamper
- Workspace Cleanup
- Ant
- Gradle
- Pipeline (and Pipeline Graph View)
- GitHub Branch Source
- Pipeline: GitHub Groovy Libraries
- Git
- SSH Build Agents
- Matrix Authorization Strategy
- LDAP
- Email Extension + Mailer
- Dark Theme
- Dashboard View
- NodeJS
- Configuration as Code
- SSH Agent
- GitHub
- Role-based Authorization Strategy

## Post-install steps to complete
- **Restart if prompted** to load plugins cleanly.
- **Create admin user** (avoid leaving default admin).
- **Set Jenkins URL** under Manage Jenkins → Configure System: `https://jenkins.rdhcloudlab.com` (or `http://` if no TLS).
- **GitHub integration**: add a GitHub server/token (Manage Jenkins → System) and credentials for multibranch/PR builds. Configure repo webhooks to `/github-webhook/`.
- **Tools** (Manage Jenkins → Global Tool Configuration):
  - NodeJS: add a version (e.g., node20) with “Install automatically”.
  - Ant/Gradle: add if you’ll use them.
- **Credentials**: add SSH keys and secrets under Manage Jenkins → Credentials (global/folders). Use Credentials Binding or SSH Agent in pipelines.
- **Build hygiene defaults**: set Build Timeout (e.g., 60m), enable Timestamper, and enable Workspace Cleanup post-build.
- **Authorization**: switch off anonymous admin. Configure Matrix or Role-based auth; ensure your user is an Admin. Integrate LDAP if needed.
- **Email**: configure SMTP for Mailer/Email Extension (alerts).
- **Configuration as Code**: once configured, export CasC YAML (/configuration-as-code/) and store it for repeatable setup.
- **Theme/UI**: enable Dark Theme and set up Dashboard View if desired.

## Quick validation
- Dashboard loads without warnings; plugins show as up-to-date.
- GitHub credentials test succeeds; webhooks receive events.
- NodeJS tool install works in a test Pipeline: `tools { nodejs 'node20' }`.
- A sample pipeline can clone via GitHub Branch Source and run with SSH Agent/Credentials Binding.
