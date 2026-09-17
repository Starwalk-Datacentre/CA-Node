#!/bin/bash

set -euo pipefail
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
      ;;
    centos|rhel|almalinux|rocky)
      PKG_INSTALL="yum install -y -q"
      PKG_UPDATE="yum makecache -q" 
      SSH_SERVICE="sshd"
      ;;
    fedora)
      PKG_INSTALL="dnf install -y -q"
      PKG_UPDATE="dnf makecache -q"
      SSH_SERVICE="sshd"
      ;;
    amzn)
      PKG_INSTALL="yum install -y -q"
      PKG_UPDATE="yum makecache -q"
      SSH_SERVICE="sshd"
      ;;
    alpine)
      PKG_INSTALL="apk add --no-cache"
      PKG_UPDATE="apk update"
      SSH_SERVICE="sshd"
      ;;
    arch|manjaro)
      PKG_INSTALL="pacman -S --noconfirm --needed"
      PKG_UPDATE="pacman -Sy --noconfirm"
      SSH_SERVICE="sshd"
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

BOOTSTRAP_USER="bootstrap-$(openssl rand -hex 4)"
BOOTSTRAP_PASS="$(openssl rand -base64 24)"
BOOTSTRAP_PORT=2222
BOOTSTRAP_TTL=15
CERTS_DIR="/etc/certs"
CERT_USER="cert"

echo "[*] Starting node preparation..."

detect_distro
check_requirements

echo "[*] Refreshing package cache..."
sudo $PKG_UPDATE

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

echo "$CERT_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx" \
  | sudo tee /etc/sudoers.d/cert-nginx > /dev/null
sudo chmod 440 /etc/sudoers.d/cert-nginx
sudo visudo -cf /etc/sudoers.d/cert-nginx \
  || { sudo rm -f /etc/sudoers.d/cert-nginx; echo "[!] cert-nginx sudoers syntax error — aborted" >&2; exit 1; }
echo "[*] sudoers entry written for $CERT_USER"

sudo useradd -m -s /bin/bash "$BOOTSTRAP_USER"
echo "$BOOTSTRAP_USER:$BOOTSTRAP_PASS" | sudo chpasswd
echo "[*] Created bootstrap user: $BOOTSTRAP_USER"

echo "$BOOTSTRAP_USER ALL=(ALL) NOPASSWD: ALL" \
  | sudo tee /etc/sudoers.d/bootstrap-window > /dev/null
sudo chmod 440 /etc/sudoers.d/bootstrap-window
sudo visudo -cf /etc/sudoers.d/bootstrap-window \
  || { sudo rm -f /etc/sudoers.d/bootstrap-window; echo "[!] bootstrap sudoers syntax error — aborted" >&2; exit 1; }
echo "[*] Root-level sudoers entry written for $BOOTSTRAP_USER"

if ! sudo grep -q "# Bootstrap window - temporary" /etc/ssh/sshd_config; then
  sudo tee -a /etc/ssh/sshd_config > /dev/null <<EOF

# Bootstrap window - temporary
Port $BOOTSTRAP_PORT
Match User $BOOTSTRAP_USER
    PasswordAuthentication yes
    PermitTTY yes
EOF
  echo "[*] Bootstrap SSH block added"
fi

sudo sshd -t || { echo "[!] sshd config invalid — reload aborted. Check /etc/ssh/sshd_config" >&2; exit 1; }
sudo systemctl reload "$SSH_SERVICE"
echo "[*] $SSH_SERVICE reloaded"

_buser="$BOOTSTRAP_USER"
_svc="$SSH_SERVICE"

sudo systemd-run \
  --on-active="${BOOTSTRAP_TTL}m" \
  --unit=bootstrap-cleanup \
  bash -c "
    # Remove bootstrap user and its home dir
    userdel -r '$_buser' 2>/dev/null || true

    # Remove the bootstrap sudoers entry
    rm -f /etc/sudoers.d/bootstrap-window

    # Strip the bootstrap SSH block (Port line + Match block)
    sed -i '/# Bootstrap window - temporary/,/PermitTTY yes/d' /etc/ssh/sshd_config

    # Validate before reloading — never reload a broken config
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
echo "       -i $PRIMARY_IP \\"
echo "       -p $BOOTSTRAP_PORT \\"
echo "       -u $BOOTSTRAP_USER \\"
echo "       --pass '$BOOTSTRAP_PASS'"
echo ""
echo "  Bootstrap Config closes in $BOOTSTRAP_TTL minutes automatically."
echo "════════════════════════════════════════════════════════"