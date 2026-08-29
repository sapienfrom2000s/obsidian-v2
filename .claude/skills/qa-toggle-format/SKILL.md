---
name: qa-toggle-format
description: Format a list of interview/practice questions and answers into clean, collapsible Q&A blocks for an Obsidian note, using plain HTML <details><summary> toggles (question visible, answer collapsed by default). Use when the user asks to "format questions", "make answers collapsible/toggleable", "clean up a Q&A section", or references this layout for interview questions, practice questions, or FAQ-style notes.
---

# Q&A Toggle Format

Turns a raw or messy Q&A list into a clean Obsidian note where each question is a
one-line clickable toggle and the answer is hidden until expanded.

## Output shape

```markdown
## <Section Title>

<details>
<summary>1. <Question text></summary>
<Answer text, plain prose or a short list/code block as needed.>
</details>

<details>
<summary>2. <Question text></summary>
<Answer text.>
</details>
```

Rules:
- One `<details>` block per question. Keep the numbering sequential (1, 2, 3, ...) —
  fix any duplicate or skipped numbers found in the source.
- `<summary>` holds only the question (numbered), nothing else — no arrows (`->`), no
  bold, no extra markup. This is the only thing visible when collapsed.
- Answer goes directly below `<summary>` as plain text. Preserve short multi-line
  answers (numbered steps, command lists) as separate lines — don't force them into
  one paragraph.
- Escape angle brackets in inline code/commands inside the block, e.g. `<image_id>`
  becomes `&lt;image_id&gt;`, since raw `<...>` inside an HTML block can be swallowed
  as a tag.
- No callouts (`> [!question]-`), no admonition syntax, no emoji, no colored borders —
  those render as visually "busy" in Obsidian. Plain `<details>` is deliberately
  minimal.
- Leave one blank line between each `<details>` block for readability in source.
- If an answer is missing from the source, keep the block but write `(unanswered)`
  as the body rather than inventing content.

## When applying this to an existing note

1. Read the target file first.
2. Preserve the section heading (e.g. `## Interview Questions`) above the toggle list.
3. Renumber only if the source has gaps/duplicates; otherwise keep original numbering.
4. Do not alter answer content/meaning — only reformat wrapping and whitespace.
5. Write the whole file back (Write tool) rather than many small edits, since nearly
   every line changes shape.
