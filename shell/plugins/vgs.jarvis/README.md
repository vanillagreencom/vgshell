# Jarvis

Jarvis is a voice assistant for your desktop. You talk to it, it answers through the AI model you choose, and it can act on your windows, files, clipboard, media, screen and a private browser.

![The Jarvis daemon's status on its Settings page](../../../docs/images/plugins/vgs.jarvis-page.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

## Features

- A bar icon that shows whether Jarvis is off, loading, ready, listening, working, speaking, muted or has a problem. Its tooltip says what to do next. A click toggles mute.

- Talk, Mute, Stop and Console keys. Talk is Super with Right Alt, Mute is Super with Shift and Right Alt, Stop is Super with Alt and Period, and Console is Super with Alt and C.
- The Console window lets you type a message to Jarvis, review the conversation, and stop the current turn without using the microphone.
- Mute stays on across restarts and blocks talk input.
- A listening bubble whose orb and text let clicks reach the application below.
- Always talk mode: say Hey Jarvis to start a request. The word is heard by the local voice on this computer; nothing reaches the AI model until you speak after it. While Jarvis waits for the word its bubble shows a still orb.
- A home folder you choose for what Jarvis knows: your instructions, skills, memory and state. Every AI model uses them the same way, and no AI model can change anything in the folder but its `state/` part.
- An AI model from an API key you added, or from an app you are signed in to, such as Claude Code, Codex, GitHub Copilot or Pi with its own providers.
- Local voice: speech to text and spoken replies on your computer, with no network access, after Set up local voice.
- Realtime voice with a saved OpenAI key. OpenAI hears you and speaks the reply. The selected AI model answers each request through Jarvis's action and release checks.
- Half duplex audio: Jarvis closes its microphone while speech plays, and Talk interrupts speech.
- Provider keys stored in your desktop keyring. Plugins shows whether a key is present, absent, locked or unavailable without reading it.
- Accounts finds the account folders of other tools in your home, config and data folders, and can remember a key another tool stored without copying its value. A login hint never proves that the AI answers.
- Verify sends one small request to an account after you consent, because a real request may cost money.
- Window, workspace and application tools that read each change back from Hyprland before they report it done.
- File tools that list, read, search, write, move and delete files in your home folder. They refuse credential stores, account folders and VGS's own files, and never follow a link out of your home folder.
- Shell tools that keep commands inside a kernel sandbox. Plugins shows whether the sandbox is ready and offers Install Bubblewrap when it is missing.
- Desktop tools that read and copy clipboard text, play, pause and skip media, set and mute the speaker volume, and show a notification. A clipboard read refuses a copy that a password manager marks as secret.
- Screen tools that read the screen, a monitor, a window, a region or an area you draw, at most four times a turn. Windows of password managers and private browsing are painted black before a screenshot leaves Jarvis.
- A private browser from Set up browser. Jarvis asks for input access to each site, a submit needs your confirmation, and password entry stays with you.
- Coding tasks in their own tmux session or a floating terminal. Plugins shows how many are running. A stop ends every process of the task before it is recorded as stopped.
- Jarvis speaks a coding agent's question and sends your spoken answer back to it. It calls a task done only when the agent reports it done. With no conversation open, it shows these as desktop notifications.

### Bar icon states

| State | Icon | When | What the tooltip tells you |
| --- | --- | --- | --- |
| Off | `power-off` | Jarvis needs setup, a requirement, or an unlocked screen. | What setting or action turns Jarvis on. |
| Loading | `loader` | Jarvis starts, checks setup or loads local voice. | What is loading and to wait. |
| Ready | `mic` | Jarvis can listen. | How to talk: hold Talk, press Talk, or say Hey Jarvis. |
| Listening | `audio-lines` | The microphone is open. | Speak now, or say Hey Jarvis in Always mode. |
| Working | `brain` | Jarvis is thinking, waiting for confirmation or using a tool. | What Jarvis is doing and the Stop or Confirm key to use. |
| Speaking | `volume-2` | Jarvis plays its answer. | That Jarvis is speaking and the Stop key to use. |
| Muted | `mic-off` | Privacy mute is on. | Click or press the Mute key to unmute. |
| Problem | `circle-alert` | Jarvis or audio stopped with a fault. | What failed and what action to take. |

## Setup

The Setup section at the top of the Jarvis page says Ready when Jarvis has an AI model it can use and the selected voice provider, and Not ready when it does not. It offers Sign in, AI model, Voice, Browser and Input. The AI model and voice steps read Done or To do. Sign in is optional. A step with a setup action shows its action beside it. The browser and input steps read Optional until they are done.

Setup actions are buttons on the Jarvis page in Plugins or rows in the launcher's Jarvis group. These actions open a floating terminal. For the Realtime voice, use Add key under Setup at the top of this page to save an OpenAI key. With no OpenAI key, Jarvis uses the local voice and Setup does not ask for a key. Jarvis selects the only available OpenAI key when Realtime key is empty, and Voice provider Auto then uses the Realtime voice. With several keys, choose one under Voice.

- Add key stores a new API key from an AI provider in your keyring, with hidden key input. You choose the provider from a list that names the page where it makes keys, then give the key a name.
- Sign in opens the app's own sign-in: Claude Code, Codex or GitHub Copilot. Give a new account a name, or select an existing account folder. Jarvis shows the folder before sign-in and creates it if needed. After sign-in, select the account as the AI model. The app keeps its login token.
- Set up local voice lists the tiers this computer can run, with the download size of each, and recommends the first. It checks free space, downloads the models and a private runtime, and reports Ready only after verification and a bundled test clip succeed.
- Set up browser checks an installed browser on a blank page, or offers a private download. The Browser driver row offers Install while agent-browser is missing.
- Accounts adds a directory, chooses an existing keyring item by label or inspects login hints.
- Check input checks the desktop input tools.

The shell's requirement notice installs a missing tool in one click.

Home folder shows in Setup only when Jarvis cannot use the folder you chose, and says what to change. Jarvis checks the folder again when you press Talk.

With a GitHub Copilot account, Setup shows Copilot Memory. GitHub keeps that memory in your account, so only you can turn it off: open [GitHub Copilot settings](https://github.com/settings/copilot/features) and set Copilot Memory to Disabled.

## Settings

| Setting | What it changes |
| --- | --- |
| Talk mode | Hold: Jarvis takes what you said when you let go of the Talk key. Toggle: the conversation stays open until you press Talk again. Always: say Hey Jarvis, then your request; Talk listens at once. Always needs the local voice: the word is heard on this computer, and the bubble stays on screen while the microphone is open. |
| Microphone, Speaker | The audio devices Jarvis uses. |
| Voice provider | Auto uses Realtime when an OpenAI key is stored, else Local; in Always talk mode it stays Local. Local keeps speech on this computer. Realtime sends microphone audio and released results to OpenAI. A choice of Local or Realtime stays, whatever keys are stored. Changing it ends the conversation. |
| Realtime key | A saved OpenAI key the Realtime voice uses. Add key opens hidden key input and stores the key in your desktop keyring. Get the key at [OpenAI API keys](https://platform.openai.com/api-keys). |
| AI model | The AI that answers you: an API key you added, or an app you are signed in to. It lists only the choices Jarvis can use. An app with more than one account shows each by its sign-in email. |
| Home folder | The folder for what Jarvis knows. None leaves Jarvis with what VGS ships. Changing it ends the conversation. |
| Task terminal | Where a coding task opens. Auto uses tmux when it is installed, so several tasks run at once, and the floating terminal otherwise. |
| Screen to cloud | Whether a screenshot or its text goes to an AI outside this computer. Ask withholds it unless granted for the conversation, Allow sends it, Never withholds it. When the AI and the voice both run on this computer, they always receive it. |
| Private windows | Comma-separated words. A window whose class or title contains one is painted black before a screenshot leaves Jarvis. A title cannot always show private browsing. |

The keys are under Keys on the same page. Show in bar puts the bar icon back after Hide.

## Home folder

Choose a folder under Home folder. Jarvis adds the entries the folder lacks and changes no file it finds outside `skills/base/`. It never follows a link in the folder, and it does not start with a folder that has a link in place of an entry below or anywhere in `skills/base/`.

| Entry | What it holds |
| --- | --- |
| `AGENTS.md` | Your instructions for Jarvis: who it is and how it talks. Every AI model gets this text at the start of a conversation, so keep it under 8 KB. |
| `CLAUDE.md` | One line that points Claude Code at `AGENTS.md`, for your own Claude Code session in this folder. |
| `skills/base/jarvis/` | The Jarvis skill VGS provides: `SKILL.md`, `persona.md`, `README.md` and `references/` with `accounts-and-secrets.md`, `browser.md`, `communication.md`, `computer-use.md`, `decisions.md`, `long-session.md`, `memory.md`, `research.md` and `verification.md`. Every AI model gets `persona.md` before `AGENTS.md`, and reads the skill and each reference when it needs it. When this folder differs from the copy VGS installed, after an update or an edit, Jarvis replaces `skills/base/` with that copy and removes anything else in it. Keep your changes in `AGENTS.md` and `skills/own/`. |
| `skills/own/` | Your own skills. A skill is a Markdown file, or a folder with a `SKILL.md` file. Its name is the file name without `.md`, or the folder name: it starts with a letter or a digit and has only letters, digits, `_` and `-`, at most 48 characters. Jarvis skips a skill with any other name. A folder skill's `references/` holds more Markdown files, each a skill named `<skill>/<file name without .md>` by the same rule. Every AI model gets each skill's name and first line, or its `description`, and reads the skill itself when it needs it. A skill has no size limit. |
| `memory/` | The place for memory notes: `MEMORY.md` and `inbox/`. Jarvis does not read them yet. |
| `state/` | Work in progress. This is the one part of the folder that Jarvis's file tools can read or change. They refuse every other path in the folder, a file of your own that this table does not name included. |
| `.claude/settings.json`, `.codex/config.toml` | Settings that turn off Claude Code's and Codex's own memory for your own session in this folder. |

A size limit applies only to what every conversation starts with: `AGENTS.md`, at 8 KB, and the list of skill names and first lines, at 8 KB for the whole list and 256 entries in `skills/own/` or in one skill's `references/`. That text takes room in every conversation. Jarvis starts no conversation with a folder that is over a limit, and says which limit. A skill or a reference takes room only in the conversation that reads it, so it has no limit.

The folder gives Jarvis knowledge, never permission. A skill that says an action needs no question changes nothing: Jarvis still asks before it deletes a file, runs a command or sends something.

The AI models never run inside this folder. A setting, hook or server that you keep there for your own tools does not run in Jarvis. Each app's own memory is off while Jarvis uses the app.

Jarvis asks the Realtime voice to speak each sentence of a result exactly. Jarvis counts formatting violations in the transcript of what the voice said. This check does not control the audio OpenAI makes.
