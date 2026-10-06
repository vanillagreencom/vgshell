# Lock

Lock protects your session with your password. The lock screen uses your theme and background, and the session stays locked if VGS stops or crashes.

![The lock screen after a wrong password](../../../docs/images/plugins/vgs.lock-screen.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

## Features

- Locks with `SUPER+DELETE` or the launcher's Lock row. `vgshell lock` locks the session from a script or an idle daemon.
- Locks after five minutes without input. A playing video that inhibits idle holds it off.
- Locks before the computer sleeps, and the sleep waits for the lock.
- Shows the time, the date and the password field on every screen. Typing on any screen fills every field.
- Pauses the password check for two minutes after ten wrong passwords, and says so.
- Takes over from another lock screen that holds the session. If that lock screen later unlocks the session, the Settings page warns you.
- Warns you with a toast if the computer slept before the lock was confirmed.
- Locks the session again when the shell starts after a crash while locked.
- Needs no setup. The password check uses the plugin's own PAM stack, and the shell's requirement notice installs a missing tool in one click.

## Settings

| Setting | What it changes |
| --- | --- |
| Lock when inactive | Time without input before the session locks. Never turns it off. |
| Lock before sleep | Whether the computer waits for the lock before it sleeps. |

The key is under Keys on the plugin's Settings page.
