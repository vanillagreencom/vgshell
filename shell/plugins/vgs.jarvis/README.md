# Jarvis

Jarvis is a voice assistant for your desktop. Talk or type to the AI model you choose, ask it to work with your windows and files, or give it a coding task. It asks before it deletes a file or submits something in its browser.

![Jarvis Console with a conversation in the dark theme](../../../docs/images/plugins/vgs.jarvis-page.webp)

![Jarvis Console with a conversation in the light theme](../../../docs/images/plugins/vgs.jarvis-console-light.webp)

## Features

- Tap or hold a key to talk, or say Hey Jarvis.
- Hear and speak on your computer with Local voice.
- Choose OpenAI Realtime, Gemini Live or ElevenLabs for cloud voice.
- Speak in a voice recorded on your computer after cloned-voice setup.
- Use Claude Code, Codex, GitHub Copilot, Pi or an AI provider key, with backup models.
- Change volume or workspace with short spoken commands.
- Work with windows, applications, files, clipboard, media and notifications.
- Read your screen with private windows hidden, and run commands in a sandbox.
- Use a private browser that asks before it submits.
- Give coding agents work, hear their questions and answer by voice.
- Read conversations, coding tasks and refused actions in the Console.
- Share your instructions, skills and memory notes with every answering AI model.
- Start or resume your Jarvis session and send it confirmed agent fleet requests.
- Keep provider keys in your desktop keyring and mute Jarvis across restarts.

## How it works

```mermaid
flowchart TD
    you(["You"])
    voice["Voice<br/>hears your words and speaks the answer"]
    home["Your Jarvis home folder<br/>instructions · skills · memory notes"]
    model["The AI model you choose"]
    check{"Jarvis checks each action"}
    subgraph own["What Jarvis does itself"]
        desktop["Desktop<br/>windows, apps, clipboard, media, screen"]
        files["Your files"]
        shell["Commands in a sandbox"]
        memory["Your memory notes"]
    end
    session["Your Jarvis session<br/>does bigger work from its mail"]

    you <-- "you talk, Jarvis speaks" --> voice
    voice <-- "your words and its answer" --> model
    home --> model
    model -- "asks for an action" --> check
    check --> desktop & files & shell & memory
    check -- "mail request, after you confirm" --> session
```

Jarvis turns your words into text and asks your chosen AI model to answer. The model uses your instructions and reads skills or memory notes when it needs them. Jarvis checks an action before it runs and checks the result before it calls the action done. A request for your agent fleet goes to your Jarvis session after you confirm it; that session works through its mail.

Your request goes to the AI model you choose, over the network when that model runs elsewhere. Local voice keeps speech on your computer. OpenAI Realtime sends speech to OpenAI; Gemini Live sends it to Google. With ElevenLabs, Local voice hears you on your computer. ElevenLabs receives the reply text and turns it into speech. ElevenLabs may keep request history and use data for model training. To stop new data being used for training, open Terms and privacy → Data use in your account ([ElevenLabs help](https://elevenlabs.io/docs/help-center/legal/is-my-data-used-to-improve-eleven-labs-ai-models)).

## Setup

Jarvis comes with VGS. Open Plugin settings from the launcher and choose Jarvis. On its Settings tab, turn Enabled on if it is off:

1. On Settings, choose an Account under AI model. On Setup, Sign in uses the app's own sign-in; Add key stores a provider key.
2. On Settings, choose a Voice provider. On Setup, use Set up local voice for Local or Add a key for a cloud voice. Choose the cloud Voice key on Settings. Run Check microphone when Setup offers it.
3. When the required Setup steps read Done, tap Talk, Super with Right Alt, and speak.

The Jarvis J in the bar shows what to do next. Click it to open the Console, or use its right-click menu to mute or unmute. A saved session's Resume offer takes that click until you resume or dismiss it. Change Jarvis's shortcuts in the Keys section on its Settings tab. The Enabled switch turns Jarvis off and stops its session.

The Settings tab holds these choices. Each setting's information button explains it; the Details tab shows readings.

| Setting | What to choose |
| --- | --- |
| Account and Model | The AI that answers you. Backup models are the alternatives to try when it cannot answer. |
| Voice provider and Voice | Local, or the cloud company and voice you want. Local voice model selects a download for your computer; leave it on Auto to let Jarvis choose. OpenAI Realtime and Gemini Live take speech only. |
| Talk mode | Tap or hold, Toggle, or Always. Always listens locally for Hey Jarvis and works with Local or ElevenLabs. Press Talk to interrupt a spoken reply. |
| Microphone and Speaker | Your audio devices. Local voice uses the system default microphone; change it under Sound in System Settings. Set feedback tones under Sounds in that window. |
| Home folder | Where Jarvis keeps your instructions, skills and notes. On Setup, use Edit beside Personality for your instructions or Open folder beside Home folder to open the folder. |
| Screen to cloud and Private windows | Choose Ask, Allow or Never for sending screen images or text outside your computer. Choose which windows Jarvis paints black before it sends a screenshot; titles do not reliably identify private browsing. |
| Start Jarvis at boot and Session at boot | Start your chosen app in your Home folder when you sign in, resuming its saved conversation or starting a new one. Voice and chat work without this session. |

Use Optional tools on Setup for missing tools. For agent fleet requests, use Install mail tool on the Agent fleet step and start your Jarvis session from its Setup row. With GitHub Copilot, turn Copilot Memory off in [GitHub Copilot settings](https://github.com/settings/copilot/features); Details links to that account setting too.

Cloned voice is optional and starts off. With Local selected, use Set up cloned voice beside Cloned voice on Setup, with your own voice or the speaker's permission. It needs the Large local voice model and an NVIDIA graphics card; the recording and model stay on your computer. ElevenLabs voices you design or clone on its site appear under Voice after you select its key.

## Licence

[MIT](../../../LICENSE). The private-browser skill is [Apache-2.0](backend/skills/browser/LICENSE).
