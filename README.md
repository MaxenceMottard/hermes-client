# Hermes Client

Client natif iOS et macOS pour une instance self-hosted de [Hermes Agent](https://github.com/NousResearch/hermes-agent), destiné à un usage personnel. Il remplace le dashboard web pour discuter avec l'agent.

> Projet privé. Tous droits réservés, voir [LICENSE](LICENSE).

## Fonctionnalités visées

Voir les [milestones](../../milestones) : client API OpenAI-compatible avec streaming SSE, écran de chat, persistance SwiftData, réglages sécurisés (Keychain), intégrations système (MenuBarExtra, App Intents), finitions.

## Structure

```
App/                Sources, ressources et tests de l'app iOS (UI uniquement)
Project.swift       manifeste Tuist (le .xcodeproj est généré, non versionné)
Tuist.swift         configuration Tuist
mise.toml           outils (tuist) et tâches du projet
HermesKit/          Package SPM local : logique métier, testable sans UI
  Sources/
    HermesAPI/        client HTTP, parsing SSE, modèles Codable, erreurs typées
    HermesStore/      persistance SwiftData (à venir, M3)
    HermesSecurity/   wrapper Keychain (à venir, M4)
  Tests/
scripts/
  test.sh           lance les tests du package
  lint.sh           vérifie le format (swift-format)
```

## Prérequis

- Xcode 27 et SDK iOS 27 / macOS 27.
- Swift 6 (strict concurrency activée).
- Aucune dépendance tierce dans l'app : uniquement les frameworks Apple.
- [mise](https://mise.jdx.dev) pour installer l'outillage (Tuist), version fixée dans `mise.toml`.

## Démarrage

```sh
mise install          # installe Tuist
mise run generate     # génère Hermes.xcworkspace
open Hermes.xcworkspace
```

`mise run build` compile l'app en ligne de commande.

## Tests

```sh
scripts/test.sh
```

## Sécurité

La clé API de l'instance donne un accès shell au serveur. Elle est stockée uniquement dans le Keychain, n'est jamais journalisée, et ne doit jamais figurer dans le repo. L'URL de base et la clé ne sont jamais codées en dur.

## Documentation

- [CLAUDE.md](CLAUDE.md) : conventions, architecture, commandes.
- [CONTRIBUTING.md](CONTRIBUTING.md) : workflow issue → branche → PR.
