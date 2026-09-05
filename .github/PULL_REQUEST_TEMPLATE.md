## What this changes

<!-- What problem does this solve? Link the issue if there is one. -->

## Test plan

<!-- Tick items as they land. Screenshot or recording for UI changes. -->

- [ ] `swift test` passes
- [ ] `make build` succeeds

## Privacy and permissions

Layer captures screen content and holds an API key, so these are worth a
deliberate answer rather than a skim.

Tick **exactly one**:

- [ ] This change does **not** widen what Layer captures, monitors, stores, or
      sends off the machine.
- [ ] This change **does** widen that. The note below says exactly how, and
      the README's "Privacy and permissions" section is updated to match.

<!-- If you ticked the second box, explain here. -->

## Checklist

- [ ] Follows the vocabulary in [CONTEXT.md](../CONTEXT.md) (Notch, Chat
      conversation, Turn, Screen context)
- [ ] Tests added or updated for changed logic
- [ ] No secrets, build output, or `.DS_Store` files in the diff
- [ ] Any new dependency is recorded in `THIRD-PARTY-NOTICES.md`
