Liminal is a modern "personal knowledge base" / note taking system based on obsidian and roam research.

## Known Architecture Decisions

- targeting apple platforms only (initially macOS only, then iOS etc. for v2)
- built in swift/swiftui/uikit/appkit using modern best practices

## Features

### Core

- [x] vault / file management (sidebar, open/save/create, directory watching, bookmark persistence)
- [x] adjustable font size (Cmd+/-, 10-40pt range)
- [x] basic text editor interface in the main window
    - [x] full syntax highlighting for "obsidian flavored" markdown ie:
        - [x] commonmark (headings, paragraphs, code blocks, blockquotes, lists, thematic breaks)
        - [x] GFM features (tables, strikethrough, task lists, autolinks)
        - [x] latex / mathjax support for math equations (both inline $...$ and display $$...$$)
        - [x] Wikilinks: [[Note title]] and [[Note title|Alias]]
        - [x] Embeds: ![[Note title]] or ![[image.png]]
        - [x] Block references/embeds: [[Note#^block-id]] and ^block-id to define blocks
        - [x] Highlights: ==text==
        - [x] Comments (invisible in preview): %%hidden text%%
        - [x] Block IDs (^block-id)
        - [ ] Image resizing and alignment: ![[image.png|300]] (width in pixels), ![[image.png|300x200]], or ![[image.png|300x]] (auto height).
        - [ ] You can also combine with headings/blocks: [[Note#Heading|Display text]] or ![[Note#^block-id|Alias]].
        - [ ] mermaid diagrams
        - [x] yaml frontmatter
        - [x] inline footnotes: This is a sentence with an inline footnote^[This appears at the bottom of the note].
        - [x] block-level HTML (CommonMark types 1-7, rendered via NSAttributedString/NSTextView with CSS)
        - inline HTML: out of scope (block-level HTML is sufficient)
        - [x] special whitespace detection (tooltips for non-standard whitespace chars)

    - [x] rendering capability for the above "obsidian flavored" markdown
        - [x] standalone rendering
        - [x] live rendering preview
        - note: embeds and images render as placeholders only (no actual image/file loading yet)
- [ ] wikilink navigation (with backlinks)
    - wikilinks are styled and have URLs attached, but no navigation handler yet
    - [ ] for rendered markdown
    - [ ] also from the editing text view (eg holding cmd + click link)

- [ ] basic pdf viewing (not inline, no markup support needed, just basic off-the-shelf pdf viewing)

### Explicitly out of scope

- NO plugins system. all functionality will be baked in for simplicity / coherence since we control the source code. The (future work) structured custom data will be extensible in a more restricted/semantic way than arbitrary plugin behavior supported by obsidian.

- Canvas

- inline HTML (block-level HTML is sufficient)

- no need for app store compliance. v1 will be built for source code distribution to developers (since i will use it personally mostly)


### Future work

- obsidian flavored markdown is a good foundation, but we will want to enhance this with stronger navigation metadata and custom semantic rendering types. need to think about what this will be as it affects all future work, but the core is fully satisfied by well-tread OFM behavior. structured data should subsume admonition blocks, yaml frontmatter, mermaid diagrams, inline images, links, etc. basically anything that isn't normal text should have a "first class" structured data description.

- html scraper plugin for quickly extracting structured data (or just links) from eg chrome, safari, firefox (this is a standalone plugin for each browser, but we should think about the html -> structured data conversion semantics in a unified way first)

- graph rendering (like obsidian but will want to augment / tweak depending on the final data model)

- vim style navigation (mostly normal vim keybindings plus special navigation keybindings unique to the markdown format eg jumping to / following links etc. will need to think about exactly the right keybindings and behavior here

- admonition blocks (eg based on https://github.com/xfap/obsidian-admonition/tree/master)
    - but these will be extended to full "structured data display" later

- html rendering + blog packaging pipeline (like "obsidian publish"). will need to think about:
    - the right rendering format / navigation system (eg obsidian publish has "panes" for opening multiple pages in the same window, graph navigation etc. but we may want more / different depending on the eventual underlying semantic structure)
    - target hosting system to bundle for

- sync functionality (probably backed by apple cloud, but need to think about the right format / sync behavior eg in light of collaberative edit)
- collaberative live editing (google docs style) but structure-aware (need to think about what structure aware means here - depends on the eventual enhanced data model)

- git integration for version control
    - need to think of good knowledgebase-focused ui for managing git history / trees more simply than full (developer focused) git interface.
