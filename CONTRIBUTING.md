# Contributing

A personal project, but with a strict workflow.

## Workflow

1. One issue = one branch = one PR.
2. Branch named `feat/<m>-<slug>` or `fix/<slug>` (e.g. `feat/m1-sse-parser`).
3. Small commits following [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).
4. Before pushing: `mise run test` must pass.
5. The PR references its issue (`Closes #N`) and checks off the acceptance criteria.
6. An issue only moves to `Done` once its acceptance criteria are met and the tests pass.

## Style

- Everything in English: code, comments, docs, commits, PRs.
- Swift 6, `async/await`, `@Observable`, no global singletons.
- No external dependencies (SPM or otherwise).
- No real secrets, URLs or keys in code, tests or fixtures.

See [CLAUDE.md](CLAUDE.md) for the detailed architecture.
