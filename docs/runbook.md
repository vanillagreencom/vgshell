# VGS operations

## Use temporary desktop access

Use this procedure for tools that use the Temporary unlock permission in [Lock settings](../shell/plugins/vgs.lock/README.md#setup).

A refusal or a missed transition ends the step. The tool must not ask for another grant on its own or restart VGS to recover.

<details>
<summary>Show command</summary>

1. Lock the session.

   ```sh
   vgshell lock
   ```

2. Request temporary access. Set `seconds` to a whole number from 1 through 60.

   ```sh
   vgshell ipc call vgs.lock invoke delegate-unlock '{"seconds":60}'
   ```

3. Read the lock status. Repeat the status call until both `locked:false` and `secure:false` confirm that the desktop is unlocked. Do not use the desktop before both readings confirm it.

   ```sh
   vgshell ipc call vgs.lock invoke status ''
   ```

4. Finish the work within the time requested.

5. When the step ends, even after an error, request a lock.

   ```sh
   vgshell ipc call vgs.lock invoke lock ''
   ```

6. Repeat the status call until both `locked:true` and `secure:true` confirm the lock.

</details>
