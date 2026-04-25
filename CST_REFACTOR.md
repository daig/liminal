## Locked down architecture decisions
- use [[cstree]] for the core CST and typed AST view
- [[logos]] for lexing
- hand-rolled recursive descent parser for the source->CST parsing
- use [[ungrammar]] to generate the typed AST wrapper
- use [[UniFFI]] for rust->swift bindings

