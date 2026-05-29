### What's changed in v1.5.0

* chore(deps): update unbounded-tech/workflow-vnext-tag action to v1.21.3 (#5) (by @renovate[bot])

  Co-authored-by: renovate[bot] <29139614+renovate[bot]@users.noreply.github.com>

* chore(deps): update unbounded-tech/workflow-simple-release action to v2.1.3 (#4) (by @renovate[bot])

  Co-authored-by: renovate[bot] <29139614+renovate[bot]@users.noreply.github.com>

* chore(deps): update unbounded-tech/workflows-crossplane action to v3 (#2) (by @renovate[bot])

  * chore(deps): update unbounded-tech/workflows-crossplane action to v3

  * chore: Change workflow publish action repository

  ---------

  Co-authored-by: renovate[bot] <29139614+renovate[bot]@users.noreply.github.com>
  Co-authored-by: Patrick Lee Scott <pat@patscott.io>

* feat: drive Zitadel SMTP from a platform SMTPSender (#12) (by @patrickleet)

  Add spec.smtp to AuthStack so the running Zitadel instance's SMTP provider
  is configured from a platform SMTPSender (SES + Cloudflare DKIM), entirely
  declaratively:

  - 040 observes the referenced SMTPSender for host/port/username + DKIM status
  - 160 pulls the bare SES password from AWS SM via ESO (whole-secret, no property)
  - 170/175 assemble a zitadel ProviderConfig from this stack's published
    iam-admin PAT (push auto-enabled by spec.smtp.enabled)
  - 180 drives Zitadel's SMTP via a smtp.zitadel Config MR

  Gating avoids destructive-omit: the durable Secrets + ProviderConfig gate on
  stable intent (smtp.enabled + smtpSenderRef.name); only the Config MR gates on
  observed existence ($smtp.render). No .ready/dkim gates (would delete the live
  SMTP config on a chart upgrade or status flip). fromAddress is validated
  against the SMTPSender's verified SES domain once observed.

  Verified end-to-end on pat-local: Zitadel SMTP config 375049110438290685
  created (Synced/Ready). 23/23 render tests pass.

  Implements [[tasks/authstack-smtp-sender]]

  Co-authored-by: Claude Opus 4.8 (1M context) <noreply@anthropic.com>


See full diff: [v1.4.1...v1.5.0](https://github.com/hops-ops/auth-stack/compare/v1.4.1...v1.5.0)
