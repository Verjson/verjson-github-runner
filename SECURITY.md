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
* **Controller boundary**: The launcher transfers a renewable PAT through a
  one-use mode-0600 FIFO that is destroyed before registration. The controller
  holds it only in non-exported process memory, or uses
  `RUNNER_TOKEN_CMD`, alongside the host Docker socket. It
  mints a short-lived, one-shot registration token for each job child and
  streams it over stdin so it is absent from Docker argv, inspectable
  environment, logs, images, and reusable host state. The renewable credential
  and removal-token command are never forwarded. The
  child discards registration material before executing workflow code and
  receives no socket by default. Enabling `RUNNER_CHILD_MOUNT_SOCK=1` is a
  separate trusted-only decision.
* **Restart constraint**: Docker auto-restart is disabled for FIFO-launched
  containers. A restart cannot replay the destroyed transport; an authorized
  launcher must create a new one.

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
* **Isolated-lane admission**: Advertising `untrusted-pr` fails closed unless the immutable image is digest-pinned, the group is non-Default, all canonical isolation labels are present, the socket is disabled, and a dedicated child network plus `RUNNER_METADATA_DENY_ATTEST_CMD` attest metadata denial. The controller retains host metadata access for token minting; only the child is attached to the deny network.
* **Network Egress**: Restrict outbound container networking to required endpoints (GitHub API, package registries) via firewall rules or proxy filters.

### Fail-Closed `ci` Capability Admission
* **Control**: When `RUNNER_LABELS` contains the exact `ci` label, matched
  case-insensitively to GitHub's label semantics, `entrypoint.sh`
  exercises GitHub CLI, Docker daemon access, Compose, Buildx, Node.js 24, npm, jq, git,
  bash, curl, grep, sed, awk, find, base64, tar, gzip, unzip, and python3 before
  resolving any registration credential.
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
* **Isolation-supervisor contract label**: The base image — and therefore every kind image
  built `FROM` it — carries the OCI config label
  `com.verjson.gha-runner.isolation-supervisor="1"`, which declares that the entrypoint
  implements the one-job supervisor contract. Isolated-mode consumers
  (`@verjson/cli-cloud`'s runner-image-contract step) read the label off the image config
  and fail closed on a missing or unrecognized value, so an image predating the supervisor
  cannot be admitted for isolated PR lanes. The value versions the contract; bump it only
  when the supervisor admission contract changes incompatibly.
* **Public repository boundary**: Image publication runs on fixed GitHub-hosted
  capacity. This public repository does not require access to the shared persistent
  Verjson runner group.
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
