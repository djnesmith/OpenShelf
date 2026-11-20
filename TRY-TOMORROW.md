# Morning page

What is new in the installed OpenShelf (built 2026-11-19 night), what to try in order, and
what is left for you to decide. Details for each item are in FORK-FEATURES.md (#numbers).

## Try, in this order

The Mail helpers have not been tried on real Mail yet. Use test messages.

1. **Check Mail, first.** In Mail, select a message, open Message › Remind Me › Remind Me
   Later… and leave it open. Then OpenShelf's menu bar icon › **Check Mail (read only)**.
   *Expect:* a toast "Checked Mail". Send `~/Library/Logs/OpenShelf/mail-check.txt` (it holds
   no message text). It shows whether the snooze can set Mail's date picker. (#58)
2. **Snooze.** Select a test message, press **⌃⌥S**, type `in 2 minutes`, **Return**.
   *Expect:* the time it understood shows before Return; the message leaves the inbox and comes
   back two minutes later. A "Not snoozed: …" toast means the date picker didn't take the time:
   send that line. (#58)
3. **Send.** In a message you are writing, **⌘↩** always sends. Reply to a test message to
   yourself and press **⇧⌘↩**.
   *Expect:* the reply in Sent, the original in Archive. The first time, macOS asks to let
   OpenShelf control Mail: allow it. A new message (not a reply) with ⇧⌘↩ sends and says
   "Sent, not archived". (#59)
4. **Filing.** Select a test message, **⌃⌥M**, type part of a folder's name, **Return**.
   *Expect:* the message is in that folder; recent folders come first next time. (#60)
5. **Message link.** Select a message, **⌃⌥K**, paste into Notes, click the link.
   *Expect:* Mail opens that message. (#60)
6. **Unsubscribe and block.** Select a newsletter, **⌃⌥U**, read the question, confirm.
   *Expect:* Mail unsubscribes and the sender is in Mail › Settings › Junk Mail › Blocked. If you
   click another message before confirming, it does nothing and says so. (#62)
7. **Single keys (optional).** Menu bar › **Mail Single Keys** on. "Mail keys" shows in the menu
   bar while Mail is in front. In the message list try **j k e ?**.
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
12. **Live preview.** Select a few lines, ⌃⌥Space, More ▸ Lines ▸, move over Sort A to Z.
    *Expect:* the sorted lines beside the wheel; nothing changes until you choose it. (#65)
13. **Recent first.** Run Sort A to Z on some lines, then ⌃⌥Space again.
    *Expect:* Sort A to Z is the first wedge. Settings › Wheels › Text wheel's first page picks up
    to four tools. (#66)
14. **More vim** in the Edit window: `:%s/old/new/g` then `u`; `jk` quickly leaves insert mode;
    **⌃A** on a number adds one; `R` overwrites; `gqip` re-wraps a long paragraph; **⌃V**, `jj`,
    `I// ` then Esc puts `// ` on three lines. (#53)
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
- **Keys left out:** `u`, `n`/`p`, `* n`; `[` archives then moves up.
- **Audio Tags, several files:** a "Mixed" field typed into and then emptied clears that tag
  on every file. Keep, or treat empty-on-mixed as "leave alone"?
- **Image model for Clean:** a LaMa model (about 100–200 MB) would fill busy backgrounds far
  better than today's smooth fill. It needs your yes.
- **Push:** nothing is pushed.

## Not built, or different from vim

- `:s`: no `c` flag, `~` in a replacement, `\u` `\l` `\U` `\L`, or `\v`; case follows
  smartcase (stock vim is case-sensitive).
- `.` does not repeat visual-mode changes (it does nothing after one).
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
