---
name: engineer-spring-modulith-events
description: Design, implement, diagnose, and review Spring Modulith runtime interactions and event-delivery semantics, including ApplicationEventPublisher, @ApplicationModuleListener, publication registries, synchronous-versus-event consistency, consumer idempotency, duplicate and concurrent delivery, retries, restart recovery, poison work, and post-commit external side effects. Use when event timing, durability, recovery, replay, or provider outcomes are material. Use as a companion for public event contracts or event-driven state changes. Do not use for package boundaries, aggregate modeling, or test-only work alone.
---

# Engineer Spring Modulith Events

This skill defines a reusable method. Repository instructions remain authoritative for domain
invariants, sensitive payload rules, framework versions, publication mode, migrations, and
verification commands.

## Establish the consistency contract

Inspect the producer, every consumer, transaction annotations, database constraints, migrations,
event configuration, external adapters, and existing tests. Trace the complete path rather than
trusting an event-flow name or this skill's examples.

Record:

- state-owning producer and consumer modules;
- the business fact starting the interaction;
- state that must commit atomically;
- outcomes allowed to converge after the originating commit;
- a stable business idempotency key;
- retryable, terminal, conflicting, and outcome-unknown failures;
- recovery, retention, reconciliation, and observability requirements.

Stop when desired consistency, failure behavior, or idempotency cannot be stated.

## Choose the interaction deliberately

- Use a synchronous public port when the caller needs a result immediately or both decisions must
  commit or roll back together.
- Use an application event when the producer may commit before an independently owned follow-up.
- Use a durable workflow/process manager when several steps need explicit progress, compensation,
  timeout handling, or operator recovery.
- Put external calls behind outbound ports and model their retry and reconciliation semantics.

Do not introduce an event merely to hide a dependency or reuse code. Do not postpone an invariant
required for the current response to an asynchronous listener. Name events as past-tense business
facts, not commands.

## Identify the actual delivery mode

Distinguish these modes from configuration and dependencies:

1. Plain in-memory Spring event delivery.
2. Transaction-bound listener without a persistent publication registry.
3. Spring Modulith persistent publication and resubmission.
4. Explicit outbox, durable job, or workflow state owned by the application.

`ApplicationEventPublisher` alone does not prove post-crash delivery. When durable publication is
part of the contract, prove that producer state and the configured publication/job record enlist in
the same database transaction. Manage publication schemas through the repository's migration owner.

Confirm `@ApplicationModuleListener`, listener transactions, completion mode, serialization,
restart resubmission, cleanup, and retention against the exact Spring Modulith version in use. Do
not replace proven publication semantics with an ad-hoc executor or untracked `@Async` call.

## Make consumers safe for the promised delivery semantics

For durable or retryable delivery, assume duplicate, concurrent, delayed, and replayed messages.

- Prefer the source fact ID, `(aggregate ID, version)`, or external operation ID over a delivery
  attempt ID.
- Enforce create-once effects with a unique constraint and an atomic write supported by the
  production database; do not rely on lookup-then-insert.
- If a constraint failure aborts the current database transaction, do not catch it and continue as
  though publication completion can still commit. Use an atomic upsert or isolate expected conflict.
- Return success when the target state already matches. Treat the same key with incompatible input
  as an explicit conflict.
- For mutable state, choose locking and bounded retry only when reevaluating the business rule is
  safe after conflict.

If delivery is intentionally best effort, state the loss window explicitly rather than adding
idempotency machinery that implies durability.

## Keep event contracts durable and minimal

- Publish immutable values needed by consumers; exclude entities, lazy relations, repositories,
  transport objects, and external SDK types.
- Apply repository data-classification and privacy rules. Do not put sensitive data in an event
  merely because the current consumer needs it.
- Keep cross-module events in the provider's public package or an explicit events Named Interface;
  keep module-internal events internal.
- Treat the fully qualified event type and serialized fields as compatibility contracts whenever
  outstanding publications can survive deployment.

Before renaming, moving, removing, or changing a persisted event field, inspect outstanding work and
choose an explicit path: drain it, retain compatible deserialization/upcasting, or introduce a
versioned event with consumer-before-producer rollout.

## Design failure and recovery

- Let a failed listener transaction roll back and leave durable work incomplete.
- Never silently mark poison work complete or delete it to make a queue look healthy.
- Define repeated-failure thresholds, classification, quarantine/resubmission authority, and
  operator-visible context without logging sensitive payloads.
- Observe outstanding count, oldest age, processing delay, attempts/resubmissions, and repeated
  failures when the delivery contract is durable.
- Exclude outstanding work from retention cleanup and test actual restart/recovery when it changes.

For an external side effect:

1. Persist intent and processing state before the call when recovery requires it.
2. Send a stable provider idempotency key when supported.
3. Distinguish transient, permanent, conflicting, and outcome-unknown failures.
4. Treat timeout or disconnect as unknown, not confirmed failure.
5. Reconcile provider state before repeating an ambiguous operation.
6. Validate the provider response against server-owned state.
7. Persist the confirmed result before publishing the next fact.

Do not hold database locks across slow external I/O unless the repository has an explicit, tested
reason and bounded timeout.

## Define proof obligations

Prove only the guarantees claimed by the selected delivery mode:

- producer state and durable publication/job atomicity;
- exact event contract and observable consumer result;
- sequential and concurrent duplicate behavior;
- rollback, retry, repeated failure, and resubmission;
- restart recovery and persisted-event compatibility when those policies change;
- ambiguous external outcomes and reconciliation.

Use `$test-spring-modulith` for harness and execution selection. For a proposal, recommend proof
without running nonexistent tests. For implementation, report every command and unavailable gate.
Use `$coordinate-spring-modulith-change` once when ownership, boundaries, or domain state also
change and no coordinator is already active.

Reject a change that substitutes an event for required synchronous consistency, separates producer
state from promised durable publication, lacks the required idempotency guarantee, can strand
persisted events, treats configuration as recovery proof, or omits failure paths introduced by the
change.
