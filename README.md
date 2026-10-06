# auth-stack

Installs Zitadel into a Kubernetes cluster as the platform identity provider, and hosts a focused set of `auth.hops.ops.com.ai` primitive XRDs (`HumanUser`, `MachineUser`, `Grant`, `OIDCClient`) that compose against the installed Zitadel.

The stack XRD (`AuthStack`) wraps the upstream `zitadel/zitadel` Helm chart — handling the namespace, database wiring, Gateway API routing, and re-projecting chart-managed bootstrap secrets (admin PAT + login-client PAT) into XR status for downstream consumers.

The primitive XRDs let operators declaratively manage the identity model inside a running Zitadel — see [Auth-group primitives](#auth-group-primitives) below.

## Quick Start

Local-dev (colima cluster, bundled Postgres, no TLS):

```yaml
apiVersion: hops.ops.com.ai/v1alpha1
kind: AuthStack
metadata:
  name: auth
  namespace: default
spec:
  clusterName: colima
  domain: auth.localtest.me
  externalSecure: false
  database:
    bundled: true
```

Production (managed Postgres + Gateway API):

```yaml
apiVersion: hops.ops.com.ai/v1alpha1
kind: AuthStack
metadata:
  name: auth
  namespace: platform
spec:
  clusterName: prod
  domain: auth.example.com
  firstInstance:
    org: hops-ops
  database:
    external:
      dsnSecretRef:
        name: zitadel-db
        key: dsn
  gateway:
    enabled: true
    parentRef:
      name: platform-gateway
      namespace: istio-system
```

## Database Modes

Exactly one of:

| Mode | When | Notes |
|---|---|---|
| `external` | Production with managed Postgres (RDS, CNPG cluster, etc.) | Provide a Secret containing the DSN; chart reads `ZITADEL_DATABASE_POSTGRES_DSN`. |
| `bundled` | Local dev only | Sets `postgresql.enabled=true` so the chart uses its bundled Bitnami subchart. Not for production. |
| `psqlStack` | Future | Reserved for the platform PSQLStack integration; pending the `PSQLDatabase` XRD. The composition currently rejects this mode. |

## Bootstrap & Status Contract

The `zitadel/zitadel` chart's setup hook creates two machine users on first install:

- `<iamAdmin.username>` — JWT machine key in a chart-managed Secret named after the username
- `<iamAdmin.username>-pat` — admin PAT
- `<loginClient.username>` — login-client PAT

This stack does not author its own init Job. It re-projects those Secret references into XR status so downstream consumers (the future Zitadel Crossplane provider, ad-hoc admin tooling) have a stable place to read the credentials:

```yaml
status:
  oidc:
    issuerURL: https://auth.example.com
    discoveryURL: https://auth.example.com/.well-known/openid-configuration
  bootstrap:
    iamAdminPatSecretRef:    { name: iam-admin-pat,  namespace: zitadel, key: pat }
    iamAdminKeySecretRef:    { name: iam-admin,      namespace: zitadel, key: key }
    loginClientPatSecretRef: { name: login-client,   namespace: zitadel, key: pat }
```

## Auth-group primitives

Per [[specs/identity-architecture]], the auth-group primitive XRDs that have substantive composition value-add — `HumanUser`, `MachineUser`, `Grant`, `OIDCClient` — live in this repo alongside `AuthStack` under the `auth.hops.ops.com.ai` group.

Status:

| Kind | Plural | Composes | Status |
|---|---|---|---|
| `HumanUser` | `humanusers` | One provider `HumanUser` with organization-ID reference resolution | ✓ |
| `MachineUser` | `machineusers` | `MachineUser` + opt-in `AccessToken` + opt-in AWS SM `Secret` + ESO `PushSecret` (provider-kubernetes Object) | ✓ |
| `Grant` | `grants` | `user.zitadel.../Grant` (same-Org) or `project.zitadel.../Grant + user.zitadel.../Grant` with `projectGrantId` (cross-Org) | ✓ |
| `OIDCClient` | `oidcclients` | provider-kubernetes ESO bridge + namespaced Zitadel ProviderConfig + OIDC application + connection Secret | ✓ |

Single-resource wrappers we deliberately didn't make: `IDP`, `OrganizationSsoConfig` (and the previously-attempted `Organization`, `Project`). Operators apply raw Zitadel / OpenPanel MRs directly for those.

### `HumanUser`

Declarative Zitadel human identity with organization-reference resolution. The
upstream provider documents `orgId` as optional, but its HumanUser v2 create path
sends an invalid empty organization when it is omitted. `HumanUser` resolves a
concrete organization UUID from a stable local resource such as a Zitadel
Project's `status.atProvider.orgId`, then renders the raw provider HumanUser.

Use `spec.orgIdRef` for GitOps so generated UUIDs do not enter the repository, or
use explicit `spec.orgId` for adoption and external integrations. Initial
passwords are accepted only by namespaced Secret reference. Typed status exposes
`userId`, `orgId`, and `loginName` for `Grant` and other consumers. The composed
resource remains rendered from its own observed `orgId` if the reference lookup
temporarily disappears.

See `examples/humanusers/{with-org-ref,explicit-org}.yaml`.

### `MachineUser`

Declarative Zitadel machine identity for CI runners, Crossplane providers, cross-cluster syncs — anything that needs a long-lived credential to call a SaaS API.

The XRD's value-add is bundling. The `MachineUser` MR alone is one Zitadel resource. With `spec.pat.enabled: true` it adds an `AccessToken` MR (the PAT). With `spec.pat.pushToAwsSm: true` it adds an AWS Secrets Manager `Secret` MR + an ESO `PushSecret` Kubernetes Object — pushing the control-plane connection secret's `access_token` into AWS SM at the canonical path `push/<cluster>/<tenant>/<name>` per [[reference_aws_sm_push_tag_convention]]. Four resources, one declarative flag.

PAT generation is **opt-in by default** — `pat.enabled: false` means no long-lived token is minted. Adoption of an existing Zitadel machine user uses `spec.machineUserId` (propagates as `crossplane.io/external-name` on the underlying MR).

See `examples/machineusers/{minimal,with-pat,with-pat-push}.yaml`.

### `Grant`

First-class membership relationship that ties a Zitadel User to a Project + Roles. For GitOps, prefer local references: `userIdRef` points to a raw HumanUser/MachineUser MR or the Hops `HumanUser` XR, and `projectIdRef` points to a Project MR in the Grant namespace. The composition resolves the Hops XR's typed status or raw resources' `status.atProvider`, so no live Zitadel UUIDs need to be committed. Explicit `userId + userOrgId + projectId + projectOrgId` inputs remain available for adoption and cross-stack cases.

Polymorphic dispatch then picks the right Zitadel mechanism:

- **Same-Org** (`userOrgId == projectOrgId`): composes one `user.zitadel.m.crossplane.io/Grant` MR (the user's role assignment within the project).
- **Cross-Org** (`userOrgId != projectOrgId`): composes a `project.zitadel.m.crossplane.io/Grant` (cross-Org Project Grant authorizing the role set for the user's home Org) plus a `user.zitadel.m.crossplane.io/Grant` with `projectGrantId` set (the user's role assignment, pulling roles from the granted set). Multi-iter: user/Grant emits once project/Grant is observed.

See `examples/grants/{referenced-same-org,same-org,cross-org}.yaml`.

### `OIDCClient`

Declarative Zitadel web client for a namespaced consumer. `OIDCClient` reads an
existing provider bootstrap token through an ExternalSecret applied by
provider-kubernetes, creates a same-namespace Zitadel ProviderConfig and OIDC
application, and writes the generated client ID and secret to the
consumer-selected Secret name. Exact redirect URIs are required because Zitadel
does not support wildcard callback URIs.

The XR assumes External Secrets, provider-kubernetes,
provider-upjet-zitadel, and its referenced SecretStore are already installed.
Missing dependencies leave the XR unready; they never produce an
unauthenticated fallback. See
`examples/oidcclients/storybook-preview.yaml`.

## Cross-Stack Integration

Consumer stacks (gitops/ArgoCD, observe/Grafana, the-website) should wire to
AuthStack's status surface rather than configuring OIDC manually. Namespaced
workloads can use `OIDCClient` when they need an independently owned web client
and connection Secret. Larger stacks can continue composing Zitadel managed
resources directly when they already own the provider lifecycle.

See [[specs/auth-stack-zitadel]] for the design and open questions.

## Out of Scope

- Istio `RequestAuthentication` / `AuthorizationPolicy` (per-app concern, may land later).
- Consumer migration and decommission work is tracked separately.

## References

- Spec: `[[specs/auth-stack-zitadel]]`
- Task: `[[tasks/auth-stack]]`
- Upstream chart: `zitadel/zitadel` 9.34.1 (ships Zitadel v4)

## System API and instance metadata

AuthStack accepts optional `systemAPIUsers`: each entry has `id`,
`publicKeySecretRef: {name, key}`, and optional `memberships` entries
(`memberType`, `roles`, optional `aggregateId`). Keys must exist in the target
install namespace. Only public key files are mounted; generate and persist
private keys outside AuthStack and deliver them to provider consumers via ESO.
No user or hostname is enabled by default. Omitting memberships grants Zitadel's
SYSTEM_OWNER default; specify memberships explicitly when narrower access fits.

Set `instanceDiscovery.enabled: true` and select an existing Zitadel
ProviderConfig. AuthStack composes a namespaced, read-only `Instance` using
provider-upjet-zitadel **v0.3.0 or newer**:

```yaml
spec:
  instanceDiscovery:
    enabled: true
    providerConfigRef:
      name: zitadel-admin
      kind: ClusterProviderConfig
```

The ProviderConfig owns authentication, endpoint, TLS and instance headers. It
must target the instance installed by this AuthStack; AuthStack cannot verify
that an arbitrary consumer-owned endpoint belongs to its Helm release. Provision
credentials with ESO, and publish chart-generated PATs through PushSecret before
waiting for native observation. For first install, wait for the composed Helm
Release, establish the ProviderConfig, then wait for AuthStack readiness. Do not
wait for AuthStack readiness before creating its observer's credentials.

Successful, current-generation observation publishes `status.instanceId` and
`status.instanceRef: {name, namespace}`. Domain resources can use the named
observer directly, without copying the ID or importing an external name:

```yaml
apiVersion: instance.zitadel.m.crossplane.io/v1alpha1
kind: TrustedDomain
metadata:
  name: browser
  namespace: preview
spec:
  forProvider:
    instanceIdRef:
      name: identity-instance  # AuthStack metadata.name + "-instance"
      namespace: platform     # AuthStack namespace
      policy: {resolve: Always}
    domain: preview.example.com
  providerConfigRef:
    name: zitadel-admin
    kind: ClusterProviderConfig
```

`instanceIdSelector` is also supported by the provider; use a unique label match
when consumers should discover the observer rather than name it explicitly.
The observer retries API failures and reads rotated credentials on reconciliation.
It binds the first observed ID and refuses a different ID until deliberately
recreated. Deleting it does not delete Zitadel; Helm still owns that lifecycle.
A Usage keeps the Helm release available until the observer has been deleted.

### Migrating existing instance discovery

This changes only the **opt-in discovery API** introduced previously. Replace
`internalURL`, `allowInsecureHTTP`, `caCertSecretRef` and `image` with
`providerConfigRef`. Configure transport in that ProviderConfig instead; an
old discovery configuration without the new reference is rejected. The Job,
ConfigMap, ServiceAccount and RBAC are removed by composition reconciliation.
`enabled` and `status.instanceId` remain; `status.instanceRef` is additive.
AuthStack consumers with discovery disabled retain their installation behavior.
No localhost, plaintext transport or secret backend is defaulted by this API.
The package dependency now requires provider v0.3.0+, so upgrade that provider
before applying this configuration. Recreate only the observer when intentionally
replacing an installed instance; preserve Helm/database resources otherwise.
