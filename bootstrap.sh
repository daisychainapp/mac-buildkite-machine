#!/bin/bash
#
# Bootstrap script for macOS build machines
# Run this once on a fresh Mac to initialize configuration management
#
# Usage: curl -fsSL https://raw.githubusercontent.com/daisychainapp/mac-buildkite-machine/main/bootstrap.sh | bash
#    or: ./bootstrap.sh
#

set -euo pipefail

# Configuration
REPO_URL="${MAC_BUILD_REPO:-git@github.com:daisychainapp/mac-buildkite-machine.git}"
REPO_BRANCH="${MAC_BUILD_BRANCH:-main}"
LOCAL_REPO="/opt/mac-build"
VAULT_PASSWORD_FILE="/etc/ansible/.vault-pass"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate SSH private key format
validate_ssh_key() {
    local key="$1"
    if [[ "$key" == *"-----BEGIN"*"PRIVATE KEY-----"* ]] && [[ "$key" == *"-----END"*"PRIVATE KEY-----"* ]]; then
        return 0
    fi
    return 1
}

# Read multiline input (SSH key) interactively
read_ssh_key() {
    local key=""
    local line

    echo "Paste your deploy key below (the private key content)."
    echo "The key should start with '-----BEGIN' and end with '-----END...PRIVATE KEY-----'"
    echo ""

    while IFS= read -r line; do
        key+="$line"$'\n'
        # Stop when we see the END marker
        if [[ "$line" == *"-----END"*"PRIVATE KEY-----"* ]]; then
            break
        fi
    done

    echo "$key"
}

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    log_error "This script is intended for macOS only"
    exit 1
fi

# Don't run as root
if [[ "$EUID" -eq 0 ]]; then
    log_error "Do not run this script with sudo. Run as a normal user."
    log_error "The script will ask for sudo password when needed."
    exit 1
fi

echo "=============================================="
echo "  macOS Build Machine Bootstrap"
echo "=============================================="
echo ""

# Cache sudo credentials upfront
log_info "This script requires sudo access for some operations."
if ! sudo -v; then
    log_error "Failed to obtain sudo access"
    exit 1
fi

# Keep sudo alive in background
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Step 1: Enable Screen Sharing for remote admin
log_info "Enabling Screen Sharing..."
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
log_info "Screen Sharing: OK"

# Step 1b: Configure power management for headless operation
log_info "Configuring power management for headless operation..."
sudo pmset -a sleep 0              # Disable system sleep
sudo pmset -a disablesleep 1       # Prevent sleep entirely
sudo pmset -a displaysleep 0       # Don't sleep display
sudo pmset -a hibernatemode 0      # Disable hibernation
sudo pmset -a autopoweroff 0       # Disable auto power off
sudo pmset -a standby 0            # Disable standby mode
sudo pmset -a powernap 0           # Disable Power Nap
sudo pmset -a womp 1               # Wake on Magic Packet (Wake on LAN)
sudo pmset -a autorestart 1        # Restart automatically after power failure
log_info "Power management: OK (sleep disabled, auto-restart enabled)"

# Step 1c: Check auto-login for headless screen sharing
log_info "Checking auto-login configuration..."
CURRENT_USER="$(whoami)"

# Check if FileVault is enabled (incompatible with auto-login)
if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then
    log_warn "FileVault is enabled - auto-login is not possible."
    log_warn "After any reboot, you'll need to enter the disk password manually."
    log_warn "To disable FileVault: sudo fdesetup disable"
else
    # Check if auto-login is already configured
    EXISTING_AUTOLOGIN=$(sudo defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || echo "")

    if [[ -n "$EXISTING_AUTOLOGIN" ]]; then
        log_info "Auto-login configured for: $EXISTING_AUTOLOGIN"
    else
        echo ""
        log_warn "Auto-login is NOT configured."
        log_warn "For headless operation, enable it manually:"
        log_warn "  System Settings → Users & Groups → Login Options → Automatic login"
        log_warn "  Select user: $CURRENT_USER"
        echo ""
        read -p "Press Enter to continue..."
    fi
fi

# Step 2: Install Xcode Command Line Tools
log_info "Checking Xcode Command Line Tools..."
if ! xcode-select -p &>/dev/null; then
    log_info "Installing Xcode Command Line Tools..."
    xcode-select --install

    echo ""
    log_warn "Please complete the Xcode Command Line Tools installation dialog."
    log_warn "After installation completes, re-run this script."
    echo ""
    read -p "Press Enter after installation completes to continue, or Ctrl+C to exit..."

    # Verify installation
    if ! xcode-select -p &>/dev/null; then
        log_error "Xcode Command Line Tools installation not detected. Please install and retry."
        exit 1
    fi
fi
log_info "Xcode Command Line Tools: OK"

# Step 2: Install Homebrew
log_info "Checking Homebrew..."
if ! command -v brew &>/dev/null; then
    log_info "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for this session
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

# Ensure brew is in PATH
if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

log_info "Homebrew: OK ($(brew --version | head -1))"

# Step 3: Install Ansible and Git
log_info "Installing Ansible and Git via Homebrew..."
brew install ansible git

log_info "Ansible: OK ($(ansible --version | head -1))"
log_info "Git: OK ($(git --version))"

# Step 4: Set up SSH for GitHub (if using SSH URL)
if [[ "$REPO_URL" == git@* ]]; then
    log_info "Setting up SSH for GitHub..."

    SSH_DIR="$HOME/.ssh"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    # Check if we need to set up deploy key
    if [[ ! -f "$SSH_DIR/mac-build-deploy" ]]; then
        echo ""
        log_warn "GitHub deploy key not found."
        log_warn "Please paste your deploy key private key (the one added to GitHub)."
        log_warn "Press Ctrl+D when done:"
        echo ""

        cat > "$SSH_DIR/mac-build-deploy"
        chmod 600 "$SSH_DIR/mac-build-deploy"

        # Add to SSH config
        if ! grep -q "mac-build-deploy" "$SSH_DIR/config" 2>/dev/null; then
            cat >> "$SSH_DIR/config" << EOF

# GitHub deploy key for mac-build repo
Host github.com
    IdentityFile ~/.ssh/mac-build-deploy
    IdentitiesOnly yes
EOF
        fi

        log_info "Deploy key configured"
    fi

    # Test GitHub connection
    log_info "Testing GitHub SSH connection..."
    if ! ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        log_warn "GitHub SSH test did not return expected output. This may be OK."
    fi
fi

# Step 5: Clone or update the configuration repository
log_info "Setting up configuration repository..."

if [[ -d "$LOCAL_REPO" ]]; then
    log_info "Repository exists, updating..."
    cd "$LOCAL_REPO"
    git fetch origin
    git checkout "$REPO_BRANCH"
    git pull origin "$REPO_BRANCH"
else
    log_info "Cloning repository..."
    sudo mkdir -p "$(dirname "$LOCAL_REPO")"
    sudo chown "$(whoami)" "$(dirname "$LOCAL_REPO")"
    git clone "$REPO_URL" "$LOCAL_REPO"
    cd "$LOCAL_REPO"
    git checkout "$REPO_BRANCH"
fi

log_info "Repository: OK ($LOCAL_REPO)"

# Step 6: Install Ansible Galaxy requirements
log_info "Installing Ansible Galaxy requirements..."
cd "$LOCAL_REPO"
ansible-galaxy install -r requirements.yml --force

log_info "Galaxy requirements: OK"

# Step 7: Set up Ansible Vault password
log_info "Setting up Ansible Vault..."

if [[ ! -f "$VAULT_PASSWORD_FILE" ]]; then
    echo ""
    log_warn "Ansible Vault password file not found."
    echo -n "Enter the Ansible Vault password: "
    read -s VAULT_PASS
    echo ""

    sudo mkdir -p "$(dirname "$VAULT_PASSWORD_FILE")"
    echo "$VAULT_PASS" | sudo tee "$VAULT_PASSWORD_FILE" > /dev/null
    sudo chmod 600 "$VAULT_PASSWORD_FILE"

    log_info "Vault password stored"
else
    log_info "Vault password file exists"
fi

# Step 8: Run initial playbook
log_info "Running initial configuration playbook..."
echo ""

cd "$LOCAL_REPO"
ansible-playbook playbooks/site.yml \
    --vault-password-file "$VAULT_PASSWORD_FILE" \
    --connection=local \
    --inventory localhost, \
    -e "ansible_python_interpreter=$(which python3)"

# Step 9: Verify installation
echo ""
echo "=============================================="
echo "  Bootstrap Complete!"
echo "=============================================="
echo ""
log_info "Configuration management is now active."
log_info "The machine will self-update every 30 minutes via ansible-pull."
echo ""
log_info "Useful commands:"
echo "  - View ansible-pull logs: tail -f /var/log/ansible-pull.log"
echo "  - Manual update: cd $LOCAL_REPO && ansible-playbook playbooks/site.yml --vault-password-file $VAULT_PASSWORD_FILE -c local -i localhost,"
echo "  - View last run: cat /var/log/ansible-last-run.json"
echo ""
