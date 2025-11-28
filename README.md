# macOS Build Machine Configuration

Ansible-based configuration management for macOS Buildkite CI agents.

## Features

- **Docker Desktop** - Installed and configured for container-based builds
- **Buildkite Agent** - 3 concurrent agents per machine (configurable)
- **Auto-updates** - Machines pull configuration from Git every 30 minutes
- **Nightly maintenance** - Docker cleanup and reboot at 3 AM
- **Unattended operation** - Sleep disabled, auto-restart after power failure
- **Log rotation** - Prevents disk space issues

## Quick Start

### 1. Prepare the repository

```bash
# Clone this repo
git clone git@github.com:YOUR_ORG/mac-build.git
cd mac-build

# Update configuration
vim group_vars/all.yml  # Set your repo URL, agent count, etc.

# Add your Buildkite token and secrets
vim group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml
# Enter a password when prompted (save this securely!)

# Commit and push
git add -A
git commit -m "Initial configuration"
git push
```

### 2. Bootstrap a new Mac

```bash
# On the new Mac, run:
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/mac-build/main/bootstrap.sh | bash

# Or clone and run locally:
git clone git@github.com:YOUR_ORG/mac-build.git /opt/mac-build
cd /opt/mac-build
./bootstrap.sh
```

The bootstrap script will:
1. Install Xcode Command Line Tools
2. Install Homebrew
3. Install Ansible
4. Clone this repository
5. Run the initial configuration
6. Set up auto-updates via launchd

### 3. GitHub Deploy Key Setup

For ansible-pull to work, each machine needs access to this repository:

```bash
# Generate a deploy key (do this once)
ssh-keygen -t ed25519 -C "mac-build-deploy-key" -f deploy_key -N ""

# Add deploy_key.pub to GitHub:
# Repository → Settings → Deploy keys → Add deploy key

# Add the private key to vault.yml:
vault_github_deploy_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ... (contents of deploy_key)
  -----END OPENSSH PRIVATE KEY-----
```

## Configuration

### Variables (`group_vars/all.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `ansible_pull_repo_url` | - | Git URL for this repository |
| `ansible_pull_interval` | 1800 | Seconds between auto-updates (30 min) |
| `buildkite_agent_count` | 3 | Number of concurrent agents |
| `buildkite_agent_tags` | queue=default,os=macos | Agent targeting tags |
| `docker_memory_gb` | 8 | Docker Desktop memory limit |
| `docker_cpus` | 4 | Docker Desktop CPU limit |
| `maintenance_hour` | 3 | Hour for nightly maintenance (0-23) |

### Secrets (`group_vars/vault.yml`)

| Variable | Description |
|----------|-------------|
| `vault_buildkite_agent_token` | Buildkite agent registration token |
| `vault_github_deploy_key` | SSH private key for repo access |
| `vault_npm_token` | (optional) NPM registry token |
| `vault_docker_hub_token` | (optional) Docker Hub token |

## Manual Operations

### Run configuration manually

```bash
cd /opt/mac-build
ansible-playbook playbooks/site.yml \
  --vault-password-file /etc/ansible/.vault-pass \
  -c local -i localhost,
```

### Run only specific roles

```bash
# Just update Docker settings
ansible-playbook playbooks/site.yml --tags docker ...

# Just update Buildkite
ansible-playbook playbooks/site.yml --tags buildkite ...
```

### Force immediate maintenance

```bash
sudo /usr/local/bin/nightly-maintenance.sh
```

### Check logs

```bash
# Ansible-pull (auto-updates)
tail -f /var/log/ansible-pull.log

# Buildkite agents
tail -f /var/log/buildkite-agent-1.log

# Nightly maintenance
tail -f /var/log/nightly-maintenance.log

# Last successful run
cat /var/log/ansible-last-run.json
```

### Restart Buildkite agents

```bash
for i in 1 2 3; do
  launchctl unload ~/Library/LaunchAgents/com.buildkite.buildkite-agent-${i}.plist
  launchctl load ~/Library/LaunchAgents/com.buildkite.buildkite-agent-${i}.plist
done
```

## Scheduled Tasks

| Task | Schedule | Description |
|------|----------|-------------|
| ansible-pull | Every 30 min | Pull and apply configuration |
| nightly-maintenance | 3:00 AM daily | Docker cleanup + reboot |
| docker-weekly-clean | 4:00 AM Sunday | Deep Docker cleanup |
| disk-check | Every hour | Warn if disk > 90% full |

## Directory Structure

```
/opt/mac-build/              # This repository
/opt/homebrew/               # Homebrew (ARM) or /usr/local (Intel)
  etc/buildkite-agent/       # Buildkite config
    buildkite-agent.cfg
    hooks/
    secrets/
  var/buildkite-agent/       # Build artifacts
    builds/
    plugins/
/etc/ansible/.vault-pass     # Vault password file
/var/log/                    # Logs
  ansible-pull.log
  buildkite-agent-*.log
  nightly-maintenance.log
```

## Troubleshooting

### Builds not running

```bash
# Check if agents are running
pgrep -f buildkite-agent

# Check agent logs
tail -100 /var/log/buildkite-agent-1.log

# Verify token
grep token /opt/homebrew/etc/buildkite-agent/buildkite-agent.cfg
```

### Docker not starting

```bash
# Check if Docker is running
docker info

# Start Docker manually
open -a Docker

# Check Docker logs
tail -100 ~/Library/Containers/com.docker.docker/Data/log/vm/dockerd.log
```

### Ansible-pull failing

```bash
# Check logs
tail -100 /var/log/ansible-pull.error.log

# Test SSH access to GitHub
ssh -T git@github.com

# Run manually with verbose output
ansible-pull -U git@github.com:YOUR_ORG/mac-build.git \
  -C main -d /opt/mac-build \
  --vault-password-file /etc/ansible/.vault-pass \
  -i localhost, playbooks/site.yml -vvv
```

### Machine won't sleep (expected)

Sleep is intentionally disabled for build machines. To re-enable:

```bash
sudo pmset -a sleep 10  # Sleep after 10 minutes
```

## Adding a New Machine

1. Unbox and power on the Mac
2. Complete initial macOS setup (create admin user)
3. Enable SSH: System Preferences → Sharing → Remote Login
4. Run bootstrap script
5. Verify in Buildkite dashboard that agents appear

## Security Notes

- Vault password file (`/etc/ansible/.vault-pass`) is mode 0600
- Build secrets are in `/opt/homebrew/etc/buildkite-agent/secrets/` (mode 0700)
- SSH keys for GitHub are per-machine with read-only access
- Gatekeeper is disabled for easier CLI tool usage (can be re-enabled)
