Read this before merging upstream. Every item must still work after the merge.

# Fork features

What `djnesmith/OpenShelf` adds over `Manan-Santoki/OpenShelf`. The list comes from
`git log upstream/main..djnesmith`. Each new feature adds a line here in the same commit.

After any merge, run `swift test` (all tests must pass) and then `make app`. The checks
below name the tests for each feature: `swift test --filter <name>`. "In the app" checks
need the built app at `/Applications/OpenShelf.app`.

Upstream 1.5.0 took in its own adapted copies of #3, #6, #7, #8, #9, #10, #24, #39, #40
(shelves following a Move) and #46; its `docs/FORK_REVIEW.md` lists them. Where both had
a version, the merge kept the fork's and added upstream's hardening, except that OCR
(`OCR.swift`, `OCREditor.swift`) and the ProcessOutputTests and WheelBadgeTests files are
upstream's, which hold all of the fork's code and tests plus more: credential-like
`LC_*` names are dropped (#3); pipe writers close when a launch fails (#6); OCR runs on
its own queue, cancels, retries on the CPU and maps rotated pages (#24); ⌘⌥-number keeps
its modifiers (#39); a Move saves the shelves and moves the selection anchor (#40); the
Excel row count handles CR, UTF-16 and escaped quotes (#9, keeping "Save as CSV or
Parquet"). Expect those files to conflict again when upstream fixes them further. The
fork's own copies of tests that upstream's files also hold were removed, so each runs once.

Upstream 1.6.0 and 1.7.0 added Pandoc as an installable Extra Formats row and a
`DocumentEngine` that sends Markdown, Word, ODT and HTML through it. The merge keeps both
Pandoc paths in `PandocConversion.swift`: the fork's sandboxed markup conversions (#30,
`handles`, `convertMarkup`) and upstream's unsandboxed engine (`convert`), with a dead
proxy (#4). Pandoc left the fork's Command-Line Tools list for upstream's row (#45).
The fork's own tools now also send their results back to the shelf they came from, as
upstream's do (`sourceShelfID` in `ToolLauncher.swift`). The welcome window is gone for
upstream's tour; no fork feature used it.

## Security

### 1. No in-app updates
Sparkle is gone, so the app never downloads or installs updates by itself. Upstream 1.4.0's update reminder (a blue menu-bar icon and an "Update to Version…" item) needs Sparkle, so the merge leaves it out; `MenuBarIcon.updateAvailableImage` is unused.
- Commits: 28bb48c, f036332 (the Makefile no longer fetches Sparkle)
- Files: `Package.swift`, `Makefile`, `Support/Info.plist`, `Sources/OpenShelf/App/AppDelegate.swift`, `App/OpenShelfApp.swift`, `Settings/SettingsPanes.swift`, `Settings/SettingsTab.swift` (`App/Updater.swift` deleted)
- Check: `grep -ri sparkle Package.swift Makefile Support Sources` finds nothing. With the app running, `lsof -nP -i -a -p $(pgrep -x OpenShelf)` shows no sockets.

### 2. David's signing identity and bundle ID
Builds are signed as "Apple Development: David Nesmith (JFGJA89Z8H)" with the hardened runtime. The bundle ID is `com.djnesmith.OpenShelf`. The only entitlement is `com.apple.security.automation.apple-events`, which is needed to read Finder's selection.
- Commits: f036332
- Files: `Makefile` (`SIGN_IDENTITY ?=`), `Support/Info.plist`, `Support/OpenShelf.entitlements`, `Sources/OpenShelf/Convert/ExternalTools.swift` (the `defaults` domain in a comment)
- Check: `codesign -dv --verbose=2 /Applications/OpenShelf.app` shows `Identifier=com.djnesmith.OpenShelf`, `TeamIdentifier=CHJ32A2B4N`, and `flags=0x10000(runtime)`. `codesign -d --entitlements - /Applications/OpenShelf.app` lists only apple-events.

### 3. Minimal environment for child processes
Every tool the app runs (ffmpeg, calibre, pandoc, yq, duckdb, sqlite3, jet, LibreOffice, brew…) gets an allowlisted environment: HOME, TMPDIR, USER, LOGNAME, SHELL, LANG, LC_*, TERM and a fixed PATH. Names that look like credentials are always dropped.
- Commits: e24bfd8
- Files: `Sources/OpenShelf/Convert/ChildEnvironment.swift`, `Convert/ProcessRunner.swift`, `Convert/MediaProbe.swift`, `Convert/DocxWriter.swift`, `Convert/PackageZip.swift`, `Convert/EbookConversion.swift`, `Install/Homebrew.swift`
- Check: `swift test --filter ChildEnvironmentTests`. Any new `Process()` in upstream code must go through `ChildEnvironment` too: `grep -rn 'Process()' Sources` and check each hit.

### 4. Locked-down data tools
duckdb runs with autoinstall, autoload and community extensions off, `lock_configuration` on, and `-init /dev/null`. sqlite3 runs as `/usr/bin/sqlite3 -readonly -safe -init /dev/null`. A file can't make these tools run its own SQL or load code.

pandoc runs two ways. Markup conversions (#30) run with `--sandbox`: no network and no files but the input. Upstream's engine for Markdown, Word, ODT and HTML runs without it, so pictures next to the document embed; its environment sets `http_proxy`, `https_proxy`, `HTTP_PROXY` and `HTTPS_PROXY` to `http://127.0.0.1:9`, where nothing listens, so pandoc can't fetch web pictures. Not verified: Homebrew's pandoc 3.12.1 is built without HTTP, so the proxy block was never tried against an HTTP-capable pandoc (such as the GitHub build Settings installs). A weasyprint or wkhtmltopdf PDF engine could still fetch web pictures, since pandoc passes their addresses through; the engine list tries xelatex, lualatex and tectonic first.
- Commits: e31f6ad, e5e1b51, the 1.7.0 merge
- Files: `Sources/OpenShelf/Convert/DatabaseConversion.swift`, `Convert/PandocConversion.swift` (`arguments(source:to:output:)`, `noNetworkProxy`)
- Check: `swift test --filter refusesToRunSQLFromTheFile`, `swift test --filter pandocRunsSandboxed` and `swift test --filter unsandboxedPandocGetsADeadProxy`.

## Reliability and memory

### 5. calibre without the GPU
calibre's `ebook-convert` runs with `QTWEBENGINE_CHROMIUM_FLAGS=--disable-gpu`, to work around a calibre crash.
- Commits: 2242aa9
- Files: `Sources/OpenShelf/Convert/EbookConversion.swift`, `Convert/ProcessRunner.swift`
- Check: `swift test --filter calibreRunsWithoutTheGPU`.

### 6. A tool's last output is never lost
ProcessRunner reads stdout and stderr on their own threads and waits up to 2 s for both to finish, so a tool's last error line always reaches the toast.
- Commits: 556ed2b
- Files: `Sources/OpenShelf/Convert/ProcessRunner.swift`
- Check: `swift test --filter ProcessOutputTests` (`Tests/OpenShelfTests/ProcessOutputTests.swift`, upstream's copy since 1.5.0).

### 7. ffmpeg race fixes
Frames are decoded before ffmpeg's temporary PNGs are deleted, and progress that arrives after a job ends is dropped.
- Commits: b7f0f32, ab60495
- Files: `Sources/OpenShelf/Tools/Media/MediaLoading.swift`, `Convert/FFmpegJob.swift`
- Check: `swift test --filter MediaRaceTests` (`Tests/OpenShelfTests/MediaRaceTests.swift`, upstream's copy since 1.5.0: `ffmpegFramesOutliveTheirTemporaryFile`, `progressStopsWhenTheJobEnds`).

### 8. PDF pages rendered one at a time
OCR and PDF-to-image release each page before rendering the next one. OCR of a 500-page scan went from 16.4 GB to 485 MB.
- Commits: 207bc44
- Files: `Sources/OpenShelf/Convert/DocumentConversion.swift`, `Tools/OCR.swift`, `Tools/PDF/PDFImagesEditor.swift`
- Check: `swift test --filter pdfPagesAreRenderedOneAtATime` (`Tests/OpenShelfTests/ImageRenderingRegressionTests.swift`, upstream's copy since 1.5.0).

### 9. Excel row limit
Output to XLSX is refused, with a message, when it would pass Excel's 1,048,576 rows.
- Commits: 309934c
- Files: `Sources/OpenShelf/Convert/Spreadsheet.swift`, `Convert/DatabaseConversion.swift`
- Check: `swift test --filter ExcelLimitTests` (`Tests/OpenShelfTests/ExcelLimitTests.swift`, upstream's copy since 1.5.0) and `swift test --filter parquetAndSQLiteOverTheLimitAreRefused` (`MoreConversionTests.swift`, needs duckdb).

### 10. Shared Core Image contexts
The Resize and Remove Background editors reuse one Core Image context instead of making one per render.
- Commits: 81e412e
- Files: `Sources/OpenShelf/Tools/ImageContexts.swift`, `Tools/Editors/ResizeEditor.swift`, `Tools/Editors/RemoveBackgroundEditor.swift`
- Check: `swift test --filter sharedContextsRenderTheSame` (`Tests/OpenShelfTests/ImageRenderingRegressionTests.swift`, upstream's copy since 1.5.0).

## Media edits (Tools wheel)

### 11. Keep the format when editing
An edit saves in the file's own format and codecs: an MP3 stays an MP3 at about its bitrate, and HEVC or ProRes stays HEVC or ProRes. MKV, WebM and AVI are edited with ffmpeg and keep their container. When the format has to change, the toast says why.
- Commits: 74466c7, f67fca7, 258b3e3
- Files: `Sources/OpenShelf/Tools/Media/KeepFormat.swift`, `Tools/Media/MediaFilters.swift`, `Tools/Media/MediaToolsFFmpeg.swift`, `Tools/Media/MediaTools.swift`, `Tools/Media/MediaEdits.swift`, `Convert/MediaFallback.swift`, `Convert/ProbedMedia.swift`, `Tools/EditorWindow.swift`, plus each media editor
- Upstream 1.3.0 lets Trim, Split, Crop and Rotate edit several files at once through `Tools/Media/MediaBatch.swift`; its `sources:` carries the "why the format changed" note there too.
- Check: `swift test --filter KeepFormatTests` (includes `batchEditsSayWhyTheFormatChanged`), `--filter KeepVideoFormatTests` and `--filter ffmpegContainersKeepTheirFormat`.

### 12. Still frame
Saves one frame of a video as a full-size image. It works on one video; with several, a toast says which one opened (`showOneFileNote`, which upstream removed for its own editors).
- Commits: b97e541
- Files: `Sources/OpenShelf/Tools/Media/StillFrame.swift`, `Tools/Media/StillFrameEditor.swift`, `Tools/ToolLauncher.swift`
- Check: `swift test --filter stillFrameSavesAFullSizeImage`.

### 13. Reverse
Plays video and audio backwards. Clips too long to fit in memory are refused.
- Commits: e92b999
- Files: `Sources/OpenShelf/Tools/Media/MediaFilters.swift`
- Check: `swift test --filter reversesPictureAndSound` and `--filter reverseRefusesWhatWouldNotFitInMemory`.

### 14. Strip metadata
Removes tags from video and audio without re-encoding.
- Commits: 8e3ee6c
- Files: `Sources/OpenShelf/Tools/Media/MediaFilters.swift`
- Check: `swift test --filter stripsTagsWithoutReencoding`.

### 15. Mono
Mixes audio down to one channel.
- Commits: 56220fa
- Files: `Sources/OpenShelf/Tools/Media/MediaFilters.swift`
- Check: `swift test --filter mixesDownToOneChannel`.

### 16. Even out loudness
Normalises sound to -16 LUFS.
- Commits: 927e854
- Files: `Sources/OpenShelf/Tools/Media/MediaFilters.swift`
- Check: `swift test --filter bringsSoundToTheTarget`.

### 17. Volume
Makes video and audio louder or quieter without clipping.
- Commits: 18c4a86
- Files: `Sources/OpenShelf/Tools/Media/MediaVolumeEditor.swift`, `Tools/Media/MediaFilters.swift`
- Check: `swift test --filter changesVolumeWithoutClipping`.

### 18. Flip vertically and grayscale
Adds a vertical flip to Rotate and a grayscale tool for video.
- Commits: 911be86
- Files: `Sources/OpenShelf/Tools/Media/Grayscale.swift`, `Tools/Media/VideoRotateEditor.swift`, `Tools/Media/MediaEdits.swift`
- Check: `swift test --filter flipAndGrayscaleChangeThePicture`.

### 19. Frame rate
Changes a video's frame rate and keeps its length.
- Commits: cc96f17
- Files: `Sources/OpenShelf/Tools/Media/FrameRateEditor.swift`, `Tools/Media/MediaFilters.swift`
- Check: `swift test --filter changesTheFrameRateKeepingTheLength`.

### 20. Fit under a size
Re-encodes video or audio to fit under a chosen file size.
- Commits: 83e530c
- Files: `Sources/OpenShelf/Tools/Media/FitSize.swift`, `Tools/Media/FitSizeEditor.swift`
- Check: `swift test --filter fitsUnderTheSize`.

### 21. Compress audio
Re-encodes audio at a chosen bitrate.
- Commits: ebe700d
- Files: `Sources/OpenShelf/Tools/Media/AudioCompression.swift`
- Check: `swift test --filter compressesAudioToTheChosenBitrate`.

### 22. Export in a chosen codec or container
Video as H.264, HEVC, AV1, VP9 or ProRes, or in MPEG, TS, M2TS or VOB. Audio as AAC, ALAC, CAF, PCM, Vorbis or MKA.
- Commits: d5dc473, 37100fe, ec3644a
- Files: `Sources/OpenShelf/Tools/Media/MediaExport.swift`, `Tools/Media/MediaExportEditor.swift`, `Tools/EditorWindow.swift` (`FittingPicker`, in an upstream file), `Tests/OpenShelfTests/MediaExportLayoutTests.swift`
- Check: `swift test --filter exportsInEachCodec`, `--filter exportsSoundInEachFormat` and `--filter exportsBroadcastAndDiscContainers`. Layout: `swift test --filter MediaExportLayoutTests`. The window is 520 pt so every audio format and every container's codecs fit as segments; `FittingPicker` turns them into a menu if they ever don't.

### 23. Transcribe
Turns speech into TXT and SRT, on this Mac, with Apple's speech recognition.
- Commits: 9314e81
- Files: `Sources/OpenShelf/Tools/Media/Transcription.swift`, `Support/Info.plist` (`NSSpeechRecognitionUsageDescription`)
- Check: `swift test --filter writesSRT`. In the app, run Tools → Transcribe on a one-minute audio file; it writes a TXT and an SRT.

## Image and PDF tools

### 24. OCR
Recognises text in images and scanned PDFs and makes text files or searchable PDFs. Pages that already have text are kept as they are.
- Commits: d0b71b4
- Files: `Sources/OpenShelf/Tools/OCR.swift`, `Tools/OCREditor.swift`
- Check: `swift test --filter OCRTests` (`Tests/OpenShelfTests/OCRTests.swift`, upstream's copy since 1.5.0).

### 25. PDF pages to images
Saves chosen pages at a chosen DPI. Offered for one PDF at a time; upstream's other page tools take several.
- Commits: f6ab6eb
- Files: `Sources/OpenShelf/Tools/PDF/PDFImagesEditor.swift`, `Convert/DocumentConversion.swift`, `Tools/FileTool.swift`
- Check: `swift test --filter savesChosenPagesAtTheResolution`.

### 26. Crop to subject
The Crop editor can crop around the subject that Vision finds. With several images (upstream 1.3.0), it crops the one shown, and the others follow while they share one crop.
- Commits: b9382f1
- Files: `Sources/OpenShelf/Tools/Editors/CropEditor.swift`
- Check: `swift test --filter cropsAroundTheSubject`.

### 27. GIF loop count
Sets how many times a GIF plays.
- Commits: e684f12
- Files: `Sources/OpenShelf/Tools/Editors/GIFLoopEditor.swift`
- Check: `swift test --filter setsHowManyTimesAGIFPlays`.

### 28. Icons and animated PNGs
Makes ICNS and ICO icons (ICNS through `iconutil`, so every size is kept). Turns GIFs and video into APNG.
- Commits: 0b6f8df
- Files: `Sources/OpenShelf/Tools/IconMaker.swift`, `Convert/ImageConversion.swift`, `Convert/MediaConversion.swift`
- Check: `swift test --filter makesIconsWithEverySize` and `--filter turnsAGIFIntoAnAnimatedPNG`.

## Conversions (Convert wheel)

### 29. Ebooks with calibre
EPUB, MOBI, AZW3, FB2 and others, to and from each other and PDF, through calibre's `ebook-convert`.
- Commits: 4cd1c39
- Files: `Sources/OpenShelf/Convert/EbookConversion.swift`, `Convert/ExternalTools.swift`, `Convert/FileKind.swift`, `Convert/OutputFormat.swift`
- Check: `swift test --filter convertsBooksBothWays`.

### 30. Markup documents with pandoc
LaTeX, Typst, reST, AsciiDoc and Org, to and from Markdown, Word, HTML, EPUB and text. Markdown ↔ Word, HTML and EPUB without markup is upstream's engine since 1.6.0. Pandoc's row in Settings → Extra Formats (upstream's) lists these formats.
- Commits: e5e1b51
- Files: `Sources/OpenShelf/Convert/PandocConversion.swift` (`handles`, `markupWriter`, `convertMarkup`), `Convert/Converter.swift`, `Convert/ExtraFormats.swift` (`ExtraTool.pandoc.unlocks`)
- Check: `swift test --filter convertsMarkupBothWays`.

### 31. Data files
JSON, YAML, XML, property lists and CSV. Foundation handles JSON and plists; yq handles the rest.
- Commits: 946b13a
- Files: `Sources/OpenShelf/Convert/DataConversion.swift`
- Check: `swift test --filter yamlXMLAndCSVWithYQ` and `--filter jsonAndPropertyListsWithFoundation`.

### 32. EDN with jet
EDN to and from JSON and YAML. Keys are not keywordized, so keys like "weird key" survive the round trip.
- Commits: aaf2e3f
- Files: `Sources/OpenShelf/Convert/EdnConversion.swift`
- Check: `swift test --filter ednRoundTrips`.

### 33. Parquet and SQLite
Parquet, SQLite, CSV and XLSX to and from each other through duckdb and sqlite3. Includes a table picker for SQLite files.
- Commits: e31f6ad
- Files: `Sources/OpenShelf/Convert/DatabaseConversion.swift`, `Tools/SQLiteTablesEditor.swift`
- Check: `swift test --filter parquetAndSQLiteRoundTrip`.

### 34. Archives
Packs files and folders as tar.xz, tar.zst and 7z with bsdtar.
- Commits: fe9573e
- Files: `Sources/OpenShelf/Convert/ArchiveConversion.swift`, `Convert/ConversionRunner.swift`
- Check: `swift test --filter bsdtarWritesEachFormat`.

### 35. Subtitles
SRT, VTT, ASS, SSA and TTML through ffmpeg.
- Commits: 7020449
- Files: `Sources/OpenShelf/Convert/SubtitleConversion.swift`
- Check: `swift test --filter convertsSubtitlesThroughFFmpeg`.

### 36. JPEG XL
Writes JXL with `cjxl`.
- Commits: c953578
- Files: `Sources/OpenShelf/Convert/ImageConversion.swift`, `Convert/ExternalTools.swift`
- Check: `swift test --filter writesAndReadsJPEGXL`.

## Shelves, wheel and file actions

### 37. New shelves open expanded
- Commits: 755a174
- Files: `Sources/OpenShelf/Shelf/Shelf.swift`
- Check: `swift test --filter newShelvesOpenExpanded`.

### 38. Hide Shelves / Show Shelves
A menu item hides every shelf and brings them all back. A new shelf or a drop while hidden shows them again.
- Commits: 45756ef
- Files: `Sources/OpenShelf/Shelf/ShelfManager.swift`, `Shelf/ShelfWindowController.swift`, `App/OpenShelfApp.swift`
- Check: `swift test --filter HideShelvesTests`.

### 39. ⌘-number wedges
On the keyboard wheel, ⌘1–⌘7 run that wedge and ⌘0 opens More. Each wedge shows its number as a badge.
- Commits: e543433
- Files: `Sources/OpenShelf/Wheel/WheelKeyboard.swift`, `Wheel/WheelController.swift`, `Wheel/WheelView.swift`
- Check: `swift test --filter WheelBadgeTests` (`Tests/OpenShelfTests/WheelBadgeTests.swift`, upstream's copy since 1.5.0, with ⌘⌥-number and pass-through cases).

### 40. Wheel on selected shelf items
"Open Wheel for Selection" opens the wheel on the selected shelf items when a shelf is in front, and on Finder's selection otherwise. Moving files from that wheel moves the shelf items too.
- Commits: a2c6d6f
- Files: `Sources/OpenShelf/App/FinderSelection.swift`, `App/AppDelegate.swift`, `App/OpenShelfApp.swift`, `Shelf/ShelfManager.swift`
- Check: `swift test --filter shortcutPicksTheSelectionInFront` (`Tests/OpenShelfTests/ShelfWheelSelectionTests.swift`, upstream's copy since 1.5.0) and `swift test --filter aMoveFromTheWheelMovesTheShelfItemsToo` (`HideShelvesTests.swift`).

### 41. Open in iTerm2
The Terminal action opens folders in iTerm2 when it is installed, and in Terminal otherwise.
- Commits: 4fb8b48
- Files: `Sources/OpenShelf/Support/FileActions.swift`, `Wheel/WheelItem.swift`
- Check: `swift test --filter prefersITermThenTerminal`.

### 42. Copy Name
Copies file names, next to Copy Path.
- Commits: 9237917
- Files: `Sources/OpenShelf/Support/FileActions.swift`, `Shelf/Views/ShelfMenu.swift`, `Wheel/WheelItem.swift`
- Check: `swift test --filter copyNameSitsNextToCopyPath`.

### 43. Copy to a folder, and the name-clash dialog
Copy asks for a folder, the way Move does. When a name is already taken, a dialog offers Keep Both (the default), Overwrite (sends the old file to the Trash), Cancel, and Apply to all.
- Commits: 9dcc640, 634e18d
- Files: `Sources/OpenShelf/Support/FileActions.swift`, `App/AppDelegate.swift`
- Check: `swift test --filter copiesIntoAFolderKeepingTheOriginals`, `--filter overwriteSendsTheOldOneToTheTrash` and `--filter applyToAllAsksOnce`.

## Source code

### 44. Pretty Print
A Tools-wheel wedge that saves a re-formatted copy as `name.formatted.ext` next to the original. It shows only when every file has an installed formatter. An already-formatted file gets "Already formatted" and no new file. A formatter error saves nothing and the toast shows the error line.
- Formatters: deno (JS, TS, JSON, YAML, Markdown, HTML, CSS), cljfmt (Clojure, EDN), ruff (Python), shfmt (sh, bash), Xcode's swift-format, `/usr/bin/xmllint` (XML), pg_format (SQL, `brew install pgformatter`), clang-format (C, C++, Obj-C), gofmt, rustfmt.
- Lockdown: the file goes in on stdin and never by path. Each formatter runs in an empty temp folder that is also its HOME, with the child-process env allowlist, and gets explicit config: `deno fmt --no-config` plus indent options (deno reads .editorconfig otherwise), `cljfmt --config`, `ruff --isolated`, `shfmt -i 2`, `swift-format --configuration`, `xmllint --nonet`, `pg_format --no-rcfile`, `clang-format --style=LLVM`, `rustfmt --config-path` (cljfmt and rustfmt search parent folders otherwise).
- Commits: this one
- Files: `Sources/OpenShelf/Tools/PrettyPrint.swift`, `Convert/ExternalTools.swift` (`Formatters`), `Tools/FileTool.swift`, `Tools/ToolLauncher.swift`, `Convert/ConversionRunner.swift` (`unchangedLabel`)
- Check: `swift test --filter PrettyPrintTests`. `configsNearTheFileAreIgnored` plants configs next to the file and in the folder above it, and fails if any formatter follows one.

### 45. Settings lists every tool, and missing-tool hints name it
Settings → Extra Formats has a collapsed "Command-Line Tools · N of M installed" row under ffmpeg, LibreOffice and Pandoc (Pandoc moved to upstream's own row in 1.7.0). It opens to every other tool OpenShelf finds: cwebp, calibre, yq, cjxl, DuckDB, jet, the ten Pretty Print formatters and commonforms (#47). Each row shows Installed · Homebrew (path on hover) or Copy Homebrew Command; jet's row says its tap is third-party, not homebrew-core. Whether the list is open is remembered. The "X needs Y" toast uses the same list: an EPUB without calibre says "EPUB needs calibre / brew install --cask calibre", and an empty Tools wheel names the missing formatter ("PY needs ruff"). Wheels offering only ZIP, tar and 7z count as having nothing.
- Commits: this one
- Files: `Sources/OpenShelf/Convert/CommandLineTool.swift`, `Convert/ExtraFormats.swift` (`MissingTool`, `MissingToolAdvice`), `Settings/ExtraFormatsPane.swift`, `Settings/SettingsTab.swift`, `App/Preferences.swift` (`showsCommandLineTools`), `App/AppDelegate.swift`
- Check: `swift test --filter CommandLineToolTests` (fails when `ExternalTools` resolves a tool with no Settings row), `--filter MissingToolAdviceTests` and `--filter panesHaveAHeightToFit` (collapsed pane under 700 pt).

### 46. Add Background fits its window
The Background swatches sit 1 pt apart instead of 3, so nine colours and the colour well fit the 460 pt window; at 3 pt the editor needed 471 pt and the window clipped both sides.
- Commits: this one
- Files: `Sources/OpenShelf/Tools/Editors/AddBackgroundEditor.swift` (an upstream file), `Tests/OpenShelfTests/AddBackgroundLayoutTests.swift`
- Check: `swift test --filter AddBackgroundLayoutTests` (one image and several).

## PDF

### 47. Make Fillable
A PDF Tools-wheel wedge, for one PDF at a time, that saves `name.fillable.pdf` next to the original with form fields where the blanks, boxes and signature lines are. It uses commonforms (`uv tool install commonforms`, about 1.6 GB, not bundled), found on the PATH folders, in `~/.local/bin`, or in uv's or pipx's commonforms venv. The wedge shows only when commonforms is installed. Settings → Extra Formats lists it with "Copy Install Command". A run that finds no fields saves nothing and says "No fields found". A PDF that already has form fields is refused: the window says "This PDF is already fillable" and greys out the button, and the run stops before commonforms starts, since commonforms would stack a same-named field on top of each old one. The window warns "Scanned pages may miss most fields" when a page has no text, and "Downloading the form model, 18 MB, first time only" until the FFDNet-S model is in `~/.cache/huggingface`.
- Command: `commonforms input.pdf output.pdf --model FFDNet-S --use-signature-fields`, plus `--keep-existing-fields` when the PDF has any annotations, since commonforms otherwise deletes all of them (links and comments too). It runs on a copy named `input.pdf` in an empty temp folder. Closing the window stops it and saves nothing.
- Lockdown: the child-process env allowlist; HOME, TMPDIR, XDG_CONFIG_HOME and YOLO_CONFIG_DIR are the temp folder. `YOLO_OFFLINE=true` stops ultralytics' Google Analytics event on every run and its online checks ("true", since ultralytics 8.3 ignores "1"); `YOLO_AUTOINSTALL=0` stops its pip installs. `HF_HUB_OFFLINE=1` once the model is cached, `HF_HUB_DISABLE_TELEMETRY=1`, and `HF_HUB_DISABLE_IMPLICIT_TOKEN=1` so a saved Hugging Face token is never sent.
- Commits: this one
- Files: `Sources/OpenShelf/Tools/PDF/MakeFillable.swift`, `Tools/PDF/MakeFillableEditor.swift`, `Tools/FileTool.swift`, `Tools/ToolLauncher.swift`, `Convert/ExternalTools.swift`, `Convert/CommandLineTool.swift` (`installCommand`, `installNote`), `Convert/ExtraFormats.swift`, `Settings/ExtraFormatsPane.swift`
- Check: `swift test --filter MakeFillableTests` (flags and env, through a stub commonforms; no fields found; an already-fillable PDF is refused before commonforms runs; scanned and locked pages; model cache; cancelling; wheel) and `--filter CommandLineToolTests`. With commonforms installed and its model cached, `keepsALinkAndSavesNextToTheOriginal` also runs the real tool. In the app: drag a PDF form with a link to the Tools wheel, pick Make Fillable, and check the copy has fields and the link still works.

## Outside the repo

- `~/bin/update-all.sh` checks for upstream commits with `check_upstream "$HOME/Dropbox/Dev/OpenShelf" upstream OpenShelf`. It only reports them and never merges.
- Every push goes to both branches: `git push origin djnesmith djnesmith:main`, fast-forward only.
