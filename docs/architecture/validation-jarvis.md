# Every Jarvis test runs inside one private world

Read before touching the shared Jarvis test world, `scripts/lib/jarvis-env.sh`, or a Jarvis suite's private services.

## The approach

Every Jarvis suite runs inside one `jarvis_env_run` invocation of `scripts/lib/jarvis-env.sh`, which isolates processes, the network, command lookup and the session endpoints, but not the filesystem. Fixture parameters enter as arguments or scratch files, never as caller settings, credentials, account roots or live-session identifiers. No test authenticates, and no host fallback stands in for a missing stand-in.

## Why

Namespace isolation alone does not confine host authentication: PAM, polkit and faillock are shared with the host, so an auth command needs a stand-in and the PATH probe asserts its absence. The boundary is not a filesystem sandbox, so a consumer that runs an absolute host executable owns its own proof. A private socket sits under `XDG_RUNTIME_DIR`, not the scratch parent, because `dbus-daemon` refuses a listen path over 99 bytes.

## Rules

- Do start a suite's servers, daemon and children inside one `jarvis_env_run`, so they share its loopback. `scripts/test-jarvis-env.js` pins it.
- Never pass caller settings, credentials, account roots or live-session identifiers; the environment-scrubbing cases of `scripts/test-jarvis-env.js` pin it.
- Never rely on a host fallback for a missing stand-in, and never let a stand-in replace an allow-listed or bootstrap tool; the host-tool selection cases pin it.
- Never run a real PAM, polkit, sudo, faillock or keyring step; the audio suites assert the auth commands' absence.
- Do treat exit 77 as not verified, and never map a scratch or helper failure to 77; the harness control that changes a failure to 77 is rejected.
- Do give every protocol fixture its schema, version or sanitized recording and its date, checked by the shared schema checker.
- Do run tmux only through the wrapper, which refuses socket and configuration overrides; the bypass cases pin it.

## The canonical example

`scripts/test-jarvis-env.js`: the real helper driven end to end, with one case per isolation claim and a control that breaks each. Copy its shape for a new suite.

## Revisit when

A Jarvis consumer needs a filesystem boundary, or the sandbox gains its own authentication stack.

## Not governed

What each Jarvis suite asserts, which is each suite's header; the smoke's own sandbox, which is [validation-smoke.md](validation-smoke.md).
