# Glyph, the user's fork

One `main` runs on two machines:

- **Desktop** (host `isaqdn`): NVIDIA, two monitors (Acer + Alienware AW3426DW, matched by model), no built-in panel,
  a mouse wheel; case RGB (OpenRGB, Kraken Z, NuPhy keyboard, Govee lamp) and DDC brightness.
- **ThinkPad laptop**: a built-in 16:10 panel (eDP-1, 1920 wide, so the Console opens its narrow board), lid, battery,
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
- Changes are made from either machine, and each has to keep the other working. Before committing, go through the
  other machine's list below. Say so in the commit message when it isn't obvious, and write "untested on the desktop"
  (or the laptop) for the side you couldn't run.

## Changing it from the laptop: will it work on the desktop?

- Two screens at once (Acer + Alienware, by model, maybe at different scales) and no main screen: anything about
  "the screen" picks one on purpose (focused, by model) or runs per screen. Workspaces are per monitor.
- No battery, backlight or lid: those parts hide, they don't error or show 0 %.
- Prefs is the Console on both (`prefs/Console*.qml`): the wide wall here, 5 × 3 at 2580 × 1080. A change to a page has
  to fit both boards (`narrow`, `objW`/`ctlX`/`ctlW`), and a new module needs a cell on both walls. `Prefs.qml` isn't opened.
- A mouse wheel with `scroll_factor` 3: wheel handlers go through `Sys.wheel(e)`.
- NVIDIA, Alienware at 280 Hz: nothing new on top of a fullscreen window (it breaks direct scanout in games), and no
  ddcutil running while a popup opens (`Ddc.qml`: it stalls every new window).
- Its hardware helpers (Rgb, kraken.py, govee.py, keyboard.py, Ddc) keep working: `python3 -I -B tests/test_*.py`.

## Changing it from the desktop: will it work on the laptop?

- One 16:10 panel that turns off with the lid: nothing hangs on to `eDP-1` or the screen it started on.
- The Console's narrow board (any screen narrower than 2:1): the wall 4 × 4 at 1920 × 1200, a narrower frame and dock;
  a page that still overflows shrinks (`Page.k`). Same rule, a prefs change fits both boards.
- A touchpad, a battery and power profiles; no NVIDIA.
- None of the case hardware: a new helper stays quiet without its device, and nothing probes the networks a laptop
  joins (Lights did both until bb0e282).
- Anything outside the repo a commit relies on (e.g. the nvim colorscheme in `~/.config/nvim` that reads `nvim.json`)
  is named in the commit message, and the shell works without it.

## Also

- Every hunk in an upstream file is marked `// local:` (`-- local:` in Lua). Upstream lands on `dev`:
  `git fetch upstream && git merge upstream/dev`, then resolve the `local:` hunks.
- Comments short and in English.
