# 26Safari

**iOS 26 "Liquid Glass" Safari for iOS 16.** A jailbreak tweak (Theos, rootless) by **Seko** and **Lionel**
that reshapes Safari's address bar and toolbar into the iOS 26 look: a clear glass pill, round glass
buttons, a compact one-row layout, and the "alive" feel of iOS 26 when you touch it.

> iOS 16 has no public Liquid Glass API. 26Safari approximates the look with a thin backdrop blur,
> saturation boost, specular rim highlights, a soft glow and spring animations. It is a very close
> imitation, not Apple's real lensing/refraction.

---

## Features

**Look**
- Clear glass address pill (almost no blur, see-through) with a bright specular rim and inner edge glow.
- Round glass back button and "..." button on either side of the pill.
- Safari's opaque dark bar backgrounds are removed, so the page shows through the bar.

**Layout** (`LG_BOTTOM_BAR`)
- **Compact (default):** `[back] [address pill] [...]` on a single row, like iOS 26 Compact.
  The old second row (back / forward / share / bookmarks / tabs) is hidden. Its own buttons are reused,
  so nothing is re-implemented: back is the round button, the "..." menu holds Forward / Share / Bookmarks / Tabs.
- **Bottom:** keeps Safari's toolbar and wraps its five buttons in a glass capsule under the pill.
- In the tab overview and similar screens (an OK / Done button at the bottom) the tweak steps aside and
  Safari shows its normal full-width bar.

**Touch feel**
- Press-to-grow spring on the pill and the round buttons, with a glow that follows your finger.
- Jelly bounce on the button icons.
- **Jelly touch:** the glass leans toward your finger while you press and drag, stretches a little, then
  springs back with a small overshoot, plus a soft haptic tap.

**Typing mode** (while you type in the address bar, like real iOS 26)
- The back arrow fades out.
- The "..." bubble turns into a round **X** bubble. It presses Safari's own Cancel, and if the keyboard is
  still up a moment later it closes it. Safari's stock "Cancel" button is hidden while the X is showing.
- **Loupe lens:** press and hold the address field to move the cursor and a round glass lens pops up above
  your finger, magnifying the text around it (with a thin red/blue chromatic edge). Safari's stock loupe is
  hidden while the lens is in use.
- Typing inside a text box on a web page does **not** trigger any of this.

---

## Requirements

- iPhone on **iOS 16** with a **rootless** jailbreak (Dopamine, palera1n rootless).
  Rootful palera1n: delete the `THEOS_PACKAGE_SCHEME = rootless` line in the Makefile before building.
- Arm64 and arm64e are both built (A12 and newer need arm64e to be injected into Safari).
- **iOS 17 is not supported yet.** Apple renamed or restructured Safari's bar views, so the class names
  below don't exist there and the hooks find nothing. Other iOS versions are untested.

## Install

1. Download the `.deb` (see Build).
2. Install it with Sileo, Filza or `dpkg -i`.
3. Force-close Safari (or `killall MobileSafari`) and reopen it.

## Build

**GitHub Actions (no computer needed)**
1. Create a repo and upload the contents of this folder. `.github/workflows/build.yml` must be at the top level.
   On a phone, create that file with *Add file → Create new file* and type the path as its name.
2. Open the *Actions* tab. The build starts on every push (or run it by hand).
3. Download the `26safari-deb` artifact. The log prints `lipo -info` and `otool -L` for the dylib.

**Theos on a Mac / Linux**
```
export THEOS=~/theos
make package FINALPACKAGE=1
```
The `.deb` is created in `packages/`.

A real build is **much** bigger than 16 KB, links UIKit and QuartzCore, and contains strings such as
`LGGlass` and `LGJelly`. A 16 KB file with no code is a placeholder from a fake compiler and will do nothing.

---

## Configuration

All switches are `#define`s at the top of `Tweak.xm` (rebuild after changing).

| Setting | Default | What it does |
|---|---|---|
| `LG_LOW_BLUR` | 1 | 1 = thin backdrop blur (see-through glass), 0 = Apple's stock material blur |
| `LG_BLUR_RADIUS` | 2.0 | Smaller = clearer glass |
| `LG_BLUR_SCALE` | 0.6 | Backdrop capture scale (blur is radius / scale points) |
| `LG_SATURATION` | 1.35 | Colors behind the glass pop a little |
| `LG_BOTTOM_BAR` | 0 | 0 = Compact one-row layout, 1 = Bottom capsule layout |
| `LG_JELLY` | 1 | Lean-toward-finger + spring-back touch effect |
| `LG_JELLY_HAPTIC` | 1 | Soft tap on touch-down (0 = silent) |
| `LG_JELLY_SMOOTH` | 0.30 | How smoothly the glass follows the finger (lower = lazier) |
| `LG_TYPING_UI` | 1 | Hide back arrow, show X bubble and hide stock Cancel while typing |
| `LG_LENS` | 1 | Glass loupe lens while you press and hold the address field |

---

## How it works

- **Hooks.** `layoutSubviews` on Safari's bar views, plus `setBounds:` / `setFrame:` on the pill class so
  the pill is narrowed to make room for the round buttons. A small `UIView -didMoveToWindow` hook hides the
  stock loupe, and only while you are typing in the address bar.
- **Classes it looks for** (a class that doesn't exist on your iOS is skipped silently):
  `SFCapsuleCollectionView` (the full-screen container, confirmed with FLEX), `SFCapsuleView`,
  `SFUnifiedTabBarItemView` (the pills), `BrowserToolbar` / `_SFToolbar` (the old bottom row),
  `SFNavigationBarBackgroundView` (stock background), and several bar containers
  (`SFUnifiedTabBar`, `SFCapsuleNavigationBar`, `_SFNavigationBar`, `_SFBrowserNavigationBar`, ...).
- **One ticker.** A display link runs `LGSync()` every frame. It finds the active pill, keeps the old toolbar
  hidden and untouchable, positions the round buttons in a window-level overlay, and reads the toolbar's
  real buttons so each round button simply triggers Safari's own action.
- **Glass.** `LGGlass` is the glass surface (backdrop blur, saturation, specular rim, inner glow, shadow).
  `LGTouchFX`, `LGBounceFX` and `LGJelly` add the touch behaviour. `LGLens` is the loupe.
- **Typing detection.** The keyboard being visible is not enough (it also shows for web page inputs), so the
  tweak asks UIKit who the first responder is and ignores anything that lives inside a web view.
- **Safe fallbacks.** If the toolbar's buttons can't be found, Safari's normal toolbar stays visible.
  Tab overview / Done screens fall back to Safari's stock layout.

## Troubleshooting

- **Nothing changes.** The tweak isn't loading. Check the file in
  `/var/jb/Library/MobileSubstrate/DynamicLibraries/` is the real build (see Build), is signed (`ldid`), and
  has an arm64e slice (`lipo -info`). Make sure injection isn't blocked for Safari (Choicy etc.).
- **Address text missing.** Fixed in 2.2.0 (empty blur views are hidden; blur views with content only lose the blur;
  vibrancy views are left alone).
- **Taps do nothing in the bar.** The tweak moves nothing vertically for this reason; if you see it, tell us
  which Safari state it happens in.
- **Empty band under the bar.** Safari still reserves the old toolbar height. This can't be changed safely.
- **Stock loupe still shows next to the lens.** Its class name doesn't contain "Loupe" / "Magnifier" on your iOS.
  Set `LG_LENS` to 0, or send the class name found with FLEX.
- **Finding class names.** Use FLEX: open it in Safari, tap an element, read the class and its parents.

## Known limits

- No real refraction or lensing (public UIKit can't do it on iOS 16).
- The address field in typing mode keeps Safari's width (it is not stretched to the left like iOS 26).
- The loupe lens is an approximation built from a magnified snapshot, not Apple's loupe.
- iPad is not handled.

## Project layout

```
26safari/
  Tweak.xm                  all of the tweak
  Makefile                  Theos build (arm64 + arm64e, rootless)
  control                   package info (com.sekoandlionel.26safari)
  26safari.plist            injects into com.apple.mobilesafari only
  .github/workflows/build.yml   GitHub Actions build
  README.md                 this file
```

## Changelog

- **3.4.0** Typing mode: back arrow hidden, X bubble, stock Cancel hidden, glass loupe lens. README rewritten.
- **3.3.0** Jelly touch: the glass leans toward the finger and springs back, plus a soft haptic tap.
- **3.2.0** Window-level round buttons driven by one ticker, roles read from the toolbar's real buttons,
  tab-overview detection, spring press effects and finger glow.
- **3.1.0** Toolbar found directly, layout re-run at launch, hidden toolbar kept untouchable, pill no longer moved vertically.
- **3.0.0** Compact one-row layout: `[back] [pill] [...]`.
- **2.x** Real class names from FLEX (`SFCapsuleCollectionView`), clear glass pill, address text fix, debug tools off.
- **1.x** First versions: frosted glass bars, class-name discovery and debug dump.

## Credits and license

- **Seko** and **Lionel**: 26Safari.
- The glass effects (backdrop glass, specular rim, finger glow, press-to-grow spring) are adapted from
  **"Liquid (Gl)ass" by dylv**, licensed **CC BY-NC 4.0**. That credit is kept on purpose, and because of
  that license **this tweak is for non-commercial use only**.
- Not affiliated with Apple. "Liquid Glass" and "Safari" are Apple's trademarks.
