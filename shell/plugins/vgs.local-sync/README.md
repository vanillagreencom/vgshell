# Local Sync

Local Sync shows the folder copy jobs on this computer: each rsync or unison job that systemd runs for you. Its bar icon moves while a job copies, and its panel shows each job's folders, its last copy and its last error.

## Features

- Every rsync and unison job that systemd runs for you, including a job that runs rsync through its own script.
- The bar icon moves only while a job copies files. A job that only watches for changes leaves it still. With motion turned off, the icon stays still and a dot shows the copy.
- The icon turns red when a job's last copy failed.
- Each job shows its From and To folders. Select a folder to open it.
- A failed job shows what went wrong and what to do. View log opens the job's log. Send to agent asks the agent you chose in Agent Debug why it failed.
- Details shows everything Local Sync read about a job.
- Remove stops and turns off a job you made outside VGS. Its file stays.

## How it works

Local Sync reads your jobs from systemd and their logs. It reads a job's script to find its folders but never runs it, and it changes no job until you select Remove. While no job copies, it checks nothing on a timer: it waits for systemd and the copy programs to report a change.
