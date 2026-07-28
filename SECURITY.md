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
* **Control**: Select **Ephemeral runners** in `gha`. The manager starts a
  long-lived controller that creates each job runner with `docker run --rm`.
  The child registers with GitHub's `--ephemeral` flag, processes one job, exits,
  and loses its writable layer before another child is created.
* **Effect**: A file written anywhere in job container N is absent from job
  container N+1. Unit tests cover boolean parsing, renewable-token admission,
  stale-child cleanup, shutdown, and socket exclusion. Docker integration tests
  run two generations whose image fails if a prior generation's root marker is
  present, then signal a supervisor during a blocking job and assert the active
  child is removed.
* **Fail closed**: `RUNNER_EPHEMERAL=0` and other documented false values remain
  persistent. Invalid values fail startup. A direct ephemeral runner requires
  `RUNNER_FRESH_CONTAINER=1` from an external one-job orchestrator; setting
  `--ephemeral` inside a Docker container configured with `restart:
  unless-stopped` is explicitly not accepted as isolation.
* **Controller boundary**: The controller alone holds the renewable
  `GITHUB_PAT` or `RUNNER_TOKEN_CMD` credential and the host Docker socket. It
  mints a short-lived, one-shot registration token for each job child; the
  renewable credential and removal-token command are never forwarded. The
  child discards registration material before executing workflow code and
  receives no socket by default. Enabling `RUNNER_CHILD_MOUNT_SOCK=1` is a
  separate trusted-only decision.

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
* **Public repository boundary**: Image publication runs on fixed GitHub-hosted
  capacity. This public repository does not require access to the persistent
  Verjson GCP runner group.
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
