# AI Usage

AI Usage shows how much of your Claude Code, Codex and Copilot plan limits you have used. It reads each tool's own sign-in, so it needs no API key.

![AI Usage dropdown with three signed-in accounts](../../../docs/images/plugins/vgs.ai-usage-panel.webp)

Images come from `scripts/readme-shots.sh` in the nested sandbox.

## Features

- One number for your visible accounts in the bar: by default the highest share of a plan limit used. It turns to the warning colour at 80 % used.
- A card for each visible account, with the provider and the account's email. Copilot gives no email, so its card shows the GitHub login.
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
- AI Usage never changes a tool's sign-in.

## Settings

| Setting | What it changes |
| --- | --- |
| Check interval | Time between usage checks. Opening the panel also checks. |
| View | Compact shows account identity and limit lines. Full adds meters and provider details. |
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

## Extras (not supported)

- **AI Gateway**, `aiGateway`: Vercel AI Gateway credits from an API key. `{ "id": "vgs.ai-usage", "aiGateway": true }` in `plugins` in `~/.config/vgshell/shell.json` turns it on. The Settings page then lists an AI Gateway key row with Connect. With it off, the plugin reads no AI Gateway key, calls no AI Gateway API and shows no AI Gateway row.

Each AI Gateway key is stored in libsecret under `service vgs-ai-usage` and `account ai-gateway`. The Settings page shows the key state: Present, Absent, Locked or Unavailable. **Connect** opens a masked field for the key. VGS stores it in your keyring through `secret-tool`, handing it over on stdin, never on a command line. **Disconnect** removes the stored key.

<details><summary>Show command</summary>

```bash
secret-tool store --label='VGS AI Usage AI Gateway key' service vgs-ai-usage account ai-gateway
```

</details>
