# Liminal

Liminal is an early Swift and SwiftUI project for a typed, next-generation knowledge base.

The current repository is intentionally app-first. For now, the editor engine,
syntax layer, semantic model, workspace model, and rendering boundary live
together in one SwiftUI app target. Once those boundaries stabilize, reusable
parts can be extracted into separate packages.

## Open in Xcode

Open `Liminal.xcworkspace` from the repository root.

## Project Layout

- `Liminal/App`: SwiftUI app entry and top-level views.
- `Liminal/Syntax`: Cambium language definition, parser, syntax tree result, and parse session.
- `Liminal/Semantics`: typed document model, schema/prelude, lowering, surfaces, and printing.
- `Liminal/Workspace`: vault, note, document index, wiki-link, and backlink concepts.
- `Liminal/Editor`: editor session boundary.
- `Liminal/Rendering`: platform-neutral rendering boundary for future UI clients.
- `LiminalTests`: unit tests for the single app module.

The language design spec lives at `Docs/Language/liminal_markup_syntax_spec_v0_1.md`.
