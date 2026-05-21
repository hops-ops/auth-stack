### What's changed in v1.3.0

* feat: add Grant primitive XRD with polymorphic same-Org / cross-Org dispatch (#9) (by @patrickleet)

  Second auth-group primitive that survives the "is it just a single-MR
  wrapper?" test. Composes 1 or 2 underlying Zitadel MRs depending on
  whether the user's home Org matches the project's enclosing Org.

  Same-Org (spec.userOrgId == spec.projectOrgId): one MR
    - user.zitadel.m.crossplane.io/Grant — the user's role assignment
      within the project (no projectGrantId)

  Cross-Org (spec.userOrgId != spec.projectOrgId): two MRs
    - project.zitadel.m.crossplane.io/Grant — the cross-Org Project
      Grant authorizing the role set for the user's home Org
    - user.zitadel.m.crossplane.io/Grant — the user's role assignment
      with projectGrantId pointing at the Project Grant, pulling roles
      from the granted set

  Multi-iter convergence: in cross-Org mode the user/Grant emits only
  once the project/Grant's atProvider.id is observed (standard composition
  gating per feedback_crossplane_composition_gates).

  Schema takes flat IDs (userId + userOrgId + projectId + projectOrgId +
  roles[]), matching the established convention from Tenant + MachineUser
  — operator copies UUIDs from the relevant XR statuses or Zitadel UI.

  Two examples (same-org + cross-org); 4 KCL CompositionTests covering
  same-org, cross-org iter 1, multi-role, managementPolicies propagation.
  Multi-iter convergence verified via observed-resources fixture.

  21/21 KCL tests pass (13 AuthStack + 4 MachineUser + 4 Grant); all 8
  examples render via make render:all.

  Co-authored-by: Claude Opus 4.7 (1M context) <noreply@anthropic.com>


See full diff: [v1.2.0...v1.3.0](https://github.com/hops-ops/auth-stack/compare/v1.2.0...v1.3.0)
