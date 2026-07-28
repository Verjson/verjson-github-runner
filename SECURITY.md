# Security & Hardening Policy for Self-Hosted Runners

This document outlines the security threat model, runner isolation controls, and hardening practices for running self-hosted GitHub Actions runners using this project.

---

## 1. Threat Model & Scope

Self-hosted runners execute user-supplied code (including dependency lifecycle scripts like `npm postinstall`, `cargo build`, etc.) directly on host environments or inside Docker containers. When handling pull requests:
- **Untrusted Code Execution**: PRs from forks or modified branches execute arbitrary code within the runner environment.
- **Cross-Job Persistence**: On persistent runners, state changes, cached tokens, or modified files can persist across subsequent jobs, creating lateral movement or supply-chain tampering risks.
- **Credential & Egress Exposure**: Ambient cloud authority (IMDS/metadata services), mounted Docker sockets, or shared secrets can be exfiltrated if accessible to the runner container.

---

## 2. Hardening Controls

### Ephemeral / JIT Runners (`RUNNER_EPHEMERAL=1`)
* **Control**: Supported launchers parse `RUNNER_EPHEMERAL` explicitly. `1` and
  `true` select one-job registration; `0`, `false`, and empty select persistent
  registration; every other value fails before token minting or registration.
  Ephemeral launchers use Docker `--rm` without a restart policy.
* **Effect**: The runner accepts at most **one job**. On completion, runner crash,
  or operator shutdown, the entrypoint attempts de-registration and the Docker
  daemon removes the container and its writable layer. Starting capacity again
  creates a new container identity. Integration tests write a marker outside the
  checked-out repository and prove that the next container cannot see it.
* **Supervisor boundary**: `./config.sh --ephemeral` or the environment variable
  alone only limits a GitHub registration; it does not erase a reused container.
  A long-lived external reconciler may persist, but it must create a new `--rm`
  job container for every registration. The `gha` manager and setup scripts
  enforce this split. Compose users must invoke
  `docker compose --profile ephemeral run --rm runner-ephemeral`.
* **Failure behavior**: Ephemeral containers have no Docker restart policy, so a
  runner crash cannot reconfigure inside the same writable layer or settle into a
  restart loop. Re-registration requires a new invocation and a freshly minted
  registration token.

### Persistent Runners (lower isolation)
* **Control**: `RUNNER_EPHEMERAL=0`, `false`, or empty preserves
  `--restart unless-stopped` for hosts that deliberately need stable capacity.
* **Boundary**: Container identity, workspace, caches, and writable-layer state can
  survive restarts. Persistent runners must not execute untrusted pull-request
  code and must be restricted to reviewed private workflows.

### Least-Privilege Workflow Permissions
* **Control**: Specify explicit `permissions:` blocks in all workflow definitions:
  ```yaml
  permissions:
    contents: read
  ```
* **Effect**: Restricts the default `GITHUB_TOKEN` to read-only repository access. Avoid using broad tokens or `secrets: inherit` on `pull_request` events. Keep write credentials and publishing secrets strictly scoped to post-merge (`push` on `main`) or release pipelines.

### Infrastructure & Socket Isolation
* **Docker Socket**: Do **not** mount `/var/run/docker.sock` on untrusted PR CI runners. Mounting the Docker socket grants root-equivalent access to the host node.
* **Instance Metadata (IMDS)**: On cloud VMs (GCP / AWS / Azure), block or restrict access to metadata servers (e.g., set IMDSv2 hop limit to `1` on AWS or restrict GCP metadata server endpoints) to prevent containerized jobs from reading VM service account tokens.
* **Network Egress**: Restrict outbound container networking to required endpoints (GitHub API, package registries) via firewall rules or proxy filters.

### Fail-Closed `ci` Capability Admission
* **Control**: When `RUNNER_LABELS` contains the exact `ci` label, matched
  case-insensitively to GitHub's label semantics, `entrypoint.sh`
  exercises GitHub CLI, Docker daemon access, Compose, Buildx, Node.js 24, npm, jq, git,
  bash, curl, grep, sed, awk, find, base64, tar, and gzip before resolving any
  registration credential.
* **Effect**: A container cannot advertise `ci` and accept a job with a partial toolchain.
  Failure prevents both registration-token minting and `config.sh` registration; there is
  no caller-controlled bypass.
* **Boundary**: Docker daemon admission proves functionality, not isolation. A `ci`
  runner with a mounted Docker socket is host-root-equivalent and must be restricted to
  trusted repositories and ephemeral/job-clean execution.

### Image Supply-Chain Integrity
* **GitHub CLI and Node.js**: The base image pins upstream release versions and
  architecture-specific SHA-256 checksums published by GitHub and Node.js. Image
  construction fails on a checksum mismatch.
* **Published images**: BuildKit publishes SBOM and provenance attestations for the shared
  multi-architecture base and kind images. The workflow retains a receipt binding each
  commit-addressed tag to its immutable manifest digest.
* **Deployment**: Rollouts should consume the recorded digest, validate `ci` admission on
  the host, and retain the previous digest as the rollback target. Never broaden runner
  group access as part of an image rollout.

### Immutable Workflow References
* **Control**: Pin reusable workflow imports to full commit SHAs or governed release tags:
  ```yaml
  uses: Verjson/.github/.github/workflows/node-ci.yml@849d7d57eaa86e56d331cb4444d983255d48b624
  ```

---

## 3. Incident Response & Containment

If a self-hosted runner host is suspected of compromise:
1. **De-register Immediately**: Stop the runner process or container (`./gha stop` or `docker stop <container_id>`).
2. **Revoke Credentials**: Revoke any PATs or App registration tokens associated with the runner in GitHub **Org/Repo Settings → Actions → Runners**.
3. **Re-provision Instance**: Rebuild the VM/host from a clean base image.
