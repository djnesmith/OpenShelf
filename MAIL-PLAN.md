# Mail helpers: build plan

Slices A to E and G are built (FORK-FEATURES #58 to #62), not yet tried against Mail. F is covered by the Snippets wheel (C8, #63), which works in Mail's compose window like any app. It follows ROADMAP I4 (snooze) and I5 (send, and the Gmail
keys) as David decided them on 2026-11-19. Each slice can be installed and tried on its own;
say yes or no to each.

## What OpenShelf already has

- Accessibility (held). It can read Mail's menus and press a menu item by its title.
- Automation for Mail is not asked for yet. Mail's AppleScript can read the selected
  message's mailbox, subject and message id, and move a message to a mailbox. It has no
  reminder and no archive command (`sdef`, read 2026-11-19).
- Input Monitoring is not held. Only the single-key layer (slice E) needs it.

## Slices, in build order

Each slice says: what David gets · what it needs · how it drives Mail · what can break
and how we notice · tests with no screen · what to try by hand · size.

### A. Snooze prompt (S-M)
- **Gets:** one hotkey while Mail is in front opens a one-line prompt. Presets (tomorrow
  7am, this afternoon 2pm, tonight 5pm, in two days 7am, this weekend Sat 7am, next week
  Mon 7am) or typed times ("fri 2pm", "in 3 hours", "dec 3 9am"). It shows the date it
  understood before Return. Then Mail's Remind Me at that time; Archive too only when
  "Move to “Remind Me”" is off.
- **Needs:** Accessibility only.
- **Drives Mail:** Message › Remind Me › Remind Me Later… pressed by its exact title
  (AX press), then the date picker's fields set through Accessibility, then its Remind Me
  button. Archive: Message › Archive by title.
- **Can break:** Apple renames the menu items or changes the date picker. A check when the
  prompt opens finds the items by title; if one is missing, the prompt says "Mail's Remind Me
  menu has changed" and does nothing. Nothing is pressed blind.
- **Tests, no screen:** the phrase table and parser with a fixed "now" (presets, typed
  times, a preset already past today goes to the next day); the menu check against a fake
  menu tree.
- **By hand:** snooze a test message to 2 minutes from now, see it leave the inbox and come
  back; once with the setting on, once off.

### B. ⌘↩ that always sends, ⇧⌘↩ send and archive (S-M)
- **Gets:** ⌘↩ sends from any compose or reply window; ⇧⌘↩ sends, then archives the message
  being replied to.
- **Needs:** Accessibility; Automation for Mail for the archive step.
- **Drives Mail:** presses Message › Send by title (Mail's own key is ⇧⌘D), so it doesn't
  depend on the App Shortcut. For the archive: the reply's original found by message id
  (AppleScript), then Archive by title on it.
- **Can break:** the Send item's title or place; finding the original. The same launch check
  as A covers the titles. If the original can't be found, the reply is sent and a toast says
  it wasn't archived. Never archive the wrong message.
- **Tests, no screen:** choosing the window kind (compose, reply, list) from a fake
  Accessibility tree; matching a reply to its original by message id.
- **By hand:** reply and ⇧⌘↩; check the original is in Archive and the reply in Sent.
- **First:** find why ⌘↩ fails today (the App Shortcut needs an enabled "Send" item with that
  exact title). If removing the App Shortcut fixes it, this slice may only be ⇧⌘↩.

### C. Quick filing, `v` / `l` (M)
- **Gets:** a picker of mailboxes; type part of a name (fuzzy), Return moves the message.
- **Needs:** Automation for Mail (mailbox list and the move).
- **Drives Mail:** AppleScript lists mailboxes and moves the selected messages.
- **Can break:** AppleScript errors on some accounts (Exchange, Gmail labels). We'd see an
  error, shown in a toast; the message stays put.
- **Tests, no screen:** the fuzzy match and ranking (recent first) on a fixed list.
- **By hand:** move a message to a nested folder in each account.

### D. Message links (S)
- **Gets:** copy a link that opens the selected message in Mail (`message://<message-id>`).
- **Needs:** Automation for Mail (to read the message id).
- **Can break:** Mail stops opening `message:` links; a link that opens nothing is the sign.
- **Tests, no screen:** building the link from an id with odd characters (escaping).
- **By hand:** paste the link in Notes, click it.

### E. Single-key layer (L)
- **Gets:** the Gmail keys in the ROADMAP I5 table (j k o u e x r a f s b v l m ! z [ ] c / ?,
  `g` and `*` prefixes, Shift-i / Shift-u), only while Mail's message list or reading pane
  has focus.
- **Needs:** Input Monitoring for a key tap (new permission).
- **Drives Mail:** each key presses a menu item by title, or sends Mail's own key equivalent,
  or runs slice A, B or C. `?` shows the list.
- **Can break:** focus detection (see risks). A wrong guess means a letter is swallowed in a
  text field, which is the worst failure, so the layer must fail open: when in doubt, the
  key goes to Mail untouched.
- **Tests, no screen:** the key table, the prefix timeout and focus rules on fake trees.
- **By hand:** type in a reply, a search field and the To field; no key may be swallowed.

### F. Snippets in compose (M) — covered by C8
The Snippets wheel (⌃⌥I, FORK-FEATURES #63) pastes at the cursor in any app, Mail's compose
window included, and moves to `{cursor}`; nothing Mail-only was needed.
- **Gets:** the Snippets wheel's snippets (C8) typed into a compose window.
- **Needs:** C8 first. Accessibility (already used for pasting).
- **By hand:** a snippet with several lines into a rich-text reply.

### G. Unsubscribe and block (M)
- **Gets:** one step to unsubscribe (the message's List-Unsubscribe link) and block the sender.
- **Needs:** Automation for Mail (headers). Opening an unsubscribe link reaches the network,
  so it asks each time.
- **By hand:** on a real newsletter.

## Risky parts, each with a cheap check first (described, not run)

1. **The Remind Me Later… date picker.** Spike: open it on a test message by hand, dump its
   Accessibility tree (read-only), and see if the date and time fields can be set and the
   button pressed. If not, the fallback is the fixed items (in 1 hour, tonight, tomorrow)
   and the prompt offers only those.
2. **Knowing focus is the message list or reading pane, not a text field.** Spike: log (to
   the console only, not keys) the focused element's role and subrole while clicking around
   Mail: list, reading pane, search, To field, body. If the list and pane can't be told
   apart from text reliably, slice E stays out.
3. **Finding the original after a send.** Spike: read a reply window's In-Reply-To through
   AppleScript before sending, then find that message id in the inbox.
4. **The key tap.** Spike: a tap installed only while Mail is in front, that only counts
   presses (never records which key). Check: it sees keys only while installed; it's removed
   when Mail leaves the front; a menu bar indicator shows while it's on; it's off by default.

## Needs David's decision

1. **The prompt's hotkey.** Recommend ⌃⌥S, while Mail is in front only. It must not clash
   with his global ⌃⌥Space.
2. **Single keys on by default?** Recommend off, with a switch in Settings, because of the
   Input Monitoring prompt.
3. **`u` (back to the list).** Recommend: focus the message list, or close a message window.
   **Decided 2026-11-20 evening** (David: "shouldn't u be undo?"): `u` is undo, like `z`, and
   Esc goes back to the list. Esc, the first that applies: a message open in its own window closes; in the viewer with focus outside the message list (the sidebar, the reading pane, the window after a g key) the list gets the keyboard; in the list with several selected, select none; anything else (a text or search field, anything editable, a sheet, popover or open menu) goes to Mail, which cancels it.
4. **`n` / `p` (next/previous in a conversation).** Recommend: leave out at first; Mail has
   no direct command.
5. **`[` (archive, then previous).** Recommend: archive, then ↑. Mail moves to the next
   message by itself.
6. **`* n` (select none).** Recommend: leave out; Mail has no command for it.
7. **Order.** Recommend A, then B, then C and D, then E; F waits for C8, and G is last.

## Will not do

- No network, except an unsubscribe link he confirms.
- No reading message bodies.
- No changes to his Mail settings or rules (the Remind Me setting is only read).
- No keys logged, ever.
- No third-party code.
- No wheel in Mail.
