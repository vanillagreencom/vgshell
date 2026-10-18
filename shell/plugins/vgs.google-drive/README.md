# Google Drive

VGS keeps Google Drive folders on this computer and in Google Drive. It runs every hour while you are logged in, also while VGS is closed, and never deletes a file.

![The Google Drive page in Settings](../../../docs/images/plugins/vgs.google-drive-page.webp)

## Features

- Folder pairs: each pair joins one Google Drive folder and one folder on this computer. VGS copies both ways. The newer file wins.
- Every hour while you are logged in, and when you select Sync now. An hour missed while you were logged out syncs once at the next login. One sync of a pair runs at a time, whoever starts it.
- Google Docs, Sheets, Slides and Drawings arrive as Word, Excel, PowerPoint and SVG files. A local file at the same name is never uploaded.
- Nothing is deleted. A file removed on one side comes back from the other side.
- When both sides changed, VGS keeps the older local copy in its records for 30 days when Google Drive was newer. When this computer was newer, Google Drive keeps the older Drive copy in the file version history for 30 days.
- Editor temporary files, unfinished downloads, Git and agent folders, `local/`, keys and credential files and old backups are never copied.
- Once a folder pair exists, a bar icon shows the state: up to date, files to review, syncing, paused, offline, sign-in needed or failed, with the count of files to review. The bar, the window and the Settings page show the same state. The tooltip names each folder pair and its state. It never shows a file name or an account.
- A window with the state, the last complete sync, the last problem, the folder pairs with Remove, and the files to review, with Sync now, Pause and Resume. Each file says what happened and what to do, or that nothing is lost. The files that need you come first.
- A notification when Google Drive needs you: a sign-in, a failed sync or a file that needs you. A file that needs nothing, such as a file VGS put back, sends no notification.
- Pause stays on after VGS or the computer restarts. Disabling the plugin does not stop the hourly sync.
- When Google Drive cannot be reached, the files stay as the last complete sync left them, and the window shows the time of that sync.

## Setup

Open the Google Drive page in Settings and select Setup. Take the steps in their order on the tab.

1. At the top, the guide link opens [Get your Google Drive keys](#get-your-google-drive-keys). Follow it to make your Client ID and Client secret in Google Cloud.
2. Under Google Cloud keys, select Add key beside Client ID and beside Client secret, and paste each key into its masked field. The Client ID ends in `.apps.googleusercontent.com`. The Client secret starts with `GOCSPX-`. VGS stores every key in your keyring.
3. Under Sign in to Google, select Sign in. Google opens in your browser. Step 6 of the guide says what to select on each Google screen. VGS stores the sign-in in your keyring, and the Details tab shows the Google account.
4. Under First folder pair, select Add a folder pair. A setup window asks for a name, the Google Drive folder and the folder on this computer. A folder pair cannot be your home folder, a folder that holds a Git repository, a folder of VGS or your system services, or the whole Drive, and two pairs cannot overlap. The hourly sync turns on with the first folder pair.
5. Under Tools, select Review all missing or outdated tools when a tool is missing.

The Settings tab lists each folder pair with its two folders and its state. Add a folder pair, under the list, adds another pair. Remove, beside a pair on the Settings tab or in the Google Drive window, stops the sync of that pair after you confirm. Its files stay on this computer and in Google Drive.

If the folder pair list cannot be read, the Details tab says why beside Folder pair list. Select Start the folder pair list again there. VGS keeps the damaged list beside a new empty list.

Hourly sync, on the Details tab, reads On once the first folder pair has turned it on. If VGS could not turn it on, or it is from an earlier version of VGS, select Set up again beside it.

The Details tab shows the Google account, with Sign out beside it. Sign out stops the sync and removes the sign-in from your keyring. Your files stay on this computer and in Google Drive. When Google refuses the sign-in, sign in again under Sign in to Google on the Setup tab.

## Get your Google Drive keys

Google Drive needs a Client ID and a Client secret from your own Google account. They are free, and the six steps take about 5 minutes. Use the Google account whose Drive you sync in every step.

1. **[Make a project](https://console.cloud.google.com/projectcreate).** Name it VGS and select Create.
2. **[Turn on the Google Drive API](https://console.cloud.google.com/flows/enableapi?apiid=drive.googleapis.com).** Choose the VGS project if Google asks for one, then select Enable.
3. **[Describe your app to Google](https://console.cloud.google.com/auth/overview).** Google Auth Platform opens. Select Get started. Name the app VGS and give your email. For Audience, choose Internal if your account belongs to a Google Workspace organization, else External. Accept the Google API Services User Data Policy and select Create.
4. **[Publish the app](https://console.cloud.google.com/auth/audience).** Do this step only for External. On Audience, select Publish app. A new app starts in Testing. Google ends each sign-in to an app in Testing 7 days after you allow access, and Google Drive then stops until you sign in again ([Google](https://support.google.com/cloud/answer/15549945)).
5. **[Make the client](https://console.cloud.google.com/auth/clients).** On Clients, select Create client. For Application type, choose Desktop app, then select Create. Copy the Client ID and the Client secret now. Google shows the secret only when it makes the client ([Google](https://developers.googleblog.com/en/usability-and-safety-updates-to-google-auth-platform/)).
6. **Paste and sign in.** Add each key on the Setup tab, then select Sign in. On "Google hasn't verified this app", select Advanced, then Go to VGS. It is your own app. Tick the box for Google Drive access and select Continue.

If you lost the Client secret, open your client on [Clients](https://console.cloud.google.com/auth/clients) and select Add secret ([Google](https://support.google.com/cloud/answer/15549257)). Copy the new secret and add it on the Setup tab.

[developer.md](developer.md) states the sync contract, the conflict records, the credential rules, the files and the runner's commands.
