# Liminal

Liminal is an early Swift and SwiftUI project for a typed, next-generation knowledge base.

The current repository is intentionally package-first. The reusable document engine lives in `Packages/LiminalCore`; app targets can be added under `Apps/` once the core scaffold is stable.

## Open in Xcode

Open `Liminal.xcworkspace` from the repository root.

## Package Layout

- `LiminalSyntax`: Cambium language definition, parser, syntax tree result, and parse session.
- `LiminalSemantics`: typed document model, schema/prelude, lowering, surfaces, and printing.
- `LiminalWorkspace`: vault, note, document index, wiki-link, and backlink concepts.
- `LiminalEditor`: editor session boundary.
- `LiminalRendering`: platform-neutral rendering boundary for future UI clients.
- `liminal-cli`: command-line utility target for quick parser and printer checks.

The language design spec lives at `Docs/Language/liminal_markup_syntax_spec_v0_1.md`.
