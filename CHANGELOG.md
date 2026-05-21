### What's changed in v1.2.0

* feat: add MachineUser primitive XRD with opt-in PAT + AWS SM push pipeline (#7) (by @patrickleet)

  The first auth-group primitive that survives the "is it just a single-MR
  wrapper?" test. Composes 1-4 underlying resources depending on opt-ins:

  1. Always: Zitadel MachineUser MR (machineusers.user.zitadel.m.crossplane.io)
  2. When spec.pat.enabled (default false): + Zitadel AccessToken MR (the PAT;
     connection secret on control-plane K8s under key access_token)
  3. When spec.pat.pushToAwsSm (default false; requires pat.enabled): + AWS
     Secrets Manager Secret MR + ESO PushSecret (via provider-kubernetes
     Object) that pushes the control-plane K8s Secret's access_token into
     AWS SM at the canonical path push/<cluster>/<tenant>/<name> per
     reference_aws_sm_push_tag_convention. Consumer clusters pull via ESO
     ExternalSecret.

  Composition gating per feedback_crossplane_composition_gates: AccessToken
  emits once MachineUser.atProvider.id observed; AWS SM Secret + PushSecret
  emit once AccessToken.atProvider.id observed. Standard multi-iteration
  Crossplane convergence.

  PAT generation is opt-in by default — operators explicitly acknowledge
  minting a long-lived bearer token. Adoption via spec.machineUserId
  propagates as crossplane.io/external-name on the underlying MR.

  upbound.yaml gains provider-upjet-zitadel >=v0.1.1 and
  provider-aws-secretsmanager >=v2.5.0 deps (both required by the
  composition; aws-secretsmanager only matters when pushToAwsSm is on).

  3 examples (minimal, with-pat, with-pat-push) — all render via
  up composition render. Multi-iter convergence verified via
  --observed-resources fixtures.

  4 KCL CompositionTests covering: minimal-machineuser-only, pat-enabled-
  iter1-still-only-machineuser (gating verification), adopt-existing-
  machineuser-via-id, field-overrides. All 17 tests (13 AuthStack + 4
  MachineUser) pass under `up test run`.

  Makefile EXAMPLES + CI workflows updated for the new examples.
  README "Auth-group primitives" table updated: MachineUser ✓, Grant
  TO WRITE (next); HumanUser / IDP / OrganizationSsoConfig dropped as
  thin wrappers — operators apply raw provider MRs.

  Co-authored-by: Claude Opus 4.7 (1M context) <noreply@anthropic.com>


See full diff: [v1.1.0...v1.2.0](https://github.com/hops-ops/auth-stack/compare/v1.1.0...v1.2.0)
