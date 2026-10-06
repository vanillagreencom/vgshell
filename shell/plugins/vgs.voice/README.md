# Voice

Voice types what you say into the focused field. It uses voxtype to record and recognise your speech, and puts a mic in the bar's right section.

![The Voice Settings page with setup needed](../../../docs/images/plugins/vgs.voice-page.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

![The plasma orb at the bottom of the screen while Voice records](../../../docs/images/plugins/vgs.voice-osd.webp)

## Features

- `SUPER+CTRL+X` starts dictation, and a second press stops it.
- `F9` dictates while you hold it.
- A tap of Right Alt or Right Ctrl, pressed and released alone, starts and stops dictation. Right Alt used as AltGr with another key types as usual.
- Each key changes under Keys on the plugin's Settings page.
- A plasma orb at the bottom centre of the focused screen swells with your voice while you speak and pulses while your words are recognised. It takes no key and no click.
- The bar mic uses the accent colour while recording and spins while your words are recognised. A click opens Configure.
- Configure and Choose model open voxtype's own screens. Voice warns first when your voxtype config is a symlink, because those screens can replace it.

## Setup

The Setup section of the Voice Settings page shows Ready with the voxtype version and the speech model, or names what is missing. When voxtype is missing, Voice first offers to install it.

Set up copies the default voxtype config when you have none, adds the start and stop sounds, enables the speech engine, downloads the speech model and starts the Voice service. A step that needs your password says so before it asks. Set up again runs it once more.

| Setting | What it changes |
| --- | --- |
| On-screen display | `plasma`, the default orb, `ring` for the VGS voice ring, or `off`. |
