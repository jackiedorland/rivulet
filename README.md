<pre>
                                  ▄▄
▄▄  ▄▄             ▀▀             ██        ██
 ▀█▄ ▀█▄     ████▄ ██ ██ ██ ██ ██ ██ ▄█▀█▄ ▀██▀▀
  ▄█▀ ▄█▀    ██ ▀▀ ██ ██▄██ ██ ██ ██ ██▄█▀  ██
▄█▀ ▄█▀ ██   ██    ██▄ ▀█▀  ▀██▀█ ██ ▀█▄▄▄  ██
</pre>

A tiling window manager for Wayland, configured in a Haskell DSL.

Rivulet is a Haskell window manager for Wayland. It plugs into the [River compositor](https://codeberg.org/river/river) and lets you write your entire WM config in Haskell. Layouts, keybindings, rules, autostart, the works!

## Why?

Most compositor configs are flat files you edit and reload, but not here. Your config is a Haskell program that gets compiled and run. Layouts are not picked from a menu. They are code. If the tiling behavior you want does not exist, you write a `Layout` instance and it just works. Assuming you can Hask it.

Rivulet does, however, ship with some default layouts, good enough for most users: A `Tall` layout like i3, a `Grid` layout, a `BinaryPartition` layout for seasoned users of `bspwm` (I miss it every day since I switched to Wayland), and more on the way!

Keep in mind, the project is still early and not everything is wired up yet. 

## Config

Create `~/.config/rivulet/Config.hs`:

```haskell
import Rivulet

main :: IO ()
main = rivulet $ do
  -- monitors and workspaces
  monitor "DP-1"   ["I", "II", "III", "IV", "V"]
  monitor "HDMI-1" ["VI", "VII", "VIII", "IX", "X"]

  -- appearance
  debug True
  gaps 10
  borders 2 (0xff222222, 0xff8ec07c) -- 0xAARRGGBB 
  layout $ Tall >>. Full >>. Grid

  -- rules
  rules $ do 
    "gimp"    ~> Floating
    "steam"   ~> Floating
    "firefox" ~> (OnWorkspace "II") 
    -- or if you prefer...
    rule "foot" Fullscreen

  -- startup
  autostart $ do
    start "waybar"
    start "dunst"
    startOn "I" "alacritty -e htop"

  -- keybindings
  keybinds $ do
    [Super]        # Return          ~> spawn "alacritty"
    [Super]        # 'b'             ~> spawn "firefox"
    [Super]        # 'j'             ~> focusNext
    [Super]        # 'k'             ~> focusPrev
    [Super, Shift] # 'j'             ~> swapNext
    [Super, Shift] # 'k'             ~> swapPrev
    [Super]        # Space           ~> cycleLayout
    [Super, Shift] # 'q'             ~> closeFocused
    [Super, Shift] # 'e'             ~> quit
    just XF86AudioRaiseVolume        ~> spawn "pamixer -i 5"
    just XF86AudioLowerVolume        ~> spawn "pamixer -d 5"
    just XF86AudioMute               ~> spawn "pamixer -t"
    -- or if you prefer verbosity...
    bind ([Super] # Return)           $ spawn "alacritty"
```

  `debug` controls verbose runtime logs (`logInfo`/`logEvent`). It defaults to `False`, so only error/fatal messages are shown unless you explicitly set `debug True`.

Keybindings use `[Modifiers] # key`. Modifiers are a list (`[Super, Shift]`) and keys are either a `Char` (`'q'`) or a named key (`Return`, `Space`, `XF86AudioMute`, etc.). It reads like what it is.

All of the above compiles and runs today. Some actions (workspace switching, monitor focus, pointer stuff) are still being wired to the runtime, but the DSL surface is stable and the shape is not going to change much.

## What works today

Right now Rivulet:

- Connects to River and binds the private window management, XKB, and input protocols
- Registers your keybindings through River's XKB interface
- Tracks monitors, windows, seats, and focus
- Proposes dimensions and positions windows on every manage/render cycle
- Runs a proper event loop against the Wayland display
- Compiles and applies your Haskell config at startup

And windows show up where you told them to!

## Not done yet

- Most exported actions (`focusNext`, `swapNext`, `sendToWorkspace`, etc.) exist in the DSL but are not wired to the runtime yet
- Rules and monitor config get parsed but are not fully honored during placement
- Workspaces are one-per-monitor and fairly primitive
- Pointer move/resize requests come in but nothing happens with them
- Not ready to be your only window manager yet!

## Requirements

- Linux with a Wayland session
- [River](https://codeberg.org/river/river) >= 0.4.x
- wlroots >= 0.20.x
- libxkbcommon >= 1.13.x
- GHC 9.6.7 or newer (preferably via [GHCup](https://www.haskell.org/ghcup/))
- Cabal 3.x
- `wayland-client` via `pkg-config`

Neither River nor wlroots 0.20 are in most distro package managers yet, so you will likely need to build both from source. libxkbcommon 1.13.0 is also newer than what most distros ship ... the system version may be missing `xkb_keymap_get_as_string2`, which River requires to build >= 0.4.0

Arch ships new enough packages that this should work out of the box. Everyone else: your mileage may vary. Debian users: congratulations on surviving the [K-Pg extinction event](https://en.wikipedia.org/wiki/Cretaceous–Paleogene_extinction_event)! Your system packages are prehistoric (as of April 2026) and you will be building most of this from source until things catch up. Clear your weekend!

Then build libxkbcommon, wlroots, and River from source. See each project's build docs for details.

## Building

```bash
cabal build
```

`app/Main.hs` accepts two launcher flags:

```bash
rivulet --debug --no-banner
```

- `--debug` enables verbose runtime logs (same effect as `RIVULET_DEBUG=1`)
- `--no-banner` suppresses startup ASCII art (same effect as `RIVULET_BANNER=false`)

No real `cabal test` target yet. I'm working on it!

## Roadmap

- [x] River protocol bindings
- [x] Real manage/render loop
- [ ] Finish core WM actions (focus, swap, workspace switching)
- [ ] Real workspaces and multi-monitor config
- [ ] Pointer move/resize
- [ ] Actual tests

## Getting freaky with Rivulet

GHC accepts unicode operator characters. These all compile:

```haskell
import Rivulet

(>ω<) :: Binds a b r => a -> b -> r
(>ω<) = (~>)   -- I know what you are.

(💀) :: Binds a b r => a -> b -> r
(💀) = (~>)    -- oh hell naw

main :: IO ()
main = rivulet $ do
  keybinds $ do
    [Super] # 'j'       >ω<  focusNext
    [Super, Shift] # 'q' 💀  closeFocused
```

You can bind a key to run the garbage collector. 

```haskell
import System.Mem
-- in keybinds $ do
just XF86Tools ~> performGC
```

You can generate workspace keybindings with `zipWith` instead of writing them out:

```haskell
mapM_ (uncurry (~>)) $ zipWith (\k a -> ([Super] # k, a))
  ['1'..'9']
  (map focusWorkspace ["I","II","III","IV","V","VI","VII","VIII","IX"])
```

Or, with `RebindableSyntax`, you can make `>>=` mean "bind a key." Technically it still reads as "bind," but you know what you did:

```haskell
{-# LANGUAGE RebindableSyntax #-}
import Rivulet
import Prelude hiding ((>>=))

(>>=) :: Binds a b r => a -> b -> r
(>>=) = (~>)

main :: IO ()
main = rivulet $ do
  keybinds $ do
    [Super] # 'j' >>= focusNext
    [Super] # 'k' >>= focusPrev
    [Super, Shift] # 'q' >>= closeFocused
```

Rivulet's config is your config. Do what you want with it, even if it's, uh, rebinding `>>=`. 
