# radio.nix

A Nix flake packaging interactive terminal-based internet radio players. Pick a station from a fuzzy-searchable menu and listen with mpv -- with automatic ad/jingle muting.

## Quick start

```bash
nix run github:michalrus/radio.nix
```

This opens a [skim](https://github.com/lotabout/skim) fuzzy menu of all available stations. Select one and it starts playing.

## Stations

The main `radio` package reads stations from [`radio/stations.yml`](radio/stations.yml). The file ships with an example set but is easy to edit or replace.

## Features

- **Fuzzy station search** via skim (`sk`).
- **Automatic ad/jingle muting** -- a custom mpv Lua script watches ICY stream metadata and mutes when it detects ad markers or blank titles. Configured per-station in `stations.yml`.
- **Resilient playback** -- exponential backoff retry (2 s to 60 s) on stream failure, with automatic reset after sustained playback.

## Supported systems

`x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`.

## License

[Apache 2.0](LICENSE)
