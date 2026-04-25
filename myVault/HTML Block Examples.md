# HTML Block Examples

Some normal markdown paragraph text before the HTML blocks.

## Basic Formatting

<div style="font-size: 15px; line-height: 1.8;">
This is a div with <b>bold</b>, <i>italic</i>, <u>underline</u>, and <s>strikethrough</s> text.
Also <em>emphasis</em>, <strong>strong</strong>, and <code style="background-color: #2d2d2d; color: #e06c75; padding: 2px 6px;">inline code</code>.
Plus <span style="font-variant: small-caps;">small caps</span> and <span style="letter-spacing: 4px;">wide tracking</span>.
</div>

## HTML Table

<table style="border: 2px solid #4a9eff;">
<tr style="background-color: #1e3a5f;"><th style="color: #4a9eff; padding: 8px 16px;">Language</th><th style="color: #4a9eff; padding: 8px 16px;">Year</th><th style="color: #4a9eff; padding: 8px 16px;">Typing</th></tr>
<tr style="background-color: rgba(255,255,255,0.03);"><td style="padding: 6px 16px;"><b>Python</b></td><td style="padding: 6px 16px;">1991</td><td style="padding: 6px 16px;">Dynamic, strong</td></tr>
<tr><td style="padding: 6px 16px;"><b>Rust</b></td><td style="padding: 6px 16px;">2015</td><td style="padding: 6px 16px;">Static, strong</td></tr>
<tr style="background-color: rgba(255,255,255,0.03);"><td style="padding: 6px 16px;"><b>JavaScript</b></td><td style="padding: 6px 16px;">1995</td><td style="padding: 6px 16px;">Dynamic, weak</td></tr>
</table>

## Multi-Column Table with Alignment

<table>
<tr style="background-color: #2a1a3a;"><th style="color: #c084fc; padding: 8px 12px;">Status</th><th style="color: #c084fc; padding: 8px 12px;">Feature</th><th style="color: #c084fc; padding: 8px 12px; text-align: right;">Priority</th></tr>
<tr><td style="padding: 6px 12px;"><span style="color: #22c55e;">&#9679;</span> Done</td><td style="padding: 6px 12px;">Block parsing</td><td style="padding: 6px 12px; text-align: right;">P0</td></tr>
<tr><td style="padding: 6px 12px;"><span style="color: #22c55e;">&#9679;</span> Done</td><td style="padding: 6px 12px;">NSTextView rendering</td><td style="padding: 6px 12px; text-align: right;">P0</td></tr>
<tr><td style="padding: 6px 12px;"><span style="color: #eab308;">&#9679;</span> In Progress</td><td style="padding: 6px 12px;">CSS class support</td><td style="padding: 6px 12px; text-align: right;">P1</td></tr>
<tr><td style="padding: 6px 12px;"><span style="color: #ef4444;">&#9679;</span> Todo</td><td style="padding: 6px 12px;">Inline HTML</td><td style="padding: 6px 12px; text-align: right;">P2</td></tr>
</table>

## Nested Lists with Styling

<ul style="line-height: 1.8;">
<li><span style="color: #60a5fa; font-weight: bold;">Parsing</span>
  <ul>
    <li>CommonMark types 1-7</li>
    <li>Multi-line accumulation</li>
    <li style="color: #9ca3af;"><i>Future: inline HTML</i></li>
  </ul>
</li>
<li><span style="color: #34d399; font-weight: bold;">Rendering</span>
  <ul>
    <li>NSAttributedString from HTML</li>
    <li>NSTextView for layout (tables, lists)</li>
  </ul>
</li>
<li><span style="color: #f472b6; font-weight: bold;">Editor</span>
  <ul>
    <li>Syntax highlighting <span style="background-color: #831843; color: #f9a8d4; padding: 1px 6px;">pink theme</span></li>
  </ul>
</li>
</ul>

## Links and Colored Text

<p style="line-height: 2;">
Visit <a href="https://developer.apple.com" style="color: #60a5fa; font-weight: bold;">Apple Developer</a> for docs.
Here is <span style="color: #ef4444;">red</span>,
<span style="color: #f97316;">orange</span>,
<span style="color: #eab308;">yellow</span>,
<span style="color: #22c55e;">green</span>,
<span style="color: #3b82f6;">blue</span>,
<span style="color: #a855f7;">purple</span> text.
And <span style="background-color: #854d0e; color: #fde68a; padding: 2px 8px;">highlighted</span> with background.
</p>

## Blockquote and Preformatted

<blockquote style="border-left: 4px solid #6366f1; padding-left: 16px; color: #a5b4fc;">
<p style="font-size: 1.1em; font-style: italic;">The best way to predict the future is to invent it.</p>
<p style="font-size: 0.9em; color: #818cf8;">— Alan Kay</p>
</blockquote>

<pre style="background-color: #1e1e2e; color: #cdd6f4; padding: 12px 16px; font-family: Menlo, monospace; font-size: 13px; line-height: 1.5;">
<span style="color: #cba6f7;">struct</span> <span style="color: #89b4fa;">Point</span> {
    <span style="color: #cba6f7;">let</span> x: <span style="color: #89b4fa;">Double</span>
    <span style="color: #cba6f7;">let</span> y: <span style="color: #89b4fa;">Double</span>

    <span style="color: #cba6f7;">var</span> magnitude: <span style="color: #89b4fa;">Double</span> {
        (x * x + y * y).<span style="color: #89dceb;">squareRoot</span>()
    }
}
</pre>

## Definition-Style Layout

<dl style="line-height: 1.8;">
<dt style="color: #60a5fa; font-weight: bold; font-size: 1.05em;">Obsidian</dt>
<dd style="margin-left: 20px; margin-bottom: 8px;">A knowledge base that works on local Markdown files. <span style="color: #9ca3af; font-size: 0.9em;">(Electron-based)</span></dd>
<dt style="color: #34d399; font-weight: bold; font-size: 1.05em;">Liminal</dt>
<dd style="margin-left: 20px; margin-bottom: 8px;">A native macOS personal knowledge base inspired by Obsidian. <span style="color: #9ca3af; font-size: 0.9em;">(SwiftUI/AppKit)</span></dd>
<dt style="color: #f472b6; font-weight: bold; font-size: 1.05em;">Roam Research</dt>
<dd style="margin-left: 20px;">A note-taking tool for networked thought. <span style="color: #9ca3af; font-size: 0.9em;">(Web-based)</span></dd>
</dl>

## Heading Tags

<h3 style="color: #c084fc; border-bottom: 1px solid #4c1d95; padding-bottom: 4px;">This is a styled h3 via HTML</h3>

<p>And a paragraph with <sup style="color: #f97316;">superscript</sup> and <sub style="color: #22d3ee;">subscript</sub> text, plus <span style="text-decoration: underline wavy #ef4444;">wavy underline</span> and <span style="text-decoration: overline #3b82f6;">overline</span>.</p>

## Comment Block

<!-- This is an HTML comment and should be parsed as an HTML block -->

## Horizontal Rule

<hr style="border: none; border-top: 2px dashed #4a9eff; margin: 16px 0;">

## Admonition-Style Boxes

<div style="border-left: 4px solid #3b82f6; background-color: rgba(59, 130, 246, 0.08); padding: 10px 14px; margin-bottom: 10px;">
<b style="color: #60a5fa;">&#9432; Info</b><br>
NSAttributedString HTML rendering supports inline styles, tables, lists, and basic CSS properties. Each HTML block is rendered independently.
</div>

<div style="border-left: 4px solid #22c55e; background-color: rgba(34, 197, 94, 0.08); padding: 10px 14px; margin-bottom: 10px;">
<b style="color: #4ade80;">&#10003; Success</b><br>
Block-level HTML parsing is working with CommonMark types 1-7. Tables render with full structure via NSTextView.
</div>

<div style="border-left: 4px solid #f97316; background-color: rgba(249, 115, 22, 0.08); padding: 10px 14px; margin-bottom: 10px;">
<b style="color: #fb923c;">&#9888; Warning</b><br>
Style blocks are parsed as type-1 HTML blocks (<code>&lt;style&gt;</code>). CSS classes defined in one block won't carry to the next since each block renders independently.
</div>

<div style="border-left: 4px solid #ef4444; background-color: rgba(239, 68, 68, 0.08); padding: 10px 14px;">
<b style="color: #f87171;">&#10007; Danger</b><br>
JavaScript is completely disabled. Interactive elements like <code>&lt;details&gt;</code>, <code>&lt;input&gt;</code>, and <code>&lt;canvas&gt;</code> will not function.
</div>

## Inline Styles Stress Test

<p>
<span style="font-size: 24px; font-weight: bold; color: #f59e0b;">Large bold gold</span><br>
<span style="font-size: 11px; color: #6b7280; letter-spacing: 3px; text-transform: uppercase;">tiny spaced uppercase gray</span><br>
<span style="font-family: Georgia, serif; font-style: italic; font-size: 16px; color: #a78bfa;">Serif italic in purple</span><br>
<span style="font-family: Menlo, monospace; font-size: 13px; color: #2dd4bf; background-color: #042f2e; padding: 2px 6px;">monospace teal on dark</span>
</p>

## Mixed with Markdown

Normal markdown continues here. **Bold markdown** and *italic markdown* work fine after HTML blocks.

- Regular markdown list
- Still works after HTML
