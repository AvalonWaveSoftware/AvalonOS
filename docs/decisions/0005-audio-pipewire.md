# ADR 0005: PipeWire + WirePlumber

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Audio is PipeWire + WirePlumber + pipewire-pulse. Default sink is Intel
PCH analog, not HDMI-NVIDIA. Bluetooth audio uses WirePlumber's native
bluez support (no PulseAudio daemon).

## Alternatives

- PulseAudio daemon: Fedora default is PipeWire.
- PipeWire on NVIDIA HDMI: not the default.

## Consequences

Install pipewire, wireplumber, pipewire-pulseaudio, pipewire-alsa.
Mixer GUI is Fedora **pavucontrol-qt** (waybar volume left-click).
niri Recommends wireplumber — install it explicitly.

## Rollback

Not planned.
