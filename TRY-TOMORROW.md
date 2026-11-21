# Try today, 2026-11-20

What is new in the installed OpenShelf (built 2026-11-19 night, Mail fixes 2026-11-20 morning), what
to try in order (16 items), and what is left for you to decide. Details for each item are in
FORK-FEATURES.md (#numbers).

Fixed this morning, from your first try of the Mail keys: no "Mail keys" item in the menu bar; the
snooze prompt and the folder picker open with the cursor in the field; snooze fills Mail's real
dialog (date, time, Schedule) and cancels it if anything is off; "fri 2pm" typed on a Friday
morning is today at 2pm, not next Friday.

## Try, in this order

Only the Mail keys have been tried on real Mail so far. Use test messages.

1. **Check Mail, first.** In Mail, select a test message, open Message › Remind Me › Remind Me
   Later… and leave the dialog open (date, time, Cancel, Schedule). Then OpenShelf's menu bar
   icon › **Check Mail (read only)**, then Cancel in Mail's dialog.
   *Expect:* a toast "Checked Mail". Send `~/Library/Logs/OpenShelf/mail-check.txt` (it holds
   no message text). It shows whether OpenShelf finds the dialog and can set both pickers. (#58)
2. **Snooze** (works on your Mail as of 8:05 AM; its false "Not snoozed" toast is fixed).
   Select a test message, press **b** (single keys on) or **⌃⌥S**: the cursor is already in
   the field. Type `2` (new: a number alone is minutes; also try `5h`, `3d`, `2w`, `2 months`, `1y`, `morning`, `eom`, `next month`, `month from now`, `5 hours from now`, and see the date it shows before Return), **Return**.
   *Expect:* Mail's dialog flashes and closes, "Snoozed, Until …" shows briefly (1.5 s), and the message moves to
   "Remind Me" as Mail's own Remind Me does, then comes back two minutes later. Whatever the
   toast says, send `~/Library/Logs/OpenShelf/snooze.log` (no message text). (#58)
3. **Send.** In a message you are writing, **⌘↩** always sends. Reply to a test message to
   yourself and press **⇧⌘↩**.
   *Expect:* the reply in Sent, the original in Archive. The first time, macOS asks to let
   OpenShelf control Mail: allow it. A new message (not a reply) with ⇧⌘↩ sends and says
   "Sent, not archived". (#59)
4. **Filing** (through Mail's own Move to menu; Inbox → [Info] and back proven 2026-11-20. Still to try: ⌘Z in Mail after a move. New: in the picker **⌃N** moves the highlight down and **⌃P** up, also before typing anything; Return picks the highlighted row). The picker now lists only the selected message's account (On My Mac's folders after it) and opens at once after the first time. Select a test message, **⌃⌥M** (or **v**; the cursor is in the field), type part of a folder's name (or nothing), **⌃N** / **⌃P** to a row, **Return**.
   *Expect:* the highlight moves one row per key and stops at the ends; nothing is typed into the field; the message is in the highlighted folder; recent folders come first next time. (#60)
5. **Message link.** Select a message, **⌃⌥K**, paste into Notes, click the link.
   *Expect:* Mail opens that message. (#60)
6. **Unsubscribe and block.** Select a newsletter, **⌃⌥U**, read the question, confirm.
   *Expect:* Mail unsubscribes and the sender is in Mail › Settings › Junk Mail › Blocked. If you
   click another message before confirming, it does nothing and says so. (#62)
7. **Single keys (optional).** Menu bar › **Mail Single Keys** on. Nothing new shows in the menu
   bar (fixed 2026-11-20); the checkmark on Mail Single Keys is the only sign. In the message list try **j k e ?**.
   Open a message with `o`: r, a, f, s, b, v work in its window. On a **test thread** opened
   with `o`, `e` (or `x`) there does what Archive (Delete) does with that row selected in the
   list, then the window closes; `z` in the list undoes it (fixed: z never pressed Mail's "Undo Archive"). Proven: the same for a thread you open
   by **double-clicking** its row. A window opened another way, or after you click another row,
   archives only that message. Not tried on real Mail yet.
   Open a message with `o`, then **Esc**: the window closes. New: **`u` is undo** (like `z`), and **Esc** is back to the list: click a folder (or after a `g` key), Esc, and the list has the keyboard; with all selected and a folder clicked, the first Esc goes to the list and the second selects none. Esc in the search field or renaming a folder still cancels there; **⌃N / ⌃P** do what `j` / `k` do, also with a message of a conversation focused in the reading pane (new; in a text field or a reply they stay Mail's next/previous line); `g g` / `G` jump to the first / last message. **⇧U** toggles read / unread (⇧I is gone; proven 2026-11-20: "shift u works in Mail now").
   **New: a fired reminder in the inbox.** On a row with the Remind Me badge in All Inboxes, `e`: the row should leave the inbox (the reminder cleared). `x`: the row should leave and the message be in Trash. Try one with a reminder and one without selected together. Then `z` once and again, and tell me what comes back each time. `e` / `x` on rows without a reminder should be exactly as before.
   `g i` All Inboxes, `g f` Flagged, `g s` All Sent, `g t` All Trash, `g d` All Drafts, `g a` All
   Mail (new: your selected message's account's All Mail, else the first account with one), `g A` Archive (new; where the old `g a` went), `g T` Today (fixed: it missed the Smart Mailboxes row), `g j` All Junk, `g u` Follow Up, `g l` Send Later (tried 2026-11-20: "g l goes to \"Send Later\""), `g r` Remind Me (a toast says if one
   isn't in Mail's Favorites, or isn't showing because it is empty).
   Then `* a` and **Esc** (or `* n`): the selection clears (or only one message stays
   selected, if Mail insists on one); Esc with one message selected, or in a sheet, does what
   Mail always does.
   *Expect:* next/previous, archive, the key list. Then type in a reply, the To field, the search
   field and Spotlight over Mail: no letter may vanish. Turn it off if one does. (#61)
8. **Last folder.** Move a file with the Actions wheel's **Move**, then Move or Copy another file
   from elsewhere. *Expect:* the picker opens on the first folder. (#57)
9. **Edit window.** Select text, ⌃⌥Space › Edit.
   *Expect:* gray relative line numbers (⌥⌘L cycles off, on, relative), clear keys in the bottom
   line, and a gray italic note such as "d3j: no line below" when a command does nothing. (#53)
10. **Snippets.** Cursor in a TextEdit document, **⌃⌥I**, Dates & Times ▸, ISO Date.
    *Expect:* today's date. Settings › Wheels › Snippets folder › Show, add `Reply.txt` holding
    `Dear {cursor},`, then ⌃⌥I › Reply: the cursor lands before the comma. The same works in a
    Mail reply. (#63)
11. **Audio tags.** Drag an MP3, M4A or FLAC, Tools › **Tags**, change the title, add a cover, Save.
    *Expect:* the "… tagged" copy shows them in Finder's Get Info and in Music. (#64)
12. **Live preview** (changed 2026-11-20). Select a few lines (or copy them and select nothing),
    ⌃⌥Space. *Expect:* the pane is there at once, "Now" over your text; it stays on Edit, More
    and in sub-wheels; More ▸ Lines ▸ Sort A to Z shows "After Sort A to Z" and the sorted
    lines; nothing changes until you choose. If it doesn't show, send
    `~/Library/Logs/OpenShelf/preview.log` (no text in it). (#65)
13. **Recent first.** Run Sort A to Z on some lines, then ⌃⌥Space again.
    *Expect:* Sort A to Z is the first wedge. Settings › Wheels › Text wheel's first page picks up
    to four tools. (#66)
14. **More vim** in the Edit window: `:%s/old/new/g` then `u`; `jk` quickly leaves insert mode;
    **⌃A** on a number adds one; `R` overwrites; `gqip` re-wraps a long paragraph; **⌃V**, `jj`,
    `I// ` then Esc puts `// ` on three lines. (#53)
16. **Move lines.** In the Edit window, **⌥J** / **⌥K** (or ⌥↓ / ⌥↑) move the line down / up;
    `Vjj` then ⌥J moves three lines and keeps them selected. *Expect:* nothing is typed, line
    numbers follow, `u` undoes one move; at the last line nothing moves and a gray note shows. (#53)
15. **Clean Image.** Drag a photo with a location, Tools › **Clean**, mark a small logo, Clean.
    *Expect:* a report naming what it removed (EXIF, GPS location, …) and the filled area, with
    Copy Report; the copy has no location and no logo. (#67)

## Needs your decision

Built with these defaults; each is one setting or constant to change.

- **Mail shortcuts:** ⌃⌥S snooze, ⌃⌥M file, ⌃⌥K link, ⌃⌥U unsubscribe, only while Mail is in
  front. Clashes to know: Rectangle uses ⌃⌥U, ⌃⌥I and ⌃⌥K by default, and every ⌃⌥ letter is
  a VoiceOver command.
- **Snippets shortcut:** ⌃⌥I, in every app.
- **Single keys:** off by default.
- **Keys left out:** `n`/`p`; `[` archives then moves up.
- **Audio Tags, several files:** a "Mixed" field typed into and then emptied clears that tag
  on every file. Keep, or treat empty-on-mixed as "leave alone"?
- **Image model for Clean:** a LaMa model (about 100–200 MB) would fill busy backgrounds far
  better than today's smooth fill. It needs your yes.
- **Push:** nothing is pushed.

## Not built, or different from vim

- `:s`: no `c` flag, `~` in a replacement, `\u` `\l` `\U` `\L`, or `\v`; case follows
  smartcase (stock vim is case-sensitive).
- `.` does not repeat visual-mode changes (it does nothing after one).
- A change that can't run (`ci"` with no quotes, `cgn`, which isn't built) drops what you type
  until Esc, with a gray "typing ignored until Esc"; vim would run those keys as commands.
- vim commands that aren't built (`=`, `gc`, marks, `zz`, `gJ`, …) read all their keys and do
  nothing, with a gray "not built" (marks: "marks are not built").
- `R` ignores Return (vim breaks the line); a Backspace in `R` drops its count.
- Visual block and `j`/`k` use character columns, not screen columns (tabs count as one).
- `J` and `gq` put one space after a period (vim: two); `gq` keeps the first line's indent on
  the lines it makes.
- The Edit window turns Shift-Return breaks (U+2028) into plain line breaks when the text also
  has Return paragraphs.
- The live preview shows a random UUID or password; choosing the tool makes a different one.
- Clean's fill smears on detailed backgrounds; large marked areas are slow to preview.
- The shelf-focus test (`ShelfWheelSelectionTests`) fails when another app is in front; it fails
  the same way on the branch's starting commit.

## Unpushed

`stage2-catalogue`, `b257044..HEAD` (`git log --oneline b257044..HEAD`), on top of the fork's
`main` at b257044.
