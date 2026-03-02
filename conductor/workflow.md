# Workflow — Water Tracker

## TDD Policy

**Moderate** — tests are encouraged but do not block implementation. Unit tests should be written for business logic, data models, and non-trivial algorithms. UI tests are optional. Complex features (e.g., webcam detection logic, bottle tracking calculations) should have test coverage.

## Commit Strategy

**Conventional Commits** format:

```
<type>(<scope>): <description>

Types: feat, fix, refactor, test, docs, chore, style, perf
```

Examples:
- `feat(logging): add one-click water entry from menu bar`
- `fix(reminders): correct interval timer reset on wake`
- `test(models): add unit tests for bottle volume calculations`

## Code Review

**Optional / self-review OK** — this is a solo project. Review your own changes before committing. For significant features, take a moment to re-read the diff before merging.

## Verification Checkpoints

Manual verification is required **at track completion** — before marking a track done, manually test the feature end-to-end on a real Mac.

## Task Lifecycle

```
pending → in_progress → completed
```

- A task is **in_progress** when actively being worked on
- A task is **completed** only when implementation is done, tests pass (where applicable), and the feature works as expected
- Tracks are **completed** only after manual end-to-end verification

## Branch Strategy

- Work directly on `main` for solo development, or use short-lived feature branches per track
- Squash or rebase before merging feature branches to keep history clean
