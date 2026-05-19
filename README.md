# auth-stack

Installs Zitadel into a Kubernetes cluster as the platform identity provider, and hosts a focused set of `auth.hops.ops.com.ai` primitive XRDs (`HumanUser`, `MachineUser`, `Grant`, `IDP`) that compose against the installed Zitadel.

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

Per [[specs/identity-architecture]], the auth-group primitive XRDs that have substantive composition value-add — `HumanUser`, `MachineUser`, `Grant`, `IDP` — live in this repo alongside `AuthStack` under the `auth.hops.ops.com.ai` group.

Status:

| Kind | Plural | Composes | Status |
|---|---|---|---|
| `HumanUser` | `humanusers` | `HumanUser` + optional `UserIDPLink` MRs | TO WRITE |
| `MachineUser` | `machineusers` | `MachineUser` + `PAT` + AWS SM push pipeline | TO WRITE |
| `Grant` | `grants` | `ProjectMember` (same-Org) or `ProjectGrant + GrantMember` (cross-Org) | TO WRITE |
| `IDP` | `idps` | polymorphic over `GoogleIDP` / `GitHubIDP` / `OIDCIDP` / `SAMLIDP` | TO WRITE |

Operators apply raw Zitadel `Org` / `Project` / `Role` MRs (`org.zitadel.m.crossplane.io`, `project.zitadel.m.crossplane.io`) directly when they need them — the `Tenant` business kind in [[tenant-stack]] composes the initial set during Tenant scaffolding.

## Cross-Stack Integration

The intent is for consumer stacks (gitops/ArgoCD, observe/Grafana, the-website) to wire to AuthStack's status surface rather than configuring OIDC manually. Today, those consumers still need a Zitadel OIDC application created out-of-band (via the Zitadel UI/API) and a client ID/secret provided to them. Once the Zitadel Crossplane provider lands, consumer stacks can declaratively create OIDC applications by referencing `status.bootstrap.iamAdminPatSecretRef`.

See [[specs/auth-stack-zitadel]] for the design and open questions.

## Out of Scope

- Per-app OIDC client creation (lives with the Zitadel API or the future Zitadel Crossplane provider).
- Istio `RequestAuthentication` / `AuthorizationPolicy` (per-app concern, may land later).
- Authentik decommission (per-consumer migration tracked separately).

## References

- Spec: `[[specs/auth-stack-zitadel]]`
- Task: `[[tasks/auth-stack]]`
- Upstream chart: `zitadel/zitadel` 9.34.1 (ships Zitadel v4)
