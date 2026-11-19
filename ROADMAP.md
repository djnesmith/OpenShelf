# Roadmap

Planned features for this fork and the order to build them in. Nothing here is built yet
unless it is marked **exists**. File references are to `djnesmith` at `8cd7c70`.

## What OpenShelf does today

OpenShelf is a menu-bar app with floating shelves. You drop **files** on a shelf. While you
drag files, or select shelf items, or press the hotkey (default ⌃⌥Space) with files selected
in Finder, a wheel appears. There are three wheels: Convert, Tools and Actions
(`Wheel/WheelItem.swift` `WheelKind`). What each wheel offers depends on the kind of file
(`Convert/FileKind.swift` `FileKind`). Results go back to the shelf the file came from
(`Shelf/ShelfConversionTarget.swift`).

A wheel shows at most **7 wedges**. With more than 7 items it pages: 6 items and a More wedge
per page (`Wheel/WheelPaging.swift` `slotCount`, `itemsPerPage`). The Convert wheel lists at
most 12 formats (`Convert/OutputFormat.swift` `ConversionCatalog.maxWedges`). There are no
sub-wheels today.

### What it does with text today

Almost nothing:

- **Dropped text, links and web images are ignored.** Every drop target reads file URLs
  only: `Shelf/ShelfDropView.swift` (`registerForDraggedTypes([.fileURL])`),
  `Wheel/WheelController.swift` `WheelDropView`, `Shelf/EdgeTab.swift`, and the drag watcher
  `DragDetection/DragMonitor.swift` `isDraggingFiles`.
- **Dragging out writes only the file URL** (`Shelf/Views/DragSourceArea.swift`,
  `NSDraggingItem(pasteboardWriter: item.url as NSURL)`).
- **The clipboard is only written**, by Copy Path and Copy Name (`Support/FileActions.swift`
  `copyText`). Nothing reads it.
- **No Services menu entries** (no `NSServices` in `Support/Info.plist`).
- **Shortcuts actions take and return files only** (`Intents/FileIntents.swift`).
- **Text files** (`.txt`, `.md`) get Convert formats (PDF, DOCX, TXT, MD, EPUB, HTML, RTF), but
  **no Tools** (`Tools/FileTool.swift` `FileTool.available(for:tools:)`). Only formats that
  Pretty Print knows get a tool.
- **The hotkey works on files only**: shelf selection first, then Finder's selection
  (`App/FinderSelection.swift` `WheelSelectionSource.choose`,
  `App/AppDelegate.swift` `openWheelForSelection`, `openWheelForFinderSelection`).

### Permissions today

- The hotkey uses Carbon `RegisterEventHotKey` (`App/GlobalHotKey.swift`).
- The drag watcher uses `NSEvent` global mouse monitors (`DragDetection/DragMonitor.swift`).
- The code comments say neither needs Accessibility or Input Monitoring. Not yet tested by
  turning both off.
- Automation (Apple Events) is used for Finder's selection and for Pages, Numbers and Keynote.

## Decisions already made

1. **Accessibility permission is fine.** It is our own app.
2. **Firefox and Electron gaps do not matter.** Ideas that miss them are still in.
3. **One hotkey (⌃⌥Space)** decides what to do from what is in front (see B2).
4. **Selected text is treated as a file.** It is saved to a temporary file, so every existing
   wheel, converter and formatter works on it unchanged (see B1).
5. **Write back by paste, not by an Accessibility write.** A paste lands on the app's own undo
   stack (see B5).
6. **Proposed, David to confirm:** a text tool **replaces the selection** by default. Holding
   ⌥ when picking copies the result instead. Holding ⇧ puts a file on a shelf.
7. **Translation is on-device.** Apple's Translation framework, no web service.
8. **Nothing is sent to third-party services.** The only network use is fetching a page or
   media the user asked for, or downloading a translation language.

## Ideas

Size: **S** = a tool or action on an existing wheel. **M** = a new wheel, drop type or window.
**L** = new permission or new architecture.

### A. Text on the shelf

**A1. Drop text on a shelf** (M)
- Drag selected text onto a shelf. It becomes a text item you can drag out again or run
  through the wheels.
- Builds on `ShelfDropView` `fileURLs(in:)` and `Shelf.add(_:)`. `ShelfItem` holds a `url`,
  so the text is written to a file (`.txt`, or `.md`, `.json`, … by sniffing the content) in
  Application Support and added.
- New: `.string` and `.rtf` drop types on the three drop targets.
- Permissions: none.
- Risk: naming and clean-up of the saved files. Decide whether a dragged link arrives as text
  or as a link (see D1).

**A2. Drag a text item out as text** (S)
- Drag a text item into a text field, chat box or email body. Its text lands there, not an
  attached file. ⌥-drag attaches the file instead.
- Builds on `DragSourceView` in `Shelf/Views/DragSourceArea.swift`: write a pasteboard item
  with both `.string` and `.fileURL`.
- Permissions: none.
- Risk: **unknown** how Mail, Notes, Safari, Slack and VS Code choose when both are offered.
  Test before picking the default.

**A3. New shelf from the clipboard** (S)
- A menu-bar item (and an optional shortcut) turns the clipboard's text, image or files into
  a shelf item.
- Builds on `ShelfManager` and A1's text-to-file step.
- Skips clipboard items marked `org.nspasteboard.ConcealedType` (password managers).
- Permissions: none.

**A4. Pin a text item** (S)
- A pinned item is copied, not moved, when dragged out, and stays on the shelf for reuse.
- Builds on `ShelfStore` and A2. Merged with "custom snippets on a shelf" (C8).

**A5. Text History shelf** (S)
- The originals of recent text transforms show as text items you can drag back (see B6).

### B. Selected text with the hotkey

**B1. Selected text becomes a file** (M, the core plumbing)
1. Read the selection (B3).
2. Write it to a temporary file. Rich selections (from a browser, Mail, Pages, Word) also keep
   their HTML or RTF version.
3. Open the wheel on that file with `WheelController.presentForKeyboard(urls:at:sourceShelfID:)`.
4. When the tool writes its output: text results replace the selection (B4). File results
   (PDF, DOCX, EPUB) go to a shelf as today.

For pure-Swift tools the text stays in memory, with no temporary file, to keep it fast (B7).

**B2. One hotkey decides** (M)

The order, checked on every press of ⌃⌥Space:

| # | Situation | Result |
|---|---|---|
| 1 | A shelf has selected items | Wheel for those files (exists) |
| 2 | Finder is in front with files selected | Wheel for those files (exists) |
| 3 | Another app has selected text (Accessibility `kAXSelectedTextAttribute`) | Text wheel at the pointer |
| 4 | The cursor is in a text field and nothing is selected | Snippets wheel (C8); now open, see C8 "To settle" |
| 5 | Accessibility gave nothing | Try ⌘C; if the clipboard changes within ~200 ms, use that text as in 3, then restore the clipboard |
| 6 | None of these | Today's toast; a second press within 2 s opens Settings (exists, `RepeatedEmptyPress`) |

- The new branch goes where `openWheelForFinderSelection` today returns
  `.finderNotFrontmost`.
- A text field inside Finder (renaming) counts as text.
- A **second hotkey** opens the Snippets wheel even when text is selected, to replace a
  selection with a date (planned, David 2026-11-18; see C8).

**B3. Read the selection** (L: Accessibility)
- Accessibility first: the focused element's `kAXSelectedTextAttribute`. For Electron apps,
  first set `AXManualAccessibility` on the app.
- Fallback: post ⌘C and watch the pasteboard `changeCount`. This route also captures HTML and
  RTF, which "To Markdown" needs, so use it for rich text even when Accessibility works.
- Cap every Accessibility call with `AXUIElementSetMessagingTimeout` (about 0.25 s) so a hung
  app cannot freeze OpenShelf.
- **Password fields:** only a focused password field (Accessibility subrole
  `AXSecureTextField`: a password input in a browser, 1Password, the Passwords app) is refused,
  with a toast. Every other field and app is allowed, whatever the system-wide secure-input
  flag says (David, 2026-11-19: "everything else should be ok"); it is often left on by
  loginwindow, and the pid macOS reports for it follows the frontmost app.
- What the user sees the first time: a toast, then System Settings → Privacy & Security →
  Accessibility. They switch OpenShelf on, and may need to relaunch it. macOS updates
  sometimes reset this switch.

**B4. Put the result back** (L: Accessibility)
1. Give focus back to the app the text came from. The keyboard wheel can activate OpenShelf
   (`WheelController.takeKeyboard`), so the target app must be active again before pasting.
2. Snapshot the clipboard (every item, every type).
3. Write the result, plus the markers `org.nspasteboard.TransientType` and
   `org.nspasteboard.AutoGeneratedType`, so clipboard managers skip it.
4. Post ⌘V.
5. About 300 ms later, restore the snapshot. Skip the restore if the clipboard changed again
   in between.

- Before pasting, check that the focused element and its selection are still the ones that
  were read. If not, copy the result instead and say so.
- An Accessibility write (setting `kAXSelectedTextAttribute`) is a fallback only, for apps
  that ignore a posted ⌘V. Read the value back to confirm it worked.
- Risk: the restore is best effort. Data an app only promised, and slow apps that read the
  clipboard late, can break it.

**B5. Undo in the app** (no new code; a reason for B4's choice)
- A paste is an ordinary edit, so ⌘Z in the app should bring the original back. This is
  expected, not tested.
- An Accessibility write probably skips the app's undo stack. An old developer report says
  neither setting the value nor setting the selected text "gets picked up by Undo".
- **Must be tested in Stage 1** in TextEdit, Mail, Notes, Safari, Slack and VS Code: paste vs
  Accessibility write, then one ⌘Z.

**B6. OpenShelf's own undo** (S-M)
- Keep the last 10 transforms in memory (original, result, app, time). Cleared on quit.
- A setting keeps nothing; another keeps them on disk. Never kept from secure input or a
  secure text field.
- When the current selection equals the last result, the text wheel's first wedge is
  **Undo**: it pastes the original back.
- After a paste nothing is selected. Where the field supports `kAXSelectedTextRangeAttribute`,
  re-select the inserted range first. Otherwise offer **Copy Original**.

**B7. Speed** (no code; a budget)

Measured on the author's Mac with tiny input, best of three:

| Tool | Time |
|---|---|
| Starting any process | 7 ms |
| `xmllint` | 10 ms |
| `jq` | 12 ms |
| `shfmt` | 13 ms |
| `ruff` | 14 ms |
| `deno fmt` | 14 ms (60 ms the first time) |
| `yq` | 15 ms |
| `jet` | 16 ms |
| `cljfmt` | 16 ms |
| `pandoc` | 36 ms (110 ms the first time) |
| `pg_format` | 48 ms |
| `black` | 85 ms |

- The wheel opens with no deliberate delay (`presentForKeyboard` → `orderFrontRegardless`).
- A pick hides it at once, then a 160 ms fade runs (`WheelController.dismiss`). The paste
  does not wait for the fade.
- **The slowest part is the person's flick (200-500 ms)**, then handing focus back and letting
  the paste settle (an estimated 50-150 ms).
- Expected: the text changes about 0.1-0.3 s after the pick for pure-Swift tools. External
  tools add 10-50 ms. To be measured in Stage 1.
- To make it feel instant:
  - pure Swift for the common tools, in memory;
  - don't wait on the clipboard when Accessibility already returned the text;
  - try to take keys without activating OpenShelf (the panel is already `.nonactivatingPanel`);
  - tune the paste delay by measurement.

### C. Text tools

David's named tools first. Every tool works on a selection (B1) and on a text file or text
item on a shelf.

**C1. Trim and clean up** (S, pure Swift)
- Trim: strip whitespace from the start and end of the whole text.
- Trim lines: strip trailing (optionally leading) whitespace on each line.
- Clean up:
  - collapse runs of spaces;
  - collapse 3 or more blank lines to 1;
  - turn CRLF and CR into LF;
  - remove zero-width and non-breaking spaces.
- Tabs to spaces and back (width from Settings: 4 by default, 2 for JSON, YAML and Clojure).
- Straighten smart quotes and dashes, and the reverse.

**C2. Re-indent code** (S-M)
- Builds on `Tools/PrettyPrint.swift` `PrettyPrint.formatter(forExtension:)`. It already maps
  extensions to formatters and runs them on standard input in an empty folder.
- **How the language is found** (the extension comes from the first that answers):
  1. the file's extension;
  2. the content sniff (C3);
  3. the app in front (a code editor implies its language).
- **Formatters Pretty Print already uses** (found by `ExternalTools.detect`, `Convert/ExternalTools.swift`
  `Formatters`): deno (JSON, Markdown, YAML, HTML, CSS, JS, TS), cljfmt (Clojure, EDN), ruff
  (Python), shfmt (shell), swift-format (Swift; found by name, or at Xcode's toolchain path as a
  fallback), pg_format (SQL), clang-format (C family), gofmt, rustfmt, and xmllint (XML, at
  `/usr/bin/xmllint`). Swift pretty-printing already works when Xcode is installed.
- If HTML Tidy is ever added: use only Homebrew's 5.x. macOS also ships a 2006 `tidy` in
  `/usr/bin` that predates HTML5, so check the version, not just the name.
- No formatter is needed for JSON: `JSONSerialization` with `.prettyPrinted` and `.sortedKeys`
  is the fallback.
- Pure-Swift helpers that need no language:
  - Dedent: remove the common leading whitespace. Fixes code pasted from a web page or chat.
  - Indent and Outdent a block.
  - Re-wrap to N columns, and unwrap hard-wrapped paragraphs.
  - Align a block on its first `=` or `:`.
- Limit: real re-indentation of code needs a formatter for that language. Without one, the
  honest tools are Dedent, Indent/Outdent and tabs to spaces.

**C3. Convert data: EDN, JSON, YAML, XML, TOML, CSV, plist** (S-M)
- **Exists for files:**
  - `Convert/DataConversion.swift` `DataConversion.formats(forExtension:tools:)`:
    - JSON → YAML, XML, plist, CSV
    - YAML → JSON, XML, plist, CSV
    - XML → JSON, YAML
    - plist → JSON, YAML
    - CSV/TSV → JSON, YAML, XML
    - Foundation does JSON and plist; yq does the rest.
  - `Convert/EdnConversion.swift` `EdnConversion`: EDN → JSON, YAML; JSON and YAML → EDN, with
    jet.
- **New:**
  - EDN ↔ XML, by chaining jet and yq (as EDN → YAML already does).
  - TOML in and out with yq. yq 4.54.3 round-trips TOML both ways.
  - Selected text, via a content sniff:
    1. `JSONSerialization` parses → JSON;
    2. starts with `<` and xmllint parses → XML;
    3. jet parses → EDN;
    4. yq parses as more than a bare value → YAML.
- **What is lost, plainly:**
  - **EDN:** keywords and symbols become strings; sets become arrays; `#inst` and `#uuid`
    become text; unknown tagged literals are refused.
  - **XML:** attributes become `+@name` keys (`<r id="7">` → `{"r":{"+@id":"7"}}`); mixed
    text and comments do not survive.
  - **JSON or YAML → XML** needs one root element.
  - **YAML:** comments and anchors are lost.
  - **CSV** works only for lists of flat records.

**C4. To Markdown, and save text as a file** (S-M)
- **Exists for files:**
  - HTML, Word, RTF and ODT → Markdown with pandoc (`Convert/PandocConversion.swift`
    `PandocConversion.readers`).
  - PDF → Markdown (`ConversionCatalog.formats(for:tools:fitsTheWheel:)`).
  - Text → PDF, DOCX, EPUB, HTML, RTF.
- **New:**
  - A **To Markdown** wedge for rich selections. It uses the HTML or RTF version kept in B1,
    so headings, links and bold survive. It only shows when there is a rich version.
  - **Save as PDF / DOCX / Markdown** for a selection. The file goes to a shelf.

**C5. Translate** (M)
- Uses Apple's Translation framework, on-device.
- `TranslationSession(installedSource:target:)` needs macOS 26 or later and is meant for code
  with no UI.
- It needs a known source language. Detect it with `NLLanguageRecognizer`.
- Both languages must already be downloaded; this kind of session cannot start a download.
- Downloads happen in System Settings → General → Language & Region → Translation Languages.
  A small Settings view using SwiftUI's `.translationTask` can ask for them too.
- The app's minimum is macOS 14, so the wedge shows only on macOS 26 and later.
- Use the default or low-latency strategy. Whether the "high fidelity" strategy (Apple
  Intelligence) stays on the device is not documented.
- **On the wheel:** "Translate ▸" opens a sub-wheel of target languages: the last used first,
  then the ones picked in Settings. The source's own language is skipped. The detected
  language shows in the centre.
- **On a file:** a `.txt` or `.md` is translated paragraph by paragraph with the batch call,
  so Markdown structure survives (code blocks skipped). The result is `name.<lang>.md` on the
  shelf. Word and PDF go through C4 first, so only what Markdown can hold survives.
- Risks:
  - Not every language pair is supported.
  - No length limit is documented.
  - The first call loads the model.

**C6. The text catalogue** (S each, pure Swift unless noted)

| Group | Tools |
|---|---|
| Case | UPPER, lower, Title Case, Sentence case, camelCase, PascalCase, snake_case, kebab-case, CONSTANT_CASE |
| Lines | sort (A-Z, natural, by length), reverse, remove duplicates, remove blank lines, number, shuffle, join with a separator, split on a delimiter, add a prefix or suffix, quote or unquote, lines → Markdown list, CSV or TSV → Markdown table |
| Cleanup | HTML to plain text, Markdown to plain text, remove tracking parameters from links (`utm_*`, `fbclid`, `gclid`, `mc_eid`), fix mis-decoded text (Latin-1 read as UTF-8), strip ANSI colour codes |
| Encode and decode | URL, Base64, HTML entities, JSON string escape, hex, Unicode escapes, JWT (shows header and payload; does not verify) |
| Extract | links, email addresses, numbers, dates, phone numbers (`NSDataDetector`), lines matching a pattern |
| Count | characters, words, lines, sentences, reading time (a toast; the text is not changed) |
| Hash | MD5, SHA-1, SHA-256 (CryptoKit) |
| Dates | Unix time ↔ ISO 8601 ↔ local date, whichever way is detected |
| Wrap | in quotes, parentheses, brackets, braces, a Markdown code fence, a block quote |
| Markdown | link from the selection plus a link on the clipboard (`[text](url)`), align a Markdown table, headings up or down |
| Generate | UUID, timestamp, placeholder text, random password (overlaps with C8) |

**C7. Sub-wheels, recent first, favourites** (M)
- **Sub-wheels:** a wedge marked ▸ opens a wheel of its own in the same place. Back returns.
  Needed because a wheel shows 7 wedges and the catalogue has dozens of tools.
- **Page 1 of the text wheel:** Trim · Clean up · Re-indent · Convert ▸ · To Markdown ·
  Translate ▸, plus More.
- **More** leads to Case ▸, Lines ▸, Cleanup ▸, Encode ▸, Extract ▸, Wrap ▸, Count, Hash,
  Dates.
- **Recent first:** the last 3 tools used take the first slots, building on
  `Wheel/WheelOrdering.swift`.
- **Favourites:** Settings lets David choose page 1.
- **Search (built, 2026-11-18):** David: "we need to add a search to it as well, so when it
  is open there is a floating search bar over it that narrows down the numbers of pie
  buttons", started by typing ("actually i like type to start"), and ⌘F "should still work
  too ... it should select all the text in the search box". Typing a letter or digit on any
  keyboard wheel (text or files) searches every tool that wheel leads to, across pages and
  sub-wheels; the matches become the wedges. Recent tools win ties, kept for one launch
  only until recent-first has a store. Not yet: formats the 12-wedge Convert cap hides.

**C8. Snippets: dates, times and your own text** (M)
- **Built-in, no setup:**
  - ISO date (`2026-11-17`)
  - long date (`November 17, 2026`)
  - time (`14:22`)
  - ISO timestamp with time zone
  - Unix time
  - ISO week (`2026-W47`)
  - Formats can be edited in Settings using standard date patterns.
- **Custom snippets: a folder of small plain text files** (David, 2026-11-18: "i don't want
  it to be YAML", then "i like the many small files and it would have replacement variables
  and where to put the cursor"). One snippet per file; the file name is the snippet's name
  and subfolders are groups (▸ on the wheel). Settings has "Choose Folder…", so it can live
  in a synced folder; OpenShelf builds no sync of its own. Each file may hold the
  placeholders below and one `{cursor}` marker for where the cursor lands.
- **Placeholders:**
  - `{date format="yyyy-MM-dd" offset="+3d"}`
  - `{time}`
  - `{clipboard}`
  - `{selection}`
  - `{cursor}`
  - `{uuid}`
  - `{epoch}`
- **Its own wheel and hotkey (David, 2026-11-18):** "i like the idea of a new wheel and
  hotkey for snippets". A second hotkey that opens the Snippets wheel directly is the
  planned way in, no longer optional.
- **To settle when C8 is built:** B2 step 4 sends "cursor, nothing selected" to Snippets,
  but Stage 2 sends that case to text copied in the last 60 s (copy-only). Proposed: the
  main hotkey goes selection, then recent copy, then a "nothing selected" toast that names
  the Snippets hotkey; snippets come only from their own hotkey. That keeps one meaning
  per hotkey and no 60-second timer deciding which wheel opens.
- **Where they show up:**
  - the Snippets hotkey;
  - favourites go on page 1, groups behind ▸;
  - pinned text items on a shelf (A4) are snippets too.
- **How text goes in:** paste with clipboard restore (B4). Typing keystrokes is slower and
  unreliable for long text.
- `{cursor}`: after the paste, press the left arrow once per character after the marker.
- Permissions: Accessibility (shared with B).

**C9. Text wheel during a text drag** (M)
- Drag selected text, tap the wheel key, and drop on a wedge. The result goes to the
  clipboard or a shelf.
- Builds on `DragMonitor` (`isDraggingFiles`, `draggedFileURLs`): add a text branch.
- Permissions: none.
- Risk: the source text is not changed, because the drop lands on the wheel.

**C10. Services menu entries** (M)
- "Transform with OpenShelf" and "Add to Shelf" appear in the right-click Services menu.
  Text returned by a service replaces the selection.
- New: `NSServices` in `Info.plist` and a services provider.
- Permissions: none.
- Risk: Firefox and most Electron apps lack Services (accepted).

**C11. Detect dates, places and people in text** (S-M)
- A text item or selection with a date or address gets wedges:
  - **Make Event** (`.ics` on the shelf);
  - **Make Contact** (`.vcf` from a signature block);
  - **Open in Maps**;
  - **Copy Number**.
- Builds on `NSDataDetector`.
- Permissions: none for the files. Writing straight into Calendar or Contacts would need
  their permission, so files come first.

**C12. More for the Edit window** (David, 2026-11-18: "add your recs to the future features")
The Edit window (FORK-FEATURES #53) has vim's motions, operators, text objects, surround,
`.`, registers and macros. Next, in this order:
1. `:s` find and replace: `:%s/old/new/g`, flags g, i and c if cheap, `&` to repeat.
2. `jk` leaves insert mode, as Doom's evil-escape does by default.
3. Visual block (⌃V) with `I` and `A`.
4. `gq` re-wraps a paragraph to a line width (`gqip`).
5. ⌃A and ⌃X add to or take from a number.
6. Replace mode `R`; `gv` selects the last selection again; `o` swaps the ends in visual line mode too.

Left out for now:
- Marks: the text in the window is short.
- `:g`, `:sort` and `:normal`: the Lines tools cover them.
- `:!` shell filters: the app would run shell commands, which is a safety decision.
- David's vim or Doom config and plugins: the price of a built-in engine.
- Keeping macros between windows.

**C13. Live preview beside the text wheel** (David, 2026-11-19: "a preview of the text changing
in a edit window to the right of the wheel, when you hover over the button that would change the
text it would automatically show the change, if you click the button it would make the change and
post it back as normal")
- A pane to the right of the text wheel shows the text as it would be after the hovered tool
  runs. Hovering a wedge, or moving to it with the arrow keys, updates it live. Clicking applies
  the tool and writes back exactly as today.
- To settle when it is built:
  - Which tools preview: pure text tools show their result; Generate, Hash, Count and JWT show
    what they would make or copy; Edit says it opens the editor; Re-indent and To Markdown run
    external tools, so they preview only if fast enough.
  - Show a diff (what changed, highlighted) or the plain result.
  - Long text: scroll, or show the part around the first change.
  - Sub-wheel wedges (▸) preview nothing; only tools do.
  - Speed: compute off the main thread and cancel when the hover moves.
  - A preview never touches the source app or the clipboard.

### D. Links and the web

**D1. Drop links** (M)
- Drag a link or an address-bar URL. It becomes a `.webloc` item.
- Wheel: Open, Copy as Markdown link, Copy clean link (no tracking parameters), QR Code
  (E1), Save Page as PDF.
- New: `.URL` drop type. Save as PDF via WebKit's PDF export.
- Risks:
  - the page title needs a fetch;
  - Save as PDF may lack the browser's login.

**D2. Web images and promised files** (M)
- Images dragged from a browser or Photos arrive as files, so the image wheels work on them.
- New: `NSFilePromiseReceiver` and raw image data (`.png`, `.tiff`) on the drop targets.
- Risk: Photos only writes the file when asked; the source picks the name.

**D3. Article as Markdown** (M)
- A link becomes the article's text as `.md` on the shelf.
- Fetch the page, strip menus and ads with a Readability port, then `pandoc -f html -t gfm`.
- Risk: paywalls and pages built by JavaScript.

**D4. Download media from a link** (M)
- A video or audio link becomes a file on the shelf, through `yt-dlp`, added to `ExternalTools` and found the
  way other tools are (Homebrew's folder first).
- Risk: each site's terms.

### E. Images and colour

**E1. Make a QR code** (S)
- Text or a link becomes a QR code PNG on the shelf.
- The reverse of `Tools/QRReader.swift` `QRReader`. Uses Core Image's QR generator.

**E2. Pick a colour** (S)
- The system eyedropper (`NSColorSampler`) picks a colour. The hex code is pasted at the
  cursor (B4) or copied.
- A text item holding a hex code gets "Copy as RGB / HSL / SwiftUI".

**E3. Colour palette from an image** (S)
- An image gives its five main colours as hex text and a swatch PNG.
- Core Image k-means.

**E4. Describe an image** (S)
- Vision's on-device labels plus OCR text become a short description to copy, for alt text.

**E5. Wi-Fi QR code** (S-M)
- Makes a "join this Wi-Fi" QR code from a network name and password.
- Risk: reading the current network name needs Location permission on recent macOS, and the
  password needs typing or Keychain access.

**E6. Clean an image: hidden data and marked areas, with a report** (M, more with a model)
David, 2026-11-19: "should remove non-hidden and hidden ones that the same time, it should report
back what it removed". One tool that does two passes and then lists what it removed, e.g.
"Removed: EXIF (camera, lens), GPS location, IPTC caption and creator, XMP, Content Credentials
(C2PA) manifest, embedded thumbnail; filled 1 marked area (bottom right, 220×60 px)". The copy
is "<name> Clean.<ext>" beside the original (never overwritten), same format, quality kept; the
report is in the result panel and can be copied.
- Hidden pass: every metadata container goes (EXIF, GPS, TIFF, IPTC, XMP, MakerNotes, embedded
  thumbnails and previews, JPEG APP11 JUMBF boxes that hold C2PA, PNG tEXt/iTXt/zTXt and caBX
  chunks, HEIC and AVIF item properties; the ICC profile only if asked). Checked 2026-11-19 with
  files made for the test: re-encoding the pixels drops all of these in JPEG and PNG, and a
  lossless JPEG copy drops APP11 too, but a lossless PNG copy (`CGImageDestinationCopyImageSource`,
  what Metadata › Clean uses when it keeps orientation and profile) KEEPS the caBX (C2PA) and tEXt
  chunks, and ImageIO's property check can't see them. So this tool re-encodes, or rewrites PNG
  chunks itself, and checks the bytes, not only ImageIO's properties. The report never claims
  more than it did: "pixel-embedded marks, if any, are untouched" (a SynthID-style mark lives in
  the pixels and no metadata pass removes it).
- Visible pass: the user marks the area, as in Redact, and the tool fills it to blend with what is
  around it instead of a box. No automatic "find any watermark" detection: it cleans the areas
  the user points at on his own images, like a retouch tool. Fill options to compare:
  - No dependency: diffusion from the edges (Core Image, or a Laplace fill with Accelerate) is
    fine on flat or smooth backgrounds and smears on detail; a small PatchMatch-style
    content-aware fill in Swift or Metal copies nearby texture, good on repeating backgrounds
    (sky, grass, fabric), weaker on structure (edges, text, faces). A few hundred lines; no model.
  - A Core ML inpainting model such as LaMa (Apache-2.0; about 200 MB as published, roughly half
    that as a Core ML half-precision conversion; not measured here): much better on detailed
    backgrounds, on device, but a large new dependency that needs David's yes.
  - A public system API: none found. Vision and Core Image have no inpainting filter, and Photos'
    Clean Up isn't offered to other apps (as far as checked; to confirm against the current SDK
    when built).
- Could ship first: the hidden pass and the report, plus the marked-area fill with the
  no-dependency method. A model is a second step, if the simple fill isn't good enough.
- Tests without a screen: per-format fixtures made in the test, with the container list before
  and after; the report's text; the fill on synthetic images (a flat field with a stamp: the
  stamp's pixels are gone and the area matches its surround within a tolerance).

### F. Audio, video and the screen

**F1. Waveform image** (S)
- Audio or video becomes a PNG of its waveform, through ffmpeg's `showwavespng`.

**F2. Contact sheet** (S)
- A video becomes one image with a grid of frames (ffmpeg `tile`). Builds on Still Frame.

**F3. Screenshot to a shelf** (S-M)
- A shortcut takes an interactive screenshot (`screencapture -i`). It lands on a shelf with
  the wheel ready.
- **Check first:** a Watched Folder on the screenshot folder may already give most of this
  (`WatchedFolders/ArrivalTracker.swift` already skips Screenshot's temporary files).
- Risk: macOS may ask for Screen Recording permission.

**F4. Screen recording** (L)
- Record a region, then the existing video tools and GIF apply.
- ScreenCaptureKit. Needs Screen Recording permission.

### G. PDFs

**G1. Page numbers, watermark, stamp** (S-M)
- Draws text on each page with PDFKit. Builds on `Tools/PDF/PDFTools.swift`.

**G2. Fake-redaction check** (M)
- Flags text that sits under black boxes or annotations, where a redaction only hid it.
- Builds on Check Safety (`Tools/PDF/CheckSafety.swift`).

### H. Files and sharing

**H1. Email it** (S)
- An Actions wedge opens a new Mail draft with the files attached, or with a text item as the
  body.
- Builds on `FileAction` in `Wheel/WheelItem.swift`. Uses
  `NSSharingService(named: .composeEmail)`.
- Permissions: none. No CC or BCC.

**H2. Send in Messages** (S)
- An Actions wedge beside AirDrop, using `NSSharingService(named: .composeMessage)`. Builds on
  `FileActions.airDrop`.

**H3. Open With…** (S)
- Lists the apps that open this kind of file (`NSWorkspace.urlsForApplications(toOpen:)`),
  recent first.

**H4. Checksums** (S)
- Copies a file's SHA-256 or MD5.
- **Verify** compares it with a hash on the clipboard and shows a green or red toast.
- CryptoKit is already used (`Install/ToolIntegrity.swift`).

**H5. Batch rename** (M)
- Date prefix, numbering, find and replace, change case, with a live preview.
- Builds on the name-clash dialog (`Support/FileActions.swift`).
- Risk: undo, and name collisions.

**H6. Compare two items** (M)
- Two text items open side by side with the differences marked. Two images show a difference
  overlay.

**H7. Find duplicates** (M)
- Drop a folder to see groups of identical files (by hash), and pick which go to the Trash.
- Trash only, never delete.

**H8. Upload and copy a link** (M-L)
- Upload to a storage place David sets up himself, and copy the link.
- Risk: credentials. It goes against decision 8 unless the storage is his own, so it is
  **opt-in only**.

**H9. Remove the quarantine flag** (S-M)
- Drop a downloaded app (or any file) that macOS marks as quarantined, and an Actions wedge
  **Remove Quarantine** appears. The wedge only shows when the item actually carries the
  `com.apple.quarantine` attribute.
- Before anything changes, it shows the decoded quarantine record: which app downloaded the
  item and when (the attribute is `flags;hex-time;agent;id`, so "Downloaded by Safari,
  Oct 30"). The user confirms each item; it never runs on a batch without showing every item.
- It removes the attribute from the item and from everything inside an app bundle (after an
  unzip, nested items carry it too), with the native `removexattr` call. No external tool.
- Why: since macOS 15 (to be checked against Apple's documentation), opening an unsigned app
  means System Settings → Privacy & Security → Open Anyway and a password. Removing the flag
  also stops App Translocation, where a quarantined app runs from a random read-only copy.
- Builds on `FileAction` in `Wheel/WheelItem.swift` and the Actions wheel's filter in
  `App/AppDelegate.swift` `items(for:urls:tools:)`. `FileActions.transfer` keeps quarantine on
  copies on purpose, so this stays an explicit choice.
- Permissions: none for items the user owns. Root-owned apps fail with a clear error, never
  a silent no-op.
- Risks: it turns off a macOS safety check, so it always confirms first. It does not fix a
  bad or missing signature or notarization; an app whose signature is broken still won't open
  and the confirm text says so.

### I. Automation and developer tools

**I1. Run a Shortcut on an item** (S-M)
- A wedge lists chosen Shortcuts. The item is passed in, and output files land on the shelf.
- Uses `/usr/bin/shortcuts run NAME -i FILE -o OUT`.
- This also reaches things OpenShelf cannot do itself, such as Focus modes.

**I2. Your own scripts as wedges** (M-L)
- Settings lists scripts that say what they take (files or text). Each shows as a wedge, gets
  its input on standard input or as arguments, and its output becomes a shelf item or
  clipboard text.
- Builds on `Convert/ProcessRunner.swift` and the minimal child environment
  (`Convert/ChildEnvironment.swift`).
- Risks: running user code from a drag; error messages.

**I3. Run an HTTP request file** (M)
- A `.http` file is sent with curl, and the response is saved next to it.
- Risk: it sends network requests, so it asks first.

**I4. Mail shortcuts and snooze** (M; first slice S-M)
David, 2026-11-19, after looking at a third-party Mail helper: "i feel like i wouldn't want the
openshelf wheel popping up", and "the snooze feature should work like it does now, the only
difference would be the natural language would set it to the right time/date and then archive the
message because it stays in the inbox even though it has a reminder. if you archive it it comes
back at the right time."
- Not on the wheel: keys that act only while Mail's message list or reading pane has focus,
  never in a compose window or another app.
- Snooze is Mail's own Remind Me at the chosen date and time, then Archive (⌃⌘A); Mail brings
  the message back at that time. No mailbox or timer of OpenShelf's own.
- Presets: tomorrow morning (7am), this afternoon (2pm), tonight (5pm), in two days (7am:
  David to confirm), this weekend (Saturday 7am), next week (Monday 7am). Free text ("fri 2pm",
  "in 3 hours", "dec 3 9am") in a one-line prompt that shows the date it understood before
  Return. Proposed rule for a preset whose time has passed today ("this afternoon" at 4pm): the
  next day at that time, shown in the prompt before it is used.
- Found 2026-11-19 (read-only, Mail 16 on macOS 27.2):
  - Mail's AppleScript dictionary (`sdef`) has no reminder and no archive: Remind Me can only be
    driven through its menu (Message › Remind Me › Remind Me in 1 Hour, Tonight, Tomorrow, Remind
    Me Later…; "Later…" opens a date picker with a Remind Me button) with Accessibility, which
    OpenShelf holds. Archive is a menu item too (⌃⌘A).
  - Archive keeps the reminder: confirmed by David's daily use on this Mac (2026-11-19: "i have
    seen it work with archive. that's how i do it all the time"). Apple's Mail guide is silent on
    archived messages, and some users report reminders lost when a message leaves the inbox on
    other setups. An alternative, noted only: Mail's Settings › General › Remind Me behavior,
    "Move to “Remind Me”", moves a reminded message out of the inbox without archiving.
  - NSDataDetector reads "tomorrow morning" (9am), "this afternoon" (3pm), "tonight" (7pm),
    "saturday morning", "next monday morning", "fri 2pm", "in 2 days", "dec 3 9am" and "monday
    7am"; it reads nothing for "in two days", "this weekend", "next week", "in 3 hours" or "eod",
    and only "tomorrow" of "tomorrow 9". So the presets need a small table of David's meanings,
    with relative times ("in 3 hours", "in two days") parsed by us; the detector for the rest.
  - Single keys only in Mail: an event tap active only while Mail is in front and focus isn't a
    text field (needs Input Monitoring; it sees key presses while active, so: installed only then,
    never logs keys, off by default, an indicator while on). App Shortcuts in Keyboard settings
    take a key only with a modifier (not verified here). A global NSEvent monitor can't stop the
    key reaching Mail.
- First slice: snooze only, behind one hotkey while Mail is in front: presets and free text, then
  Remind Me Later… through Accessibility at that date and time, then Archive. Then the
  single-key layer.
- Tests without a screen: the phrase table and parsing (pure functions with a fixed "now").

### Considered and not a fit

- **Moving and tiling windows.** A wheel for a dropped item has no window to act on.
- **Turning on Focus.** There is no public API; I1 covers it through a Shortcut.
- **iCloud Drive share links.** There is no public API to create one.

### Already in OpenShelf (not new work)

- **Images:** compress, metadata (including removing GPS location), edit, annotate, add
  background, crop, resize, remove background (Vision), redact, read QR, OCR, icon, GIF loop,
  combine into a PDF, and convert to PNG, JPG, HEIC, TIFF, AVIF, BMP, WebP, JPEG XL, PDF,
  DOCX.
- **PDFs:** organize pages, split, page images, compress, metadata, OCR to a searchable PDF,
  Make Fillable, Check Safety, and convert to DOCX, TXT, MD, EPUB, PPTX, XLSX.
- **Video:** trim, speed, crop, rotate, split, compress, mute, still frame, grayscale,
  transcribe, reverse, even out loudness, volume, fit under a size, frame rate, export in a
  chosen codec, GIF and APNG, and pull out the audio.
- **Audio:** trim, speed, split, compress, export, transcribe, reverse, metadata, mono, even
  out loudness, volume, fit under a size, BPM, merge.
- **Archives:** ZIP, tar.xz, tar.zst, 7z, and extract.
- **Subtitles:** SRT, VTT, ASS, SSA, TTML.
- **Data:** JSON, YAML, XML, plist, CSV; EDN ↔ JSON and YAML; Parquet and SQLite.
- **Code:** Pretty Print.
- **Actions:** AirDrop, copy and move to a folder, Copy Path, Copy Name, open in Terminal.
- **Other:**
  - Quick Look.
  - Watched Folders with an action on arrival (`WatchedFolders/WatchedFolder.swift`
    `WatchedFolderAction`).
  - Shortcuts actions provided by OpenShelf.

## Build plan

Each stage ships on its own: build it, install it, use it. Every stage follows the repo's
rules:
- add its lines to `FORK-FEATURES.md` in the same commit;
- add new tests in `Tests/OpenShelfTests/` (Swift Testing);
- stub external tools with `FakeToolRunner`;
- run real tools only under `OPENSHELF_TOOL_TESTS=1`;
- end with `swift test` passing and `make app`.

### Stage 1: select, press, fix it

**Built** (FORK-FEATURES #50). Differences from the plan below:
- Finder keeps its file wheel even when a Finder text field (renaming) has text selected, so
  Finder works exactly as before.
- To Markdown shows for prose and copies the formatted selection only when chosen, so the
  clipboard isn't borrowed on every press. Accessibility gives plain text only.
- Copy Original is ⌥ on the Undo wedge (⌥ copies everywhere), not a wedge of its own, and
  Undo appears when the selection is OpenShelf's last result in that app. Re-selecting the
  pasted range through Accessibility is not built.
- Temporary files go in the system temporary folder and are removed after each tool; ⇧
  results are saved in Application Support/OpenShelf/Text.
- Re-indent picks the language from the content only; the app in front is not used yet.
- Indent width is fixed at 4 (Settings later). ⌘C and ⌘V are posted as the QWERTY C and V
  keys, so other keyboard layouts may need work.
- Recent-first and favourites stay in Stage 2, as planned.
- Added after the first try: rules per app. In a terminal the result is copied, never
  pasted (David), and ⌃ pastes it back for vim's insert mode (David: "hold to paste back
  sounds good"). No keys are ever sent to a terminal: iTerm2 can map ⌘C to Ctrl-C. Terminal
  text comes from a copy made in the last 60 s. GUI Emacs is read and replaced through
  emacsclient, as one undo step. A failed read names the app.
- Next, not built: inside herdr or an iTerm2 tab, find the foreground program (herdr's
  `pane process-info`; iTerm2 needs an Automation prompt) and ask nvim through its own server
  for the visual selection and to replace it. Vim's mode can't be seen from outside, so it
  stays with ⌃ to paste. In Emacs insert state with no region, nothing happens yet.
- Still to check in the running app: everything under "Verify in the running app" below.

- **Goal:** select text in any app, press ⌃⌥Space, pick a tool, and the text is replaced.
- **Delivers:** B1-B6, C1, C2, C3, C4, C7 (sub-wheels; recent-first can wait for Stage 2).
- **Text wheel page 1:** Trim · Clean up · Re-indent · Convert ▸ (JSON, YAML, EDN, XML, TOML)
  · To Markdown · More. More holds Dedent, Indent, Outdent, Tabs ↔ Spaces, Trim Lines,
  Straighten Quotes.
- **Shared plumbing it adds:**
  - a selection reader: Accessibility, the ⌘C fallback, the secure-input check, the
    permission prompt;
  - a result writer: focus hand-back, paste, clipboard snapshot and restore, Transient
    marker;
  - text as a temporary file;
  - sub-wheels;
  - the text branch in the hotkey;
  - Text History with the Undo wedge.
- **Tests:**
  - every pure-Swift transform, table-driven, including empty text, CRLF and Unicode;
  - the content sniff;
  - the hotkey decision table (shelf, Finder, text, cursor only, nothing) with Accessibility
    and the pasteboard stubbed;
  - clipboard snapshot and restore on a private named `NSPasteboard`;
  - sub-wheel paging;
  - Convert ▸ argument building with `FakeToolRunner`;
  - TOML and EDN ↔ XML under `OPENSHELF_TOOL_TESTS=1`.
- **What David sees:**
  - the first time, a toast and the Accessibility settings page;
  - after that, select → ⌃⌥Space → flick → the text changes in place; ⌥ copies instead;
  - in Finder with files, nothing changes;
  - in a password field, a toast and nothing else.
- **Verify in the running app:**
  - ⌘Z after a paste and after an Accessibility write, in TextEdit, Mail, Notes, Safari,
    Slack and VS Code;
  - time from pick to changed text;
  - whether the target app keeps its selection when focus comes back;
  - whether the wheel can take keys without activating OpenShelf;
  - the clipboard comes back intact, including an image on it;
  - the hotkey still works with Accessibility off (it should, with Carbon).

### Stage 2: the text catalogue

- **Goal:** the full set of text tools, quick to reach.
- **Delivers:** C6 (all groups), C7 recent first and favourites.
- **Plumbing:** none new; it is all tools on Stage 1's sub-wheels.
- **Tests:** table-driven for each tool; ordering and favourites persistence.
- **What David sees:** More → Case ▸, Lines ▸, …; his last three tools first.
- **Verify in the app:** two flicks reach any tool; Count and Hash show toasts.
- **Built so far (first slice):** the Lines and Case groups, after David asked for sort
  lines in Mail. More ▸ is now Lines ▸ · Case ▸ · Indent ▸ · Trim Lines · Straight Quotes.
  Lines ▸ and Case ▸ have sub-wheels of their own (Order, Join & Split, Lists, Code Case) so
  no wheel pages, and Back goes to the wheel a group opened from. Dedent, Indent, Outdent
  and Tabs ↔ Spaces moved from More into Indent ▸ to make room. Sort A–Z, Remove
  Duplicates, Remove Blank Lines and UPPER/lower/Title/Sentence are three picks (More, the
  group, the tool); the Order, Join & Split, Lists and Code Case tools are four. The plan's
  "two flicks reach any tool" is not met by flicks; typing a few letters now reaches any
  tool (C7 Search). Join, split, prefix and suffix use fixed
  separators; typing your own needs a text field the wheel doesn't have.
- **Also built:** copied text as the last way in for every app (David, 2026-11-18: "also
  the text changes should work in any text editing field or on copied text right?"):
  selection first, then a copy from the last 60 s, copy-only, ⌃ pastes at the cursor.
- **Left in Stage 2:** Cleanup, Encode and decode, Extract, Count, Hash, Dates, Wrap,
  Markdown, Generate; recent first and favourites.

### Stage 3: text on the shelf

- **Goal:** text you can drop, keep and drag back out.
- **Delivers:** A1, A2, A3, A4, A5.
- **Plumbing:** text drop types on the shelf, wheel and edge tab; text items with both string
  and file on drag-out.
- **Tests:** a drop pasteboard with `.string` → a file of the right extension; the drag-out
  pasteboard holds both types.
- **What David sees:** drag a paragraph from Safari onto a shelf; later drag it into an
  email.
- **Verify in the app:** what Mail, Notes, Safari, Slack and VS Code do with string-plus-file
  (A2's default depends on it).

### Stage 4: snippets

- **Goal:** insert dates, times and saved text anywhere.
- **Delivers:** C8.
- **Plumbing:** the snippets folder reader (one text file per snippet, subfolders as groups),
  the placeholder engine, the Snippets
  wheel's own hotkey; whether the main hotkey also reaches it is open (C8 "To settle").
- **Tests:**
  - placeholder expansion with a fixed clock and time zone (date offsets across month and
    year ends);
  - a bad placeholder reports its file and line; subfolders become groups;
  - `{cursor}` arrow counts.
- **What David sees:** cursor in a field, ⌃⌥Space, flick ISO Date, and `2026-11-17` appears.
- **Verify in the app:** `{cursor}` lands right in TextEdit, Safari and Slack.

### Stage 5: translate

- **Goal:** on-device translation of a selection or a text file.
- **Delivers:** C5.
- **Plumbing:** a translation service wrapper (macOS 26 or later), language detection, a
  language picker and download button in Settings, paragraph batching for files.
- **Tests:** paragraph splitting keeps Markdown structure and skips code blocks; language
  list ordering. The real framework runs only in an opt-in test.
- **What David sees:** select Spanish text → Translate ▸ English → replaced. A `.md` file →
  `name.en.md` on the shelf.
- **Verify in the app:** first use with a language not downloaded; time per call; the result
  matches Apple's Translate app.

### Stage 6: links and the web

- **Goal:** links and web content become useful shelf items.
- **Delivers:** D1, D2, D3, D4, E1, the tracking-parameter cleanup from C6 on links.
- **Plumbing:** `.URL` and file-promise drop types, `.webloc` items, a page fetcher with
  Readability.
- **Tests:** link cleaning cases; `.webloc` read and write; Markdown link building; promise
  handling with a fake receiver.
- **What David sees:** drag a link to a shelf; Copy as Markdown link; Article as Markdown;
  drag a web image and convert it.
- **Verify in the app:** drags from Safari's address bar, a link in a page, an image in a
  page, and Photos.

### Stage 7: more actions

- **Goal:** everyday file actions on the Actions wheel.
- **Delivers:** H1, H2, H3, H4, H9, I1.
- **Plumbing:** none shared with Stages 1-6.
- **Tests:** checksum values against known vectors; `shortcuts run` arguments with
  `FakeToolRunner`; the app list for Open With is sorted; quarantine record decoding and
  removal on a temporary bundle with `setxattr`-made flags, including a nested item, and
  the wedge hidden when no flag is present.
- **What David sees:** Email, Messages, Open With, Checksum, Run Shortcut, Remove Quarantine
  wedges.
- **Verify in the app:** Mail opens with the attachment; a real Shortcut runs and its output
  lands on the shelf; a freshly downloaded unsigned app opens after Remove Quarantine without
  the Open Anyway step.

### Stage 8: images, colour and media

- **Goal:** the remaining image, colour and media tools.
- **Delivers:** E2, E3, E4, E5, F1, F2.
- **Plumbing:** E2 reuses Stage 1's result writer; the rest are tools on existing wheels.
- **Tests:** palette and label extraction on fixture images; ffmpeg arguments with
  `FakeToolRunner`; Wi-Fi QR payload escaping.
- **What David sees:** new wedges on the image, audio and video wheels; Pick Colour from the
  hotkey wheel.
- **Verify in the app:** E5's Location prompt; the eyedropper on two screens.

### Stage 9: files, PDFs and detection

- **Goal:** larger file tools.
- **Delivers:** H5, H6, H7, G1, G2, C11.
- **Plumbing:** a preview window for rename and compare.
- **Tests:** rename patterns and collisions; duplicate grouping; `.ics` and `.vcf` output;
  stamping on a fixture PDF; fake-redaction detection on a fixture with hidden text.
- **What David sees:** Rename, Compare, Find Duplicates, Stamp, and Make Event or Make Contact
  on text.
- **Verify in the app:** undo of a rename; the `.ics` imports into Calendar.

### Stage 10: capture, services and power tools

- **Goal:** the rest.
- **Delivers:** F3 (after checking Watched Folders), F4, C9, C10, I2, I3, H8 (opt-in).
- **Plumbing:** Screen Recording permission; `NSServices`; the script-wedge contract.
- **Tests:** the script contract (input, output, failures); service text round trip; HTTP
  file parsing.
- **What David sees:** a screenshot shortcut, a text wheel during a text drag, Services menu
  entries, his own script wedges.
- **Verify in the app:** Screen Recording prompt; Services in Safari and Mail; a script that
  fails shows its error.

### What can run in parallel

- **Stage 1 comes first** for Stages 2, 4, 5 and the E2 part of Stage 8. They all need its
  reader, writer or sub-wheels.
- **Stages 2, 3 and 4** can run side by side once Stage 1 is in.
- **Stage 6** needs Stage 3's drop-type work.
- **Stage 7 needs nothing** and can start at any time, even before Stage 1.
- **Most of Stages 8 and 9** need nothing either: E3, E4, E5, F1, F2, G1, G2, H5, H6 and H7.

## Open questions for David

1. Should a text tool replace the selection by default, with ⌥ to copy (decision 6)?
2. Where should the snippets file live? A synced folder works, since OpenShelf builds no sync
   of its own.
3. Which languages go on the Translate wheel?
4. Is it fine to show Translate only on macOS 26 and later?
5. When a text item is dragged out, should the default be text or the file (decided after
   Stage 3's test)?
6. Should Text History keep anything on disk, or only in memory?

## References

Other apps' mechanics, for comparison. Vendor pages are their claims, not tests.

- Radial menus:
  - https://radial.appverge.net/features
  - https://radial.appverge.net/docs/actions/type-text
  - https://radial.appverge.net/docs/actions/ai-action
  - https://kando.menu/usage
  - https://github.com/kando-menu/kando/issues/573
  - https://github.com/kando-menu/kando/issues/993
- Drop shelves:
  - https://dropoverapp.com
  - https://eternalstorms.at/yoink
  - https://github.com/aptonic/dropzone4-actions
  - https://bru.build
- Selected text:
  - https://www.popclip.app/dev/actions
  - https://www.popclip.app/dev/api/interfaces/PopClip.html
  - https://manual.raycast.com/dynamic-placeholders
  - https://www.alfredapp.com/help/features/universal-actions/
  - https://github.com/tisfeng/Easydict/wiki/FAQ
- Clipboard and paste:
  - https://nspasteboard.org/
  - https://espanso.org/docs/configuration/options
  - https://github.com/p0deje/Maccy
- Snippets:
  - https://www.alfredapp.com/help/workflows/advanced/placeholders
  - https://espanso.org/docs/matches/extensions/
- Accessibility and permissions:
  - https://developer.apple.com/forums/thread/820594
  - https://developer.apple.com/forums/thread/720840
  - https://www.electronjs.org/docs/latest/tutorial/accessibility
  - https://bugs.webkit.org/show_bug.cgi?id=48080
- Undo after an Accessibility write:
  - https://lists.apple.com/archives/accessibility-dev/2008/Jan/msg00024.html
- Undo in text views:
  - https://christiantietze.de/posts/2022/09/undoable-text-changes/
- Secure input:
  - https://developer.apple.com/library/mac/technotes/tn2150/_index.html
- Services:
  - https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html
- Translation:
  - https://developer.apple.com/documentation/translation/translationsession
  - https://wwdcnotes.com/documentation/wwdc24-10117-meet-the-translation-api/
- Article to Markdown:
  - https://github.com/lake-of-fire/swift-readability
  - https://github.com/JohannesKaufmann/html-to-markdown
