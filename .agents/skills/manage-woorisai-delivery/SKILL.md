---
name: manage-woorisai-delivery
description: Verify and deliver the Woorisai Spring backend and SwiftUI app across local Docker, GitHub Actions, Railway, TestFlight, and ignored dotenv boundaries. Use for local deployment or release rehearsals, CI/CD changes, public-main protection, Railway source/deployment checks, TestFlight preparation, environment drift, or diagnosing a gap between local gates and hosted delivery.
---

# Manage Woorisai Delivery

Treat repository instructions, executable configuration, and provider state as separate evidence.
Never infer that a local branch, GitHub `main`, Railway deployment, and TestFlight archive share a
revision; resolve and compare their SHAs explicitly.

## Establish the delivery boundary

1. Read `AGENTS.md`, `README.md`, `git status`, and `docs/README.md`.
2. For Railway work, also read `docs/operations/railway.md` and
   `docs/operations/security-and-secrets.md`, then use `$use-railway`.
3. For iOS release work, also read `docs/operations/ios-release.md` and
   `docs/architecture/ios-architecture.md`.
4. Inspect the checked-out branch, `HEAD`, remotes, and working-tree status. Local verification may
   run on a change branch; production delivery must resolve to the protected public `main` SHA.
   A remote named `origin` is not proof of repository identity or visibility; verify its URL and
   provider metadata. If the index or working tree differs from `HEAD`, label harness evidence as a
   checkout snapshot rather than evidence for the immutable commit.
5. State whether the requested outcome is local proof, hosted CI proof, Railway production delivery,
   TestFlight upload, or App Store promotion. Do not broaden one into another.

## Use the local harness

Run the deterministic harness from the repository root:

```bash
.agents/skills/manage-woorisai-delivery/scripts/delivery-harness.sh preflight
.agents/skills/manage-woorisai-delivery/scripts/delivery-harness.sh backend
.agents/skills/manage-woorisai-delivery/scripts/delivery-harness.sh local-smoke
.agents/skills/manage-woorisai-delivery/scripts/delivery-harness.sh ios
.agents/skills/manage-woorisai-delivery/scripts/delivery-harness.sh all
```

- `preflight` checks tracked secret boundaries, committed env schemas, ignored env permissions, and
  whitespace without reading actual dotenv values.
- `backend` runs the hosted backend contract through the repository Gradle wrapper.
- `local-smoke` builds the root image and starts it with an ephemeral PostgreSQL container on an
  isolated Docker network. It seeds exactly two synthetic participants, uses only synthetic
  credentials, and deletes its temporary resources.
- `ios` creates disposable supported-screen simulators, runs API/app/UI tests, and builds the Release
  simulator artifact with the non-routable tracked host placeholder.
- `all` runs all four gates. Treat a missing Docker runtime, Xcode runtime, or pinned toolchain as an
  unverified gate, not a pass.

Use the repository validators directly when an operator asks whether ignored local inputs are ready:

```bash
backend/scripts/validate-env.sh local
backend/scripts/validate-env.sh production
apps/ios/scripts/validate-env.zsh --kind local apps/ios/.env.local
apps/ios/scripts/validate-env.zsh --kind production apps/ios/.env.production
```

These validators may report missing or malformed key names. Never open, print, grep, source, diff, or
copy the actual `.env.local`/`.env.production` files. Keep them ignored and mode `0600`; provider
stores remain the production source of truth.

## Promote through hosted gates

For GitHub delivery:

1. Require the public `main` branch to receive changes through a pull request.
2. Require `Repository hygiene`, `Backend check`, `Container smoke`, and `iOS app gates` from the
   `Verify` workflow.
3. Keep Actions read-only by default, external actions pinned to full SHAs, force-push disabled, and
   secret scanning/push protection enabled.
4. Do not publish private-history refs, populated env files, provider artifacts, or operator records.

For Railway production:

1. Obtain explicit authorization for deploy or configuration mutation.
2. Scope every operation to the documented project, environment, and API service; read back source,
   branch, and `Wait for CI` after a change.
3. Accept only the protected GitHub `main` SHA after its four checks succeed.
4. Wait for a terminal successful deployment, then verify `/health`, public login options, and an
   invalid protected request returning `401` with `Cache-Control: no-store`.
5. Never use a production PIN, private response, data write, migration, or provider side effect in
   the generic smoke.
6. A source-connect or configuration-driven deployment may not create a GitHub `deployment_status`
   event. After confirming the exact protected `main` SHA reached terminal success, dispatch
   `Backend production smoke` manually from `main`. Record this as fallback proof; the next normal
   `main` push must still prove Railway's native post-deploy event path.

For iOS delivery:

1. Run `iOS TestFlight` manually only for the protected `main` SHA with all four checks successful.
2. Restore production host, Firebase client realm assertions, and App Store Connect inputs through
   GitHub secrets into a mode-`0600` runner temp file.
3. Let `release-testflight.zsh` validate the archive and upload the same IPA; do not rebuild between
   TestFlight proof and promotion.
4. Keep App Store public promotion manual after signed-device, review-realm, privacy, and production
   contract gates.

## Keep local and hosted behavior aligned

When build commands, simulator support, container startup, env keys, or required checks change,
update the harness, workflows, examples, and owning runbook together. Regenerate the Xcode project
from `apps/ios/project.yml` and review the generated diff. Do not weaken a hosted gate merely to make
the harness pass.

Finish by reporting the exact local branch/SHA, hosted SHA, commands run, provider terminal state,
smoke results, skipped gates, and remaining security or release risk. Never report secret values.
