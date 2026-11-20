# To try

One place to read what is new in the installed OpenShelf and what to try, newest first.
Each line says how to try it and what should happen. Details are in FORK-FEATURES.md.

## Installed 2026-11-19 (evening)

Mail helpers: none of these has been tried on real Mail yet.

1. **Check Mail, first.** In Mail select a message, open Message › Remind Me › Remind Me
   Later… by hand and leave it open; then OpenShelf's menu bar icon › Check Mail (read only).
   Send `~/Library/Logs/OpenShelf/mail-check.txt` (no message text in it). (#58)
2. **Snooze.** Select a test message, ⌃⌥S, type "in 2 minutes", Return. It leaves the inbox
   and comes back in 2 minutes. If it says "Not snoozed: …", send that line. (#58)
3. **Send.** ⌘↩ in a message you are writing always sends. Reply to a test message to
   yourself with ⇧⌘↩: the reply is in Sent and the original in Archive. macOS asks once to
   let OpenShelf control Mail. (#59)
4. **Filing.** Select a test message, ⌃⌥M, type part of a folder's name, Return. (#60)
5. **Links.** ⌃⌥K, paste in Notes, click: Mail opens the message. (#60)
6. **Unsubscribe and block.** Select a newsletter, ⌃⌥U, read the question, confirm. (#62)
7. **Single keys, optional.** Menu bar › Mail Single Keys on; "Mail keys" shows in the menu
   bar while Mail is in front. In the message list: j k e ?. Then type in a reply, the To
   field and the search field: no letter may vanish. Turn it off if one does. (#61)

Not Mail:

8. **Last folder.** Move a file with the Actions wheel's Move, then Move or Copy another file
   from somewhere else: the picker opens on the first folder. (#57)
9. **Edit window.** The keys in the bottom line read clearly; line numbers, ⌥⌘L, and a gray
   italic note such as "d3j: no line below" when a command does nothing. (#53)
10. **Snippets.** Cursor in a TextEdit document, ⌃⌥I, Dates & Times ▸, ISO Date: today's
   date appears. Settings › Wheels › Snippets folder › Show, add `Reply.txt` holding
   `Dear {cursor},`, then ⌃⌥I › Reply: the cursor lands before the comma. (#63)
   Then the same in a Mail reply (MAIL-PLAN F): a snippet of several lines goes in where
   the cursor is, and the reply's formatting around it is kept.
11. **Audio tags.** Drag an MP3 (or M4A, FLAC), Tools › Tags, change the title and add a
   cover, Save: the "… tagged" copy shows them in Finder's Get Info and in Music. (#64)

Open decisions (built with these defaults, easy to change): ⌃⌥S, ⌃⌥M, ⌃⌥K and ⌃⌥U while Mail
is in front; ⌃⌥I for Snippets; single keys off by default; `u`, `n`/`p` and `* n` left out; `[` archives then
goes up.
