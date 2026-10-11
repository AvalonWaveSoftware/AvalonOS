# ADR 0021: First-boot Flathub remote and Obsidian (exception to ADR 0009)

- Status: accepted
- Date: 2026-11-22
- Fedora: 44

## Decision

The installer ISO stays RPM-signed only. Ship the Fedora `flatpak`
package in the image. On first boot, when a network route is up, add the
Flathub remote and install `md.obsidian.Obsidian` system-wide. Do not
vendor or preinstall Flathub content on the ISO. An offline first boot
must still reach login; Obsidian is installed later, when the network is
available.

This is a narrow exception to ADR 0009 (repos: Fedora + updates, plus
RPM Fusion only for NVIDIA). Flathub is used only for this first-boot
Obsidian install, not as a general third-party package source for the
ISO or the kickstart.

Master Chief packing decision, 2026-11-22 11:04 CT: "First boot: ship
the Fedora flatpak package in the image, then add Flathub and install
Obsidian on first boot when the network is up. The ISO stays RPM-signed
only; an offline install gets Obsidian later."

## Alternatives

- Vendor or preinstall the Obsidian Flatpak in the ISO: rejected. It
  would put unsigned Flathub ostree content on the installer image.
- Enable Flathub at install time in the kickstart: rejected for the
  same reason; Anaconda would pull Flathub content into the image or
  the installed system before first boot, and an offline install would
  fail the transaction.
- Skip Obsidian unless the user installs it later: rejected; the
  product decision is to install it by default when the network is up.

## Consequences

`kickstart/packages.inc` lists `flatpak`. `avalonos-firstboot` ships
`avalonos-flathub-obsidian.service` (After=network-online.target, not
Before=greetd) and `/usr/libexec/avalonos/flathub-obsidian`. A stamp at
`/var/lib/avalonos/obsidian-flatpak.done` makes the unit idempotent.
Failed or offline attempts are retried. How-to-Install, the README
locked stack, and the 0.1.0-9 release notes document the offline delay.

## Rollback

Remove the unit, the script, the `flatpak` package entry, and this
exception; ADR 0009 then stands without a Flathub path.
