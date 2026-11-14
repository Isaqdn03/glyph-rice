# Glyph, the user's fork

One `main` runs on two machines:

- **Desktop** (host `isaqdn`): NVIDIA, two monitors (Acer + Alienware AW3426DW, matched by model), no built-in panel,
  a mouse wheel; case RGB (OpenRGB, Kraken Z, NuPhy keyboard, Govee lamp) and DDC brightness.
- **ThinkPad laptop**: a built-in 16:10 panel (eDP-1, 1920 wide, so the old Prefs pages run there), lid, battery,
  touchpad, none of the desktop's hardware.

## Every commit works on both

- Both machines run all of `main`. No per-machine branches and no cherry-picking between machines: `git pull` before
  starting, `git push` when done. A diverged `main` gets merged, never force-pushed.
- Code detects, it doesn't assume. Screens by model or by kind (`/^(eDP|LVDS|DSI)/` is a built-in panel), never by
  connector or "the first screen". Hardware by probing: with no device a helper stays quiet (no respawn loop, no log
  every few seconds) and its prefs row hides. Hypr values are read live (`hyprctl getoption`), as `Sys.scrollFactor` does.
- Machine-only values never go in tracked files. They live in `config/hypr/user.lua` (gitignored: keys, monitors,
  scroll_factor, env), `~/.config/demonshot/rules.json`, `~/.local/state/rice/*.json` and `loadout-setup.md`. Code that
  needs one of them reads it, with a default that's right for the other machine.
- Before committing, ask what it does on the other machine: without its hardware, one screen vs two, touchpad vs wheel,
  on battery, at another scale. Say so in the commit message when it isn't obvious, and say "untested on the laptop"
  (or the desktop) when it is.
- Anything outside the repo a commit relies on (e.g. the nvim colorscheme in `~/.config/nvim` that reads `nvim.json`)
  is named in the commit message, and the shell works without it.

## Also

- Every hunk in an upstream file is marked `// local:` (`-- local:` in Lua). Upstream lands on `dev`:
  `git fetch upstream && git merge upstream/dev`, then resolve the `local:` hunks.
- Comments short and in English.
