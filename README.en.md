# Nativ Pro

[Русский](README.md) | **English**

**A Pixelmator Pro alternative for macOS: a layer-based photo editor written in Swift (AppKit + Metal).**

> 🚧 **Work in progress.** This is an early version: the interface and the core are in place, but most tools
> (brushes, selections, text, adjustments) do not work yet. Not ready for everyday use: expect bugs, and the file
> format may still change.

> The idea, plan and architecture are the author's. The code was written by **vibe coding** with the AI tool
> **[Claude Code](https://claude.com/claude-code)** (Anthropic).

## What it is

Nativ Pro is a Pixelmator Pro alternative: a professional photo editor for macOS with the same layout and workflow.
Layers on the left, canvas in the middle, tool options and the tool strip on the right.

The project is at an **early stage**. The interface and the core engine are in place, and the painting and
adjustment tools are being wired up one by one.

### Working now

- **Layered documents.** Bitmap layers, groups, masks, opacity, 28 blend modes, undo/redo history.
- **Own `.pedoc` format.** A zip package with an SQLite database and pixel tiles (8 and 16 bits per channel), plus
  a Finder preview. Unmodified images are stored as the original file, without re-encoding.
- **Rendering.** Metal for the window, CPU as a reference for tests. Tests compare the output of the two renderers.
- **Editor window.** Layers panel (drag, rename, visibility), zoomable canvas, a strip of 21 tools with their option
  panels, and a title bar with zoom and quick actions.
- **Menus in Russian and English** with keyboard shortcuts. The language follows the system.
- **Files.** Opens PNG, JPEG, HEIC, TIFF, GIF and WebP. Exports PNG, JPEG, TIFF and HEIC. Paste from clipboard,
  import images as layers, autosave.
- **`pe` command-line tool** for the core: rendering, speed and memory benchmarks on large documents, PNG diff.

### In progress

Brushes, fill, eraser, selections, text, shapes, crop, color adjustments and effects. Their panels exist, and the
operations themselves are being added stage by stage.

## Building

Requires **macOS 26** and **Xcode 26** (Swift 6).

```bash
git clone https://github.com/Vitaliy-vibe/nativ-pro.git
cd nativ-pro
./tools/build_app.sh            # build .build/app/PhotoEditor.app and launch it
./tools/build_app.sh --no-run   # build only
swift test                      # tests
```

The core (`EditorCore`, `EditorApp`, `pe`) also builds and passes its tests on Linux. The AppKit window is
macOS-only.

## Architecture

| Module | Contents |
|---|---|
| `EditorCore` | document model, tiles, history, PNG, `.pedoc` format, reference CPU renderer |
| `EditorRenderMetal` | Metal and Core Image renderer |
| `EditorApp` | window logic without AppKit: menus, commands, zoom (covered by tests) |
| `PhotoEditor` | the macOS app (AppKit) |
| `pe` | command-line tool for the core |
| `CSQLite`, `CZlib` | bundled SQLite and system zlib |

## How it was made

The idea, plan and architecture are the author's: what to build, how it should look and work, in what order, and
when it counts as done. The author leads the project and makes every decision.

The code was written by vibe coding: the AI tool Claude Code wrote it following the author's plan. It also:

- wrote the tests and scripts;
- built and launched the app on a Mac;
- checked window sizes and spacing to the point against Accessibility measurements and screenshots.

Development started in October 2026.

## Author

Vitaliy ([Vitaliy-vibe](https://github.com/Vitaliy-vibe)): idea, plan, architecture, development.

## License

[GNU GPL v3.0](LICENSE). You are free to use, study, modify and share the code. Software based on it must also be
distributed under GPL-3.0 with its source code.

The bundled SQLite (`Sources/CSQLite`) is in the public domain.

Pixelmator Pro is a trademark of Apple Inc. Nativ Pro is an independent project, not affiliated with or endorsed
by Apple. No Pixelmator Pro code, icons or images are used.
