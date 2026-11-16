# Contribuer

Projet personnel, mais on garde un workflow strict.

## Workflow

1. Une issue = une branche = une PR.
2. Branche nommée `feat/<m>-<slug>` ou `fix/<slug>` (ex. `feat/m1-sse-parser`).
3. Commits petits, au format [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).
4. Avant de pousser : `mise run test` doit passer.
5. La PR référence l'issue (`Closes #N`) et coche les critères d'acceptation.
6. Une issue ne passe en `Done` que si ses critères d'acceptation sont remplis et les tests passent.

## Style

- Swift 6, `async/await`, `@Observable`, pas de singletons globaux.
- Pas de dépendance externe (SPM ou autre).
- Pas de secret, d'URL ou de clé réelle dans le code, les tests ou les fixtures.

Voir [CLAUDE.md](CLAUDE.md) pour l'architecture détaillée.
