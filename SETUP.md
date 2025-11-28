# Setup Guide

Follow these steps to deploy the macOS build machine configuration.

## Prerequisites

- A GitHub repository to host this code (private recommended)
- Your Buildkite agent token (from Buildkite → Agents → Reveal Agent Token)
- One or more macOS machines to configure

---

## Step 1: Create GitHub Repository

```bash
# Create a new private repo on GitHub, then:
cd /Users/nathanwoodhull/work/mac-build
git init
git remote add origin git@github.com:YOUR_ORG/mac-build.git
```

---

## Step 2: Update Configuration

Edit `group_vars/all.yml` and update these values:

```yaml
# Change this to your repository URL
ansible_pull_repo_url: "git@github.com:YOUR_ORG/mac-build.git"

# Adjust agent count if needed (default is 3)
buildkite_agent_count: 3

# Adjust Docker resources based on your Mac specs
docker_memory_gb: 8
docker_cpus: 4
```

---

## Step 3: Generate GitHub Deploy Key

Each Mac needs read access to this repository. Generate a deploy key:

```bash
# Generate key pair (no passphrase)
ssh-keygen -t ed25519 -C "mac-build-deploy-key" -f deploy_key -N ""

# View the public key (add this to GitHub)
cat deploy_key.pub

# View the private key (add this to vault.yml)
cat deploy_key
```

Add the **public key** to GitHub:
1. Go to your repository → Settings → Deploy keys
2. Click "Add deploy key"
3. Title: `mac-build-deploy-key`
4. Paste the contents of `deploy_key.pub`
5. Leave "Allow write access" unchecked
6. Click "Add key"

---

## Step 4: Configure Secrets

Edit `group_vars/vault.yml` with your actual secrets:

```yaml
# Get this from Buildkite → Agents → Reveal Agent Token
vault_buildkite_agent_token: "YOUR_ACTUAL_BUILDKITE_TOKEN"

# Paste the entire contents of the deploy_key file
vault_github_deploy_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAA...
  ... (paste full key here) ...
  -----END OPENSSH PRIVATE KEY-----
```

---

## Step 5: Encrypt the Vault File

Choose a strong password and encrypt the secrets:

```bash
ansible-vault encrypt group_vars/vault.yml
# Enter your vault password when prompted
# SAVE THIS PASSWORD - you'll need it for each Mac
```

To edit later:
```bash
ansible-vault edit group_vars/vault.yml
```

---

## Step 6: Update Bootstrap Script

Edit `bootstrap.sh` and update the repository URL:

```bash
# Find this line near the top:
REPO_URL="${MAC_BUILD_REPO:-git@github.com:YOUR_ORG/mac-build.git}"

# Change YOUR_ORG to your actual organization/username
```

---

## Step 7: Commit and Push

```bash
# Remove the generated deploy key files (don't commit these!)
rm -f deploy_key deploy_key.pub

# Commit everything
git add -A
git commit -m "Initial mac-build configuration"
git push -u origin main
```

---

## Step 8: Bootstrap First Mac

On your first macOS build machine:

### Option A: Direct download (easiest)
```bash
# Download and run bootstrap script
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/mac-build/main/bootstrap.sh | bash
```

### Option B: Clone first (if SSH isn't set up)
```bash
# Clone via HTTPS first
git clone https://github.com/YOUR_ORG/mac-build.git /tmp/mac-build
cd /tmp/mac-build
./bootstrap.sh
```

The bootstrap script will prompt you for:
1. **Deploy key** - Paste the private key when prompted
2. **Vault password** - Enter the password from Step 5

---

## Step 9: Verify Installation

After bootstrap completes, verify everything is working:

```bash
# Check Buildkite agents are running
pgrep -f buildkite-agent
# Should show 3 processes

# Check Docker is running
docker info

# Check scheduled services
launchctl list | grep com.internal
# Should show: ansible-pull, nightly-maintenance, disk-check

# View last configuration run
cat /var/log/ansible-last-run.json

# Check Buildkite dashboard
# Your agents should appear at: https://buildkite.com/organizations/YOUR_ORG/agents
```

---

## Step 10: Bootstrap Additional Macs

Repeat Step 8 for each additional Mac. They will all:
- Pull the same configuration from GitHub
- Register with Buildkite using the same token
- Self-update every 30 minutes
- Reboot and clean up nightly at 3 AM

---

## Ongoing Maintenance

### Making Configuration Changes

1. Edit files locally
2. Test on one machine: `ansible-playbook playbooks/site.yml --vault-password-file /etc/ansible/.vault-pass -c local -i localhost,`
3. Commit and push to GitHub
4. All machines will pick up changes within 30 minutes (or trigger manually)

### Updating Secrets

```bash
# Edit encrypted vault
ansible-vault edit group_vars/vault.yml

# Commit and push
git add group_vars/vault.yml
git commit -m "Update secrets"
git push
```

### Forcing Immediate Update on a Mac

```bash
# SSH to the Mac, then:
cd /opt/mac-build
git pull
ansible-playbook playbooks/site.yml \
  --vault-password-file /etc/ansible/.vault-pass \
  -c local -i localhost,
```

### Checking Machine Status

```bash
# On any Mac, check last successful run:
cat /var/log/ansible-last-run.json

# Check ansible-pull logs:
tail -100 /var/log/ansible-pull.log

# Check Buildkite agent logs:
tail -100 /var/log/buildkite-agent-1.log
```

---

## Troubleshooting

### "Permission denied" when pulling from GitHub

The deploy key isn't set up correctly:
```bash
# Test SSH connection
ssh -T git@github.com

# Check key is in place
ls -la ~/.ssh/mac-build-deploy

# Check SSH config
cat ~/.ssh/config
```

### Buildkite agents not appearing

```bash
# Check agent logs
tail -50 /var/log/buildkite-agent-1.error.log

# Verify token in config
grep token /opt/homebrew/etc/buildkite-agent/buildkite-agent.cfg

# Restart agents
for i in 1 2 3; do
  launchctl unload ~/Library/LaunchAgents/com.buildkite.buildkite-agent-${i}.plist
  launchctl load ~/Library/LaunchAgents/com.buildkite.buildkite-agent-${i}.plist
done
```

### Docker not starting

```bash
# Start Docker manually
open -a Docker

# Wait for it to start, then verify
docker info
```

### Vault password errors

```bash
# Verify password file exists and has correct content
sudo cat /etc/ansible/.vault-pass

# Re-enter password if needed
echo "YOUR_VAULT_PASSWORD" | sudo tee /etc/ansible/.vault-pass
sudo chmod 600 /etc/ansible/.vault-pass
```

---

## Security Checklist

- [ ] GitHub repository is private
- [ ] Deploy key has read-only access
- [ ] `group_vars/vault.yml` is encrypted
- [ ] Vault password is stored securely (password manager)
- [ ] `deploy_key` and `deploy_key.pub` files are NOT in the repo
- [ ] `.gitignore` includes sensitive file patterns
