# RTL for Claude Desktop

Right-to-left text direction for **Claude Code in the Claude desktop app**. Hebrew, Arabic and Persian replies are laid out right to left, while English, code and math stay left to right.

[English](README.md) · [עברית](README.he.md)

## Features

- **Smart direction detection.** A block is RTL when its first strong character is RTL, after skipping a leading filename, URL, path or inline code. If that test says LTR, the block is still RTL when it holds more RTL letters than Latin ones.
- **Paragraphs** that open with `index.js`, a command or an English term still read right to left.
- **Mixed paragraphs.** An English line inside a Hebrew paragraph, or the reverse, keeps its own reading order.
- **Lists** take their direction from all their items, not just the first one.
- **Tables** take their direction from a majority vote over the header row and first column. Each cell is laid out in its own direction.
- **Inline code, math and LaTeX** (`2 + 3 = 5`, `$x^2$`) are kept left to right inside RTL text, so they don't get mirrored.
- **Code blocks** are never touched.
- **Your own messages** are fixed too.
- **`/rtl`** turns the fixes on and off. The setting is remembered across sessions.

## Install

In Claude Code:

```
/plugin marketplace add xShakedDev/RTL-For-Claude-Desktop
/plugin install smart-rtl@smart-rtl
```

Or from a terminal:

```sh
claude plugin marketplace add xShakedDev/RTL-For-Claude-Desktop
claude plugin install smart-rtl@smart-rtl
```

The plugin uses Claude Code's function-hook plugin API, which is in early access. It was tested with Claude Code 2.1.289.

## How it works

A plugin can't change the app's CSS or set `dir` attributes. Instead, it rewrites the text of each message just before it is drawn, inserting invisible Unicode bidi control characters. The text saved in your conversation is not changed.

| Character | Purpose |
| --- | --- |
| `RLM` (U+200F) at the start of a block | Makes the desktop app's built-in direction detection treat the block as RTL |
| `RLI` / `LRI` … `PDI` | Isolates a line, list item, table cell, code span or formula so it keeps its own direction |

## Limitations

- **Alignment.** Where the app has no built-in RTL detection, such as your own messages, the reading order is fixed but the text stays left-aligned.
- **Input box.** The input box isn't affected.
- **Fonts and window controls.** Custom fonts and the window title bar can't be changed by a plugin.
- **Terminal.** The terminal is left as is, because some terminals show the control characters as visible symbols.
- **Copying.** Copying a message may include the invisible control characters.

## Development

```sh
claude plugin validate .
claude plugin test .
claude --plugin-dir .
```

The detection logic lives in `hooks/rtl-core.ts`, the markdown rewriting in `hooks/transform.ts`, and the hooks in `hooks/register.tsx`.

## Credits

The detection engine is ported from [claude-desktop-rtl-patch](https://github.com/shraga100/claude-desktop-rtl-patch) by shraga100.

## License

[MIT](LICENSE)
