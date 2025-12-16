# macOS Build Machine Configuration

Ansible-based configuration management for macOS Buildkite CI agents (ARM Macs).

## Features

- **Docker Desktop** - Installed (requires manual configuration, see below)
- **Buildkite Agent** - 3 concurrent agents per machine (configurable)
- **Auto-updates** - Machines pull configuration from Git every 30 minutes
- **Nightly maintenance** - Docker cleanup and reboot at 3 AM
- **Unattended operation** - Sleep disabled, auto-restart after power failure
- **Log rotation** - Prevents disk space issues

## Prerequisites

Before bootstrapping a Mac, you need:

1. **Buildkite Agent Token** - Get from [Buildkite](https://buildkite.com) → Organization Settings → Agents → Reveal Agent Token
2. **GitHub Deploy Key** - For ansible-pull to access this repo (see below)
3. **Ansible Vault Password** - Create a strong password and store it securely

## Quick Start

### 1. Configure this repository (one-time setup)

```bash
# Clone this repo
git clone git@github.com:daisychainapp/mac-buildkite-machine.git
cd mac-buildkite-machine

# Generate a deploy key for ansible-pull
ssh-keygen -t ed25519 -C "mac-buildkite-deploy" -f deploy_key -N ""

# Add the PUBLIC key to GitHub:
# 1. Go to: https://github.com/daisychainapp/mac-buildkite-machine/settings/keys
# 2. Click "Add deploy key"
# 3. Paste contents of deploy_key.pub
# 4. Check "Allow write access" is OFF (read-only)

# Copy the example vault file and add your secrets
cp group_vars/vault.yml.example group_vars/vault.yml
vim group_vars/vault.yml
# Set:
#   vault_buildkite_agent_token: "your-token-from-buildkite"
#   vault_github_deploy_key: |
#     (paste entire contents of deploy_key file)

# Encrypt the vault
ansible-vault encrypt group_vars/vault.yml
# Enter a password - SAVE THIS PASSWORD SECURELY

# Update group_vars/all.yml
vim group_vars/all.yml
# Change ansible_pull_repo_url to: git@github.com:daisychainapp/mac-buildkite-machine.git

# Commit and push
git add -A
git commit -m "Configure for daisychainapp"
git push
```

### 2. Bootstrap a new Mac

On the new Mac:

1. Complete initial macOS setup (create an admin user)

2. **Disable FileVault** (required for auto-login and unattended reboots):
   - System Settings → Privacy & Security → FileVault → Turn Off
   - Or via terminal: `sudo fdesetup disable`
   - Wait for decryption to complete before proceeding

3. **Enable Auto-Login** (required for headless screen sharing after reboots):
   - System Settings → Users & Groups → Login Options → Automatic login → Select your user
   - Note: This option only appears when FileVault is disabled

4. **Complete Docker Desktop Setup** (after bootstrap):
   - Open Docker Desktop manually the first time
   - Go to Settings → General → Choose Virtual Machine Manager: **Docker VMM** (required for ARM)
   - Accept the license agreement
   - Wait for Docker to start successfully

5. Open Terminal and run:

```bash
# Download and run bootstrap interactively
curl -fsSL https://raw.githubusercontent.com/daisychainapp/mac-buildkite-machine/main/bootstrap.sh -o /tmp/bootstrap.sh
bash /tmp/bootstrap.sh
```

The script will prompt you for:
- **Deploy key** - Paste the private key (contents of `deploy_key` file)
- **Vault password** - The password you used with `ansible-vault encrypt`

### 3. Verify

After bootstrap completes:

```bash
# Check Buildkite agents are running
pgrep -f buildkite-agent

# Check agent logs
tail -f /var/log/buildkite-agent-1.log

# Verify in Buildkite dashboard that agents appear
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
brew services restart buildkite/buildkite/buildkite-agent
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
/opt/mac-build/                              # This repository (cloned by bootstrap)
/opt/homebrew/                               # Homebrew prefix (ARM Macs)
  bin/buildkite-agent                        # Buildkite agent binary
  etc/buildkite-agent/
    buildkite-agent.cfg                      # Agent configuration
    hooks/                                   # Buildkite hooks (environment, pre-exit)
    secrets/
      build-secrets.env                      # Optional build secrets
  var/buildkite-agent/
    builds/                                  # Build checkouts
    plugins/                                 # Buildkite plugins
/etc/ansible/.vault-pass                     # Vault password (root-only, mode 0600)
/usr/local/bin/
  nightly-maintenance.sh                     # Nightly cleanup script
  check-disk-space.sh                        # Hourly disk check
/opt/homebrew/var/log/
  buildkite-agent.log                        # Agent stdout
  buildkite-agent.error.log                  # Agent stderr
/var/log/
  ansible-pull.log                           # Auto-update logs
  ansible-pull.error.log
  ansible-last-run.json                      # Last successful run metadata
  nightly-maintenance.log                    # Maintenance logs
  disk-check.log                             # Disk space warnings
~/Library/LaunchAgents/
  homebrew.mxcl.buildkite-agent.plist        # Brew-managed agent service
/Library/LaunchDaemons/
  com.internal.ansible-pull.plist            # Auto-update service
  com.internal.nightly-maintenance.plist     # Nightly maintenance service
  com.internal.docker-weekly-clean.plist     # Weekly Docker cleanup
  com.internal.disk-check.plist              # Hourly disk check
```

## Troubleshooting

### Builds not running

```bash
# Check if agents are running
pgrep -f buildkite-agent

# Check agent logs
tail -100 /opt/homebrew/var/log/buildkite-agent.log

# Restart agent
brew services restart buildkite/buildkite/buildkite-agent

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
ansible-pull -U git@github.com:daisychainapp/mac-buildkite-machine.git \
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
