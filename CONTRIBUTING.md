# Contributing to eloEngine

Thank you for taking the time to contribute! This document explains how to report issues, suggest features, and submit code changes.

---

## Reporting Bugs

Before opening a new issue, search existing issues to avoid duplicates.

When filing a bug report, please include:
- Dart version (`dart --version`)
- Platform and OS version
- Steps to reproduce
- Expected behaviour vs. actual behaviour
- Any relevant log output or stack traces

---

## Suggesting Features

Open an issue with the `enhancement` label. Describe the problem you are trying to solve rather than jumping straight to a solution — this helps discussion stay focused.

---

## Development Setup

```bash
git clone <repo-url>
cd elo_engine
dart pub get
```

Run the test suite to verify your environment:

```bash
dart test
```

---

## Code Style

All contributions must pass the following checks before review:

```bash
# Format
dart format .

# Static analysis (must have zero issues)
dart analyze

# Tests (must all pass)
dart test
```

The project uses `package:lints` with standard rules — no overrides. Do not disable lint rules without a well-reasoned justification in the PR description.

---

## Testing

- Every new feature must include tests.
- Bug fixes should include a regression test where feasible.
- Tests live in `test/` and mirror the `lib/` structure.
- This is a pure Dart package with no native dependencies — tests run with `dart test` only, no device or emulator required.

---

## Pull Request Workflow

1. Fork the repository and create a feature branch from `main`:
   ```bash
   git checkout -b feat/my-feature
   ```
2. Make your changes, following the code style rules above.
3. Open a PR against the `main` branch with a clear description of what changed and why.
4. Link any related issues in the PR description (`Closes #123`).

PRs that fail `dart analyze` or `dart test` will not be merged.

---

## Architecture Notes

eloEngine is a pure Dart package with no Flutter or native dependencies. The public API exposes:

- An `EloEngine` or equivalent class for managing a collection of items and their ELO ratings.
- Head-to-head matchup recording (winner/loser or draw).
- Rating query and ranking sort utilities.

When adding new functionality:

1. Keep the package pure Dart — no `flutter` or platform-specific imports.
2. Add or update the corresponding unit tests in `test/`.
3. Keep the public API minimal and well-documented with Dart doc comments.

---

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

## Contact

Questions or proposals that don't fit an issue? Open an issue and tag it `question`.
