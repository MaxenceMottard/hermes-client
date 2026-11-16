# Hermes Client

Native iOS and macOS client for a self-hosted [Hermes Agent](https://github.com/NousResearch/hermes-agent) instance, for personal use. It replaces the web dashboard for chatting with the agent.

> Personal project released under the [GNU GPL v3](LICENSE). Copyright (C) 2026 Maxence Mottard.

## Planned features

See the [milestones](../../milestones): OpenAI-compatible API client with SSE streaming, chat screen, SwiftData persistence, secure settings (Keychain), system integrations (MenuBarExtra, App Intents), polish.

## Structure

```
App/                iOS app sources, resources and tests (UI only)
Project.swift       Tuist manifest (the .xcodeproj is generated, not committed)
Tuist.swift         Tuist configuration
mise.toml           project tools (tuist) and tasks
HermesKit/          Local SPM package: business logic, testable without UI
  Sources/
    HermesAPI/        HTTP client, SSE parsing, Codable models, typed errors
    HermesStore/      SwiftData persistence (coming in M3)
    HermesSecurity/   Keychain wrapper (coming in M4)
  Tests/
```

## Requirements

- Xcode 27 with the iOS 27 / macOS 27 SDKs.
- Swift 6 (strict concurrency enabled).
- No third-party dependencies in the app: Apple frameworks only.
- [mise](https://mise.jdx.dev) to install the tooling (Tuist), version pinned in `mise.toml`.

## Getting started

```sh
mise install          # installs Tuist
mise run generate     # generates Hermes.xcworkspace
open Hermes.xcworkspace
```

`mise run build` builds the app from the command line, `mise run test-app` runs its tests on a simulator.

The GitHub Actions CI (`.github/workflows/ci.yml`) runs the HermesKit tests and builds the app on every PR. App tests do not run in CI: the business logic is tested in HermesKit.

## Tests

```sh
mise run test
```

## Security

The instance API key grants shell access to the server. It is stored only in the Keychain, never logged, and must never appear in the repository. The base URL and the key are never hard-coded.

## Documentation

- [CLAUDE.md](CLAUDE.md): conventions, architecture, commands.
- [CONTRIBUTING.md](CONTRIBUTING.md): issue → branch → PR workflow.

## License

Copyright (C) 2026 Maxence Mottard.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed without any warranty. See [LICENSE](LICENSE).
