# CLAUDE.md

Instructions pour Claude Code sur ce repo.

## Projet

Client natif SwiftUI iOS 27 / macOS 27 pour une instance self-hosted Hermes Agent (API compatible OpenAI). Usage personnel uniquement. Le plan de travail est dans les milestones et issues GitHub (M0 à M6).

## Architecture

- `HermesKit/` : package SPM local, toute la logique métier, testable sans UI.
  - `HermesAPI` : client HTTP (`URLSession`), parsing SSE (`URLSession.bytes`), modèles Codable OpenAI-compatibles, erreurs typées.
  - `HermesStore` : persistance SwiftData (`Conversation`, `Message`). M3.
  - `HermesSecurity` : wrapper Keychain, synchronisation iCloud Keychain optionnelle. M4.
- L'app (`App/`, vues, navigation, injection de dépendances) ne contient que de la UI. Projet Xcode généré par Tuist depuis `Project.swift` : ne jamais versionner ni éditer le `.xcodeproj` / `.xcworkspace`, modifier le manifeste puis régénérer.
- Le client API se construit à partir d'une config explicite (URL + clé). Pas de singleton global.

## Conventions

- Swift 6, strict concurrency. `swiftLanguageModes: [.v6]`.
- Concurrence : `async/await`, `AsyncThrowingStream` pour le stream, `Sendable` partout où ça traverse une frontière d'acteur.
- Observation : `@Observable`, pas `ObservableObject`.
- Tests : Swift Testing (`import Testing`, `@Test`, `#expect`). Réseau mocké via un `URLProtocol` custom. Fixtures SSE dans des fichiers.
- Aucune dépendance tierce. Uniquement les frameworks Apple.
- Aucun secret, URL réelle ou clé dans le code, les tests ou les fixtures. Utiliser `https://hermes.example.test` dans les tests.
- Les requêtes POST ne sont jamais retentées automatiquement. Timeouts larges (une requête agent peut durer ~30 min).
- Format : `swift-format` avec `.swift-format` à la racine.

## Commandes

```sh
# Tests du package (macOS avec Xcode 27, ou Linux avec Swift 6.2)
scripts/test.sh

# Vérification du format (sans modifier les fichiers)
scripts/lint.sh

# Correction automatique du format
swift format format -i -r -p HermesKit
```

```sh
# Outillage (Tuist, version fixée dans mise.toml)
mise install

# Génération du projet Xcode puis build de l'app iOS
mise run generate
mise run build

# Tests de l'app sur simulateur iOS 27 (IOS_DESTINATION pour changer de simulateur)
mise run test-app
```

CI : `.github/workflows/ci.yml` (lint, tests HermesKit, build + tests de l'app) sur chaque PR et sur `main`, runner `xcode-27`.

## Git

- Une issue = une branche = une PR. Branche `feat/<m>-<slug>` ou `fix/<slug>`.
- Commits Conventional Commits, petits et clairs.
- Ne jamais marquer une issue Done sans critères d'acceptation remplis et tests verts.

## Questions ouvertes

Les points marqués `needs-verification` dans les issues sont des hypothèses sur l'API Hermes (chemin du health check, `GET /v1/models`, comportement en arrière-plan iOS). Ne pas figer ces hypothèses dans le code sans vérification, et garder une abstraction facile à ajuster.
