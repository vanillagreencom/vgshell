# AI Usage

AI Usage shows how much of your Claude Code, Codex and Copilot plan limits you have used. It reads each tool's own sign-in, so it needs no API key.

![AI Usage dropdown with three signed-in accounts](../../../docs/images/plugins/vgs.ai-usage-panel.webp)

Images come from `scripts/readme-shots.sh` in the nested sandbox.

## Features

- One number for your visible accounts in the bar: by default the highest share of a plan limit used. It turns to the warning colour at 80 % used.
- A card for each visible account, with the provider and the account's email. Copilot gives no email, so its card shows the GitHub login.
- Sort cards by provider, email or the most room left in their limits. Accounts with no reported limit come last when sorted by room.
- Provider marks identify the cards. An API account carries an [API] chip. Codex API accounts show that they have no plan limits.
- Limit values use the theme's success, warning and danger colours as their used share grows.
- A compact panel view with one line for each limit and the time left until it resets.
- A full panel view with meters and provider details when the provider sends them.
- An account that has had no use yet says so instead of showing 0 %. A limit that starts with your first message reads Not started until then.
- The panel grows to half the screen height before it scrolls.
- Copilot AI credits per account, with the amount used this month and the renewal date.
- Claude Code extra usage and Codex credit balance when those providers report them.
- Every Claude Code, Codex and Copilot account on this computer.
- Filters for providers and hidden accounts.
- The bar item stays hidden until you sign in to one of the visible tools. A click opens the panel.
- When a check fails, the panel keeps the last figures and says that they may be old.
- Each card shows how long ago its figures were read. When Claude limits how often usage can be read, the card keeps the last figures and says so, and the next check tries again. After a limit resets, the card says that the kept figures may be old.
- AI Usage never changes a tool's sign-in.

## Settings

| Setting | What it changes |
| --- | --- |
| Check interval | Time between usage checks. Check now in the panel starts a check at once. |
| View | Compact shows account identity and limit lines. Full adds meters and provider details. |
| Sort accounts | Provider, Email or Most room first. |
| Bar number | How the bar figures one number from each account's highest limit: Average, Most left or Most used. An account with no limits is left out. |
| Bar shows | Used shows the share used. Left shows the share that is left. |
| Colour by usage | Shows the bar number in the warning colour from 80 % used, whichever share it shows. |
| Providers | Show or hide Claude Code, Codex and Copilot in the panel and bar total. |
| Hidden accounts | Hide selected accounts from the panel and bar total. |
| Sign-in | One row per tool. While no account of a tool is signed in, its row offers Sign in, which opens the tool's own sign-in in a terminal window. |

When a Claude Code or Copilot sign-in has expired, open that tool once to refresh it.

<details><summary>Show command</summary>

```bash
claude auth login
codex login
```

</details>

## AI Gateway credits

Turn on AI Gateway credits in Settings. Select Get AI Gateway key to open Vercel. In the dashboard, open AI Gateway, then API keys, then Create key. The key unlocks AI Gateway credit figures.

Under Sign-in, select Connect beside AI Gateway. Paste the key into the masked field. VGS stores it in your keyring. Disconnect removes it. A connection or a switch change checks the figures at once. With the switch off, VGS reads no AI Gateway key and calls no AI Gateway API.

## Credits

The Claude, GitHub Copilot and Vercel marks come from [Simple Icons 16.17.0](https://github.com/simple-icons/simple-icons/tree/16.17.0), under [CC0-1.0](https://github.com/simple-icons/simple-icons/blob/16.17.0/LICENSE.md). The source files are [Claude](https://github.com/simple-icons/simple-icons/blob/16.17.0/icons/claude.svg), [GitHub Copilot](https://github.com/simple-icons/simple-icons/blob/16.17.0/icons/githubcopilot.svg) and [Vercel](https://github.com/simple-icons/simple-icons/blob/16.17.0/icons/vercel.svg). The cards draw these marks in the theme's text colour. Codex has no bundled mark.
