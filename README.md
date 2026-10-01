# CA-Node

Node-side bootstrap script for the CA Control Plane.

Run this on a machine that is to become a CA-managed node. It prepares the
host — installs SSH server, sudo, and ACL tooling, creates the `cert`
management user with a least-privilege sudoers profile, and opens a
**temporary 15-minute bootstrap window** through which the control plane
completes enrollment.

- **CA-Node** (this repo) = node-side bootstrap and baseline configuration
- **CA-Control-Plane** (https://github.com/starwalk-datacentre/ca-cp) = the
  certificate authority, dashboard, and node lifecycle management

All bootstrap credentials are generated at runtime on the node and printed
to your terminal — nothing is embedded in this script and nothing is stored
here.

---

## Install (one command, on the node)

Latest (tracks `main`):

```bash
curl -sSL https://raw.githubusercontent.com/starwalk-datacentre/ca-node/main/install.sh | sudo bash
```

Pinned, immutable (recommended for production baselines):

```bash
curl -sSL https://github.com/starwalk-datacentre/ca-node/releases/latest/download/install.sh | sudo bash
```

Verify the script before running it (optional but encouraged):

```bash
curl -sSL https://raw.githubusercontent.com/starwalk-datacentre/ca-node/main/install.sh -o ca-node-install.sh
sha256sum -c <<< "$(curl -sSL https://raw.githubusercontent.com/starwalk-datacentre/ca-node/main/install.sh.sha256)  ca-node-install.sh"
sudo bash ca-node-install.sh
```

---

## What the script does

1. Ensures SSH server, sudo, and ACL tooling are present (installs them when
   missing; supports Debian/Ubuntu, RHEL-family, and Arch)
2. Creates `/etc/certs` with ACLs for the `cert` management user
3. Creates a **temporary bootstrap user** (`bootstrap-XXXXXXXX`) with a
   random password and `NOPASSWD: ALL` sudo, available for **15 minutes** on
   port 2222
4. Writes the least-privilege sudoers profile the `cert` user will use after
   enrollment (certificate installs, service reloads, key inspections —
   command-allowlisted, nothing broader)
5. Prints the exact `ca node add` command to run on the control plane

The script is idempotent: re-running it is safe, and it fails fast on
unrecoverable errors.

---

## Enroll (on the control plane, within the 15-minute window)

```bash
ca node add web-01 \
  -i <node-ip> \
  -p 2222 \
  -u bootstrap-XXXXXXXX \
  --pass '<password printed by the script>'
```

The control plane then connects via SSH, verifies every step remotely,
signs the host key, configures sshd to trust the CA, closes the bootstrap
window, and confirms each stage before reporting success.

---

## Relationship to CA-Control-Plane

This repository is the node-side counterpart of
https://github.com/starwalk-datacentre/ca-cp — it makes a host
"control-plane-ready". When updating node bootstrap behavior here, check
compatibility with the control-plane enrollment flow and keep both
repositories in sync.

---

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
