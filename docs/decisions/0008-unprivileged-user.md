# ADR 0008: Unprivileged daily user

- Status: accepted (username **admin**)
- Date: 2026-09-06
- Fedora: 44

## Decision

Graphical session runs as a non-root user in `wheel`. No root GUI, no
root autologin. On this box and the default ISO that user is **admin**
(uid 1000). ISO username can still be changed at whip time (ADR 0017).

## Context

Inventory originally had root only. logind seats, portals, PipeWire user
services, and the niri user session assume a real user. **admin** exists
on the reference box; `graphical.target` is the default.

## Alternatives

- Autologin root: rejected.
- systemd lingering for the user: optional later, not required for
  greetd-started sessions.

## Consequences

The ISO path is `scripts/tailwhip --user NAME` (ADR 0017). Overlay does
not hardcode a username. Default whip/ISO user is `admin`.

## Rollback

N/A.
