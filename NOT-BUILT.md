# Not built yet

What is left of ROADMAP.md, MAIL-PLAN.md and TRY-TOMORROW.md, checked against the code at
a486985 (2026-11-20; the Mail rows re-checked after the day's Mail keys, filing and snooze work). Sizes come from ROADMAP.md: S small, M medium, L large.
"Needs first" names what must happen before work starts. "—" means nothing.

## Count

| Group | Built | Partly built | Not built |
|---|---|---|---|
| Stage 1: select, press, fix it | 10 | 2 | 0 |
| Stage 2: the text catalogue | 1 | 1 | 0 |
| Stage 3: text on the shelf | 0 | 0 | 5 |
| Stage 4: snippets | 1 | 0 | 0 |
| Stage 5: translate | 0 | 0 | 1 |
| Stage 6: links and the web | 0 | 0 | 6 |
| Stage 7: more actions | 0 | 0 | 6 |
| Stage 8: images, colour and media | 0 | 0 | 6 |
| Stage 9: files, PDFs and detection | 0 | 0 | 6 |
| Stage 10: capture, services and power tools | 0 | 1 | 6 |
| Outside the stages (C12, C13, E6, F5, H10, I4, I5) | 6 | 1 | 0 |
| Mail leftovers (MAIL-PLAN, ROADMAP I5 list) | 0 | 0 | 2 |
| Text tools on files and syntax highlighting (C14, C15) | — | — | 2 |
| Vim features (C16–C43) | 28 | 0 | 0 |
| Reminders and Notes keys (I6, an idea) | — | — | 1 |
| **Total** | 46 | 5 | 41 |
| Won't build: the Edit window surviving a relaunch (C44) | — | — | 1 |
| Edit window, different from vim (TRY-TOMORROW) | — | — | 6 |

## Stage 1: select, press, fix it

Built: B1, B2, B3, B4, B5, B7, C1, C2, C4, C7 sub-wheels.

Partly built:

| Id | What is missing | Size | Needs first |
|---|---|---|---|
| B6 | OpenShelf's own undo works (last 10 changes, in memory). Missing: the setting that keeps nothing, and the one that keeps them on disk. | S | — |
| C3 | Convert text works for JSON, YAML, EDN, XML and TOML (`TextSniffer`). Missing for text: CSV and plist. Files already convert both (`Convert/DataConversion.swift`). | S | — |

## Stage 2: the text catalogue

Built: C7 recent first and favorites; every "Left in Stage 2" group (Cleanup, Encode and
decode, Extract, Count, Hash, Dates, Wrap, Markdown, Generate).

Partly built:

| Id | What is missing | Size | Needs first |
|---|---|---|---|
| C6 | Join and split work only on commas and spaces: no separator you choose. No add a prefix or suffix. No "lines matching a pattern" in Extract. | S each | A way to type the separator, prefix or pattern (a small prompt) |

## Stage 3: text on the shelf

| Id | What it is | Size | Needs first |
|---|---|---|---|
| A1 | Drop text on a shelf; it becomes a text item. `ShelfDropView` takes file URLs only. | M | Decide: does a dragged link arrive as text or as a link (D1) |
| A2 | Drag a text item out as text, not as a file. | S | A1; a test of how Mail, Notes, Safari, Slack and VS Code pick between text and file |
| A3 | New shelf item from the clipboard. | S | A1 |
| A4 | Pin a text item: copied, not moved, when dragged out. | S | A2 |
| A5 | Text History shelf: originals of recent text changes as items to drag back. | S | A1; B6 keeps history in memory today |

## Stage 4: snippets

Built: C8.

## Stage 5: translate

| Id | What it is | Size | Needs first |
|---|---|---|---|
| C5 | Translate selected text on the device. | M | Apple's language downloads (the system asks per language) |

## Stage 6: links and the web

| Id | What it is | Size | Needs first |
|---|---|---|---|
| D1 | Drop a link on a shelf; it becomes a link item with wedges. | M | A1 |
| D2 | Drop web images and promised files (`NSFilePromise`). | M | A1 |
| D3 | Save a web page's article as Markdown. | M | D1; the network |
| D4 | Download media from a link. | M | D1; yt-dlp installed through the tool installer |
| E1 | Make a QR code from text or a link. | S | — |
| C6 on links | Remove tracking parameters from dropped links. The text tool exists (Fix › Strip Tracking). | S | D1 |

## Stage 7: more actions

| Id | What it is | Size | Needs first |
|---|---|---|---|
| H1 | Email it: a new Mail message with the file attached. | S | — |
| H2 | Send in Messages. | S | — |
| H3 | Open With… a chosen app. | S | — |
| H4 | Copy a file's SHA-256 or MD5; Verify against a hash on the clipboard. Text Hash exists, files have none. | S | — |
| H9 | Remove the quarantine flag. | S-M | Decide: a safety question (it skips Gatekeeper's check) |
| I1 | Run a Shortcut on an item. | S-M | — |

## Stage 8: images, colour and media

| Id | What it is | Size | Needs first |
|---|---|---|---|
| E2 | Pick a color from the screen. | S | — |
| E3 | Color palette from an image. | S | — |
| E4 | Describe an image (Vision labels and text). | S | — |
| E5 | Wi-Fi QR code. | S-M | E1 |
| F1 | Waveform image of an audio file. | S | ffmpeg (already used) |
| F2 | Contact sheet of a video. | S | ffmpeg (already used) |

## Stage 9: files, PDFs and detection

| Id | What it is | Size | Needs first |
|---|---|---|---|
| H5 | Batch rename. | M | — |
| H6 | Compare two items. | M | — |
| H7 | Find duplicates. | M | — |
| G1 | PDF page numbers, watermark, stamp. | S-M | — |
| G2 | Fake-redaction check: black boxes with text still under them. | M | — |
| C11 | Detect dates, places and people in text: Make Event, Make Contact, Open in Maps, Copy Number. | S-M | — |

## Stage 10: capture, services and power tools

Partly built:

| Id | What is missing | Size | Needs first |
|---|---|---|---|
| F3 | A Watched Folder on the screenshot folder already puts screenshots on a shelf. Missing: a shortcut that takes one. | S | Screen Recording permission may be asked |

Not built:

| Id | What it is | Size | Needs first |
|---|---|---|---|
| F4 | Screen recording. | L | Screen Recording permission |
| C9 | Text wheel during a text drag. | M | — |
| C10 | Services menu entries ("Transform with OpenShelf", "Add to Shelf"). | M | — |
| I2 | Your own scripts as wedges. | M-L | Decide: running his scripts is a safety question |
| I3 | Run an HTTP request file (`.http`). | M | — |
| H8 | Upload and copy a link. | M-L | Decide: which upload service; opt-in |

## Outside the stages

Built: C12 items 1-6 (#53), C13 (#65), F5 (#64), H10 (#57), I4 (#58, #60, #61, #62),
I5 (#59). Since 2026-11-19, proven on David's Mail: `v` / ⌃⌥M move through Mail's own Move to menu (a true move on Gmail), ⌃N/⌃P in the folder picker and as j/k, `g a` All Mail, `g A` Archive, `g T` Today, `g l` Send Later, `u` and `z` undo, Esc back to the list (after it: select none), ⇧U read ↔ unread, `e` on a double-clicked thread acting on the whole conversation. Built, not yet tried: snooze numbers (5, 2h, 3d, 2w, 2mo, 1y, any spelling), "end of month", "next month", "… from now".

Partly built:

| Id | What is missing | Size | Needs first |
|---|---|---|---|
| E6 | Clean works with a smooth fill (#67). Missing: a fill that copies nearby texture, or a LaMa model, for busy backgrounds. | M | David's yes to the model (about 100-200 MB) |

C12's "left out for now" list (marks, `:g`, `:sort`, `:normal`, `:!`, his vim config, keeping
macros) stays out by choice.

## Text tools on files

ROADMAP.md:220 says every text tool works on a selection and on a text file or shelf item.
Only the selection is built. A text or source file reaches the file wheel, not the text wheel:

- Finder with the hotkey: `Text/HotkeyRouting.swift:40` `if frontmostBundleID == finderBundleID { return .finder }`
  opens `openWheelForFinderSelection()` (`App/AppDelegate.swift:174`). A shelf selection and a
  drag onto the wheel use the same file wheel. Its items come from `App/AppDelegate.swift:248-250`
  (Convert formats, `FileTool.available`, Actions).
- Tools: `Tools/FileTool.swift:209-210` gives only Pretty Print, and only when a formatter for the
  extension is installed (`Tools/PrettyPrint.swift:33-52`: js, ts, json, md, css, html, yaml, clj,
  edn, py, sh, swift, xml, sql, C, go, rs). Pretty Print writes "name.formatted.ext" beside the
  file. `.txt` gets no tools.
- Convert: `.txt` and `.md` become PDF, DOCX, HTML and the like; JSON and YAML convert between
  data formats (`Convert/DataConversion.swift:12-13`).
- The text wheel opens only on text read from an app (`App/AppDelegate.swift:144`,
  `SelectedTextController.open(_:from:in:at:)` at `Text/SelectedTextController.swift:74`).
  So no Trim, Lines, Case, Indent, Stage 2 tool, live preview, Edit window or `:s` runs on a file.

| Id | What it is | Size | Needs first |
|---|---|---|---|
| Text tools on files (ROADMAP C14) | A "Text" entry in the file Tools wheel for text and source files that opens the text wheel on the file's text (UTF-8 only, size cap, binary refused). Changes save as a copy beside the file ("name Sorted.ext"), as other tools do, so no undo is needed. Reports (Count, Hash) show a toast. The live preview works as is. The Edit window would need a Save to a copy. Snippets do not apply. | M | Decide: copy beside the file (as every tool does today) or change it in place (then it needs an undo) |

### Editing a file in place: a safe design (not built)

Today Edit in the file Tools wheel is the image editor (`Tools/FileTool.swift:8`). The text
Edit window only puts text back into an app or on the clipboard; "nothing is written to disk"
(`Text/SelectedTextController.swift:201-202`).

- Open: read the file's bytes. Refuse a file with NUL bytes or one that won't decode, and one
  over a size cap (for example 2 MB). Remember the encoding (UTF-8, with or without BOM,
  UTF-16), the line ending (LF, CRLF, CR), whether it ends with a newline, and its size, date
  and hash.
- Edit with plain LF lines. ⌘W, `:q!` or the close button leaves the file untouched.
- ⌘↩ or `:w`: if the file changed on disk since it opened (size, date or hash differ), stop and
  say so. Otherwise put back the same line ending, final newline and encoding, and write
  atomically (`Data.write(to:options: .atomic)`), keeping the file's permissions. Do nothing if
  the text is unchanged.
- Undo: before writing, copy the old bytes to Application Support (last 10 files, cleared on
  quit, like `TextHistory`). The toast and the menu bar offer Undo. Undo writes the old bytes
  back only if the file still has the hash OpenShelf wrote; if not, it says the file has changed
  since and leaves it.
- One-shot tools (Sort, Case, Trim…) use the same read, write and undo steps without the
  window. The live preview shows the result first.
- Edge to watch: the Edit window turns U+2028 into line breaks when the text also has Return
  paragraphs (TRY-TOMORROW), so in-place writes must skip that change or refuse such files.
- Size: M for one-shot tools plus undo; M for the Edit window on top. Needs David's choice of
  in place (this design) or a copy beside the file.

### Syntax highlighting (ROADMAP C15)

| Id | What it is | Size | Needs first |
|---|---|---|---|
| C15 | Color the Edit window's text by file type when editing a file, with tree-sitter (chosen 2026-11-19). | M | C14; the spike (size, speed) and a security read of each grammar; open question: also for selected text |

## Reminders and Notes keys (ROADMAP I6)

An idea, not designed: single keys in Reminders and Notes in the style of the Mail keys. Needs
a read-only check of each app's menus and Accessibility first. Size M-L, a guess.

## Mail leftovers

| Item | What it is | Size | Needs first |
|---|---|---|---|
| Command palette | Type to run any of Mail's menu actions (ROADMAP I5 list). | M | Decide: wanted at all |
| `n` / `p`, next and previous in a conversation | Moving between the messages of one conversation in the reading pane. j/k (and ⌃N/⌃P) from a conversation's message move the message list instead; Mail has no direct command. (`* n` is built; `u` is undo since 2026-11-20 and Esc goes back to the list.) | S | David's decision |

## Vim: related features

Every not-built and partly-built row below is on the roadmap as C16–C43 (ROADMAP.md); the Edit window surviving a relaunch (C44) is won't build (David, 2026-11-20: "i think this is too much of an edge case to worry about").

Checked against the engine at 6833d73 by running each key sequence (2026-11-20). "Built" means
it matches vim --clean where vim has it. Ordered by what David's Doom setup has: Doom's
`:editor evil` module (`~/.config/emacs/sources/doom+/modules/editor/evil/packages.el` and
`config.el:640-682`) plus his own `~/.doom.d/config.el`. He has no lispy, parinfer,
evil-cleverparens or targets (`~/.doom.d/init.el:61,64`); smartparens is on, with `s-R` raise sexp
(`config.el:455`).

### In his Doom setup

| Feature | State | Note | Size |
|---|---|---|---|
| Surround: `ys` `yss` `cs` `ds`, visual `S`, tags (`cst<b>`, `ysiw<em>`), `.` | Built | evil-surround's spacing: an opening bracket adds spaces | — |
| Surround a function call, `ysiwf` | Built | Also `ysiw⌃F` for `(foo x)`, `dsf`, `ds⌃F` and `csf`, as embrace in Doom | — |
| `i(` `i[` `i{` `ib` `iB` `i<` `it` and `a…`, counts | Built | Cross lines; seek forward on the line as vim 9 does | — |
| `i"` `i'` `` i` `` and `a…` | Built | One line only, as vim; escaped quotes skipped | — |
| `iq` / `aq`, any quote (Doom) | Built | The smallest quoted text of any kind, as Doom's anyblock picks it | — |
| `ia` / `aa`, argument (evil-args) | Built | Only `,` and `;` split, as in evil-args, so a Clojure form is one argument | — |
| `ii` / `ai`, indent level (evil-indent-plus; also `ij` `ik`) | Built | With evil-indent-plus's quirks: `dii` leaves an empty line | — |
| `ig` / `ag`, whole buffer (Doom) | Built | | — |
| `if` / `af`, function (Doom defun) | Built | Whole lines and one blank line after, as Doom; Lisp text by top-level form, other text by indentation | — |
| `ic` / `ac`, comment (evil-nerd-commenter) | Built | Comments over several lines make a block, as in Doom | — |
| `iu` url, `ix` XML attribute (exato) | Built | A URL needs a scheme, as in Emacs | — |
| `iB` / `aB` any block (anyblock) | Built | Doom's meaning (David, 2026-11-21): the nearest of `( ) { } [ ] < >`; `i{` is `{ }` | — |
| Comment: `gcc`, `gc{motion}`, visual `gc` (evil-nerd-commenter) | Built | Comment string guessed from the text (`;;` Lisp, `--` SQL, `//`, else `#`) | — |
| evil-snipe: `s`/`S` two-character find, `;` `,` | Built | Doom's way (David, 2026-11-21): `s` `S` and `f` `t` `F` `T` are evil-snipe's; vim's `s` `S` are `cl` `cc` | — |
| evil-exchange `gx` / `gX` | Built | Not on visual blocks; a change between drops the mark | — |
| evil-lion `gl` / `gL` align | Built | On a character, or a pattern after `/`; Return (the mode's own rules) not built | — |
| evil-numbers `⌃A` `⌃X` | Built | Visual `⌃A` and `g⌃A` (increasing) too; Doom's own `g=` `g-`, visual `g=` `g-` `g+` | — |
| evil-visualstar: `*` `#` on a visual selection | Built | From the cursor, as Doom: `viw#` finds the word itself first | — |
| evil-escape `jk` | Built | | — |
| `⌥J` / `⌥K` move lines (his `config.el`) | Built | | — |
| evil-multiedit: visual `R`, `M-d` / `M-D` (his `config.el:738-759`) | Built | `M-d` is `⌥D`; in the regions `C` `D` `⌃N` `⌃P` Return, Esc to leave, `c` as usual | — |
| Slurp, barf, raise (`s-R` sp-raise-sexp) | Built | His keys: `⌃L` `⌃H` slurp, `⌃J` `⌃K` barf (`~/.doom.d/config.el:821-824`), `⌘⇧R` raise (`:456`); lines are not re-indented | — |

### Vim itself

| Feature | State | Note | Size |
|---|---|---|---|
| `iw` `aw` `iW` `aW` `ip` `ap` | Built | | — |
| `is` / `as` sentence | Built | evil's, with Doom's one space after a period | — |
| `gu` `gU` `g~` (and `guu` `gUU` `g~~`) | Built | | — |
| `=` re-indent (`==`, `=ip`) | Built | Through the Text wheel's Re-indent formatter (cljfmt for Clojure), so both agree | — |
| `%` matching bracket | Built | | — |
| `*` `#` `n` `N` `/` `?` | Built | Matches highlighted while typing and after, until `:noh` or Esc (C35) | — |
| `gn` / `cgn` | Built | `cgn` then `.` changes match after match | — |
| `f` `t` `F` `T` with `;` `,` | Built | evil-snipe's since C26 | — |
| Marks `m{a-z}`, `'` and `` ` `` | Built | They move with the text, as evil's markers | — |
| Registers `"a`–`"z`, `"A` append, `"+` `"*` `"_` `"0` | Built | | — |
| `:s` | Built | Gaps in "Edit window, different from vim" below | — |
| `:g` `:norm` `:sort` `:m` `:t` `:d` with ranges | Built | Also `:v`, `:co`; `:sort` takes `!` `i` `u`, as evil's | — |
| Counts on motions, operators, objects, `.`, `p`, `⌃A` | Built | | — |
| `.` repeat | Built | Not after visual-mode changes | — |
| `zz` `zt` `zb`, `H` `M` `L`, `⌃D` `⌃U` `⌃E` `⌃Y` | Built | Also `z.` `z-` `z↩`; Doom's `⌃U` scrolls (evil-want-C-u-scroll) | — |
| `⌃O` / `⌃I` jump list, `g;` change list, `gi` | Built | Also `''` and `` `` ``; Tab is `%`, as in Doom | — |
| `gv`, `o` in visual, `⌃V` block, `R` | Built | | — |
| `gJ`, `gp`, `ga`, `[(` `])` | Built | `gp` is Doom's: select the last paste again; visual `gp` pastes without keeping what it replaced | — |
| Undo `u`, redo `⌃R` | Built | A line of undo, as David's Doom has it (undo-fu, `~/.doom.d/init.el:73`, no tree); `g-` is Doom's evil-numbers | — |
| Macros `q` `@` `@@` | Built | Not kept between windows; `@:` built (C43) | — |

Found while checking on 11-20 and since fixed: `cgn`, `=ip`, `ma` and `gcc` are built (C36, C34,
C37, C25); unbuilt commands read all their keys and say "not built".

## Edit window, different from vim

From TRY-TOMORROW "Not built, or different from vim". All S.

- `:s` lacks the `c` flag, `~` in a replacement, `\u` `\l` `\U` `\L` and `\v`.
- `.` does not repeat visual-mode changes.
- `R` ignores Return, and Backspace in `R` drops its count.
- Visual block and `j`/`k` count tabs as one column.
- `J` and `gq` put one space after a period (vim: two); `gq` keeps the first line's indent.
- Shift-Return breaks become plain line breaks when the text also has Return paragraphs.

Known limits, not features: the live preview's UUID and password differ from the result,
Clean's fill smears on detail, and the shelf-focus test fails when another app is in front.
