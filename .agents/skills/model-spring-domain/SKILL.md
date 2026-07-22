---
name: model-spring-domain
description: Design, implement, and review domain models used inside a Spring Modulith application, including aggregate ownership, invariants, entities, value objects, policies, lifecycle transitions, internal repository authority, persistence reconstruction, failures, auditing, and database-backed constraints. Use when changing business state, aggregate roots, entity/value semantics, derived values, cardinality, locking assumptions, deletion policy, or domain failures. Use as a companion when boundary or event work changes owned state. Do not use for cross-module public API design, event delivery mechanics, or test-layer selection alone.
---

# Model a Spring Domain

Build the domain decision from repository evidence before editing implementation details.

## Define the model decision

1. Inspect the affected use case, entities or records, creator/application service, repositories,
   mappings, migrations, and focused tests.
2. Name the owning module, aggregate root or transaction script, atomic state, lifecycle
   transitions, invariants, and concurrency assumptions.
3. Identify one source of truth for every derived value and state.
4. Record current persistence technology and legacy-schema constraints instead of assuming JPA,
   JDBC, generated schema, identifier types, or deletion policy.

Assign each rule to a primary enforcement layer:

- Transport shape and serialization: web/message adapter.
- Primitive and command meaning: command or value construction.
- Lifecycle and cross-field invariant: aggregate or domain policy.
- Uniqueness, range, cardinality, referential integrity, and concurrency backstop: database.

Use independent validation at multiple layers only when each layer protects a distinct boundary;
do not scatter the same rule through controllers, services, and entities by accident.

## Protect consistency and authority

- Let the aggregate root perform legal transitions; do not bypass it with repository field updates.
- Keep state that must commit atomically inside one transaction and persistence boundary.
- Call multi-repository orchestration a transaction script when it is not one aggregate.
- Let one module own each table and mutation path even when foreign keys cross modules.
- Add database constraints when concurrent transactions could both pass an application pre-check.
- Choose pessimistic locking, optimistic locking, an atomic statement, or serialization from the
  actual contention and caller-visible contract; do not add a version field by reflex.
- Re-evaluate authorization and invariants after acquiring the lock protecting mutable state.

## Make invalid states difficult to represent

- Reject invalid identifiers, ranges, required text, and mutually exclusive inputs at construction
  or command creation.
- Model mutually exclusive lifecycle variants explicitly when nullable fields allow impossible
  combinations.
- Derive totals, counters, result values, and status from owned state where practical.
- If a derived value is persisted for performance or history, update it atomically and reinforce
  legal combinations with constraints or consistency checks.
- Introduce typed identifiers or value objects only when they centralize repeated rules, units, or
  realistic argument-order mistakes.

## Model entity and value semantics deliberately

- Use structural equality for immutable values and records.
- Do not generate entity equality over mutable fields, versions, audit timestamps, collections, or
  lazy relationships.
- Omit entity equality or implement a stable identity policy compatible with persistence proxies
  and pre-persist entities.
- Ensure every transition preserves identifiers, optimistic versions, creation metadata, and
  required legacy columns.
- Treat hard delete, soft delete, tombstone, and immutable history as complete policies. Define
  write authority, query visibility, retention, and cascade behavior consistently.
- Keep cross-module JPA associations from turning internal entities into a public object graph;
  prefer owned IDs or narrow snapshots at module contracts.

## Keep services and abstractions pragmatic

- Keep application services focused on authorization, transaction orchestration, locking, and
  calls to domain behavior.
- Split a policy or strategy only when variants change independently or contain substantial rules.
- Add interfaces at real module boundaries or provider variation points, not around every class.
- Keep HTTP, logging, messaging, persistence-provider, and external-SDK details behind adapters.
- Require production implementations and test fakes to honor the same success, failure,
  idempotency, and ordering contract.

## Keep failures domain-oriented

- Express expected business failures with stable reasons, codes, or explicit result variants.
- Map them to transport status and log severity at the adapter boundary.
- Do not convert unexpected programming defects into declared client failures.
- Keep Spring HTTP, logging, persistence exceptions, and external SDK types out of the domain model.
- Make public module APIs consistent about exception, result, or outcome semantics.

## Preserve existing data deliberately

- For legacy schemas, verify explicit table/column names, identifier widths, null/default behavior,
  enum encoding, foreign keys, indexes, sequences, timestamps, and delete semantics.
- Use schema validation rather than automatic mutation when repository policy requires it.
- Keep applied migrations immutable and coordinate additive/backfill/constraint phases with the
  repository's schema owner.
- Verify persistence reconstruction does not create an invalid aggregate or fire a business
  transition unintentionally.

## Define proof obligations

Cover construction, legal and illegal transitions, derived values, persistence reconstruction,
database constraints, authorization-after-lock, uniqueness, duplicate commands, and lost-update
risk introduced by the change. Use `$test-spring-modulith` to choose test layers and the production
database harness.

Confirm that application services do not duplicate rules and repositories cannot bypass required
transitions. Report every invariant left to convention and why it cannot yet be enforced.

For a proposal, recommend proof without running nonexistent tests. Use
`$coordinate-spring-modulith-change` once when ownership, boundaries, or runtime consistency also
change and no coordinator is already active.

Stop and redesign when ownership is ambiguous, two stored values can contradict each other, a
transition loses persistence metadata, or correctness depends only on a concurrent pre-check.
