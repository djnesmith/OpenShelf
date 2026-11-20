Read this before merging upstream. Every item must still work after the merge.

# Fork features

What `djnesmith/OpenShelf` adds over `Manan-Santoki/OpenShelf`. The list comes from
`git log upstream/main..djnesmith`. Rule: every new feature adds its entry here and a line to
the "What this fork adds" block at the top of `README.md`, in the same commit.
Planned features and the order to build them in are in `ROADMAP.md`.

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

Upstream 1.8.0 and 1.8.1 added Pages, Numbers and Keynote conversions, watched folders,
and Shortcuts actions (App Intents). Upstream's releases leave the Shortcuts actions out
(`SKIP_APPINTENTS=1`) because macOS won't run them from an ad-hoc signed app; the fork's
`make app` keeps them, since it signs with a team ID (#2). The fork's formats are in
upstream's Shortcuts format list too (`IntentFormat` in `Intents/FileIntents.swift`), and
Convert Files packs TAR.XZ, TAR.ZST and 7Z into one archive, as the wheel does (#34).

Upstream 1.8.2 and 1.9.0 added whisper.cpp transcripts (TXT, SRT, VTT on the Convert wheel),
its own calibre ebook conversions, Pandoc ODT output and EPUB input, and Word to PDF through
Quick Look. None of it downloads anything: whisper.cpp and calibre are only found, and the
speech model is added by hand to `~/Library/Application Support/OpenShelf/Models`. The merge
renamed the fork's Apple-speech Transcribe to `SpeechTranscription` (#23), since upstream's
whisper.cpp converter is `Transcription`. `EbookConversion.swift` is upstream's (crash retry,
temp folder) with the fork's formats and environment on top (#29). Upstream's own "Command-line
tools" Settings section was left out; whisper.cpp joined the fork's list instead (#45). Not
verified: Word to PDF prints Quick Look's HTML preview in a WebKit view, which could fetch a
picture a Word file links by web address.

Upstream 1.10.0 added Developer ID signing and notarization (`scripts/sign.sh`,
`scripts/notarize.sh`, and `make notarize` targets), a Homebrew cask, a Sparkle feed on its
`appcast` branch, and About OpenShelf in the menu-bar menu. The merge keeps About and the
1.10.0 version number. It keeps the fork's Makefile, so builds sign with the fork's identity
(not ad-hoc) and have no Sparkle (#1, #2); the fork has no `notarize` targets, and `sign.sh`
and `notarize.sh` are in the tree but unused. README.md, CHANGELOG.md, docs/SPEC.md and the
DMG background are upstream's and describe upstream's builds and releases: ad-hoc local
builds, self-updating, notarized, installed with Homebrew. None of that applies to this
fork; where they disagree with this file, this file is right. Don't install upstream's
Homebrew cask here: with `--force` it would replace the fork's app in
`/Applications/OpenShelf.app` with upstream's self-updating one.

## Security

### 1. No in-app updates
Sparkle is gone, so the app never downloads or installs updates by itself. Upstream 1.4.0's update reminder (a blue menu-bar icon and an "Update to Version…" item) needs Sparkle, so the merge leaves it out; `MenuBarIcon.updateAvailableImage` is unused.
- Commits: 28bb48c, f036332 (the Makefile no longer fetches Sparkle)
- Files: `Package.swift`, `Makefile`, `Support/Info.plist`, `Sources/OpenShelf/App/AppDelegate.swift`, `App/OpenShelfApp.swift`, `Settings/SettingsPanes.swift`, `Settings/SettingsTab.swift` (`App/Updater.swift` deleted)
- Check: `grep -rw Sparkle Package.swift Makefile Support Sources` finds nothing. With the app running, `lsof -nP -i -a -p $(pgrep -x OpenShelf)` shows no sockets.

### 2. David's signing identity and bundle ID
Builds are signed as "Apple Development: David Nesmith (JFGJA89Z8H)" with the hardened runtime. The bundle ID is `com.djnesmith.OpenShelf`. The only entitlement is `com.apple.security.automation.apple-events`, which is needed to read Finder's selection and to ask Pages, Numbers and Keynote to export copies.
- Commits: f036332
- Files: `Makefile` (`SIGN_IDENTITY ?=`; `bundle_app` adds upstream's App Intents metadata before signing), `Support/Info.plist`, `Support/OpenShelf.entitlements`, `Sources/OpenShelf/Convert/ExternalTools.swift` (the `defaults` domain in a comment)
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
- Files: `Sources/OpenShelf/Tools/Media/SpeechTranscription.swift` (`SpeechTranscription`, renamed in the 1.9.0 merge), `Support/Info.plist` (`NSSpeechRecognitionUsageDescription`)
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
Since 1.9.0 the code is upstream's `EbookConversion`, plus the fork's FB2 in and out, Word and text out (calibre still makes these from EPUB when Pandoc is installed too; upstream would use Pandoc), and PDF to FB2. Pandoc adds Markdown, HTML and ODT for EPUB. A book with neither tool still offers every archive format.
- Commits: 4cd1c39
- Files: `Sources/OpenShelf/Convert/EbookConversion.swift`, `Convert/ExternalTools.swift`, `Convert/FileKind.swift`, `Convert/OutputFormat.swift`
- Check: `swift test --filter convertsBooksBothWays`.

### 30. Markup documents with pandoc
LaTeX, Typst, reST, AsciiDoc and Org, to and from Markdown, Word, HTML, EPUB and text. Markdown ↔ Word, HTML and EPUB without markup is upstream's engine since 1.6.0. Pandoc's row in Settings → Extra Formats (upstream's) lists these formats. A wheel with one format too many leaves out ADOC: ODT, DOCX, RTF, Markdown and HTML with pandoc (upstream's ODT output takes the wedge), and TXT with Pages too. DOCX and RTF with both Pandoc and Pages have two too many and also leave out TYP. RST, ORG, TEX, ODT and PAGES always keep their wedges (David's call, 1.9.0 merge). Shortcuts' Convert Files offers every format, uncapped (`IntentRouting.formats`).
- Commits: e5e1b51
- Files: `Sources/OpenShelf/Convert/PandocConversion.swift` (`handles`, `markupWriter`, `convertMarkup`), `Convert/Converter.swift`, `Convert/ExtraFormats.swift` (`ExtraTool.pandoc.unlocks`), `Convert/OutputFormat.swift` (the ADOC-then-TYP rule in `ConversionCatalog.formats`)
- Check: `swift test --filter convertsMarkupBothWays`, `--filter iWorkOutputsNeedTheirApp`, `--filter odtWheelKeepsOrg`, `--filter wheelsStayWithinTwelveWedges` and `--filter shortcutsOfferFormatsTheWheelHasNoRoomFor`.

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
A menu item hides every shelf and brings them all back. A new shelf, a drop or a watched-folder arrival (upstream 1.8) while hidden shows them again.
- Commits: 45756ef
- Files: `Sources/OpenShelf/Shelf/ShelfManager.swift`, `Shelf/ShelfWindowController.swift`, `App/OpenShelfApp.swift`
- Check: `swift test --filter HideShelvesTests` (includes `everyWatchedFolderArrivalWhileHiddenShowsThemAll`).

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
Settings → Extra Formats has a collapsed "Command-Line Tools · N of M installed" row under ffmpeg, LibreOffice and Pandoc (Pandoc moved to upstream's own row in 1.7.0). It opens to every other tool OpenShelf finds: cwebp, calibre, whisper.cpp (with upstream's "Open Models Folder" button while it has no speech model), yq, cjxl, DuckDB, jet, the ten Pretty Print formatters, commonforms (#47), qpdf (#48) and aubio (#49). Each row shows Installed · Homebrew (path on hover) or Copy Homebrew Command; jet's row says its tap is third-party, not homebrew-core. Whether the list is open is remembered. The "X needs Y" toast uses the same list: an EPUB without calibre says "EPUB needs calibre / brew install --cask calibre" (books name calibre first, though Pandoc reads EPUB too; upstream shows no hint), and an empty Tools wheel names the missing formatter ("PY needs ruff"). Wheels offering only ZIP, tar and 7z count as having nothing.
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
A PDF Tools-wheel wedge, for one PDF at a time, that saves `name.fillable.pdf` next to the original with form fields where the blanks, boxes and signature lines are. It uses commonforms (`uv tool install commonforms`, about 1.6 GB, not bundled), found on the PATH folders, in `~/.local/bin`, or in uv's or pipx's commonforms venv. The wedge shows only when commonforms is installed. Settings → Extra Formats lists it with "Copy Install Command". When the small FFDNet-S model finds no fields, it runs once more with FFDNet-L, which fills typed forms S can miss (a 2-page NCISAA concussion form: S found 0 fields, L found 25). A run where neither finds a field saves nothing and says "No fields found". A PDF that already has form fields is refused: the window says "This PDF is already fillable" and greys out the button, and the run stops before commonforms starts, since commonforms would stack a same-named field on top of each old one. The window warns "Scanned pages may miss most fields" when a page has no text, and "Downloading the form model, 18 MB, first time only" until the FFDNet-S model is in `~/.cache/huggingface`, then "May download a larger form model, 49 MB, if the first finds nothing" until FFDNet-L is too.
- Command: `commonforms input.pdf output.pdf --model FFDNet-S --use-signature-fields` (then `--model FFDNet-L` if S found nothing), plus `--keep-existing-fields` when the PDF has any annotations, since commonforms otherwise deletes all of them (links and comments too). It runs on a copy named `input.pdf` in an empty temp folder. Closing the window stops it and saves nothing.
- Lockdown: the child-process env allowlist; HOME, TMPDIR, XDG_CONFIG_HOME and YOLO_CONFIG_DIR are the temp folder. `YOLO_OFFLINE=true` stops ultralytics' Google Analytics event on every run and its online checks ("true", since ultralytics 8.3 ignores "1"); `YOLO_AUTOINSTALL=0` stops its pip installs. `HF_HUB_OFFLINE=1` once the model that run uses is cached, `HF_HUB_DISABLE_TELEMETRY=1`, and `HF_HUB_DISABLE_IMPLICIT_TOKEN=1` so a saved Hugging Face token is never sent.
- Commits: this one
- Files: `Sources/OpenShelf/Tools/PDF/MakeFillable.swift`, `Tools/PDF/MakeFillableEditor.swift`, `Tools/FileTool.swift`, `Tools/ToolLauncher.swift`, `Convert/ExternalTools.swift`, `Convert/CommandLineTool.swift` (`installCommand`, `installNote`), `Convert/ExtraFormats.swift`, `Settings/ExtraFormatsPane.swift`
- Check: `swift test --filter MakeFillableTests` (flags and env, through a stub commonforms; FFDNet-L after S finds nothing; no fields found; an already-fillable PDF is refused before commonforms runs; scanned and locked pages; model cache for S and L; cancelling; wheel) and `--filter CommandLineToolTests`. With commonforms installed and its model cached, `keepsALinkAndSavesNextToTheOriginal` also runs the real tool. In the app: drag a PDF form with a link to the Tools wheel, pick Make Fillable, and check the copy has fields and the link still works.

### 48. Check Safety
A PDF Tools-wheel wedge, for one or more PDFs, that shows a read-only report: for each file, the risky markers it has with counts, then SAFE, CHECK or NOT SAFE. With several files the worst verdict is on top. It never changes the PDF. The report ends with "This is a triage, not an antivirus."
- NOT SAFE: /JS, /JavaScript, /Launch, /EmbeddedFile(s), /RichMedia or /XFA. CHECK: /AcroForm, /Encrypt, /JBIG2Decode, /ObjStm, /OpenAction or /AA (without JavaScript), a qpdf warning, or a file qpdf can't read. SAFE: none of these.
- Command: `qpdf --json=2 --json-key=qpdf --json-key=encrypt --json-stream-data=none --warning-exit-0 file.pdf`. Only real dictionary keys and name values count, so "/JS" bytes inside stream data don't. qpdf (`brew install qpdf`) isn't bundled; the wedge shows only when it's installed, and Settings → Extra Formats lists it with "Copy Homebrew Command".
- A file qpdf can't read: its raw bytes are searched for the NOT SAFE names as whole name tokens (/JS counts, /JSON doesn't). Any hit is NOT SAFE ("qpdf could not parse; raw bytes contain /JS /JavaScript (…)"); none is CHECK. Files qpdf reads never use the raw bytes.
- Commits: e05a1f8, and this one (the raw-byte fallback)
- Files: `Sources/OpenShelf/Tools/PDF/CheckSafety.swift`, `Tools/PDF/CheckSafetyEditor.swift`, `Tools/FileTool.swift`, `Tools/ToolLauncher.swift`, `Convert/ExternalTools.swift`, `Convert/CommandLineTool.swift`
- Check: `swift test --filter CheckSafetyTests` (clean, /OpenAction only, JavaScript, embedded file, unreadable file, JavaScript bytes in an unreadable file are NOT SAFE, whole-name matching, "/JS" bytes in a stream stay SAFE, the file is unchanged, worst verdict on top, wedge hidden without qpdf; the qpdf tests skip when it isn't installed) and `--filter CommandLineToolTests`. In the app: drag two PDFs to the Tools wheel, pick Check Safety, and check the report.

## Audio

### 49. BPM
An audio Tools-wheel wedge, for one or more files, that shows a small read-only window with one line per file: "drums.mp3 — 146 BPM". It never changes the file.
- Command: `aubio tempo file`. aubio prints "146.44 bpm", "… bpm (uncertain)" (under 10 beats), "unknown bpm", or exits 1 with an `AUBIO ERROR`. The app rounds to a whole number and shows "(uncertain, few beats)", "no steady beat found", or "couldn’t read: <aubio's error>". The error is aubio's own `AUBIO ERROR` line (not Python's last traceback line), with the file name in place of its path. "inf bpm" or no tempo line counts as no steady beat. A failed file doesn't stop the others.
- aubio (`brew install aubio`) isn't bundled; the wedge shows only when it's installed, and Settings → Extra Formats lists it with "Copy Homebrew Command".
- Offered for WAV, MP3, M4A, AIF/AIFF, CAF, AAC and Opus only. Known gap: Homebrew's aubio 0.4.9 can't read FLAC ("source_apple_audio: … ('fmt?')") or OGG ("could not find RIFF header"), so files of those kinds don't get the wedge.
- aubio can read half or double the real tempo (the window says so), and repeat runs are not always identical, because aubio's beat tracker sometimes finds a different number of beats: on an unchanged drums.mp3, 19 of 120 runs gave 146.63 instead of 146.44 (both show as 146), and a rare run gives 145.31, which shows as 145. The same song as M4A and as MP3 can differ by about 2 BPM.
- Commits: this one
- Files: `Sources/OpenShelf/Tools/Media/BPM.swift`, `Tools/Media/BPMEditor.swift`, `Tools/FileTool.swift`, `Tools/ToolLauncher.swift`, `Convert/ExternalTools.swift`, `Convert/CommandLineTool.swift`
- Check: `swift test --filter BPMTests` (aubio's real output lines, the exact command, several files in order, a failing file, aubio's error line over Python's, no tempo line, aubio missing, wedge only with aubio and only for the formats it reads; one test runs the real aubio on /System/Library/Sounds/Funk.aiff when it's installed) `--filter WheelOrderingTests` (BPM is last on a one-file audio wheel, so Compress stays on page 2) and `--filter CommandLineToolTests`. In the app: drag two songs to the Tools wheel, pick BPM, and compare with `aubio tempo` by hand.

## Selected text

### 50. Text wheel for selected text
Select text in any app and press the wheel shortcut (⌃⌥Space): a Text wheel opens at the pointer. The chosen tool replaces the selection; ⌥ copies the result instead, ⇧ saves it as a file on a shelf. Finder (and shelf selections) work exactly as before: the shortcut only looks for text when Finder isn't in front.
- Wheel: Undo (only when the selection is OpenShelf's last result in that app) · Trim · Clean Up · Re-indent (code and data) · Convert ▸ (JSON, YAML, EDN, XML, TOML, for data) · To Markdown (prose) · More ▸ (Lines ▸, Case ▸ and Indent ▸, see #51; Trim Lines, Straight Quotes). Sub-wheels replace the wheel in place and end in Back, which returns to the wheel they opened from; every list fits the 7-wedge wheel.
- Reading: Accessibility's selected text, each call capped at 0.25 s; apps that don't answer get ⌘C, and the clipboard is put back. Only a focused password field (Accessibility subrole AXSecureTextField: a password input in a browser, 1Password, the Passwords app) is refused, with a toast; every other field and app works, including Terminal or iTerm2 with Secure Keyboard Entry and any app while macOS's secure-input flag is on. Without Accessibility, the shortcut asks once per launch (macOS's prompt) and says where to turn it on.
- Writing: the result is pasted (⌘V) so the app's own ⌘Z undoes it, marked `org.nspasteboard.TransientType` so clipboard managers skip it; the clipboard is restored 300 ms later unless something else wrote to it. If the selection changed meanwhile, the result is copied instead. The last 10 changes are kept in memory only.
- Per app (`Text/TextApps.swift`, `TextAppStrategy`): terminals (iTerm2, Terminal, Ghostty, WezTerm, Alacritty, kitty, Warp) never get a synthetic key, since a profile can map ⌘C to Ctrl-C and interrupt the running program. They read Accessibility or else the clipboard (the wheel shows "Copied: <first line>"), and the result is only copied ("Trimmed and copied"); ⌃ pastes it back (for vim's insert mode), ⇧ saves to a shelf. A terminal can hold a selection OpenShelf can't read (herdr and other mouse-driven TUIs draw their own); then the clipboard is used, and only with no text there does a toast say there is nothing to work on. GUI Emacs (`org.gnu.Emacs`) is read and replaced through emacsclient as one undoable change (the evil visual range or the active region). Other apps: Accessibility, then ⌘C, written back by paste.
- Copied text, any app: when nothing is selected, the last way in is the clipboard's text, however long ago it was copied (David: "the text changes should work in any text editing field or on copied text"; 2026-11-19: "if there is no text selected then it should just automatically work on the clipboard", which dropped the 60-second limit and the "Copy first" toast). A selection always wins. With no selection to replace, the result is only copied ("Copied: …" on the wheel, "On the clipboard" after, the hint says "Return copies · ⌃ pastes · ⇧ to shelf"); ⌃ pastes it at the cursor. ⌘C with nothing selected leaves the clipboard as it was (nothing is restored because nothing changed), and OpenShelf's own ⌘C and paste don't count as a new copy (`ClipboardWatcher.willBorrow`/`didRestore` keep the copy's age). A focused password field is still refused first.
- Where the result goes (David, 2026-11-20): a selection that can be changed is replaced in place and the clipboard put back ("Replaced"); a selection that can't be changed (a web page, a PDF, a message being read in Mail) goes on the clipboard ("On the clipboard", "…; this text can't be changed here"), where it used to be pasted into nothing and lost; text from the clipboard goes back on the clipboard. Tools, Undo, Convert and the Edit window's ⌘↩ all follow it; cancelling leaves the clipboard as it was. Whether a selection can be changed comes from Accessibility when the wheel opens (`AccessibilityText.selectionIsEditable`: AXEditable, or a settable value or selected text); when it can't tell (apps read with ⌘C, such as Chrome pages or some Electron apps), it pastes as before.
- When nothing is found the toast names the app and what to do; the Finder message only shows for Finder. Each decision is logged without the text: `log show --last 1h --predicate 'subsystem == "com.djnesmith.OpenShelf"'`.
- Trim, Clean Up and the More tools are pure Swift, in memory. Re-indent uses Pretty Print's formatters (JSON falls back to Foundation without deno); Convert uses the data converters (yq, jet) and yq for TOML; To Markdown copies the formatted selection and converts its HTML or RTF.
- Commits: this one
- Files: `Sources/OpenShelf/Text/` (all), `App/AppDelegate.swift`, `Wheel/WheelController.swift` (`presentForKeyboard(items:title:summary:hint:at:)`), `Wheel/WheelItem.swift`
- Check: `swift test --filter 'TextTransformsTests|TextSnifferTests|TextWheelTests|TextHistoryTests|HotkeyRouteTests|ClipboardRelayTests|TextConversionTests|EmacsClientTests'`, and `OPENSHELF_TOOL_TESTS=1` for the real yq, jet, deno and pandoc runs and the Emacs elisp in a batch Emacs. In the app: select text in TextEdit, press ⌃⌥Space, Trim, then ⌘Z; in iTerm2 select, ⌘C, ⌃⌥Space, Trim, and the result is on the clipboard; in Emacs select a region, Trim, then undo once; and with files selected in Finder, the shortcut still opens the file wheel.

### 51. Lines and Case tools on the text wheel
More ▸ holds Lines ▸ · Case ▸ · Fix ▸ · Format ▸ · Code ▸ · Extract ▸ (David's layout, 2026-11-18; see #55). Indent ▸ is under Format ▸, Trim Lines and Straight Quotes under Fix ▸. The tools work like the rest of the text wheel (replace the selection, ⌥ copies, ⇧ to a shelf, copy-only in terminals with ⌃ to paste, Undo wedge); a result the same as the selection shows "Nothing to change".
- Lines ▸: Sort A–Z (case ignored, ties keep their order) · Remove Duplicates (exact, the first stays) · Remove Blank Lines · Order ▸ (Sort Natural, as Finder sorts numbers; Sort by Length; Reverse; Shuffle) · Join & Split ▸ (Join with Commas, Join with Spaces, Split at Commas, Split at Spaces) · Lists ▸ (Number, Markdown List, CSV → Table, Quote, Unquote, Add Commas).
- Case ▸: UPPER · lower · Title Case (keeps inner capitals such as "iPhone"; all-caps text is lowered first; no small-word rule) · Sentence case (lowers everything, then capitals after . ! ? and blank lines) · Code Case ▸ (camelCase, PascalCase, snake_case, kebab-case, CONSTANT_CASE, line by line; words split at spaces and punctuation, lower-to-upper changes, and acronyms, so "HTTPServer" is HTTP + Server).
- Indent ▸: Dedent, Indent, Outdent, Tabs ↔ Spaces (moved from More).
- Line tools keep the line ending (CRLF, LF, a lone CR or U+2028) and a final newline; Join keeps it too, so the next line isn't pulled up. Sorts put blank lines last. Split keeps blank lines. Number goes after the indentation and renumbers lines already numbered. Shuffle always gives a new order when there is one. Unquote only takes quotes off a line that is one quoted string. CSV → Table uses tabs when the first line has one, reads quoted fields (commas, doubled quotes, line breaks), pads short rows and escapes `|`; a quote that never closes is read as an ordinary character.
- Not built, needs a text field the wheel doesn't have: join or split with a separator you type, and a prefix or suffix you type. Fixed variants stand in (commas, spaces, quotes, "1. ", "- ").
- Commits: this one
- Files: `Sources/OpenShelf/Text/LineTransforms.swift`, `CaseTransforms.swift`, `TextWheel.swift` (`TextGroup.wedges`, `parent`), `SelectedTextController.swift` (Back to the parent wheel)
- Check: `swift test --filter 'LineTransformsTests|CaseTransformsTests|TextWheelTests'`. In the app: select three lines in Mail, ⌃⌥Space, More ▸, Lines ▸, Sort A–Z, then ⌘Z.

### 52. Search on the wheel
Type while a keyboard wheel is open (the ⌃⌥Space text wheel, Finder or a shelf, or a drag dropped on More) and a search bar replaces the label above it: the wedges become the tools that match, best first, from every wheel this one leads to, across pages and sub-wheels. The label names the highlighted match and where it lives ("Sort Natural · Lines › Order").
- Keys: a letter or digit starts the search (⌃, ⌥ and ⌘ letters don't); ⌘F opens it too, and when it holds text selects it all so the next letter replaces it. Backspace to empty or Esc puts the wheel back as it was (same wedges, page and highlight); a second Esc closes it. While searching, a ⇧ or ⌃ tap doesn't switch wheels (⇧ is for capitals). Arrows, Return, ⌘+number, clicks and ⌥/⇧ on Return work on the matches as on any wheel. Tab leaves the search and switches wheels. "Type to search · ⌘F" follows the opening hint.
- Matching (`Wheel/WheelSearch.swift`): every word of the query must appear, its letters in order, in the title or a keyword ("dedupe" finds Remove Duplicates, "csv" finds CSV → Table); word starts, runs and prefixes score higher; case and accents are ignored. Ties go to tools used lately (this launch only), then to the wheel's own order.
- Running a match is the same as clicking its wedge, so paste-back, copy-only in terminals and the single undo are unchanged.
- Not built: no typing method for accented letters (é needs ⌥e then e, which the wheel doesn't compose; the plain letter finds it); formats the 12-wedge Convert cap leaves out are not searched; recent tools are forgotten when OpenShelf quits.
- Commits: this one
- Files: `Sources/OpenShelf/Wheel/WheelSearch.swift`, `WheelController.swift` (`handleKey`, search state), `WheelView.swift` (`SearchPill`), `KeyboardWheel.swift` (hint), `Text/TextWheel.swift` (`searchCandidates`), `Text/SelectedTextController.swift`
- Check: `swift test --filter 'WheelSearch|WheelBadge'`. In the app: select lines in Mail, ⌃⌥Space, type "sort", Return, then ⌘Z.

### 53. Edit window with vim keys
Edit, on the text wheel's first ring after Undo, opens the selection (or the copied text) in a window with vim keys. ⌘↩, `:wq`, `:x`, `:w` or `ZZ` puts the text back where a tool's result would go: over the selection, or on the clipboard for copied text and terminals (⌥ held on Edit copies). Minutes may pass, so Edit pastes only over a selection that reads back as the same text; a field that is gone, a collapsed caret, a password field or an app that quit gets the text copied instead, with a toast saying why. Apps read with ⌘C can't be read back, so they paste as the tools do; copied text and terminals paste at the cursor with ⌃, as the tools do; nothing ever pastes into a password field. ⌘W, the close button, `:q!` or `ZQ` cancels; `:q` with changes says "E37: No write since last change". Esc never closes the window. Edit while the window is open brings it forward and says "Already editing" rather than dropping the edit. Every line break the window shows is a line to vim: Windows' (CRLF), old Mac's (CR) and Unicode's (U+2028, which Notes, Mail and TextEdit use for Shift-Return, U+2029, U+0085). Text that uses one kind gets it back at the end; text that mixes kinds comes back with "\n" only. The text stays in memory; nothing is written to disk.
- Keys (`Text/Editor/VimEngine.swift`, no dependency): normal, insert, visual and visual line modes; counts; h j k l w b e W B E 0 ^ $ gg G f F t T ; , % { } and arrows; d c y > < g~ gu gU with doubles (dd cc yy >> << g~~ guu gUU); x X s S D C Y (y$, as in Neovim) J r o O i I a A p P ~ u ⌃R; / ? n N * # (smartcase, wraps); `:N` goes to line N. Insert mode is the Mac text view's own typing, so input methods and dead keys work.
- Text objects with every operator and in visual mode: iw aw iW aW, i" a" i' a' i` a` (on the line, around the cursor or the next quoted text), i( a( ib ab, i[ a[, i{ a{ iB aB, i< a<, it at (tags), ip ap, with counts (d2i(, 2aw). Not inside a pair, i( takes the next pair after the cursor, as vim and Neovim do. Brackets on their own lines make i{ the lines between.
- `.` repeats the last change with what was typed in insert mode, and a new count replaces its count; a count on i, a, A or I types the text that many times (up to 10,000). Registers: unnamed, "a to "z ("A to "Z add to them), "0 the last yank, "_ keeps nothing, "+ and "* the Mac clipboard. Visual p and P replace the selection.
- The Mac clipboard (David, 2026-11-19, a deliberate difference from vim): every yank with no register named (y with any motion or text object, yy, Y, visual y) also puts the text on the Mac clipboard; deletes and changes (d, x, X, c, s, S, D, C, visual d/c/x, and the text a visual p replaces) never touch it. p and P with no register always paste the Mac clipboard, whoever put it there, so `dd` then `p` pastes the clipboard, not the deleted line, and `xp` doesn't swap letters. Text ending in a line break pastes as lines, as vim's "+ does. Deleted text is still in the unnamed register (`""p`) and in a named one if given (`"add`); there are no "1-"9 or "- registers. Macros and `.` read the clipboard when they play. Plain vim registers, without this rule, are what `VimEngine` does unless the window turns it on.
- Surround, as tpope's vim-surround: `ds{target}`, `cs{target}{replacement}`, `ys{motion or text object}{replacement}`, `yss`, visual `S` (linewise S puts the pair on lines of its own and indents between; ys over lines doesn't indent). Targets " ' ` ( ) [ ] { } < > t and the aliases b B r a; an opening bracket as target also takes the blanks inside. Replacements: ( [ { add a space inside, ) ] } > b B r a don't, `<tag attrs>` (or t then `tag>`) wraps in a tag, other non-letters wrap in themselves. `.` repeats surround commands, as repeat.vim does. Expected results in `VimSurroundTests` come from vim with the plugin installed on this Mac. A count on yss takes that many lines; a tag replacement ends at ">" or Return. Known differences: ds and cs on brackets that sit on their own lines remove just the brackets, where vim-surround also joins the lines (`ds}` on a code block); a tag keeps no attributes from the one it replaces; ysiw on an empty line does nothing. Not built: yS, ySS, cS, gS, the f/F/⌃F function replacements, ⌃] and ⌃T, s, and w/W/s/p targets.
- Macros: `q{a-z}` records (the status line says "recording @a"), `q` stops, `qA` adds to a, `@{a-z}` plays, `@@` plays the last one again, a count plays it that many times. Macros are the named registers, as in vim: a recorded one pastes with `"ap`, a yanked one plays. A macro stops at the first command that fails (h, l, w or b that can't move, J on the last line, a target not found, an ex error), so a recursive macro (`qaq` then `qa…@aq`) ends where vim's does; one that keeps playing is stopped after 100,000 keys with a message. One `u` takes back a whole macro. `q` inside a playing macro is ignored, as in vim, and a macro can't close the window (it stops and says so). A long macro on thousands of lines can take a few seconds. Macros last for one Edit window. Not built: `@:`, `@"`, and `q` into "0-"9.
- Behaves as vim with Neovim's defaults: expected results in `VimEngineTests`, `VimTextObjectTests` and `VimCountTests` were checked against `vim --clean`. Counts work in every place vim takes them (`3dj`, `d3j`, `2d3j`, `c3w`, `y2e`, `>3j`, `d2aw`, `d3fx`, `gU3w`, `3dd`, `d3d`, `v3jd`, `.` keeps the count, `3.` replaces it), including the edges: a count past the last paragraph fails, `{count}%` goes to that percentage of the lines, word objects cross lines, `b` stops at the text's start. `scripts/vim-compare.py` runs random counted key sequences through vim and writes a test with vim's results; on its texts, 15,000 sequences on 2026-11-19 found no difference beyond the known ones. Known differences: `>>` and linewise visual S indent with 4 spaces rather than retabbing; J puts one space after `.`, as Neovim does; j and k after a tab aim at the character's column, not the screen column vim uses.
- Wrapping: long lines wrap by default. ⌥⌘Z (in any mode; with ⌘ it never types and is no vim key) or `:set nowrap`, `:set wrap`, `:set wrap!`, `:set invwrap` turn it off or on; with it off, long lines scroll sideways and the view follows the cursor. The bottom line always shows "⌥⌘Z wrap: on" or "off", after "⌘↩ done · ⌘W cancel" and before where the text goes, so a narrow window cuts the destination first. The choice is remembered for the next window. j and k move by real lines either way. ⌥⌘Z inside a macro isn't recorded (vim never sees it); `:set nowrap` played by a macro does nothing.
- When a command does nothing where vim would beep, the bottom line says why in gray italics right after the wrap key ("d3j: no line below", "fx: no “x” on the line", "dx: not a command", and since 2026-11-20 `ci": no "…" on this line` (vim's quotes stay on one line, so a docstring over two lines has none) and `ci(: not inside ( )`) until the next key (David, 2026-11-19: "i don't want any noise"). Nothing sounds, and vim's behavior is unchanged. A macro or `.` that stops says so for the key that played it; a command with its own message (E353, E486) shows that instead. vim commands that aren't built (`=`, `!`, `g?`, `gc`, `gw`, `gx`, `gl`, `zf` with their motion; `m`, `'`, `` ` ``, `z`, `[`, `]` with their key; `gn`, `gJ`, `gp`, `gi`, `g;`, …) read all their keys and do nothing ("=ip: not built", "ma: marks are not built"), so the keys after them never run on their own (2026-11-20: `=ip` and `ma` fell into insert mode). A change that can't run, unknown (`cgn`) or failing (`ci"` with no quotes), drops what is typed until Esc ("typing ignored until Esc"), where vim would run those keys as commands.
- Line numbers (David, 2026-11-19): on by default, relative (the cursor's line shows its own number, the others their distance, as vim's number with relativenumber), in a gutter left of the text in the text's font. The numbers are gray, dimmer than the text; the cursor's line is a little brighter (tertiary and secondary label colors, so they read in light and dark). ⌥⌘L (in any mode; no vim key) cycles on, relative, off, so from the default the first press turns them off. `:set number`/`nu`, `nonumber`/`nonu`, `number!`/`nu!`/`invnumber`, `relativenumber`/`rnu`, `norelativenumber`/`nornu`, `rnu!`/`invrnu` work too; `nonumber` turns them off even with relativenumber set (vim would number from 0). One number per real line: a wrapped line's further rows have none, with wrap on or off. The gutter is as wide as the last line's number, scrolls with the text, is never selected and is not part of the text. The choice is remembered for the next window. The bottom line shows "⌥⌘L lines: relative", "on" or "off" beside the wrap key.
- The bottom line (David, 2026-11-19: the keys were "hard to make out" and "too close together"): the shortcuts are in the label color (contrast 14.9:1 in light, 12.2:1 in dark, up from the secondary gray's 3.9:1 and 5.9:1), in the 12-point semibold system font, with 2 points between a shortcut's glyphs (⌥ ⌘ Z); the words stay in the quieter gray and items have wide gaps. A failed command's reason is in italics. A narrow window leaves out where the text goes first, then the line-number key; past that the end is cut.
- Cursor (David, 2026-11-19): a blue block (#51afef, Doom One's blue) in normal and visual mode with the letter under it drawn in near-black, so it stays readable in light and dark appearance; a blue bar in insert mode; while typing a ":" or "/" command the bar is in the bottom line. The block covers the whole character (an emoji is one, a tab its full width; one cell at a line's end). Both blink at the system rate; in visual mode the block at the selection's moving end is steady. `VimTextView.blockBlinks` makes the normal-mode block steady.
- `:s` (ROADMAP C12): `:[range]s/pattern/replacement/[flags]` with ranges `%`, `N,M`, `.`, `$` and `'<,'>` (typing `:` in visual mode fills it in), flags `g`, `i`, `I`; vim's pattern syntax (`\(` `\)` `\|` `\+` `\?` `\{n,m}` `\<` `\>` `\d` `\w` `\s`, `\c`/`\C`) and replacement (`&`, `\1`–`\9`, `\r` for a line break, `\t`); an empty pattern is the last one searched for; `&` repeats the last `:s` on the line without its flags. One undo step; the cursor goes to the last line changed; "N substitutions on M lines" for more than two lines, E486 when nothing matches. Case follows smartcase, as `/` does, unless `i`, `I`, `\c` or `\C` says. Not built: the `c` flag, `~` in a replacement, `\u` `\l` `\U` `\L`, `\v` very magic. Expected results in `VimSubstituteTests` are vim's.
- `jk` typed within 0.15 s in insert mode leaves it, as Doom's evil-escape does (ROADMAP C12): the j that went in is taken back. `VimEscapeSequence` changes the two keys (empty turns it off), `VimEscapeDelay` the time.
- ⌃A and ⌃X add to or take from the first number at or after the cursor on the line (ROADMAP C12), as vim with nrformats=bin,hex: a "-" right before the digits is a sign, leading zeros keep the width, `0x` hex keeps its letters' case, `0b` binary works too; a count adds that much and `.` repeats. Expected results in `VimNumberTests` are vim's.
- Replace mode `R` (ROADMAP C12): typing replaces the character under the cursor, or adds past the line's end; Backspace puts the original back (before where `R` began it only moves left); a count types the text that many times; `.` repeats it; the bottom line says REPLACE. `gv` selects the last visual selection again, and `o` swaps the ends in visual line mode as in visual mode. Expected results in `VimReplaceModeTests` are vim's.
- `gq{motion}`, `gqq`, `gqip` (ROADMAP C12): re-wraps lines to 79 columns (vim's width with textwidth=0; `VimTextWidth` changes it), paragraph by paragraph: a paragraph's lines are joined as J joins them, then broken before the word that would pass the width, new lines taking the first line's indentation; a word longer than the width stays whole. One undo step, none when nothing changes; the cursor ends on the last line. Expected results in `VimFormatTests` are vim's. Known difference: as with J, one space after a period, not two.
- Visual block, ⌃V (ROADMAP C12): a rectangle over several lines, shown as one selection per line; `$` takes it to each line's end. `d`/`x`, `y` (pastes back as a block, from the Mac clipboard too), `c`, `r{char}`, `~` `u` `U`, `>` `<` on its lines, `o` (opposite corner) and `O` (other corner on the line). `I` and `A` type on the first line and, on Esc, the same text goes on every line: `I` skips lines too short to reach the block, `A` pads them with spaces, `$A` appends at each end. Columns are characters, not screen columns (a tab counts as one). Expected results in `VimBlockTests` are vim's.
- ⌥J / ⌥K, and ⌥↓ / ⌥↑ (David's Doom config, `~/.doom.d/config.el` my/move-line-*): in normal mode the cursor's line swaps with the one below or above, and the cursor stays on it at its column; in any visual mode every line the selection touches moves, and stays selected in visual line mode so the keys can be pressed again. A count moves that many lines. One undo step each; macros record them. At the first or last line, or with a count past it, nothing moves and the gray note says "no line below/above". The keys are caught by key code outside insert mode, so "∆" and "˚" are never typed there; in insert mode ⌥ keys type as usual. The text matches vim's `:m`. Unlike David's ⌥↑/⌥↓ mapping, lines are not re-indented after moving (the Edit window has no `=`).
- Counts are capped at 999999; undo remembers 1000 changes. Outside insert mode only vim changes the text (⌘V, drag and drop and the text menu's transformations do nothing, and ⌘X only copies); ⌘C copies a visual selection.
- Not built yet: marks, sentence objects (is, as). `.` doesn't repeat changes made in visual mode; after one it does nothing. In visual mode a second text object replaces the selection rather than extending it (viwiw). Tag names must match in case.
- Opens at once: the window is built on first use and reused. `VimEditorWindowTests.opensFast` prints the times: building measured 15-100 ms across runs, loading 2,000 lines about 5 ms (2026-11-19: the line-break check had pushed it to 15-25 ms; text with only "\n" breaks now takes one pass and no copy), reopening on short text under 1 ms.
- Commits: this one
- Files: `Sources/OpenShelf/Text/Editor/VimEngine.swift`, `Text/Editor/VimEditorWindow.swift`, `Text/Editor/LineNumberRuler.swift`, `scripts/vim-compare.py`, `Text/TextWheel.swift` (`TextCommand.edit`), `Text/SelectedTextController.swift` (`edit`, `canReplace`), `Wheel/WheelSearch.swift` (keywords vim, editor)
- Check: `swift test --filter 'Vim|EditWriteBack|TextWheelTests'`. In the app: select a paragraph in Mail, ⌃⌥Space, Edit, `dw`, ⌘↩; then copy a line in a terminal, ⌃⌥Space, Edit, `A!` Esc, ⌘↩ and paste. Cursor and wrap: `swift test --filter 'cursorShapeFollowsTheMode|blockCoversTheWholeCharacter|bottomLineShowsTheWrapKeyAndState|wrapTogglesAndIsRemembered'`; in the app the cursor is a blinking blue block with a readable letter in NORMAL and a blue bar after `i`, and ⌥⌘Z flips "⌥⌘Z wrap: on/off" in the bottom line. Line numbers: `swift test --filter 'LineNumber|Gutter|setNumber'`; in the app the gray numbers count from the cursor's line, and ⌥⌘L goes off, on, relative.

### 54. Only a password field is refused
The text wheel, Edit and the tools refuse only when the focused element is a password field: Accessibility's `AXSecureTextField` subrole, which a password input in a browser, 1Password and the Passwords app report. The toast says "Password field". Every other field and app works, including Terminal or iTerm2 with Secure Keyboard Entry and any app while macOS's system-wide secure-input flag is on (David, 2026-11-19: "everything else should be ok"). That flag is often left on by loginwindow after unlocking, and the pid macOS reports for it follows the frontmost app, so neither is used. At paste time the same rule holds: Edit's write-back and the tools' paste-back read the focused element again, and a password field that took focus meanwhile gets nothing (the result is copied instead). A refusal is logged at notice level with the flag and reported pid, never a field's value.
- Not covered: a password a site or app has revealed ("show password") is a plain text field to Accessibility, so it reads like any other text.
- Commits: 9e77d1a, a2274f1, 20d4e0a, 697a239
- Files: `Sources/OpenShelf/Text/AccessibilityText.swift` (`read`, `secureInputDiagnostics`), `Text/HotkeyRouting.swift` (`choose`), `Text/SelectedTextController.swift` (`canReplace`, `toolMayReplace`), `Text/TextLog.swift`, `App/AppDelegate.swift` (toast)
- Check: `swift test --filter 'HotkeyRouteTests|EditWriteBack'`. In the app, with iTerm2 in front holding secure input, select text in Mail, ⌃⌥Space: the wheel opens. In a browser's password field: "Password field". `log show --last 10m --predicate 'subsystem == "com.djnesmith.OpenShelf"'` shows any refusal.

### 55. More ▸ regrouped, with Count and Hash
More ▸ is Lines ▸ · Case ▸ · Fix ▸ · Format ▸ · Code ▸ · Extract ▸ (David, 2026-11-18). Fix ▸ has Trim Lines, Straight Quotes, Plain Text, Strip Tracking, Fix Encoding and Strip ANSI; Format ▸ has Indent ▸, Wrap ▸, Markdown ▸ and Dates; Code ▸ has Encode ▸, Decode ▸, Hash ▸ (MD5, SHA-1, SHA-256), Generate ▸ and JWT; Extract ▸ has Links, Emails, Numbers, Phone Numbers, Dates and Count. The rest of the Stage 2 tools fill these groups as they are built (ROADMAP C6).
- Fix ▸ (`Text/FixTransforms.swift`, pure Swift, nothing fetched): Plain Text turns HTML into text when it has real HTML tags (so "x<y and y>z" stays prose; block ends and <br> become line breaks, list items get "• ", script and style go, source whitespace is one space, common entities decode) and otherwise takes Markdown's marks off (headings, * and ** emphasis, links and images keep their words; code, fenced or inline, is kept exactly; underscores are never emphasis, so identifiers and links keep them). Strip Tracking takes utm_*, fbclid, gclid, dclid, gbraid, wbraid, msclkid, mc_eid, mc_cid, igshid, yclid, _hsenc, _hsmi and mkt_tok off every web link and keeps other parameters, the fragment and the sentence's punctuation after the link; links copied from HTML with "&amp;" between parameters work too. Fix Encoding reads text that was UTF-8 read as Windows-1252 ("cafÃ©", "itâ€™s", emoji, Chinese, Greek) again, word by word, so correct words in the same text stay. Strip ANSI takes terminal colour and cursor codes out.
- Code ▸ (`Text/CodeTransforms.swift`, pure Swift): Encode ▸ and Decode ▸ each do URL (percent-encoding all but A-Z a-z 0-9 - . _ ~), Base64 (decode also takes URL-safe, unpadded and wrapped text), HTML (& < > " '; decode takes named and numeric entities), JSON String (with its quotes; decode takes it with or without them), Hex (UTF-8 bytes; decode skips spaces, colons and 0x) and Unicode (\uXXXX with surrogate pairs; decode also \u{…} and \U). A decode that can't read the text says "Nothing to change". Generate ▸ replaces the selection with a UUID, a timestamp (ISO 8601 with the local offset), Lorem Ipsum or a 20-character password (system secure random; at least one lower, upper, digit and symbol). JWT (also "Bearer …" or in quotes) puts the header and payload, as indented JSON, on the clipboard and says the signature isn't checked; text that isn't a three-part JWT says so.
- Extract ▸ (`Text/ExtractTransforms.swift`): what of one kind the text holds, one per line, in the order found, each once; nothing found leaves the text as it is. Links and Phone Numbers and Dates use the system's detector (so a date can take a word like "Due" with it; mailto links are left to Emails); Emails and Numbers (signed, with thousands separators and decimals; not digits inside words like "v2" or parts of an IP, version, date or time; repeats kept) use patterns.
- Format ▸ (`Text/FormatTransforms.swift`): Wrap ▸ puts the text in quotes, parentheses, brackets, braces, a code fence or a block quote (a final line break stays outside). Markdown ▸: Link makes `[selection](copied link)` from an http, https or mailto link on the clipboard ("Copy a link first" otherwise); Align Table pads a Markdown table's columns and keeps alignment colons; Heading Up and Heading Down change # levels between 1 and 6. Dates converts a selection that is all one date: Unix seconds or milliseconds to ISO 8601 with the local offset, ISO 8601 to Unix seconds, a date in words to ISO 8601.
- Count shows a toast: words, characters (as people see them, so an emoji with a skin tone is one), lines, sentences and reading time at 230 words a minute; words and sentences follow the system's rules for the language. The text isn't changed.
- A hash of the text's UTF-8 bytes, as lowercase hex, goes on the clipboard and shows in a toast; the text isn't changed.
- Search finds them ("sha256", "count", "checksum", "reading time").
- Commits: 1f962b5 (TextInfo), this one
- Files: `Sources/OpenShelf/Text/TextInfo.swift`, `Text/TextWheel.swift` (`TextTool.count`, `.md5`, `.sha1`, `.sha256`, `isReport`; `TextGroup.fix`, `.format`, `.code`, `.hash`, `.extract`), `Text/SelectedTextController.swift` (`report`), `Wheel/WheelSearch.swift`
- Check: `swift test --filter 'TextInfoTests|TextWheelTests|WedgeLabel'`. In the app: select a paragraph, ⌃⌥Space, More ▸, Extract ▸, Count; then More ▸, Code ▸, Hash ▸, SHA-256 and paste.

### 56. Metadata › Clean checks the file's own bytes
Upstream's image Metadata › Clean judged a cleaned copy by ImageIO's properties alone. Some metadata survives a lossless copy and isn't in those properties. Found 2026-11-19 with made-up files: a lossless PNG copy (what Clean does when it keeps orientation and profile) kept Content Credentials (caBX) and tEXt/iTXt/zTXt comments, and a lossless TIFF copy kept ImageDescription and Artist; both were called clean. The fork's leftover check also reads the file's own bytes (memory-mapped): PNG chunks, JPEG segments (C2PA in APP11, extended XMP, an EXIF thumbnail, MPF images, comments), GIF blocks, TIFF tags on every page, WebP chunks (C2PA, XMP, EXIF), and for HEIC, AVIF and anything else a C2PA (JUMBF) box. Anything found sends the copy to the re-encode, with the ICC profile and orientation kept when asked; single PNG and TIFF images keep identical pixels (indexed PNG is saved as RGBA, same look, bigger file). Animations and multi-page TIFFs keep every frame, the GIF and APNG delays and the loop count. Anything the re-encode can't drop stops the copy with a message, never "clean". A JPEG's lossless copy already drops APP11, XMP, Photoshop IPTC and comments, and stays lossless; GIF can't be copied losslessly by ImageIO, so it is always re-encoded. Not checked: data after a PNG's IEND or inside a JPEG's image data, and BigTIFF.
- Commits: 5238589, this one
- Files: `Sources/OpenShelf/Tools/Editors/MetadataContainers.swift`, `Tools/Editors/MetadataEditor.swift` (`leftoverMetadata`)
- Check: `swift test --filter 'MetadataContainerTests|MetadataStrippingTests'`. In the app: a PNG with Content Credentials, Metadata › Clean with "keep orientation and profile" on, then `grep -c caBX` on the copy is 0.

### 57. Move and Copy open on the last folder used
David, 2026-11-19: "it should remember the last directory a file was copied or moved to and open on that instead of the current dir". Move's and Copy's folder picker opens on the folder Move or Copy last put a file in (one memory for both, UserDefaults `MoveCopyLastFolder`). It is remembered only when at least one file went there. If that folder is gone or its disk isn't mounted, the picker opens where the first file is, as before. ROADMAP H10.
- Commits: this one
- Files: `Sources/OpenShelf/Support/FileActions.swift` (`startingFolder`, `rememberFolder`)
- Check: `swift test --filter MoveCopyFolderTests`. In the app: Move a file to a folder, then Move or Copy another file from somewhere else; the picker opens on the first folder.

### 58. Mail: snooze through Mail's own Remind Me (MAIL-PLAN slice A)
**Proven on real Mail by David, 2026-11-20**: the reminder was set at the right time and the message left the inbox for Remind Me. That run's toast wrongly said "Not snoozed"; fixed the same day (below).
David, 2026-11-19 (ROADMAP I4). While Mail is in front, ⌃⌥S opens a small prompt: David's presets (tomorrow morning 7am, this afternoon 2pm, tonight 5pm, in two days 7am, this weekend Saturday 7am, next week Monday 7am; ⌘1-⌘6 or click) or a typed time ("fri 2pm", "in 3 hours", "dec 3 9am", "12/3", "3pm", "tomorrow noon"; a date with no time is 7am; a preset already past today is the next day's). Weekdays, month-days and times of day are worked out by OpenShelf against the current time, never the system detector's clock: a weekday is today while its time is still ahead, else next week's ("fri 2pm" on Friday 9am is today, at 3pm next Friday); a month-day already past is next year's; a time alone already past is tomorrow's; a bare number ("fri 2") or an impossible date ("feb 30", "13pm") is not understood. Other phrasings ("next tuesday") still go to the system's detector. Never a time in the past. It opens with the cursor in the field, from ⌃⌥S and from `b`: it is a panel that takes the keyboard without making OpenShelf the active app, because macOS may refuse to activate an app from a key tap or hotkey (2026-11-20, the field had no cursor). It shows the time it understood before Return; Esc closes it; no sound. The time goes to Mail's Message › Remind Me › Remind Me Later…, found by exact title; Mail's dialog is a sheet with a date picker, a time picker, Cancel and Schedule (David's Mac, 2026-11-20). OpenShelf looks for it on every Mail window and its sheets, polling for up to 4 seconds; sets the whole time on every picker; reads each back; and presses Schedule only if each picker shows the day or the time asked for (to the minute) and together they show both. Otherwise it presses Cancel and the toast gives a short reason. A dialog that turns up after the wait is cancelled too, so nothing is left open. Once Schedule is pressed nothing is cancelled and "Not snoozed" is never shown: Mail's Schedule can answer an Accessibility error while its sheet closes although the reminder is set (2026-11-20), so that answer is only logged. "Snoozed, Until …" shows for 1.5 s once the dialog has closed (David, 2026-11-20: "the toast stays on too long"; Moved, Link copied and Sent and archived are 1.5 s too, problems stay 3-6 s); if it stays open, "Not sure it snoozed". Every run appends its steps to `~/Library/Logs/OpenShelf/snooze.log` (pickers found, each one's role and value before and after, buttons pressed and what Accessibility answered, the toast; no message text; kept under about 256 KB). With David's Mail setting "Move to “Remind Me”" on, Mail takes the message out of the inbox itself. That setting can't be read (it is in no preference file), so Archive after Remind Me is an OpenShelf default, `MailSnoozeArchives`, off. The shortcut exists only while Mail is in front (registered and dropped as apps come forward); before the prompt opens it checks that the menu items exist and Remind Me Later… is enabled (a message is selected), and says what's wrong if not.
- Menu bar › Check Mail (read only) writes `~/Library/Logs/OpenShelf/mail-check.txt`: the focused element's role, whether Message › Send, Archive and Remind Me Later… are enabled and their shortcuts, whether the Remind Me dialog was found, and every Mail window with its sheets: roles, ids, button titles, and for each date picker its date (or its value's type) and whether it can be set. No message text: lists, bodies, text fields and static text are not read.
- Not decided by David: the shortcut (`MailPromptShortcut`, default ⌃⌥S).
- Setting the pickers through Accessibility and pressing Schedule works on David's Mail (2026-11-20). Not yet seen: what the snooze log shows for each picker; the next run writes it.
- Commits: this one
- Files: `Sources/OpenShelf/Mail/` (`SnoozeTime`, `SnoozePrompt`, `MailMenu`, `RemindDialog`, `MailHelpers`, `MailCheck`), `App/GlobalHotKey.swift` (several shortcuts by id), `App/AppDelegate.swift`, `App/OpenShelfApp.swift`
- Check: `swift test --filter 'SnoozeTimeTests|MailMenuTests'`. In the app: select a test message, ⌃⌥S, type "in 2 minutes", Return; the message leaves the inbox and comes back two minutes later.

### 59. Mail: ⌘↩ always sends, ⇧⌘↩ sends and archives (MAIL-PLAN slice B)
**Not yet proven on real Mail** (built and tested against fakes; installed 2026-11-19 for David to try).
David's Check Mail (2026-11-20): Message › Send exists only while a message is being written (it is "not found" with the viewer in front), and in his compose window it carries his App Shortcut ⌘↩. When ⌘↩ sends nothing (no message being written, Send off for this message, or a panel over Mail with the keyboard), a short "Not sent" toast says which, since the shortcut takes the key either way; every ⌘↩ and ⇧⌘↩ appends one line to `~/Library/Logs/OpenShelf/send.log` (Send found, on or off, whether Mail has the keyboard, what happened; no message text). Check Mail now writes shortcuts as people do ("⌘E"), with Accessibility's raw values after.
David, 2026-11-19 (ROADMAP I5): "i would like command - enter to always work when i send an email ... command shift enter would send and Archive". While Mail is in front, ⌘↩ presses Message › Send by its title when Mail has it enabled (and does nothing otherwise, as before), so it no longer depends on the App Shortcut reaching the menu. ⇧⌘↩ notes the one message selected in Mail's viewer (its Message-ID and subject through AppleScript, never its text) and checks that the reply's window title is that subject (ignoring Re:, Fwd: and the like); it presses Send, waits for the reply's window to close, checks the same message is still selected, and presses Message › Archive. Anything uncertain sends without archiving and says so. Both act only when Mail itself has the keyboard, so ⌘↩ typed into Spotlight, Alfred or a password manager's panel over Mail never sends a draft. Both shortcuts are registered only while Mail is in front; `MailSendKeys` (default on) turns them off. The first ⇧⌘↩ asks for Automation permission for Mail.
- Why ⌘↩ sometimes failed, as far as can be read: Mail has one "Send" item (`MainMenu.loctable` 709) and David's App Shortcut is "@\U21a9" on it; an App Shortcut fires only when the item is enabled and no view in the window takes ⌘↩ first. Check Mail right after a failed ⌘↩ shows which.
- Commits: this one
- Files: `Sources/OpenShelf/Mail/MailSend.swift`, `Mail/MailHelpers.swift`, `App/GlobalHotKey.swift`, `Support/Info.plist` (the Automation text names Mail)
- Check: `swift test --filter MailSendTests`. In the app: reply to a test message, ⇧⌘↩; the reply is in Sent and the original in Archive.

### 60. Mail: quick filing and message links (MAIL-PLAN slices C and D)
**Not yet proven on real Mail** (built and tested against fakes; installed 2026-11-19 for David to try).
While Mail is in front, ⌃⌥M opens a picker of every mailbox (with the cursor in its field: a panel that takes the keyboard without activating OpenShelf, 2026-11-20) (On My Mac and each enabled account, nested ones as "Parent/Child"), listed through Mail's AppleScript. Typing part of a name narrows it (letters in order, counted more at a word's start, in a row and in the mailbox's own name; shorter names first on a tie), recently used mailboxes come first (the last 10, `MailFilingRecent`), ↑ ↓ choose and Return moves the viewer's selected messages there with AppleScript's move; Esc closes. ⌃⌥K copies a link to the one selected message, `message://%3C<Message-ID>%3E` with anything but letters, digits and `-._~@` escaped; Mail opens it. Both ask for Automation permission for Mail the first time. Until the single keys exist (slice E, where v and l open the same picker), ⌃⌥M and ⌃⌥K are not decided by David.
- Commits: this one
- Files: `Sources/OpenShelf/Mail/MailFiling.swift`, `Mail/MailboxPicker.swift`, `Mail/MailLinks.swift`, `Mail/MailHelpers.swift`, `App/GlobalHotKey.swift`
- Check: `swift test --filter MailFilingTests`. In the app: select a test message, ⌃⌥M, type part of a folder's name, Return; the message is in that folder. ⌃⌥K, then paste in Notes and click the link.

### 61. Mail: single keys, off by default (MAIL-PLAN slice E)
**Not yet proven on real Mail** (built and tested against fakes; installed 2026-11-19 for David to try).
Menu bar › Mail Single Keys (off by default, `MailSingleKeys`) turns on Gmail-style keys in Mail: j k next and previous message, o open, / search, g i g s g t g d g a Inbox, Flagged, Sent, Drafts, Archive (Go to Favorite Mailbox), e or ] archive, [ archive then the message above, x Trash (Edit › Delete), r a f reply, reply all, forward, s flag, b snooze (#58), v or l move to a mailbox (#60), m mute, ! junk, ⇧I ⇧U read and unread, z undo, c new message, * a select all, Esc or * n select none (David, 2026-11-20: "if all msgs are selected ESC should unselect them"), ? the list (a panel that doesn't take focus; any key closes it). Each key presses Mail's menu item by its title, found anywhere under its menu; j and k move the message list's selection through Accessibility. A prefix waits one second for its second key. The keys come from a key tap installed only while the setting is on and Mail is in front, removed as soon as Mail isn't. No menu bar item (David, 2026-11-20: "i don't want any menu bar item for it"); the checkmark on Mail Single Keys is the only sign it is on. While one of OpenShelf's own panels has the keyboard over Mail (the snooze prompt, the folder picker), every key goes to that panel. It takes a key only when focus is Mail's message list or a message being read (not editable, and Message › Send disabled); and, since 2026-11-20, when one message of a conversation has focus in the viewer window (window id `Mail.messageViewer.window…`), the keys that act on one message (r a f, e ] [, x, s, b, v l, m, !, ⇧I ⇧U, ?) through Mail's own menu, as Mail's menu does for that message (David: "r / a / f only works when the main thread is selected"); never in a text or search field, anything editable, or with Send enabled. Check Mail now lists the focused element's ancestors up to its window (roles, subroles, ids; no text) and whether focus is in the viewer, with no modifier but ⇧; anything else, or anything it can't read within 0.1 s, goes to Mail untouched; so does every key while another app's panel (Spotlight, Alfred) has the keyboard over Mail. It never records or logs keys. A tap that takes keys needs Accessibility, which OpenShelf holds; macOS may also ask for Input Monitoring.
- Left out: n and p; [ is archive then up.
- Since 2026-11-20 (David: "i also want ESC on a message to close it", "i like a back to the list hotkey", "yes for g"): Esc on a message open in its own window closes it (its close button, else File › Close); `u` does the same there, and in the viewer gives the keyboard back to the message list on the selected message (Accessibility focus; the selection is unchanged); `g g` and `G` select the first and last row Mail's list exposes, scroll it into view and give the list the keyboard, from the list or the reading pane. A message window is told from one being written by what Check Mail showed: no Send button (id `send`), no From pop-up (`popup_from`) and no To/Cc/Subject fields; never with a sheet or popover open, in a field, or with Send enabled. The message list is the first table in the "Main Window Preview Pane Vertical" split group (the mailbox sidebar comes first in the window). Not seen live: whether Mail's list exposes every row of a long mailbox to Accessibility; `G` selects the last row it exposes.
- In a message open in its own window (David, 2026-11-20: "r/a/f should work as well for an open message and whatever else makes sense"): r a f, s, b, v l, m, !, ⇧I ⇧U, ?, Esc and u work there; j/k, g and * go to Mail (Mail has no next-message command for a message window). `e`, `]`, `[` and `x` do what Archive or Delete does with that message's row selected in the list ("whatever e and x do when a message is selected in the list"): when the viewer's list has exactly one row selected and every message Mail reports for it (AppleScript `selection`) has the window's subject (Re:/Fwd: aside; the subject only confirms, it never picks), the window closes and Archive or Delete is pressed in the viewer, so Mail decides what the conversation includes and its own Undo applies; otherwise only the open message is archived or trashed, and the toast says so. **Not proven on real Mail**: try on a test thread first.
- Esc is taken only when the message list has the keyboard, more than one message is selected, no modifier is held, and no sheet or popover is open in Mail (anything unreadable counts as open); otherwise Esc goes to Mail, which closes things with it. Select none sets the list's selected rows to none through Accessibility; if Mail keeps a selection, only the focused row (else the first selected) stays selected; each step is read back, never taken at Mail's word. No message is changed. Not yet seen on real Mail: whether it accepts an empty selection or keeps one row.
- Commits: this one
- Files: `Sources/OpenShelf/Mail/MailKeys.swift`, `Mail/MailKeyTap.swift`, `Mail/MailHelpers.swift`, `App/OpenShelfApp.swift`
- Check: `swift test --filter MailKeysTests`. In the app: turn Mail Single Keys on, click Mail's message list, j and k move, ? shows the list; then type in a reply, the To field and the search field: no letter may be swallowed.

### 62. Mail: unsubscribe and block in one step (MAIL-PLAN slice G)
**Not yet proven on real Mail** (built and tested against fakes).
While Mail is in front, ⌃⌥U opens Mail's own right-click menu on the one selected message (Accessibility's show-menu action) to see what Mail offers, closes it, and asks: "Unsubscribe from <sender> and block it?", or "Mail offers no unsubscribe for this message. Block <sender>?" when Mail has no Unsubscribe for it. On yes it presses Mail's "Unsubscribe" then "Block Sender" (titles from Mail 16's `MessageViewerContextMenu.loctable`), reopening the menu for each, and only while the same message (by Message-ID) is still the one selected; an item that isn't there, or a different selection, stops it with a message. Mail does the unsubscribing, so OpenShelf opens no link and reads no header; the sender's address comes from Mail's AppleScript. It asks every time.
- Commits: this one
- Files: `Sources/OpenShelf/Mail/MailUnsubscribe.swift`, `Mail/MailHelpers.swift`, `App/GlobalHotKey.swift`
- Check: `swift test --filter MailUnsubscribeTests`. In the app: select a newsletter, ⌃⌥U, confirm; Mail unsubscribes and the sender is in Mail › Settings › Junk Mail › Blocked.

### 63. Snippets wheel (ROADMAP C8)
⌃⌥I in any app opens the Snippets wheel (its own hotkey, David 2026-11-18: "i like the idea of a new wheel and hotkey for snippets"; the key itself is not decided). It shows the snippets folder's own snippets and subfolders (▸), then "Dates & Times ▸" with the built-ins: ISO Date (2026-11-17), Long Date (November 17, 2026), Time (14:22), ISO Timestamp with the time zone, Unix Time and ISO Week (2026-W47); with an empty folder the built-ins are the wheel. A built-in's pattern can be replaced with `UserDefaults` "SnippetFormat.<isoDate|longDate|time|isoTimestamp|isoWeek>". Custom snippets are plain text files, one per snippet (its name the snippet's), subfolders as groups, in Settings › Wheels › Snippets folder (Choose Folder…, Show; default `~/Library/Application Support/OpenShelf/Snippets`). A file can hold `{date format="yyyy-MM-dd" offset="+3d"}` (offsets h d w m y), `{time}`, `{clipboard}`, `{selection}`, `{uuid}`, `{epoch}` and one `{cursor}`; `{{` and `}}` are literal braces; a file's final line break is dropped. A bad placeholder shows "Snippet not used" with its file and line. Choosing a snippet pastes it at the cursor (over the selection, which also fills `{selection}`) with the clipboard put back after (the text wheel's paste), then presses ← once per character after `{cursor}`. Password fields are refused. Snippets come only from their own hotkey; the main hotkey is unchanged (ROADMAP C8 "To settle", as proposed there).
- Commits: this one
- Files: `Sources/OpenShelf/Text/Snippets.swift` (engine), `Text/SnippetWheel.swift`, `Text/TextWheel.swift` (`TextCommand.snippet`, `.snippetGroup`, `.snippetBack`), `Text/SelectedTextController.swift` (`openSnippets`, `insert`), `App/AppDelegate.swift`, `App/GlobalHotKey.swift`, `Settings/SettingsPanes.swift`
- Check: `swift test --filter 'SnippetsTests|SnippetWheelTests'`. In the app: cursor in a TextEdit document, ⌃⌥I, Dates & Times ▸, ISO Date: today's date appears. A file `Reply.txt` holding `Dear {cursor},` in the snippets folder: the cursor lands before the comma.

### 64. Edit audio tags (ROADMAP F5)
David, 2026-11-19: "editing the metadata tags of files like mp3s". Tools › Tags on audio files (shown when ffmpeg is installed) opens a window with Title, Artist, Album, Album Artist, Track, Disc, Year, Genre and Comment, read with ffprobe (any case, and the other names files use: album artist, tracknumber, discnumber, date and year, description). For several files a field they disagree on shows "Mixed" and is left alone unless typed over; only fields that change are written, and an emptied field clears its tag. Cover: kept, removed, or replaced from a JPEG or PNG (an attached picture). Saved as a copy beside each file ("… tagged") unless "Change the original files" is on, which writes a finished copy and swaps it in, so a failure leaves the original as it was. ffmpeg copies the streams (`-c copy`, `-map_metadata 0`), so the sound is never re-encoded; MP3s get ID3 v2.3, which Finder and Music read. Checked on MP3, M4A and FLAC.
- On the audio Tools wheel, Compress is now ranked with the everyday tools (it was unranked and only fit on page two by luck); Tags comes after Export.
- Commits: this one
- Files: `Sources/OpenShelf/Tools/Media/AudioTags.swift`, `Tools/Editors/AudioTagsEditor.swift`, `Tools/FileTool.swift` (`audioTags`), `Tools/ToolLauncher.swift`, `Wheel/WheelOrdering.swift`
- Check: `swift test --filter AudioTagsTests` (the round trip runs when ffmpeg is installed). In the app: drag an MP3, Tools › Tags, change the title, Save; the "… tagged" copy shows the new title in Finder's Get Info.

### 65. Live preview beside the text wheel (ROADMAP C13)
David, 2026-11-19: "a preview of the text changing ... to the right of the wheel, when you hover over the button that would change the text it would automatically show the change". Hovering a text tool, or moving to it with the arrow keys, shows a pane to the right of the wheel (the left, when there's no room) with the text as it would be after the tool, scrolled to just above the first changed line. Choosing the tool works exactly as before. Decided for now: pure text tools show their result ("Nothing to change." when they wouldn't), Generate tools show an example, Count, the hashes and JWT, Re-indent and To Markdown (which run another program), Markdown Link (which reads the clipboard), Convert, Undo and Edit show one line saying what they do, and sub-wheels, Back and snippets show nothing. The plain result is shown, not a diff. It is computed off the main thread and dropped when the highlight moves; it never touches the source app or the clipboard, never takes focus and lets clicks through. Settings › Wheels › "Show a preview beside the text wheel" (on; `TextWheelPreview`).
- Always there (David, 2026-11-20: "it should have the text in it for all text selections or clipboard editing, it didn't have it for Edit Text, and it went away when i went to more"): the pane opens with the text wheel, for a selection, copied text and the clipboard alike, and stays until the wheel closes, through More, sub-wheels and Back. On a one-shot tool it shows "After <tool>" and the result; on anything else (nothing highlighted yet, Edit, Undo, More, a group, Back, Convert, a snippet) it shows "Now" and the text as it is. Count, Hash, JWT, Re-indent, To Markdown, Markdown Link and Convert add a one-line note under "Now", over the text. A file wheel never shows it. Each step goes to `~/Library/Logs/OpenShelf/preview.log`: the text's source, the wedge's title, where the pane went or why it is hidden; never the text.
- Commits: this one
- Files: `Sources/OpenShelf/Text/TextPreview.swift`, `Text/TextPreviewPanel.swift`, `Text/SelectedTextController.swift` (`previewHighlight`), `Wheel/WheelController.swift` (`onHighlightChange`), `App/AppDelegate.swift`, `Settings/SettingsPanes.swift`
- Check: `swift test --filter TextPreviewTests`. In the app: select a few lines, ⌃⌥Space, More ▸ Lines ▸, move over Sort A to Z: the sorted lines show beside the wheel; nothing changes until you choose it.

### 66. Text wheel: your last tools first, and your own first page (ROADMAP C7)
The three text tools used last (kept between launches, `TextWheelRecentTools`) come first on the text wheel: one already on the first page moves to the front, others take the slots left free, so the wheel never pages (with Undo, Re-indent and Convert all showing, recents only reorder). Settings › Wheels › "Text wheel's first page" chooses up to four tools in place of Trim and Clean Up (`TextWheelFavorites`; "Back to Trim and Clean Up" undoes it); Edit, Undo, Re-indent, Convert and To Markdown still appear as before. Search ties already went to recent tools; that list still lasts one launch.
- Commits: this one
- Files: `Sources/OpenShelf/Text/TextRecents.swift`, `Text/TextWheel.swift` (`items(for:group:recent:favorites:)`), `Text/SelectedTextController.swift`, `Settings/SettingsPanes.swift`
- Check: `swift test --filter 'TextRecentsTests|TextWheelTests'`. In the app: run Sort A to Z on some lines, then ⌃⌥Space again: Sort A to Z is the first wedge.

### 67. Clean Image: hidden data and marked areas, with a report (ROADMAP E6)
David, 2026-11-19: "should remove non-hidden and hidden ones that the same time, it should report back what it removed". Tools › Clean on images opens the Redact window in clean mode: mark the areas to remove (none is fine), then Clean saves "<name> Clean.<ext>" beside each image (never over it), same format, quality 0.95. The marked areas are filled to blend with what's around them, a smooth fill solved from each area's edge pixels (no model, no network: good on flat or gently changing backgrounds, it smears on detail). The pixels are then re-encoded with no metadata, and the copy's own bytes are checked (as Metadata › Clean does), so nothing hidden survives. A report lists what was removed, from ImageIO's properties and the file's bytes, e.g. "Removed: EXIF (Canon, EOS R5, RF 50mm), GPS location, IPTC (caption, creator), Content Credentials (C2PA), text comments; filled 1 marked area (bottom right, 20×10 px). Pixel-embedded marks, if any, are untouched."; it has a Copy Report button. There is no automatic watermark finding: only the areas the user marks are filled. Animated images and multi-page TIFFs get the metadata pass only. Redact also gains the Fill look. Not built: a model (LaMa) for detailed backgrounds, which needs David's yes.
- Commits: this one
- Files: `Sources/OpenShelf/Tools/Editors/ImageFill.swift`, `Tools/Editors/ImageCleaner.swift`, `Tools/Editors/RedactEditor.swift` (`cleans`, `.fill`, `CleanReport`), `Tools/FileTool.swift` (`cleanImage`), `Tools/ToolLauncher.swift`, `Wheel/WheelOrdering.swift`
- Check: `swift test --filter ImageCleanerTests`. In the app: drag a photo with a location, Tools › Clean, mark a small logo, Clean: the report names GPS location and the area, and the copy's logo is gone.

## Outside the repo

- `~/bin/update-all.sh` checks for upstream commits with `check_upstream "$HOME/Dropbox/Dev/OpenShelf" upstream OpenShelf`. It only reports them and never merges.
- Every push goes to both branches: `git push origin djnesmith djnesmith:main`, fast-forward only.
- Both of upstream's GitHub Actions workflows are turned off on the fork in its Actions settings, not in the files, so upstream merges never conflict. Release (`release.yml`) would build ad-hoc and fail at Sparkle's `generate_appcast`, since the fork has no Sparkle. CI (`ci.yml`) would fail at `make app`, since the fork signs with David's certificate, which GitHub's runners don't have. Check: `gh workflow list -R djnesmith/OpenShelf --all` shows both as `disabled_manually`.
