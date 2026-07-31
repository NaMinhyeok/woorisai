---
name: publish-woorisai-api-failures
description: Design, implement, and review how a Woorisai API failure reaches the client, including the module error catalog, ApplicationException, HandlerFailures mapping, the single ApiControllerAdvice, and the ApiProblem/NotificationApiProblem schemas. Use when adding or changing an endpoint failure, an errorCode, a status or title or detail string, a framework-exception mapping, a security-filter problem response, or the instance field. Use as a companion when boundary or domain work introduces a new public failure. Do not use for domain invariants, event delivery, or test mechanics alone.
---

# Publish Woorisai API Failures

Every `/api/v2/**` failure is an RFC 7807 `ProblemDetail` assembled in one place. The catalog of
what a failure means belongs to its module; how it becomes a response belongs to `support::error`.
Treat `contracts/openapi-v2.yaml` as the authority and the code as its shadow, never the reverse.

## Inspect before changing

1. Read `AGENTS.md`, `docs/architecture/module-boundaries.md`, and the `ApiProblem` and
   `NotificationApiProblem` schemas in `contracts/openapi-v2.yaml`.
2. Read the owning module's `XxxError` enum, its failure classes, and its `XxxHandlerFailures`.
3. Read `ErrorCatalogTest`. It pins every published code with its exact status, title, detail, and
   `instance` policy, so it tells you the current contract faster than the code does.

## Ownership

| Concern | Owner |
| --- | --- |
| What a failure means: status, code, title, detail, log level, `instance` policy | The module's `XxxError` enum |
| Which module failure was raised | The module's `ApplicationException` subclass |
| Which published code a framework exception gets on this controller | The module's `HandlerFailures` bean |
| Failures raised before any module owns the request | `support::error` `CommonError` |
| How a descriptor becomes a response | `support::error` `ApiProblems` and `ApiControllerAdvice` |

`support` declares `allowedDependencies = {}` and exposes `@NamedInterface("error")`; consumers opt
in with `support::error`. Do not put business vocabulary, domain rules, or a module-to-module
reference behind it. `docs/architecture/module-boundaries.md` owns that rule.

## Add or change a failure

1. Add the constant to the owning module's `XxxError` with an explicit `code()`. Published codes
   follow no derivable rule — `INVALID_DIARY_REQUEST` inverts the module prefix and
   `UNSUPPORTED_MEDIA_TYPE` carries none — so never generate the string from the enum name.
2. Add the corresponding entry to `ErrorCatalogTest.PUBLISHED` **before** implementing, and to
   `contracts/openapi-v2.yaml` when a new endpoint or schema is involved.
3. Extend the module's failure class from `ApplicationException`, passing the descriptor. Use the
   `(descriptor, message)` constructor when several failures share one wire contract but not one
   cause; the narrower message stays in logs and only `error()` reaches the client.
4. Never widen an existing code's meaning to avoid adding a constant.

## Map framework exceptions per controller

Spring raises request-binding, locking, and data-access exceptions with no wire contract, and the
published code differs per controller: an unreadable body is `INVALID_DIARY_REQUEST` on the diary
API and `INVALID_MEDIA_UPLOAD_REQUEST` on the upload API. A single advice cannot infer the origin.

- Declare the mapping in the module's `HandlerFailures` bean keyed by `handlerType()`.
- Leave a category unmapped when the controller publishes no contract for it. `ApiControllerAdvice`
  rethrows instead of borrowing another module's code, which is the behavior
  `ApiControllerAdviceTest` guards.
- `HttpMessageNotReadableException` is thrown during argument resolution, before the controller body
  runs, so a try/catch inside the handler method cannot reach it.
- Translate a failure crossing a module boundary at the consuming controller. The participant
  directory's `ParticipantPairUnavailableException` has no fixed descriptor because each consumer
  publishes a different code for it; `LoginOptionsController` wraps it in
  `LoginOptionsUnavailableException`.

## Preserve the two problem schemas

`ApiProblem` requires `instance`; `NotificationApiProblem` excludes it. This asymmetry is
deliberate — do not "fix" it.

- Express it only through `ErrorDescriptor.exposesInstance()`.
- Spring fills a null `instance` with the request path while rendering, so leaving the field unset
  does not keep it out of the body. `ApiProblems` serializes an empty URI to suppress that default.
  Removing that line silently violates the notification contract.
- Both schemas set `additionalProperties: false`. Assert the rendered key set, not just a value; an
  empty `instance` string satisfies `doesNotExist()` on some paths yet still breaks the schema.
- `type` is absent from rendered bodies because it keeps its `about:blank` default. Neither schema
  requires it.

## Keep the security filter chain on the servlet path

`ApiSecurityProblemHandler` implements `AuthenticationEntryPoint` and `AccessDeniedHandler` and runs
before any handler is resolved. Share only `ApiProblems.body`; keep the direct
`HttpServletResponse` write and the `Basic realm="woorisai"` challenge. It cannot return a
`ResponseEntity`.

## Logging and privacy

Log the exception type and the code only, at the descriptor's declared level. Request bodies,
participant data, scores, comment or diary text, FIDs, and media URLs must not reach the log.

## Stop and reconsider

- A published `errorCode`, title, or detail string changes without a matching OpenAPI change.
- One code is reused for two different endpoint meanings, or two codes collapse into one.
- `instance` becomes uniform across both schemas.
- A framework exception is given a default code so that some response is produced.
- `support::error` gains a dependency on a business module, or business meaning moves into it.
- Parallel per-module failure families are merged because they look like duplication; their distinct
  codes are the contract that `AGENTS.md` requires preserving.

## Verify

1. `cd backend && ./gradlew test --tests '*ModularityTests'` first; it gates everything else.
2. `cd backend && ./gradlew test --tests '*ErrorCatalogTest' --tests '*ApiProblemsTest' --tests '*ApiControllerAdviceTest'`
3. `cd backend && ./gradlew check` for the HTTP contract tests, PostgreSQL semantics, and
   `openApiValidate`. Do not substitute H2 for the container-backed tests; report an unrunnable gate
   as unverified.
4. Confirm every published code still resolves to exactly one owning constant, and that no contract
   literal changed unintentionally:
   `git diff | grep -E '^[-+].*"[A-Z_]{5,}"'`
5. Standalone MockMvc tests must build the advice through `ApiErrorAdvice.of(...)` so they exercise
   the production advice. Update wiring only; the assertions are the contract guard.

Use `$test-spring-modulith` for test mechanics, `$design-spring-modulith-boundaries` when the change
moves ownership or widens `allowedDependencies`, and `$coordinate-spring-modulith-change` once when
two or more focused concerns materially apply and no coordinator is already active.
