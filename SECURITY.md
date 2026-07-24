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
* **Control**: Set `RUNNER_EPHEMERAL=1` in container environment variables or `--ephemeral` when calling `./config.sh`.
* **Effect**: The runner processes exactly **one job** and immediately de-registers and shuts down upon completion. Any temporary state, workspace files, or memory tokens are completely destroyed, preventing cross-job persistence.

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
