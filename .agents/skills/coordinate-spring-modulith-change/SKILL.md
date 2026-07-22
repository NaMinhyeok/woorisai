---
name: coordinate-spring-modulith-change
description: Coordinate repository-aware Spring Modulith planning, review, diagnosis, and implementation across module ownership, contracts, domain invariants, runtime consistency, migrations, failure handling, and verification. Use as the primary entry point for a new module, a multi-module feature, or any change where two or more of boundary, domain, event, persistence, and testing concerns materially interact or ownership is unresolved. Do not use for a localized change with one clear owner and unchanged module interactions.
---

# Coordinate a Spring Modulith Change

Create one decision ledger, choose one lead concern, and load only the focused companion skills
needed by the change. Keep repository facts separate from reusable guidance.

## Establish the operating mode

- **Plan or review:** Remain read-only. Recommend gates; do not claim unimplemented code passed.
- **Implement:** Resolve required design gates before editing, then implement and verify.
- **Diagnose:** Trace the failure to its owning concern. Do not fix unless the request includes it.

## Build a repository profile

1. Read the applicable repository instructions and inspect the worktree.
2. Discover architecture decisions, module declarations, dependencies, public APIs, persistence
   technology, migrations, events, configuration, tests, and executable build tasks with `rg` and
   the repository's own tooling.
3. Trace compile-time dependencies and the runtime path from entry point to observable outcome.
4. Classify each statement as current fact, approved decision, proposal, or assumption.
5. Never import module names, application classes, test profiles, Gradle tasks, or framework
   conventions from this skill when the repository does not establish them.

If implementation source does not exist yet, use approved documents as planning evidence and mark
all package names, annotations, and commands as provisional.

Record one ledger:

```text
Repository facts and evidence:
Requested observable outcome:
Proposed decisions:
Assumptions:
Unresolved gates:
Writable scope and protected files:
```

## Route material concerns

| Concern | Focused skill |
| --- | --- |
| Ownership, dependency direction, public contracts, Named Interfaces, workflow placement | [`$design-spring-modulith-boundaries`](../design-spring-modulith-boundaries/SKILL.md) |
| Aggregate state, invariants, entity/value semantics, repository authority | [`$model-spring-domain`](../model-spring-domain/SKILL.md) |
| Event timing, delivery, publication, retries, idempotency, external side effects | [`$engineer-spring-modulith-events`](../engineer-spring-modulith-events/SKILL.md) |
| Test layers, module verification, production-database and concurrency proof | [`$test-spring-modulith`](../test-spring-modulith/SKILL.md) |

Use intentional combinations:

- Public event contract: boundary + event + test.
- Aggregate invariant: domain + test; add boundary only if the public contract changes.
- Listener race or replay defect: event + test unless ownership also changes.
- New module: boundary plus every domain, event, persistence, or verification concern introduced.

Do not re-enter this coordinator from a focused skill during the same decision pass. Leave ordinary
adapter mechanics to the general repository workflow unless they encode a module contract,
invariant, consistency guarantee, or verification risk.

## Resolve decisions in order

1. **Ownership:** Name the use-case coordinator and the module owning each state and rule.
2. **Contract:** Define the smallest provider-owned command, result, event, query, or failure needed
   by each consumer.
3. **Consistency:** Decide what must commit atomically and what may converge after commit.
4. **Invariant:** Assign each rule to transport validation, command/value construction,
   aggregate/policy behavior, or a database constraint.
5. **Persistence:** Confirm schema ownership, identifier and mapping compatibility, locking,
   migration order, and mixed-version behavior.
6. **Failure:** Define rollback, duplicate, concurrency, retry, restart, poison-work,
   external-timeout, and reconciliation behavior where applicable.
7. **Verification:** Map every material risk to the smallest proof and use the production database
   for database-specific semantics.

Continue planning to a safe seam when a gate is unresolved, but block implementation that depends
on the missing decision.

## Sweep applicable compatibility risks

- HTTP/API compatibility and deployed-client behavior.
- Additive migration, backfill, constraint tightening, rollback, and schema-owner handoff.
- Historical state that a new consumer will not receive automatically.
- Persisted event compatibility and producer/consumer rollout order.
- Personal or sensitive data in APIs, events, logs, archives, and retention jobs.
- Provider idempotency, authentication, rate limits, timeout ambiguity, and reconciliation.
- Outstanding work age, retries, repeated failures, and operator recovery.

## Produce or execute the change brief

```text
Use case and user-visible outcome:
Coordinator and state-owning modules:
Dependencies and public contracts:
Business invariants and transitions:
Atomic transaction boundaries:
Events and caller-visible consistency:
Idempotency and concurrency controls:
Failure, restart, reconciliation, and observability:
API, migration, replay, privacy, and rollout constraints:
Required tests and discovered commands:
Unresolved gates and safe implementation boundary:
```

For implementation, work boundary-first: structural contract, behavioral proof, domain/application
behavior, persistence and event adapters, failure coverage, then full module and production-database
verification. Follow repository ordering when it establishes a stricter sequence.

## Coordinate parallel work safely

- Parallelize read-only analysis by focused concern.
- Parallelize edits only across independent write sets.
- Serialize public contracts, module declarations, event records, migrations, shared build files,
  and edits to the same aggregate.
- Give validation agents raw artifacts and realistic tasks without the expected diagnosis.
- Re-read the integrated result and report every unexecuted gate.

Escalate before crossing a safe seam that requires a new workflow owner, breaking contract,
changed caller-visible consistency, destructive migration, coordinated external rollout, or
provider behavior not established by evidence.
