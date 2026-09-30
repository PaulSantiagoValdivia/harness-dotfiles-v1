<!-- gentle-ai:integration-autonomy -->
## Approved-scope integration autonomy

- User approval of a canonical SDD/OpenSpec scope authorizes implementation,
  tests, the selected review lane, PR creation and integration without another
  routine "may I merge?" question. Record the approval reference and resolved
  integration target in canonical state; never infer approval from generated specs.
- Honor explicit holds, draft-only requests and persisted interactive boundaries.
  This standing authorization does not remove any existing safety or delivery gate.
- Integrate to `dev` when `origin/dev` exists, otherwise the verified default branch;
  preserve approved stacked targets. If merging that branch deploys production,
  production authorization is still required. Do not promote to test/prod implicitly.
- Before each merge, verify current head/base, required CI on the current candidate,
  selected review findings resolved, repository/native policy and write ownership.
  Rerun affected checks after base/head changes. Unknown or failed gates block merge;
  an unmanaged review result is not approval. Never bypass protection or forge receipts.
- For same-file overlap, the coordinator and owners agree landing order and explicit
  handoff over the available live channel, then reconcile and retest. This replaces
  routine user arbitration of who lands first, NOT ownership protections. Without a
  peer channel/acknowledgment, preserve both writers, report the exact dependency and
  continue independent work; never impersonate a peer or transfer ownership silently.
- Diagnose and fix in-scope technical failures before escalating. Ask the user only
  for changed business scope, conflicting user requirements, destructive operations,
  spending, production authorization or a necessary external account/capability action.
  Do not disguise a technical blocker as a request for generic permission.
- Report meaningful progress and verified delivery, not permission prompts. Persist
  each genuine escalation with reason and approval reference; on resume reuse it.
  Measure routine merge prompts, real escalations and blocked duration separately;
  target zero redundant merge prompts, never zero legitimate safety escalations.
<!-- /gentle-ai:integration-autonomy -->
