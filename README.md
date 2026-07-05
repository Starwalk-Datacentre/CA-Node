# CA-Node

Node-side bootstrap and configuration scripts for the CA platform.

This repository contains shell-based logic to prepare a machine to be managed by `Starwalk-Datacentre/CA-Control-Plane`.

---

## Relationship to CA-Control-Plane

- **CA-Node** = node implementation and bootstrap behavior
- **CA-Control-Plane** = orchestration and management of nodes

In short: this repo makes a host “control-plane-ready.”

Typical flow:

1. Node scripts install/prepare required runtime dependencies.
2. Node applies base configuration and service setup.
3. Control plane connects and manages the node lifecycle.
4. Node receives future updates/operations via control plane workflows.

---

## Repository Purpose

Use this repo to:

- bootstrap fresh hosts into CA nodes,
- configure node-local services/files/users/permissions,
- enforce a repeatable node baseline.

---

## Expected Script Areas

Depending on the current structure, common categories usually include:

- bootstrap/install scripts,
- host configuration scripts,
- service setup scripts,
- health/verification scripts.

---

## Quick Start

> Replace script names below with the actual entrypoint scripts in this repository.

```bash
git clone https://github.com/Starwalk-Datacentre/CA-Node.git
cd CA-Node

# make scripts executable if needed
chmod +x *.sh

# run node bootstrap (example)
./bootstrap-node.sh
```

---

## Recommended Command Table (fill in as needed)

| Script | Purpose | Example |
|---|---|---|
| `./bootstrap-node.sh` | Prepare host as CA node | `./bootstrap-node.sh` |
| `./configure-node.sh` | Apply/reapply node configuration | `./configure-node.sh` |
| `./healthcheck.sh` | Validate node readiness | `./healthcheck.sh` |

---

## Configuration

If scripts rely on environment variables, document them clearly. Example:

- `NODE_ROLE` – role/profile applied on the node
- `CA_ENV` – environment (`dev`, `staging`, `prod`)
- `CONTROL_PLANE_URL` – control-plane endpoint/identifier
- `LOG_LEVEL` – logging verbosity

Example:

```bash
export NODE_ROLE=worker
export CA_ENV=prod
export CONTROL_PLANE_URL=control-plane.internal
export LOG_LEVEL=info
./bootstrap-node.sh
```

---

## Validation

After bootstrap/configuration, verify:

- required packages/services are present and running,
- expected files/configs exist,
- control plane can reach/manage the node as expected.

---

## Dependencies

Likely requirements (adjust to actual scripts):

- POSIX shell / bash
- core GNU utilities (`sed`, `awk`, `grep`, etc.)
- package manager tools (`apt`, `yum`, etc., as applicable)
- optional: `curl`, `jq`

---

## Operational Guidelines

- Make scripts idempotent.
- Avoid hardcoded environment-specific values.
- Write clear logs for each major step.
- Fail fast on unrecoverable errors (`set -e` patterns, validation guards).

---

## Integration with CA-Control-Plane

This repository is the node-side counterpart of:

- https://github.com/Starwalk-Datacentre/CA-Control-Plane

When updating node bootstrap behavior, check compatibility with control-plane orchestration flow and update both READMEs if the integration contract changes.

---

## License

Add project license information here.
