### What's changed in v1.0.0

* initial: auth-stack with durable+operational secrets pattern (by @patrickleet)

  AuthStack XRD wraps the Zitadel Helm chart with a typed XRD surface.
  Implements [[specs/authstack-reconciler]] — durable values (masterkey,
  admin-password) project from AWS SM via ExternalSecrets, operational
  PATs (iam-admin, login-client) re-mintable via Zitadel API by an
  in-cluster reconciler CronJob.

  Composition pieces:
  - ExternalSecret + PushSecret pairs for the two operational PATs
  - ExternalSecret for masterkey + admin-password
  - Reconciler CronJob + namespaced RBAC
  - Chart values disable FirstInstance PAT sidecars when reconciler is on
  - Zitadel init wired with Admin.ExistingDatabase pinned to the configured
    database so VerifyDatabase short-circuits (CNPG app user lacks CREATEDB)

* fix(state-init): pin reconciler image default to v0.0.1 (by @patrickleet)

  The hops-ops/authstack-reconciler repo uses vnext-tag for releases and
  doesn't publish a :latest tag. Pin to the first published version;
  bump in lockstep with new reconciler releases.

* fix(state-init): bump reconciler image default to v0.0.3 (multi-arch) (by @patrickleet)

* feat(authstack): add iamAdminMachineKey durable secret (by @patrickleet)

  The reconciler's primary credential is the iam-admin JWT machine key —
  not a PAT. The chart's setup-job's MachineKey sidecar writes the K8s
  Secret \`iam-admin\` on first install, but it's purely transient — lost
  on AuthStack delete, never recreated on subsequent installs (Zitadel
  detects existing instance data and skips FirstInstance).

  This adds the missing piece of the durability pattern from
  [[specs/authstack-reconciler]]:

    - XRD: new \`spec.externalSecrets.iamAdminMachineKey.secretPath\`.
    - State-init: surface as \`state.externalSecrets.iamAdminMachineKey\`
      with K8s Secret name fixed at \`iam-admin\` (matches chart).
    - 154-external-secret-iam-admin-key: project from AWS SM to K8s.
    - 162-push-secret-iam-admin-key: capture K8s to AWS SM on first
      install.
    - 200-helm-release-zitadel: set FirstInstance.Org.Machine.MachineKey
      (ExpirationDate + Type=1) so the chart actually GENERATES the
      machine key on first install. Previously we only set Pat.
    - 250-reconciler-cronjob: RBAC + env wire-up so the reconciler reads
      \`iam-admin\` as MACHINE_KEY_SECRET.

  Lifecycle (matches the PATs):
    First install   → chart writes K8s → PushSecret → AWS SM populated
    AuthStack delete → AWS SM keeps it
    Re-install      → ESO projects back → reconciler authenticates

* feat(authstack): embed PSQLCluster; drop reconciler (by @patrickleet)

  Replaces the prior reconciler + capture-restore design with an embedded
  PSQLCluster pattern. AuthStack composes a PSQLCluster XR (XR-composing-
  XR) with targetNamespace matching the install ns, so CNPG resources land
  where Zitadel pods env-var-mount the app Secret natively. Delete cascades
  atomically (DB + ns + Secrets); reapply runs FirstInstance from scratch
  against a fresh DB, so the reconciler's re-mint path is no longer needed.

  XRD changes:
  - Add spec.database.embedded mirroring PSQLCluster's surface (storage,
    postgresql, app, ha, monitoring, sslMode, cnpg passthrough). Defaults
    to a 2Gi single-node Postgres. Mutually exclusive with psqlClusterRef
    and external.
  - Remove spec.reconciler subschema.
  - Remove spec.externalSecrets.{iamAdminMachineKey,iamAdminPat,
    loginClientPat} subschemas. ExternalSecrets retained only for the
    durable inputs: masterkey + admin-password.

  Composition changes:
  - New 120-embedded-psql-cluster.yaml.gotmpl renders the composed
    PSQLCluster XR with name <authstack>-pg.
  - 100-namespace.yaml.gotmpl: restore full `*` ns ownership.
  - 200-helm-release-zitadel.yaml.gotmpl: unify DB wiring across embedded
    and psqlClusterRef modes; chart FirstInstance sidecars left enabled
    (they own the operational Secret lifecycle).
  - Delete reconciler CronJob + RBAC template (250-) and three
    iam-admin*/login-client ExternalSecret + matching PushSecret templates
    (152-, 153-, 154-, 160-, 161-, 162-).

  Tests rewritten: dropped reconciler-pattern tests, added
  embedded-composes-psql-cluster-xr test.

  Verified end-to-end on aws/hops/pat-local: cold start reaches Ready in
  ~90s; AuthStack delete + reapply cascades cleanly and re-bootstraps in
  ~90s.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>

* feat(authstack): collapse externalSecrets to a single secretPath (by @patrickleet)

  BREAKING CHANGE: Both durable values (masterkey + admin-password) now live as JSON
  properties under one AWS SM secret instead of two. The XRD's
  `externalSecrets.{masterkey,adminPassword}.secretPath` pair is
  replaced by a single `externalSecrets.secretPath`; both ExternalSecret
  renders reference that one path with different `property:` selectors:

    externalSecrets:
      enabled: true
      secretPath: <cluster>/zitadel       # AWS SM blob
                                           #   { "masterkey": "...",
                                           #     "admin-password": "..." }

  The collapse drops the redundant directory-name=property-name shape
  in the SOPS plaintext layout (`masterkey/masterkey`,
  `admin-password/password` → flat files under one dir). Operationally
  the two values are seeded together by `hops auth bootstrap` and rotate
  together, so grouping them as one secret is the natural fit.

  BREAKING: existing manifests using
  `externalSecrets.{masterkey,adminPassword}.secretPath` need to migrate
  to `externalSecrets.secretPath`. Only consumer in-tree (pat-local) is
  updated in the hops parent repo.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>

* fix(authstack): Usage forces Zitadel helm release to drain before PSQLCluster (by @patrickleet)

  The chart's helm uninstall pre-delete hooks (init/setup/cleanup jobs)
  need DB access. If Crossplane tears down the embedded PSQLCluster XR
  (and its composed CNPG Cluster + app Secret) in parallel with the Helm
  release, the chart's jobs hang in CreateContainerConfigError ("secret
  '<cluster>-pg-app' not found") and helm uninstall stalls indefinitely
  — the release ends up stuck in `pending-upgrade` and provider-helm
  can't make progress.

  Add a Usage:
    by:  Release/<authstack>-zitadel
    of:  PSQLCluster/<authstack>-pg

  so the embedded PSQLCluster is gated on the Helm release's deletion
  completing first. Mirrors the existing `delete-zitadel-before-namespace`
  Usage (both protect their `of:` from the Helm release).

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>

* fix(authstack): render login.gateway.httpRoute when spec.gateway.enabled (by @patrickleet)

  Zitadel v4 chart ships a separate Next.js login UI Deployment+Service
  serving /ui/v2/login. Composition previously only enabled
  gateway.httpRoute (main API service); /ui/v2/login fell through to the
  main service which returned gRPC code:5 NotFound.

  Mirror $gw.parentRef + $hostnames into login.gateway.httpRoute alongside
  the existing gateway.httpRoute/grpcRoute wiring. Chart-default paths
  (/ui/v2/login) handle the route to the login UI service.

  Verified live on pat-local: pat-local-zitadel-login HTTPRoute renders
  with hostname auth.ops.com.ai; curl /ui/v2/login → HTTP/2 200 with the
  login UI; full / → /ui/console/ flow returns 200.

* feat(authstack): publish iam-admin PAT to AWS SM via PushSecret (by @patrickleet)

  Replaces the in-composition Zitadel ProviderConfig + credentials Secret
  with an ESO PushSecret that publishes the chart-managed iam-admin PAT
  to AWS Secrets Manager. Downstream consumers (any cluster, any
  namespace, any GitOps repo) now author their own ExternalSecret +
  ProviderConfig referencing the AWS SM path — AuthStack no longer
  composes a PC.

  Why: in-composition PC creation hit three trade-offs stacked together —
  (1) provider-kubernetes SA RBAC has no permission on zitadel.m.crossplane.io
  PCs by default, (2) Crossplane v2's CustomToManagedResource conversion
  ignores `metadata.name` on directly-composed CRD resources and derives
  `<xr-name>-<composition-resource-name>`, breaking the user-tunable
  `spec.providerConfig.name`, (3) function-auto-ready can't synthesize a
  Ready condition on a PC CRD without an annotation hack. The
  publisher/consumer split sidesteps all three: AuthStack publishes once,
  consumers own their own PC lifecycle.

  XRD shape:
    - drop `spec.providerConfig.{enabled, scope}` (early-alpha field, no
      consumers in the wild yet)
    - add `spec.externalSecrets.pushCredentials.{enabled, path,
      accessTokenProperty}` — defaults to top-level
      `externalSecrets.enabled`; path defaults to
      `push/<clusterName>/zitadel-credentials`
    - reshape `status.providerConfig` to `{awsSecretsManagerPath,
      accessTokenProperty}` (consumer wiring contract)

  Composition:
    - new `300-credentials-pushsecret.yaml.gotmpl`: composes a
      `kubernetes.m.crossplane.io Object` wrapping an
      `external-secrets.io/v1alpha1 PushSecret` on the target cluster
    - 11 AWS SM tags on every pushed secret for `hops secrets list`
      routing and programmatic discovery:
        hops.ops.com.ai/managed       = true
        hops.ops.com.ai/secret        = true
        hops.ops.com.ai/managed-by    = pushsecret
        hops.ops.com.ai/cluster       = <clusterName>
        hops.ops.com.ai/namespace     = <xr-namespace>
        hops.ops.com.ai/kind          = AuthStack
        hops.ops.com.ai/name          = <xr-name>
        hops.ops.com.ai/apiVersion    = hops.ops.com.ai/v1alpha1
        hops.ops.com.ai/<kind.lower>  = <xr-name>  (K8s-selector parity)
        <operator-supplied spec.labels pass-through>
        managed-by                    = external-secrets  (ESO auto-add)

  Consumer reference: `examples/consumer-providerconfig.yaml` ships a
  copy-paste ExternalSecret + ProviderConfig with `target.template`
  trimming the trailing newline on the chart-managed PAT.

  Verified live on pat-local → AWS SM:
    push/pat-local/zitadel-credentials  exists with 11 tags
    AuthStack status surfaces the path + property
    `hops secrets list` renders a "Platform-pushed secrets" section with
      `Owner=AuthStack/pat-local`

  Pairs with the SecretStack IAM grant on `push/*`.

* fix: multi-API repo cleanup + fix CI (#6) (by @patrickleet)

  Three structural changes preparing auth-stack to host additional XRDs
  in the future, plus three fixes for pre-existing CI failures.

  Structural:
  - Makefile + CI workflows refactored to multi-API. Mirror psql-stack's
    api-dir macro and hops-ops/workflows-crossplane@v3.0.0 per-example
    api_path. render:all / validate:all derive the api dir from each
    example path; single-XRD targets still work for examples/authstacks/.
  - Drop apis/authstacks/configuration.yaml from git — already matched
    by .gitignore's apis/**/configuration.yaml; the tracked copy was a
    stale leftover from initial commit. Build regenerates it.
  - README rewrites the "Auth-group primitives" section to describe the
    intended scope (HumanUser, MachineUser, Grant, IDP planned;
    Organization + Project intentionally not wrapped — Tenant composes
    Zitadel MRs directly).

  Fixes (pre-existing on main, not regressions from this PR):
  - examples/authstacks/local-colima.yaml: spec.externalSecrets.masterkey
    was the old nested-per-property shape from before b61b74b
    ("collapse externalSecrets to a single secretPath"). Replaced with
    the current flat shape (single secretPath into an AWS SM JSON blob
    containing masterkey + admin-password).
  - tests/test-render/: was missing the `model` symlink to ../../.up/kcl/models
    per the test-model-symlinks convention. Without it, KCL ran into a
    goroutine-stack overflow on schema dep resolution. Adding the symlink
    fixes it (model symlink is gitignored per .gitignore's `.up/` rule;
    the symlink target itself is tracked).
  - tests/test-render/main.k: rewrote 13 typed-import xr literals to
    dict literals (matches observe-stack/crossplane-stack convention).
    Also added missing metadata.namespace = "zitadel" to
    psql-cluster-ref-pins-existing-database test — the test asserts the
    Postgres Host string uses zitadel ns, and psqlClusterRef.namespace
    defaults to metadata.namespace.

  Co-authored-by: Claude Opus 4.7 (1M context) <noreply@anthropic.com>


