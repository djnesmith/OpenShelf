Read this before merging upstream. Every item must still work after the merge.

# Fork features

What `djnesmith/OpenShelf` adds over `Manan-Santoki/OpenShelf`. The list comes from
`git log upstream/main..djnesmith`. Each new feature adds a line here in the same commit.

After any merge, run `swift test` (all tests must pass) and then `make app`. The checks
below name the tests for each feature: `swift test --filter <name>`. "In the app" checks
need the built app at `/Applications/OpenShelf.app`.

## Security

### 1. No in-app updates
Sparkle is gone, so the app never downloads or installs updates by itself.
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
duckdb runs with autoinstall, autoload and community extensions off, `lock_configuration` on, and `-init /dev/null`. sqlite3 runs as `/usr/bin/sqlite3 -readonly -safe -init /dev/null`. pandoc runs with `--sandbox`. A file can't make these tools run its own SQL or load code.
- Commits: e31f6ad, e5e1b51
- Files: `Sources/OpenShelf/Convert/DatabaseConversion.swift`, `Convert/PandocConversion.swift`
- Check: `swift test --filter refusesToRunSQLFromTheFile` and `swift test --filter pandocRunsSandboxed`.

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
- Check: `swift test --filter ProcessOutputTests`.

### 7. ffmpeg race fixes
Frames are decoded before ffmpeg's temporary PNGs are deleted, and progress that arrives after a job ends is dropped.
- Commits: b7f0f32, ab60495
- Files: `Sources/OpenShelf/Tools/Media/MediaLoading.swift`, `Convert/FFmpegJob.swift`
- Check: `swift test --filter ffmpegFramesOutliveTheirTemporaryFile` and `swift test --filter progressStopsWhenTheJobEnds`.

### 8. PDF pages rendered one at a time
OCR and PDF-to-image release each page before rendering the next one. OCR of a 500-page scan went from 16.4 GB to 485 MB.
- Commits: 207bc44
- Files: `Sources/OpenShelf/Convert/DocumentConversion.swift`, `Tools/OCR.swift`, `Tools/PDF/PDFImagesEditor.swift`
- Check: `swift test --filter pdfPagesAreRenderedOneAtATime`.

### 9. Excel row limit
Output to XLSX is refused, with a message, when it would pass Excel's 1,048,576 rows.
- Commits: 309934c
- Files: `Sources/OpenShelf/Convert/Spreadsheet.swift`, `Convert/DatabaseConversion.swift`
- Check: `swift test --filter excelLimitMessage` and `swift test --filter csvOverTheLimitIsRefused`.

### 10. Shared Core Image contexts
The Resize and Remove Background editors reuse one Core Image context instead of making one per render.
- Commits: 81e412e
- Files: `Sources/OpenShelf/Tools/ImageContexts.swift`, `Tools/Editors/ResizeEditor.swift`, `Tools/Editors/RemoveBackgroundEditor.swift`
- Check: `swift test --filter sharedContextsRenderTheSame`.

## Media edits (Tools wheel)

### 11. Keep the format when editing
An edit saves in the file's own format and codecs: an MP3 stays an MP3 at about its bitrate, and HEVC or ProRes stays HEVC or ProRes. MKV, WebM and AVI are edited with ffmpeg and keep their container. When the format has to change, the toast says why.
- Commits: 74466c7, f67fca7, 258b3e3
- Files: `Sources/OpenShelf/Tools/Media/KeepFormat.swift`, `Tools/Media/MediaFilters.swift`, `Tools/Media/MediaToolsFFmpeg.swift`, `Tools/Media/MediaTools.swift`, `Tools/Media/MediaEdits.swift`, `Convert/MediaFallback.swift`, `Convert/ProbedMedia.swift`, `Tools/EditorWindow.swift`, plus each media editor
- Check: `swift test --filter KeepFormatTests`, `--filter KeepVideoFormatTests` and `--filter ffmpegContainersKeepTheirFormat`.

### 12. Still frame
Saves one frame of a video as a full-size image.
- Commits: b97e541
- Files: `Sources/OpenShelf/Tools/Media/StillFrame.swift`, `Tools/Media/StillFrameEditor.swift`
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
- Files: `Sources/OpenShelf/Tools/Media/MediaExport.swift`, `Tools/Media/MediaExportEditor.swift`
- Check: `swift test --filter exportsInEachCodec`, `--filter exportsSoundInEachFormat` and `--filter exportsBroadcastAndDiscContainers`.

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
- Check: `swift test --filter recognisesTextInAnImageAndAScannedPDF`.

### 25. PDF pages to images
Saves chosen pages at a chosen DPI.
- Commits: f6ab6eb
- Files: `Sources/OpenShelf/Tools/PDF/PDFImagesEditor.swift`, `Convert/DocumentConversion.swift`
- Check: `swift test --filter savesChosenPagesAtTheResolution`.

### 26. Crop to subject
The Crop editor can crop around the subject that Vision finds.
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
Markdown, reST, Org, LaTeX, AsciiDoc and others, both ways.
- Commits: e5e1b51
- Files: `Sources/OpenShelf/Convert/PandocConversion.swift`
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
On the keyboard wheel, ⌘1–⌘9 run that wedge and ⌘0 opens More. Each wedge shows its number as a badge.
- Commits: e543433
- Files: `Sources/OpenShelf/Wheel/WheelKeyboard.swift`, `Wheel/WheelController.swift`, `Wheel/WheelView.swift`
- Check: `swift test --filter WheelBadgeTests`.

### 40. Wheel on selected shelf items
"Open Wheel for Selection" opens the wheel on the selected shelf items when a shelf is in front, and on Finder's selection otherwise. Moving files from that wheel moves the shelf items too.
- Commits: a2c6d6f
- Files: `Sources/OpenShelf/App/FinderSelection.swift`, `App/AppDelegate.swift`, `App/OpenShelfApp.swift`, `Shelf/ShelfManager.swift`
- Check: `swift test --filter shortcutPicksTheSelectionInFront`.

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

## Outside the repo

- `~/bin/update-all.sh` checks for upstream commits with `check_upstream "$HOME/Dropbox/Dev/OpenShelf" upstream OpenShelf`. It only reports them and never merges.
- Every push goes to both branches: `git push origin djnesmith djnesmith:main`, fast-forward only.
