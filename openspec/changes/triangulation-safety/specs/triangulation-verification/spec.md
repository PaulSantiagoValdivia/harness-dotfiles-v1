# Triangulation Verification

## ADDED Requirements

### Requirement: Complete role gates
Gates MUST match protocol commands; missing prerequisites MUST block execution.

| Role / directory | Required command |
| --- | --- |
| back / functions | `npm run typecheck && npm run format:check && npm run lint && npm run test:unit` |
| front / root | `npm run check:all` |
| app / root | `flutter analyze && flutter test` |

#### Scenario: Complete execution
- GIVEN available role prerequisites and a successful runner
- WHEN verifying roles
- THEN required commands execute in declared directories with recorded exits/results.

### Requirement: Executed-pass admission
Promotion MUST require current executed PASS for three roles before any push. SKIPPED, BLOCKED, FAIL, timeout, or unknown execution MUST NOT qualify, even with returncode zero. Fixtures MUST inject runners, not production bypasses.

#### Scenario: Skipped or unsuccessful check
- GIVEN any skipped, missing, failed, or timed-out role check
- WHEN promotion is requested
- THEN publication is blocked with explicit non-pass status.

#### Scenario: Revision race or partial promotion
- GIVEN checks pass before refs change or publication fails
- WHEN publication is attempted
- THEN stale verification cannot authorize changed content, and partial publication cannot close the group.

### Requirement: Live proof distinct from fixtures
Coordination PASS MUST require an authorized isolated smoke with both workers' nonce/contract-revision ACKs, safe read/test reassignment, and three current role receipts. Record monotonic timings, explicit timeout/retry bounds, and failures; stale receipts MUST be rejected. Mock topology tests MUST NOT certify live messaging.

#### Scenario: Authorized smoke
- GIVEN isolated authorized sessions and temporary repositories
- WHEN executing the smoke
- THEN all messages receive ACKs, receipts match the latest contract, and measured outcomes identify sessions.

#### Scenario: Missing live prerequisites
- GIVEN denied transport, missing ownership evidence, or an unexecuted smoke
- WHEN reporting verification
- THEN report BLOCKED/UNTESTED separately from fixtures, without fabricated ACKs/latencies.
