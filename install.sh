#!/bin/bash

set -euo pipefail

BOOTSTRAP_USER="bootstrap-$(openssl rand -hex 4)"
BOOTSTRAP_PASS="$(openssl rand -base64 24)"
BOOTSTRAP_PORT=2222
BOOTSTRAP_TTL=15
CERTS_DIR="/etc/certs"
CERT_USER="cert"

echo "[*] Starting node preparation..."

sudo mkdir -p "$CERTS_DIR"
sudo chown root:root "$CERTS_DIR"
sudo chmod 755 "$CERTS_DIR"

if ! id "$CERT_USER" &>/dev/null; then
  sudo useradd -m -s /bin/bash "$CERT_USER"
  echo "[*] Created user: $CERT_USER"
fi

sudo apt-get install -y -q acl
sudo setfacl -R -m u:$CERT_USER:rwx "$CERTS_DIR"
sudo setfacl -R -d -m u:$CERT_USER:rwx "$CERTS_DIR"

sudo -u "$CERT_USER" bash -c '
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  touch ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
'

echo "$CERT_USER ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx" \
  | sudo tee /etc/sudoers.d/cert-nginx > /dev/null
sudo chmod 440 /etc/sudoers.d/cert-nginx

sudo useradd -m -s /bin/bash "$BOOTSTRAP_USER"
echo "$BOOTSTRAP_USER:$BOOTSTRAP_PASS" | sudo chpasswd

sudo bash -c "cat >> /etc/ssh/sshd_config <<EOF

# Bootstrap window - temporary
Match User $BOOTSTRAP_USER
    PasswordAuthentication yes
    Port $BOOTSTRAP_PORT
    PermitTTY yes
EOF"

sudo systemctl reload sshd

sudo systemd-run --on-active="${BOOTSTRAP_TTL}m" --unit=bootstrap-cleanup \
  bash -c "
    userdel -r $BOOTSTRAP_USER 2>/dev/null || true
    # strip the Match block we added
    sed -i '/# Bootstrap window/,/PermitTTY yes/d' /etc/ssh/sshd_config
    systemctl reload sshd
    echo 'Bootstrap window closed by timer'
  "

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Node is ready. Run this on the control plane:"
echo ""
echo "  cert-ctl add-node \\"
echo "    --name <name> \\"
echo "    --ip $(hostname -I | awk '{print $1}') \\"
echo "    --port $BOOTSTRAP_PORT \\"
echo "    --user $BOOTSTRAP_USER \\"
echo "    --pass '$BOOTSTRAP_PASS'"
echo ""
echo "  Window closes in $BOOTSTRAP_TTL minutes automatically."
echo "════════════════════════════════════════════════════════"