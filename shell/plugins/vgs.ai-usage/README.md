# AI Usage

AI Usage shows how much of your Claude Code, Codex and Copilot plan limits you have used. It reads each tool's own sign-in, so it needs no API key.

![AI Usage settings](../../../docs/images/plugins/vgs.ai-usage-page.webp)

Images come from `scripts/readme-shots.sh` in the nested sandbox.

## Features

- The highest share of a plan limit used, in the bar. It turns to the warning colour at 80 %.
- A panel with each signed-in account: its email or name, its plan, a meter for each limit and the time the limit resets.
- Copilot AI credits per account, with the amount used this month.
- Every Claude Code, Codex and Copilot account on this computer.
- The bar item stays hidden until you sign in to one of the tools. A click opens the panel.
- When a check fails, the panel keeps the last figures and says that they may be old.
- AI Usage never changes a tool's sign-in.

## Settings

| Setting | What it changes |
| --- | --- |
| Check interval | Time between usage checks. Opening the panel also checks. |
| Sign-in | One row per tool. While no account of a tool is signed in, its row offers Sign in, which opens the tool's own sign-in in a terminal window. |

When a Claude Code or Copilot sign-in has expired, open that tool once to refresh it.
