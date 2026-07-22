---
name: test-spring-modulith
description: Select, implement, review, diagnose, and execute risk-based tests for Spring Modulith applications across unit, web, persistence, module, event, workflow, migration, production-database, and concurrency layers. Use when adding or fixing tests, investigating a test failure, defining CI gates, or proving a change to module contracts, event delivery, transaction rollback, schema migration, locking, or idempotency. Use as a companion to production work that introduces material verification risk. Do not own unresolved production architecture decisions or trigger merely because a routine file changed.
---

# Test Spring Modulith Changes

This skill defines test selection and proof methods. Repository instructions and build files remain
authoritative for persistence technology, database engine, profiles, tags, task names, application
class, fixtures, and release gates.

## Start from failure risk

1. Inspect changed behavior, production code, public contracts, migrations, existing tests, and
   build configuration.
2. State the observable risk: invariant, transport contract, persistence mapping, module
   collaboration, event delivery, rollback, database semantics, concurrency, or workflow outcome.
3. Select the smallest context capable of reproducing that risk. Add broader coverage only when a
   real boundary remains unproved.
4. Assert public behavior and persisted outcomes, not private methods or incidental wiring.
5. Cover important rejection, duplicate, partial-failure, timeout, retry, and recovery paths.

For a proposal, recommend gates without running tests for code that does not exist. For a test-only
task, diagnose the current contract without redesigning production unless the failure proves it is
inconsistent. Route unresolved multi-concern decisions once through
`$coordinate-spring-modulith-change`.

## Select the smallest sufficient layer

| Risk | Starting point |
| --- | --- |
| Value, calculation, policy, aggregate transition | Plain JUnit without Spring |
| URL, JSON, validation, security, error mapping | Focused MVC/web slice supported by the repository |
| JPA mapping or repository query | `@DataJpaTest` or repository-established JPA slice |
| Spring Data JDBC mapping or query | `@DataJdbcTest` when JDBC is actually used |
| Module public use case and internal persistence | `@ApplicationModuleTest` |
| Event production contract | Module test with the version-supported published-events assertion API |
| Listener observable result | `@ApplicationModuleTest` with `Scenario` or the established equivalent |
| HTTP flow across multiple modules | Focused `@SpringBootTest` workflow test |
| Migration, dialect, unique/check/FK constraint | Production-database Testcontainers test |
| Locking, upsert, isolation, concurrent update | Deterministic concurrency test with independent transactions |
| Producer state and durable publication atomicity | Full transaction plus publication/job-store integration test |

Discover the actual stack before choosing annotations. Do not use a JDBC slice in a JPA repository
or an in-memory database to prove production-database behavior.

## Keep module tests at public seams

- Invoke another module only through its public port, event, or query contract.
- Replace a collaborator with a small recording fake or the repository-supported Spring bean test
  replacement; never construct fixtures through another module's internal entity or repository.
- Verify module bootstrap scope and public outcomes without widening dependencies for the test.
- Require structural verification when module roots, allowed dependencies, Named Interfaces, or
  public contracts change.
- Discover the Spring Boot application class and existing Modulith verification entry point; do not
  invent either from this skill.

## Verify JPA and persisted outcomes honestly

- Flush writes before asserting database constraints or SQL behavior.
- Clear the persistence context and reread when an assertion must prove mapping or reconstruction
  rather than first-level cache state.
- Use independent transactions when commit, rollback, after-commit behavior, isolation, or locking
  is part of the contract.
- Do not infer delete, cascade, orphan, enum, timestamp, sequence, or identifier behavior from an
  entity annotation alone; verify against the migration-owned schema.
- Use the repository's schema-validation policy and production database for compatibility proof.

Choose the analogous persistence checks when the repository uses JDBC or another mapper.

## Verify events and transactions

For a producer:

- Assert event type, business key, minimal payload, and exact publication count.
- Assert rejected and rolled-back commands publish no successful fact.
- Assert idempotent retry does not create an extra business effect or publication.

For a consumer:

- Drive the public event/port and wait for an observable persisted state or recording fake with a
  bounded timeout.
- Deliver duplicates sequentially and concurrently when the delivery contract requires safety.
- Do not coordinate asynchronous tests with fixed sleeps.

Separate these proofs:

- An event assertion proves an event was emitted.
- A publication-registry or job-store integration test proves durable work committed atomically.
- A committed listener test proves after-commit behavior.

Test-managed transactions that roll back automatically may never trigger after-commit listeners.
Use the repository's supported transaction test utility, `TransactionTemplate`, or an application
service call outside the test transaction to cause a real commit. When durability is promised,
prove failed work remains incomplete, retry completes it once, and restart recovery works when its
policy changes.

## Verify concurrency deterministically

- Run competitors in independent transactions and connections.
- Coordinate them with explicit barriers so they observe the intended state before proceeding.
- Bound every wait and always shut down executors.
- Assert winner and loser outcomes, final rows, aggregate state, versions, history, publications,
  and external intents relevant to the contract.
- Verify create-once constraints, duplicate command/event handling, and each read-modify-write path.
- Re-run rules after lock or optimistic conflict when production code is expected to do so.

When the production database is PostgreSQL, exercise PostgreSQL locking, transaction-abort,
constraint, upsert, and isolation behavior with PostgreSQL Testcontainers. H2, SQLite, mocks, and
pure unit tests are useful feedback but do not satisfy that gate.

## Discover and enforce execution gates

Prefer the repository's documented wrapper. Otherwise inspect the build before running commands:

```bash
./gradlew tasks --group verification
./gradlew test --tests '<fully-qualified-test>'
./gradlew test
./gradlew check
```

- Run the narrowest changed test first, then expand according to risk.
- Run a separate production-database task when one exists; verify whether `check` depends on it
  before claiming full coverage.
- Run the existing structural verification for module-boundary or public-contract changes.
- Run migration smoke coverage when business schema, Flyway history, identifier/version columns,
  or Modulith publication tables change.
- Follow repository-established profiles, tags, Testcontainers configuration, and task names.
  Never invent them in order to make a command look complete.
- Report missing Java, Docker, database, or scaffold prerequisites explicitly.
- Do not hide failures by excluding tests, weakening assertions, or extending timeouts without
  identifying and removing the cause.

## Finish with evidence

Report the risks covered, selected layers, exact commands and results, structural verification,
production-database verification, and every environmental limitation or unverified behavior.
