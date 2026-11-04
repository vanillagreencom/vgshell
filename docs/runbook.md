# VGS operations

## Use temporary desktop access

For tools that use the Temporary unlock permission in [Lock settings](../shell/plugins/vgs.lock/README.md#setup).

A tool that uses temporary access must wait until both lock readings report unlocked before it uses the desktop, and must finish its work within the time it asked for. When its step ends, even after an error, it must request a lock and wait until both readings confirm the lock. A refusal or a missed transition ends the step. The tool must not ask for another grant on its own or restart VGS to recover.

<details>
<summary>Show command</summary>

```sh
vgshell lock
vgshell ipc call vgs.lock invoke delegate-unlock '{"seconds":60}'
vgshell ipc call vgs.lock invoke status ''
vgshell ipc call vgs.lock invoke lock ''
```

`seconds` is a whole number from 1 through 60. Wait for `locked:false` and `secure:false` before the step, then for `locked:true` and `secure:true` after the final lock call.

</details>
