---
name: design-spring-modulith-boundaries
description: Design, implement, and review Spring Modulith module ownership, dependency direction, public contracts, Named Interfaces, and orchestration boundaries. Use when adding or moving modules or packages; changing package-info.java, @ApplicationModule, allowedDependencies, @NamedInterface, or root-package APIs; exposing cross-module contracts; placing shared code; or resolving cycles and structural verification failures. Use as a companion when domain or event work changes compile-time boundaries. Do not use for a purely internal change or runtime delivery semantics alone.
---

# Design Spring Modulith Boundaries

Make ownership and contracts explicit before changing code. Treat structural verification as proof
of the declared design, not permission to weaken it.

## Inspect the actual module model

1. Read repository instructions, architecture decisions, and the worktree.
2. Discover the application package, module roots, `package-info.java` declarations,
   `@ApplicationModule`, Named Interfaces, public root types, internal implementations, imports,
   persistence mappings, callers, and structural tests.
3. Derive the current dependency graph from declarations and imports. Do not copy one from this
   skill or from stale documentation.
4. If source does not exist, propose package names and annotations as candidates only.

Write a boundary brief:

```text
Use case:
Owning module and evidence:
State and rules owned:
Consumers:
Smallest public contract:
Direct dependencies:
Potential reverse dependency or cycle:
```

Stop implementation when the owning module cannot be named in one sentence.

## Assign ownership

- Assign a concept to the module controlling its rules and state transitions, not the module that
  calls it or stores adjacent data.
- Let only the owner mutate an aggregate or table. Other modules use an owner-provided port or a
  published fact.
- Infer ownership from transitions, repositories, migrations, public ports, and callers.
- Introduce a workflow/process module only when durable progress or compensation spans peer
  modules and no participant naturally owns the flow.
- Keep participant state in participant modules; orchestration does not transfer ownership.

## Preserve dependency direction

- Declare only direct, justified dependencies in each module.
- Count an event consumer as depending on the provider-owned event contract.
- Do not widen `allowedDependencies` merely to silence `ApplicationModules.verify()`.
- Replace cycles with a provider-owned port, a past-tense event, or an explicitly owned workflow,
  chosen according to consistency needs.
- Keep shared technical support independent of business modules. Do not move business vocabulary
  into `shared`, `common`, `support`, or `util` only because two callers need it.
- Do not assume any shared module or Named Interface exists until the repository declares it.

## Minimize public contracts

- Put cross-module contracts in the provider module's root package or an explicit Named Interface.
- Keep controllers, transport DTOs, JPA/JDBC entities, repositories, persistence projections,
  SDK clients, and implementations internal where practical.
- Expose narrow use-case ports, not CRUD repositories or broad service facades.
- Let the provider own commands, results, events, queries, and stable failure contracts.
- Pass immutable IDs, values, records, and read-only snapshots; defensively copy collections.
- Do not leak another module's entity, transport model, persistence type, or a third module's
  public type through a provider contract.
- Convert foreign DTOs to locally owned values at the boundary.

## Use Named Interfaces to narrow authority

- Split a broad module API only when consumers need distinct capabilities or authority.
- Name dependencies as `<module>::<capability>` only after that Named Interface exists.
- Place only stable ports, immutable contracts, and intended public events in Named Interfaces.
- Treat persisted event package/class names and serialized fields as compatibility contracts.
- Prefer one clear root API over speculative Named Interfaces that have no distinct consumer.

## Choose orchestration without hiding coupling

- Use a synchronous public port when the caller needs the result or consistency is shared.
- Use an event only when the provider may commit before an independently owned follow-up.
- Do not create an orchestration module that merely sequences stateless service calls or conceals
  a cycle.
- Keep runtime delivery mechanics in `$engineer-spring-modulith-events` and aggregate rules in
  `$model-spring-domain`.

## Stop and redesign

- Code imports another module's internal package, entity, or repository.
- A dependency creates or hides a cycle.
- Two modules can mutate the same aggregate or table.
- A public type exists only for wiring convenience or leaks a third module's type.
- Business rules move into generic support code.
- A broad allowlist replaces an ownership decision.
- A workflow module has no owned process state or recovery responsibility.

## Verify

1. Run the repository's existing Spring Modulith structural test using its discovered application
   class; add one only when implementation scope authorizes it.
2. Run affected public-contract and module tests.
3. Inspect generated module documentation after structural changes when the repository configures
   it; diagrams do not replace ownership decisions.
4. Re-read the diff for unintended public types, transitive coupling, new cycles, and widened
   allowlists.
5. For a proposal, recommend these gates without claiming they passed. Report missing commands or
   application scaffolding explicitly.

Use `$test-spring-modulith` for test mechanics and `$coordinate-spring-modulith-change` once when
two or more focused concerns materially apply and no coordinator is already active.
