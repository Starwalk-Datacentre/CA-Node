#!/bin/bash
# ca-node install — prepare a target host for CA control plane enrollment.
# Opens a temporary bootstrap SSH window; the control plane completes enrollment
# via: ca node add <name> -i <ip> -p 2222 -u bootstrap-* --pass '<password>'

set -euo pipefail

CERTS_DIR="/etc/certs"
CERT_USER="cert"
BOOTSTRAP_PORT=2222
BOOTSTRAP_TTL=15

detect_distro() {
  [[ -f /etc/os-release ]] || { echo "[!] /etc/os-release not found" >&2; exit 1; }
  local id=""
  id=$(. /etc/os-release && echo "${ID:-}")
  [[ -n "$id" ]] || { echo "[!] Could not read ID from /etc/os-release" >&2; exit 1; }
  OS="$id"

  case "$OS" in
    ubuntu|debian)
      PKG_INSTALL="apt-get install -y -q"
      PKG_UPDATE="apt-get update -qq"
      SSH_SERVICE="ssh"
      SSH_PKG="openssh-server"
      ;;
    centos|rhel|almalinux|rocky)
      PKG_INSTALL="yum install -y -q"
      PKG_UPDATE="yum makecache -q"
      SSH_SERVICE="sshd"
      SSH_PKG="openssh-server"
      ;;
    fedora)
      PKG_INSTALL="dnf install -y -q"
      PKG_UPDATE="dnf makecache -q"
      SSH_SERVICE="sshd"
      SSH_PKG="openssh-server"
      ;;
    amzn)
      PKG_INSTALL="yum install -y -q"
      PKG_UPDATE="yum makecache -q"
      SSH_SERVICE="sshd"
      SSH_PKG="openssh-server"
      ;;
    alpine)
      PKG_INSTALL="apk add --no-cache"
      PKG_UPDATE="apk update"
      SSH_SERVICE="sshd"
      SSH_PKG="openssh"
      ;;
    arch|manjaro)
      PKG_INSTALL="pacman -S --noconfirm --needed"
      PKG_UPDATE="pacman -Sy --noconfirm"
      SSH_SERVICE="sshd"
      SSH_PKG="openssh"
      ;;
    *)
      echo "[!] Unsupported distribution: $OS" >&2
      exit 1
      ;;
  esac

  echo "[*] Detected OS: $OS  (ssh service: $SSH_SERVICE)"
}

check_requirements() {
  local cmd
  for cmd in sudo openssl systemctl useradd sed awk visudo; do
    command -v "$cmd" &>/dev/null || { echo "[!] Required command not found: $cmd" >&2; exit 1; }
  done
}

get_primary_ip() {
  if command -v ip &>/dev/null; then
    ip route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}'
  elif command -v hostname &>/dev/null; then
    hostname -I 2>/dev/null | awk '{print $1}'
  else
    echo "<unknown-ip>"
  fi
}

write_sudoers() {
  local file="$1"
  local content="$2"
  echo "$content" | sudo tee "$file" > /dev/null
  sudo chmod 440 "$file"
  sudo visudo -cf "$file" || { sudo rm -f "$file"; echo "[!] sudoers syntax error in $file — aborted" >&2; exit 1; }
}

cleanup_stale_bootstrap() {
  echo "[*] Cleaning up any prior bootstrap window..."

  # Cancel a pending cleanup timer from a previous run
  sudo systemctl stop bootstrap-cleanup.service 2>/dev/null || true
  sudo systemctl reset-failed bootstrap-cleanup.service 2>/dev/null || true

  # Remove stale bootstrap users (bootstrap-xxxxxxxx)
  while IFS= read -r u; do
    [[ -n "$u" ]] && sudo userdel -r "$u" 2>/dev/null || true
  done < <(awk -F: '$1 ~ /^bootstrap-[0-9a-f]{8}$/ {print $1}' /etc/passwd 2>/dev/null || true)

  sudo rm -f /etc/sudoers.d/bootstrap-window

  if sudo grep -q "# Bootstrap window - temporary" /etc/ssh/sshd_config 2>/dev/null; then
    sudo sed -i '/# Bootstrap window - temporary/,/PermitTTY yes/d' /etc/ssh/sshd_config
    sudo sshd -t && sudo systemctl reload "$SSH_SERVICE" 2>/dev/null || true
    echo "[*] Removed stale bootstrap SSH block"
  fi
}

BOOTSTRAP_USER="bootstrap-$(openssl rand -hex 4)"
BOOTSTRAP_PASS="$(openssl rand -base64 24)"

echo "[*] Starting node preparation..."

detect_distro
check_requirements
cleanup_stale_bootstrap

echo "[*] Refreshing package cache..."
sudo $PKG_UPDATE

echo "[*] Ensuring SSH server is installed..."
if ! command -v sshd &>/dev/null && ! command -v /usr/sbin/sshd &>/dev/null; then
  sudo $PKG_INSTALL "$SSH_PKG"
fi

if ! command -v setfacl &>/dev/null; then
  echo "[*] Installing acl..."
  sudo $PKG_INSTALL acl
  command -v setfacl &>/dev/null || { echo "[!] setfacl still missing after install" >&2; exit 1; }
fi

sudo mkdir -p "$CERTS_DIR"
sudo chown root:root "$CERTS_DIR"
sudo chmod 755 "$CERTS_DIR"
echo "[*] Configured $CERTS_DIR"

if ! id "$CERT_USER" &>/dev/null; then
  sudo useradd -m -s /bin/bash "$CERT_USER"
  echo "[*] Created user: $CERT_USER"
else
  echo "[*] User already exists: $CERT_USER"
fi

sudo setfacl -R  -m  u:$CERT_USER:rwx "$CERTS_DIR"
sudo setfacl -R  -d -m u:$CERT_USER:rwx "$CERTS_DIR"
echo "[*] ACL set on $CERTS_DIR for $CERT_USER"

sudo -u "$CERT_USER" bash -c '
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  touch ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
'
echo "[*] ~/.ssh configured for $CERT_USER"

write_sudoers /etc/sudoers.d/cert-nginx \
  "$CERT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx"

write_sudoers /etc/sudoers.d/cert-ssh-mgmt \
  "$CERT_USER ALL=(ALL) NOPASSWD: /usr/bin/tee, /usr/bin/chmod, /usr/bin/chown, /usr/bin/mkdir, /usr/bin/ssh-keygen, /usr/bin/systemctl"

echo "[*] sudoers entries written for $CERT_USER"

sudo useradd -m -s /bin/bash "$BOOTSTRAP_USER"
echo "$BOOTSTRAP_USER:$BOOTSTRAP_PASS" | sudo chpasswd
echo "[*] Created bootstrap user: $BOOTSTRAP_USER"

write_sudoers /etc/sudoers.d/bootstrap-window \
  "$BOOTSTRAP_USER ALL=(ALL) NOPASSWD: ALL"

sudo tee -a /etc/ssh/sshd_config > /dev/null <<EOF

# Bootstrap window - temporary
Port $BOOTSTRAP_PORT
Match User $BOOTSTRAP_USER
    PasswordAuthentication yes
    PermitTTY yes
EOF
echo "[*] Bootstrap SSH block added"

sudo sshd -t || { echo "[!] sshd config invalid — reload aborted. Check /etc/ssh/sshd_config" >&2; exit 1; }
sudo systemctl reload "$SSH_SERVICE"
echo "[*] $SSH_SERVICE reloaded"

_buser="$BOOTSTRAP_USER"
_svc="$SSH_SERVICE"

sudo systemd-run \
  --on-active="${BOOTSTRAP_TTL}m" \
  --unit=bootstrap-cleanup \
  bash -c "
    userdel -r '$_buser' 2>/dev/null || true
    rm -f /etc/sudoers.d/bootstrap-window
    sed -i '/# Bootstrap window - temporary/,/PermitTTY yes/d' /etc/ssh/sshd_config
    sshd -t && systemctl restart '$_svc'
    echo '[*] Bootstrap window closed'
  "
echo "[*] Cleanup timer set for ${BOOTSTRAP_TTL} minutes"

PRIMARY_IP="$(get_primary_ip)"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Node is ready. Run this on the control plane:"
echo ""
echo "    ca node add <name> \\"
echo "      -i $PRIMARY_IP \\"
echo "      -p $BOOTSTRAP_PORT \\"
echo "      -u $BOOTSTRAP_USER \\"
echo "      --pass '$BOOTSTRAP_PASS'"
echo ""
echo "  Replace <name> with a short node label (e.g. worker-01)."
echo "  Complete enrollment within $BOOTSTRAP_TTL minutes."
echo "════════════════════════════════════════════════════════"
