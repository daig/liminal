# Incremental Computation Engine — Design & Migration Roadmap

> **Reference implementations** (read-only local clones, for the implementing
> session): `~/code/salsa` (the incremental engine we model on), `~/code/rust-analyzer`
> (salsa-over-CST layering), `~/code/cstree` (the CST library Cambium descends from),
> `~/code/rowan` (cstree's ancestor). Our trees: `~/code/liminal-next/cambium`
> (CST library) and `~/code/liminal-next/liminal` (the app).
>
> This document is self-contained and intended to be **reviewed thoroughly before
> implementing** — all motivating context is in §1–§2.

---

## 1. Context & Motivation

### 1.1 The problem
Caching and string interning in Cambium + Liminal are **ad-hoc and woven throughout**
the code. They work, but they underperform and — worse — every time we want to
improve them, the churn ripples across many call sites. We want to consolidate
incremental computation into a **modular engine in its own codebase** (a third
package beside Cambium and Liminal), the way rust-analyzer leans on **salsa**.

Concrete instances of the sprawl (inventoried; see §2.5 for the full map):
- **Interning** split and partial: Cambium has principled token-text interning
  (`LocalTokenInterner`/`SharedTokenInterner`), but Liminal re-derives semantic
  strings (qnames, link targets, titles) with no shared interner.
- **Cross-file incrementality is hand-rolled**: `VaultLinkIndex` (the backlink
  graph) rebuilds **globally on every vault scan** — no incremental update.
- **Per-node analysis caches are ad-hoc**: Cambium's `SyntaxMetadataStore` /
  `ExternalAnalysisCache` use manual, tree-version-keyed eviction.
- **Tree-derived memoization is bespoke**: `DocumentIndexBuilder` recently grew a
  `[ContentHash: Contribution]` memo by hand — a one-off of a pattern we want to
  generalize.

### 1.2 The aspiration, and why we don't just copy salsa
rust-analyzer gets all its incrementality from **salsa**: a database of *inputs* and
memoized *tracked queries*, with revision counting, dynamic dependency tracking,
**backdating** (recompute, compare output, suppress propagation if unchanged), and
**durability** tiers (rarely-changing inputs skip revalidation). salsa is Rust-only
(proc-macros + a `'db` lifetime), so we will build our own Swift engine — but its
*programming model* is the reference.

**The insight that makes our design diverge from rust-analyzer's:** *our CST is
content-addressed.* Cambium computes a composable content hash on every green node;
rowan/cstree do **not** (they intern structurally at build time via a *transient*
hash, verified by exact compare, and never persist a fingerprint). rust-analyzer
must therefore track dependencies + backdate for **everything**, because it has no
stored fingerprint to key on. We can instead key a memo directly on a subtree's
**content hash** — which is exactly why `DocumentIndexMemo` works. This bifurcates
our engine into **two tiers**:

- **Tier 1 — content-addressed structural memoization.** Pure function of a single
  CST subtree → key by content hash. Automatic invalidation (different content ⇒
  different hash ⇒ miss). Cheap; no dependency graph. Covers the intra-file,
  tree-derived work (document index, highlighting spans, decorations, lowering,
  fold regions).
- **Tier 2 — dependency-tracked queries (salsa-style).** For computations over
  *multiple/changing inputs* that aren't a single hashable subtree: cross-file
  (vault backlink graph), workspace, cross-file diagnostics, the future commit
  graph. Inputs + tracked queries + revisions + backdating + durability. Tier-2
  queries *call* Tier-1 memoized functions.

So the design is **not** "salsa for everything" (rust-analyzer, forced by the
absence of content hashes) nor "content-memo for everything" (impossible for
cross-file). It's two complementary tiers, with the boundary drawn exactly where a
computation stops being a function of one hashable subtree.

### 1.3 The cstree precedent (this is the reference architecture)
Cambium descends from **cstree** (persistent red nodes, `Send`/`Sync` trees, custom
node data, **trees over interned strings** — all of which Cambium mirrors). Crucial
fact: **cstree deliberately has no incremental-computation engine.** Its salsa
dependency is *commented out*; it ships only an opt-in *interop shim*
(`salsa_2022_compat`, `impl_cstree_interning_for_salsa`) so a downstream salsa
database can back cstree's interner. cstree's intended architecture is exactly
**"cstree (tree + interning) + salsa (incremental computation), bridged at the
interner."**

We are doing precisely that, with two differences: (a) we write our own Swift engine
since salsa is Rust-only, and (b) Cambium *added* a composable content hash that
cstree lacks — which powers Tier 1 and the commit graph. So splitting incremental
computation into a third codebase is **following the reference design, not
inventing.** And the **interner is the integration seam.**

### 1.4 Scope decision (settled): Option A, built "B-first"
Of three considered scopes — (B) interner + content-memo only; (A) that **plus** a
dependency-tracked query engine; (C) A plus re-basing Cambium's hot-path green/token
dedup onto the new lib — we chose **A**, sequenced so the cheap tier lands first:

1. **Tier 1 first** (interner + content-hash query + content-memo): low-risk,
   immediately retires the interning sprawl and backs intra-file editor work. This
   *is* scope B, banked as standalone value.
2. **Then Tier 2** (the dependency-tracked engine): migrate the vault index + the
   Cambium sidecars onto it.

**Not Option C.** Two boundary rules keep us out of it:
- Cambium's **hot-path green/token structural dedup stays in Cambium** (it's the
  most-tuned, perf-critical code; touching it is high-risk for conceptual-only gain,
  and rust-analyzer's clear precedent is to keep the syntax layer independent of the
  query engine).
- The engine **consumes** Cambium's interner *interface* and provides an
  implementation through it (the cstree seam) — it never reaches into Cambium's
  caches.

### 1.5 The content-hash relocation (settled): move content *addressing* into the engine
We will **relocate content addressing out of Cambium into the engine.** Today Cambium
computes a content hash **eagerly on every green node at build** (on the per-keystroke
incremental-reparse path) and stores it on every node; it's used for green-node
dedup, for green-node `Equatable`/`Hashable`, and exposed for consumers (the doc-index
memo, anchors). After the move:

- The **engine** owns content addressing as a **lazy, memoized query**
  (`engine.contentHash(node)`), computed on demand and memoized **by green-node
  storage reference** (`GreenNodeStorage`/`GreenTokenStorage` are `final class`, so
  reference identity is stable). Incremental reparse **carries unchanged subtrees
  over by reference**, so an unchanged subtree hits the memo across versions ⇒
  O(1), no recompute — reproducing exactly what the stored hash gives today, but
  lazily and only for subtrees someone actually addresses.
- **Cambium keeps only a cheap, transient dedup hash** (rowan/cstree-style: a
  non-crypto hash for the build-cache probe, verified by exact structural compare,
  **not persisted, not exposed**). This is irreducible — green-node dedup needs a
  hash *at build time, inside Cambium*, before the engine sees the tree, so Cambium
  cannot be *totally* hash-unaware. But it sheds the *persisted, exposed,
  composable content hash*.

**Why do this:**
- **Architecture (primary):** puts content addressing where it's the natural memo
  key and the commit-graph foundation; **un-forks Cambium toward cstree** (which has
  no persisted content hash); cleaner three-layer story ("an engine query Cambium is
  oblivious to" rather than "a Cambium feature Liminal consumes").
- **Memory:** drops the stored 128-bit hash from every node's storage header — across
  the whole tree and (later) every commit-graph version. This is the more tangible
  runtime win.
- **Build-path latency: marginal — do NOT lead with it.** The hash is confirmed
  **polynomial Rabin-Karp** (M₆₁, bases 131/137), *not* SHA-256
  (`ContentHashing.swift:20-39`); the "SHA-256" mentions in `GreenElement.swift:398,722`
  and `GreenSnapshotSerialization.swift:95` are stale comments from a prior
  implementation that was replaced *because* SHA-256 isn't composable
  (`PolynomialHash.swift:14-15`, `CambiumSource.swift:428-429`). Polynomial hashing is
  cheap per byte, so moving it off the keystroke build path saves little. Justify the
  relocation on architecture + memory, not perf.

**Cost to accept:** green-node `Equatable`/`Hashable` currently use `contentHash`
(as an early-out; equality is already `storage ===` first, then field + hash, then
recurse). Removing the stored hash makes equality fall through to structural
recursion (reference fast-path still catches deduped nodes) and weakens `hash(into:)`
to (kind, textLength, childCount) — acceptable, since green nodes used as
hash-keys-by-content migrate to `engine.contentHash`. This is real surgery on
Cambium's core; sequence it **after** the engine's hash tier is proven (§3).

---

## 2. Intended Architecture

### 2.1 Three codebases, one dependency direction
```
Cambium (CST library)                      ── content-hash-UNAWARE after the move
  • green/red trees, GreenTreeBuilder
  • token-text interner *interface* (TokenKey / TokenResolver)
  • cheap transient build-dedup hash (internal, not exposed)
  • incremental reparse (ParseWitness, reuse-by-reference)
        ▲ depends on
        │
The Engine (NEW — working name TBD; botanical theme suggested,
            e.g. "Phloem"/"Xylem" — vascular tissue that transports,
            fitting an engine that propagates derived values)
  • shared Interner implementation (plugs into Cambium's interface; also serves
    Liminal's semantic strings)
  • Tier 1: contentHash(node) query  +  content-addressed memo
  • Tier 2: inputs + tracked queries + revisions + backdating + durability
        ▲ depends on
        │
Liminal (the app)
  • consumers: DocumentIndex, vault link/backlink graph, highlighting,
    Phase-2 decorations, CSTAnchor, commit graph (future)
```
Engine depends on Cambium (it walks green nodes); Cambium depends on neither;
Liminal depends on both. (Same shape as cstree ← salsa ← rust-analyzer.)

### 2.2 The two tiers, and their keys (be precise — there are three distinct keys)
| Tier | For | Memo key | Invalidation |
|---|---|---|---|
| **Tier 1: content-memo** | pure fn of one CST subtree (doc index, highlight, decorations, lowering) | **content hash** of the subtree (survives reparse via content equality) | automatic: content changes ⇒ hash changes ⇒ miss |
| **(internal) hash computation cache** | computing `contentHash(node)` itself | **green-node storage reference** (`ObjectIdentifier`) | tied to node/tree lifetime; evict on version drop |
| **Tier 2: tracked queries** | multi-input / cross-file (vault graph, workspace, commit graph) | **input identity + query** (salsa-style) | dependency tracking + revisions + backdating |

Note `SyntaxNodeIdentity` (tree id + red-node id) is Cambium's existing per-node
identity; it's the natural key for Tier-2 *per-node* analyses (what
`ExternalAnalysisCache` uses today). Content hash is the cross-version *content* key
(Tier 1 + anchors); storage reference is just the hash-computation accelerator.

### 2.3 The interner seam (cstree-style)
- Cambium **owns the interner interface** (`TokenKey` / `TokenResolver`) — token
  interning is tree-storage, stays in Cambium.
- The engine **provides a shared interner implementation** Cambium plugs into via
  that interface, and that **Liminal's semantic strings** (qnames, link targets,
  titles) also use. One interner, plugged in at the existing seam — unifying token +
  semantic interning **without** Option C surgery.

### 2.4 Content addressing in the engine
`engine.contentHash(node) -> ContentHash`, lazy, memoized by storage reference,
compositional (a node's hash from its children's memoized hashes). The commit graph
and Tier-1 memo both build on it. The `ContentHash`/`ContentHasher` machinery moves
from Cambium into the engine. The green-tree hash and the **rope hash** are the
**same polynomial family**, not two systems: `ContentHasher` is a thin
discriminated-encoding wrapper over the very `PolyHash` the rope's `Aggregates.hash`
uses. So one primitive (`PolyHash`/`ContentHash`) moves to the engine and both usages
re-home. The rope usage (`CambiumSource` equality) *can* move out by the same logic
(keep utf16/line aggregates, drop the hash aggregate; rope equality falls back to
pointer-equal-root → byte-count → O(N) compare), but it's already O(1)-cheap, so
**relocate it later as a separable follow-on**, not in the first pass.

### 2.5 What lives where (after the migration)
| Concern | Lives in | Notes |
|---|---|---|
| Green/red trees, builder, reparse | Cambium | unchanged |
| Token-text interner *interface* | Cambium | `TokenKey`/`TokenResolver` |
| Transient build-dedup hash | Cambium | new, cheap, internal, not exposed |
| Interner *implementation* | Engine | plugged into Cambium's interface |
| `contentHash(node)` + `ContentHasher` | Engine | lazy, memoized-by-reference |
| Content-addressed memo (Tier 1) | Engine | generalizes `DocumentIndexMemo` |
| Inputs + tracked queries (Tier 2) | Engine | salsa-style |
| Rope hash | Cambium → Engine (later) | separable follow-on |
| DocumentIndex, vault graph, highlighting, decorations, anchors | Liminal | consume the engine |
| Commit graph (future) | Liminal | built on engine content addressing |

### 2.6 API style — DEFERRED
The macro-vs-value API is explicitly deferred. Non-binding default to revisit:
**value/closure API first** (`engine.memoize(key) { … }`, queries as registered
functions; dependency recording is runtime/task-local regardless of surface syntax),
with `@Input`/`@Tracked` macro sugar added later if it proves worthwhile (Cambium
already uses macros, so there's precedent). The implementing session should settle
this early but it does not affect the architecture above.

---

## 3. Migration Roadmap

### 3.0 Verification philosophy (read this first — it shapes the chunking)
The constraints, and what they imply:
- **No backwards compatibility.** We **replace in place** — no dual code paths, no
  fallbacks, no compat shims. The original is **not** kept runnable.
- **But we must verify correctness + performance against the original.** Since the
  original won't be runnable post-replacement, **capture a golden baseline up front**
  (Phase 0): the canary's outputs + perf measurements on the *current* code. Every
  later chunk verifies against that captured baseline.
- **The end-to-end canary is the Cambium calculator** (`cambium/Examples/Calculator/`).
  It already spans the whole stack — parse + green-node dedup (content hash) +
  incremental reparse (`ParseWitness`) + **memoized evaluation** (`CalculatorEvaluator`
  via `ExternalAnalysisCache` keyed on `SyntaxNodeIdentity` + `SyntaxMetadataStore`).
  Those caches are the *exact* ad-hoc patterns we're consolidating, so the calculator
  is both the correctness canary **and** the engine's first real client. Its REPL
  commands (`:tree`, `:ast`, `:eval`, `:fold`, `:peval`, `:save`, `:load`) and tests
  are the observable surface.
- **Work backwards from canary failures; do NOT bottom-up unit-test every primitive**
  (explicit anti-churn directive). Reserve targeted checks **only** for the critical
  parity seams called out below (content-hash bit-for-bit; behavior-identical outputs;
  perf vs baseline). salsa's `examples/calc` (input → tracked parse → derived
  type-check, diagnostics via accumulator) is the **model** for the engine's own
  minimal computation canary.

Each phase below names its **verification seam** = what to replay against the golden
baseline. Chunks are sized to keep that seam meaningful, **not** to allow old/new
coexistence.

### Phase 0 — Scaffold + golden baseline
- Create the engine package; wire it into the workspace (no behavior yet).
- **Capture the golden baseline** from current code: calculator REPL outputs for a
  fixed script (`:tree`/`:ast`/`:eval`/`:fold`/`:peval` + an incremental-edit
  sequence), a **dump of content hashes** for the calculator + `Docs/Fixtures/stress.md`
  trees, the current `DocumentIndex` for fixtures, current vault backlinks for a
  fixture vault, and perf numbers (incremental-reparse latency, doc-index build time,
  vault-update time).
- **Seam:** the baseline artifacts themselves — checked into the test suite as golden
  data.

### Phase 1 — Tier 1 in the engine (this is scope "B"; low-risk, high-value)
- **1a. Shared interner.** Build the engine's interner; validate it standalone; start
  routing Liminal's semantic strings through it. *Do not* rewire Cambium's token
  interner yet (that's a later, optional consolidation via the interface).
- **1b. `engine.contentHash(node)`** — lazy, memoized-by-storage-reference,
  compositional. **Seam (critical parity):** engine hashes must equal Cambium's
  current `contentHash` **bit-for-bit** on the calculator + stress trees (replay the
  Phase-0 hash dump). This proves the engine reproduces the existing semantics before
  anything depends on it.
- **1c. Content-addressed memo facility** (generalize `DocumentIndexMemo`). Migrate
  `DocumentIndexBuilder` (`liminal/.../Workspace/DocumentIndexBuilder.swift:49,116`)
  to key its memo via the engine. **Seam:** `DocumentIndex` identical to baseline on
  fixtures; doc-index build perf ≥ baseline.

### Phase 2 — Relocate content addressing out of Cambium
Now the engine provides content hashing, so Cambium can drop it. Replace in place:
- **2a.** Add the transient dedup hash to Cambium's builder; re-key `NodeCacheKey`
  (`cambium/.../GreenTreeBuilder.swift:424,641`) on it + exact structural verify.
  **Seam:** structural sharing preserved (dedup still collapses identical subtrees);
  calculator + stress parse identically; build perf measured.
- **2b.** Switch `GreenToken`/`GreenNode` `Equatable`+`Hashable`
  (`cambium/.../GreenElement.swift:624–639,1008–1033`) off `contentHash` (reference
  fast-path + structural fallback). **Seam:** calculator canary; audit any
  green-node-as-dictionary-key usage and migrate it to `engine.contentHash`.
- **2c.** Remove the stored `contentHash` field + `ContentHasher` from Cambium green
  elements (`GreenElement.swift:406,730,802–843`); move `ContentHash`/`ContentHasher`
  into the engine. Migrate the remaining consumers to `engine.contentHash`:
  `DocumentIndexBuilder` (done in 1c), `CSTAnchor.NodeFingerprint`
  (`liminal/.../Editor/CSTAnchor.swift:9,93,144`), `CSTInspector`/
  `CSTInspectionSnapshot`. **Green-snapshot serialization is also a consumer/persister:**
  the v2 format embeds the 16-byte `ContentHash` per record
  (`CambiumSerialization/GreenSnapshotSerialization.swift:95`) to skip recompute on
  decode — decide whether snapshots stop embedding it (engine recomputes lazily on
  load) or the encoder sources it from the engine; either way it is a **format-version
  change**, and the calculator's `:save`/`:load` exercises it. (`VaultCacheFormat`'s
  FNV-1a note hash is **separate** — no migration.) Remove/redirect Cambium's
  `greenHash` accessor (`cambium/.../SyntaxTree.swift:1141`). **Seam (critical):**
  calculator parse + reparse + `:eval`/`:fold`/`:peval` + `:save`/`:load` identical to
  baseline. (Build-path latency: confirmed marginal — polynomial, not SHA — so don't
  gate the relocation on it.)
- **2d. (separable, lower priority)** Relocate the rope's polynomial hash by the same
  pattern; keep utf16/line aggregates. Defer unless cheap.

### Phase 3 — Tier 2 in the engine (dependency-tracked queries)
- **3a. Core engine:** inputs, revision counter, task-local dependency recording,
  tracked-query memoization, backdating, lazy revalidation. **Seam:** a minimal
  computation canary modeled on salsa's `examples/calc` (input → tracked → derived;
  edit input → correct recompute + backdating suppresses unchanged downstream).
- **3b. Port the calculator's evaluation caching onto the engine.** Re-express
  `CalculatorEvaluator`'s `ExternalAnalysisCache` + `SyntaxMetadataStore` usage as
  engine queries (Tier-1 content-memo for pure per-node eval; Tier-2 where it spans
  inputs). **Seam:** calculator `:eval`/`:fold`/`:peval` + incremental edits identical
  to baseline — this is the end-to-end proof that the engine subsumes the ad-hoc
  caches.
- **3c. Durability** (active-file = LOW, rest-of-vault = HIGH).
- **3d. Migrate the vault link/backlink graph onto Tier 2.** File texts as inputs,
  per-file `DocumentIndex` as Tier-1 content-memo, **backlink graph as a tracked
  query** that recomputes only affected entries. **Seam:** vault backlinks identical
  to baseline; editing one file recomputes only affected entries (instrument
  reuse/recompute); vault-update perf ≫ baseline (today it's a global rebuild).

### Phase 4 — Consolidation
- Re-express or retire Cambium's `SyntaxMetadataStore` / `ExternalAnalysisCache` in
  favor of engine facilities (or keep them as thin engine-backed shims).
- Remove now-dead ad-hoc caches; fold remaining consumers.
- The **commit graph** (separate roadmap item) is built on the engine's content
  addressing — out of scope here, but unblocked.

### Critical files (anchors for the implementing session)
- **Engine (new):** interner impl; `ContentHash`/`ContentHasher` (moved from Cambium);
  `contentHash(node)` query; content-memo; Tier-2 query core.
- **Cambium — relocate hashing:** `Sources/CambiumCore/ContentHashing.swift`,
  `PolynomialHash.swift`, `Sources/CambiumCore/GreenElement.swift` (storage fields,
  equality/hashable; **also fix the stale "SHA-256" comments at :398,:722**),
  `Sources/CambiumBuilder/GreenTreeBuilder.swift` (`NodeCacheKey`, dedup),
  `Sources/CambiumCore/SyntaxTree.swift` (`greenHash`),
  `Sources/CambiumSerialization/GreenSnapshotSerialization.swift` (persists the hash;
  v2 format — stale "SHA-256" comment at :95).
- **Cambium — canary:** `Examples/Calculator/` (parser, evaluator, session, REPL,
  tests).
- **Liminal — consumers:** `Workspace/DocumentIndexBuilder.swift`,
  `Editor/CSTAnchor.swift`, `App/CSTInspector*.swift`, `Workspace/LiminalWorkspace.swift`
  (`VaultLinkIndex`).
- **Reference:** `~/code/salsa/examples/calc`, `~/code/salsa/src` (model);
  `~/code/cstree/cstree/src/interning` + `examples/salsa.rs` (the interner seam).

### Open questions for the reviewing session
1. **API style** (deferred): value/closure-first vs. macros. Settle early.
2. **Exact green-hash function — RESOLVED:** it is **polynomial Rabin-Karp** (M₆₁,
   bases 131/137), confirmed in `ContentHashing.swift:20-39` (the "SHA-256" mentions
   elsewhere are stale). The engine's hash need only be *internally* consistent — but
   see #3, because it IS persisted.
3. **Persisted hashes — ANSWERED (constrains Phase 2c):** green-snapshot serialization
   persists the `ContentHash` (v2 format, 16 bytes/record —
   `GreenSnapshotSerialization.swift:95`), and the calculator `:save`/`:load`
   exercises it. So changing the hash function — or moving where it is computed — is a
   **serialization format-version change**; handle it in 2c. Confirm whether the future
   commit graph will also persist hashes before finalizing the engine's hash format.
4. **Engine concurrency model**: `Sendable`/actor vs. `Mutex`-sharded (Cambium uses
   `Mutex`; salsa uses interior mutability + thread-local). Decide how task-local
   dependency recording works in Swift concurrency.
5. **Memo eviction / GC**: lifetime policy for the reference-keyed hash memo and Tier-1
   memo across tree versions (salsa uses LRU + revision GC).
6. **Rope hash relocation** (2d): now or later.
