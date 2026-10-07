# Restricted GitLab runner canary

`runner.json` is the secret-free Kubernetes deployment reviewed for the shared
GitLab/Nexus host. It creates the `verjson-runners` namespace, restricted admission,
finite quota, explicit network policies, manager-only RBAC and the Nexus-pinned
GitLab Runner 18.3.1 manager. Job pods use the unprivileged `default` service account
without an automatically mounted token. The manager uses its separately named
service account to manage jobs in this namespace.

The deployment owner supplies the existing Secret
`verjson-gitlab-runner-config` containing `config.toml`; credentials and the
registered runner token must never enter this repository. Generate the
credential-free portion with `scripts/gitlab_build_config.py` from the reviewed
Nexus publication contract, including `.verjson/runtime-candidate.json`, then
supply the approved GitLab URL and runner token through the deployment's secret
management path. Do not merge it into a permissive existing runner configuration.

GitLab Runner 18.3.1 requires the fixed advanced PodSpec merge patch to set
`securityContext.seccompProfile.type: RuntimeDefault`. The generated patch only
adds that scalar subtree; it does not replace container lists or remove runner
security settings. The scripts/logs directories use `/tmp` for nonroot execution,
and job label overrides are disabled so jobs cannot acquire the manager's
network-policy label. Restricted Pod Security Admission remains enforced even
when a job attempts feature-flag overrides.

Before applying the manifest, inventory every existing NetworkPolicy in
`verjson-runners` and stop if any additional policy grants job pods manager-only
API access or broader egress. Kubernetes combines allowed traffic across matching
policies: applying a restrictive new policy cannot cancel an old broad grant.
Back up and explicitly reconcile legacy policies with the deployment owner before
continuing. Then review the exact image digests, namespace quotas,
network destinations, RBAC and the Secret contents against the live deployment.
After applying it, inspect the actual admitted job pod and verify clone, artifacts,
UID, seccomp, image restrictions, resource limits and cleanup. Publication also
requires the separately approved OIDC broker and plan/evidence acceptance; this
manifest contains no registry publisher credentials or broker deployment.

Before activating signed candidate or release work, run a protected-main WEB job
through this runner and retain its job and pod receipts. Verify the admitted build,
helper and runtime image digests; UID 1001; dropped capabilities; the exact seccomp
and AppArmor profiles; no mounted service-account token, host socket or writable
host path; and cleanup of the job-scoped image-pull Secret. Inside that job, require
the root-owned, non-writable `/usr/bin/bwrap` and exercise the supervisor's actual
user/PID/network/IPC/UTS sandbox with fresh proc, dev and tmp filesystems and no
nested user namespaces. Prove `.git`, the host home, the outer proc filesystem,
runner scripts, acquisition inputs, credentials and sibling jobs are hidden,
with only the task output directory writable. Retain signed acquisition denial,
expiry and rollback receipts. Any failed assertion blocks activation; a manually
created pod or host image probe
cannot establish the native job's credential and isolation boundaries. Issue #208
tracks the current live failure and the remaining acceptance evidence.

The live K3s canary observed a policy convergence window for newly created pods:
initial TCP connections to the Kubernetes API succeeded, while unauthenticated
pod/Secret requests returned HTTP 401; a later probe found both API connections
denied. The observed 20-second interval is diagnostic, not a security guarantee or
an authorization delay to rely on. Do not claim immediate TCP isolation. The
startup privilege boundary is the absence of a mounted service-account token,
unprivileged job service account and restricted Pod Security Admission. Preserve
those controls and verify actual network behavior for each deployment. Sanitized
canary evidence is recorded with the live acceptance handoff in issue #201.

GitLab's matching-version and PodSpec configuration references:

- https://docs.gitlab.com/runner/#gitlab-runner-versions
- https://docs.gitlab.com/runner/configuration/advanced-configuration/#override-the-helper-image
- https://gitlab.com/gitlab-org/gitlab-runner/-/blob/v18.3.1/docs/executors/kubernetes/_index.md
- https://gitlab.com/gitlab-org/gitlab-runner/-/blob/v18.3.1/common/config.go

GitLab Runner 18.3.1 does not copy runner environment variables into the helper
container environment. The fixed `nonroot-home` strategic PodSpec patch therefore
sets `HOME=/tmp` on both named `build` and `helper` containers, preserving their
other variables and generated container configuration. Runner environment sets
the same value for generated script exports. This avoids pre-checkout global Git
configuration writes to `//.gitconfig` under UID 1001. The home stays inside each
container's bounded ephemeral storage; no host mount or privilege is added.

## Job-scoped registry authentication

The manager Deployment references `nexus-manager-pull` only for its own
control-plane image bootstrap. That credential must be scoped to manager image
reads and must not appear in job configuration, the default service account, or
project/group variables. The generated job configuration explicitly sets
`image_pull_secrets=[]` and `use_service_account_image_pull_secrets=false`.
Keep the exact build/helper/runtime image allowlist and `always` pull policy.

Each canonical CI job requests `VERJSON_REGISTRY_PULL_ID_TOKEN` with audience
`https://docker.nexus.159-195-78-163.nip.io`. Its `DOCKER_AUTH_CONFIG` variable uses
`username: verjson-oidc` and `password: $VERJSON_REGISTRY_PULL_ID_TOKEN` under that
registry host. Variable expansion is mandatory: the canonical YAML specifies
`expand: true`, corresponding to `raw: false` in GitLab's expanded job variables.
A literal unexpanded token reference cannot authenticate. Do not install static
fallback credentials in the runner environment or higher-priority project/group
variables; inspect variable names and expansion flags without displaying values.

GitLab Runner 18.3.1 creates the job-scoped Docker pull Secret before creating its
pod, and the same Secret covers build and helper pulls. The synthetic exact-binary
[proof](../../docs/gitlab/evidence/runner-18.3.1-job-pull-auth.json) records the
measured request order and immutable runner image identity. It does not establish
live GitLab, gateway or Nexus acceptance. Namespace-scoped manager permissions to
create/delete job Secrets remain necessary; job service accounts receive no API
token or corresponding permissions.

The initial gateway allowlist admits only approved projects and protected main or
explicitly configured protected canary references. All canonical jobs have a
five-minute timeout and pull tokens have at most a 300-second lifetime. Other
branches cannot pull these private job images during this initial rollout; broader
merge-request execution requires a separately approved reference policy. Publication
uses its own audience and authorization; pull access does not authorize writes.

Live acceptance must use a newly built canonical CI candidate digest that is not
already on the node, retain `always`, and prove zero static job fallback. Inspect
the admitted pod's `imagePullSecrets` and only the masked Secret structure, then
verify short-lived expiry and approved-reference denial. A warm node cache alone
cannot prove authenticated pulls. Do not purge shared caches to manufacture this
proof. Keep manager bootstrap receipts separate from per-job authentication.

GitHub currently retains history and issue/PR tracking, including existing PR
#196. Read-only enforcement and automatic mirroring are not configured; neither
is implied by making GitLab primary.
