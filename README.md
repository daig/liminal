# Liminal

Liminal is an early Swift and SwiftUI project for a typed, next-generation knowledge base.

The current repository is intentionally package-first. The reusable document engine lives in `Packages/LiminalCore`; app targets can be added under `Apps/` once the core scaffold is stable.

## Open in Xcode

Open `Liminal.xcworkspace` from the repository root.

## Package Layout

- `LiminalText`: source locations, ranges, and diagnostics.
- `LiminalSyntax`: parser-facing syntax scaffolding.
- `LiminalModel`: semantic document model scaffolding.
- `LiminalSchema`: schema and validation scaffolding.
- `LiminalLowering`: syntax-to-model boundary.
- `LiminalSurfaces`: surface reader/printer extension points.
- `LiminalPrinting`: lossless and canonical print entry points.
- `LiminalWorkspace`: vault and file-level workspace concepts.
- `LiminalEditor`: editor session boundary.
- `LiminalRender`: rendering boundary for future UI clients.
- `liminal-cli`: command-line utility target for quick parser and printer checks.
