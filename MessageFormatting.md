# Message Formatting

Slack renders a small markup in message text. It works anywhere text reaches the channel: the messages the
deploy sends, the level prefixes, the alert mention and the DM wording.

| Write                         | Shows as                                        |
|-------------------------------|-------------------------------------------------|
| `*bold*`                      | **bold**                                        |
| `_italic_`                    | *italic*                                        |
| `~strike~`                    | ~~strike~~                                      |
| `` `code` ``                  | `code`, inline                                  |
| ```` ```...``` ````           | A code block, spacing kept, on its own lines    |
| `> quote`                     | A quoted line                                   |
| `<https://example.com\|Text>` | A link reading Text                             |
| `https://example.com`         | The URL, linked, with a preview                 |
| `:warning:`                   | The emoji named, ⚠️                             |
| `<!here>`                     | @here, notifying everyone active in the channel |
| `<!channel>`                  | @channel, notifying everyone in the channel     |
| `<@U0123ABCD>`                | A mention of that member, by member ID          |

Everything else arrives as written: line breaks, tabs, quotes, backslashes, `<`, `>`, `&`, accents and emoji.
The exception is text that looks like the `<...>` forms above, such as `<!here>` or `<https://...>`: to show one
literally, write `&lt;`, `&gt;` and `&amp;` instead.
