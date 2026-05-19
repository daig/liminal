# Sync features to revisit beyond the foundation stack

Captured 2026-05-17 alongside the discussion that led to the ex/file commands slice. After the foundation stack (ex/file commands → sandbox migration → NSFileCoordinator awareness) lands, putting a vault in iCloud Drive will give us cross-device file sync, version history, and safe coexistence with the iCloud daemon — but the surface for any of it is invisible to users by default.

This doc remembers the features Obsidian Sync provides *on top of that infrastructure* so we can revisit each carefully when there's a reason to. Not a spec; not a plan.

## The set to remember

### Version history sidebar
Apple keeps ~90 days of file versions, but no app surfaces them. Obsidian shows a list with timestamps and diff/restore. Classic use case: "I deleted a paragraph yesterday and want it back."

### Sync status indicators
iCloud sync is opaque — Finder shows a cloud icon, nothing in-app. Obsidian shows per-file and per-vault status (syncing / synced / error / conflict). Builds user trust that edits made it across devices.

### Conflict resolver
When iCloud detects a conflict, it dumps both versions as separate files in the folder, oddly named. Obsidian shows a diff UI to resolve. Our CST infrastructure could enable *structural* diff (per-paragraph / per-heading) rather than just text diff — that'd be an upgrade over Obsidian's resolver, not just a port.

### Sync activity log
"What changed when, on which device?" Obsidian shows a timeline of recent sync events. Helps with "where did my edit go?" trust-and-debug questions.

### Selective sync
Configure which file types or paths sync (e.g., exclude attachments). iCloud Drive syncs folders wholesale, so true exclusion needs infrastructure — but a related "exclude from index" UX (hide from sidebar / search) is in reach.

### App-side end-to-end encryption
Obsidian encrypts vault contents with a user passphrase before upload; their servers see only ciphertext. Apple's Advanced Data Protection does account-level E2EE, but per-vault passphrase encryption is genuinely different. Big tradeoff: breaks interop with any other markdown tool — grep, Spotlight, Obsidian, Bear, Drafts all stop working on encrypted vaults.

### Custom retention windows
Obsidian lets users configure history retention (1mo / 6mo / 12mo by tier). Apple's version retention is system-determined and not app-configurable.

### Cross-platform sync
Works to Android, web, etc. Out of scope (Apple-only by decision).

## The framing question

When considering any of these later, the question isn't "does iCloud do this?" — it's "does iCloud expose this in a way users can use, or do we need to build the surface?" Most items above are the latter.
