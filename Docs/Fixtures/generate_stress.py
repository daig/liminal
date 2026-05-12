#!/usr/bin/env python3
"""
Generate a large well-formed Liminal document that exercises a broad
slice of the spec — headings, inline complexity, lists (bullet, ordered,
task), blockquotes, fenced code blocks, pipe tables, math blocks,
comments, thematic breaks, wikilinks, autolinks, markdown links. Used as
a stress fixture for the parsing/navigation engine.

Run:
    python3 Docs/Fixtures/generate_stress.py [SECTIONS]

Defaults to 2500 sections (~1.5 MB). Output goes to
Docs/Fixtures/stress.md next to this script.
"""
import os
import sys

DEFAULT_SECTIONS = 2500


def main() -> None:
    sections = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SECTIONS
    here = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(here, "stress.md")

    lines: list[str] = []
    lines.append("---")
    lines.append("title: \"Stress Test Document\"")
    lines.append("tags: [stress, perf, fixture]")
    lines.append(f"sections: {sections}")
    lines.append("---")
    lines.append("")
    lines.append("# Liminal Stress Fixture")
    lines.append("")
    lines.append(
        f"A synthetic document with **{sections}** sections covering the "
        "headings, inline styling, lists, tables, code, math, and "
        "structural-block features of the Liminal grammar. Generated "
        "from `Docs/Fixtures/generate_stress.py`."
    )
    lines.append("")

    for i in range(sections):
        level_mod = i % 6
        # Alternate heading depths but keep h1s sparse so the section
        # outline is realistic.
        if level_mod == 0:
            depth = 1
        elif level_mod in (1, 2):
            depth = 2
        else:
            depth = 3
        lines.append("#" * depth + f" Section {i}: notes on topic {i}")
        lines.append("")

        # Always a body paragraph with rich inline complexity.
        lines.append(
            f"Paragraph {i} introduces *emphasis*, **strong text**, "
            f"~~strikethrough~~, and ==highlight==. It includes an "
            f"inline `code span {i}`, a [labeled link]"
            f"(https://example.com/page/{i}), a wikilink to "
            f"[[topic-{i}]], an autolink <https://auto.example/{i}>, "
            f"and a backslash-escaped \\* asterisk."
        )
        lines.append("")

        # Bullet + task list every other section.
        if i % 2 == 0:
            lines.append(f"- Bullet item {i}.a with *italic*")
            lines.append(f"- Bullet item {i}.b with **bold**")
            lines.append(f"- [ ] Task {i} unchecked")
            lines.append(f"- [x] Task {i} done")
            lines.append("")

        # Ordered list every third section.
        if i % 3 == 0:
            lines.append(f"1. Step {i}.1 — start here")
            lines.append(f"2. Step {i}.2 — continue")
            lines.append(f"3. Step {i}.3 — finish")
            lines.append("")

        # Blockquote every fourth.
        if i % 4 == 0:
            lines.append(f"> Quote {i} drawn from [[source-{i}]],")
            lines.append(f"> continued across a second line with `code`.")
            lines.append("")

        # Fenced code block every fifth.
        if i % 5 == 0:
            lines.append("```swift")
            lines.append(f"func compute_{i}() -> Int {{")
            lines.append(f"    let base = {i}")
            lines.append(f"    return base * base + {i % 7}")
            lines.append("}")
            lines.append(f"let result_{i} = compute_{i}()")
            lines.append("```")
            lines.append("")

        # Pipe table every seventh.
        if i % 7 == 0:
            lines.append("| Column A | Column B | Column C |")
            lines.append("| -------- | -------- | -------- |")
            lines.append(f"| row{i}.a1 | row{i}.b1 | row{i}.c1 |")
            lines.append(f"| row{i}.a2 | row{i}.b2 | row{i}.c2 |")
            lines.append(f"| row{i}.a3 | row{i}.b3 | row{i}.c3 |")
            lines.append("")

        # Math block every eleventh.
        if i % 11 == 0:
            lines.append("$$")
            lines.append(f"E_{i} = \\sum_{{n=0}}^{{{i}}} \\frac{{1}}{{n!}}")
            lines.append("$$")
            lines.append("")

        # Block comment every thirteenth.
        if i % 13 == 0:
            lines.append(f"<!-- generator note: section {i} marker -->")
            lines.append("")

        # Thematic break every nineteenth.
        if i % 19 == 0:
            lines.append("---")
            lines.append("")

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
        f.write("\n")
    size = os.path.getsize(out_path)
    print(f"wrote {sections} sections to {out_path} ({size:,} bytes, "
          f"{size / 1024:.1f} KiB)")


if __name__ == "__main__":
    main()
