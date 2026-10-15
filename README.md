# 26Safari  (by Seko)
iOS 26 "Liquid Glass" style bars for Safari on iOS 16 (Theos tweak, rootless).

## Build
Push this folder to a GitHub repo. The workflow in .github/workflows/build.yml builds it on
a macOS runner with real Theos and signs it with ldid. Download the `26safari-deb` artifact
from the Actions tab. (Or: `export THEOS=~/theos && make package` on a Mac/Linux with Theos.)

A real build is much larger than 16 KB and links UIKit and QuartzCore.

## What is hooked (all -layoutSubviews unless noted)
Pills (glass):        SFUnifiedTabBarItemView, SFCapsuleView, plus any ~44pt-tall view inside
                      SFCapsuleCollectionView (REAL, confirmed with FLEX)
Toolbar (glass):      BrowserToolbar, _SFToolbar
Containers (clear if pills exist, glass otherwise):
                      SFUnifiedTabBar, SFCapsuleNavigationBar, _SFCapsuleNavigationBar,
                      CapsuleNavigationBar, SFNavigationBar, _SFNavigationBar,
                      _SFBrowserNavigationBar, _SFCapsuleContainerView, NavigationBar
Stock background:     SFNavigationBarBackgroundView (hidden)
Press effect:         UIControl -setHighlighted: (bottom-bar buttons only)

Classes that don't exist on your iOS are skipped silently.

## Disabled in 2.2.0
- Debug banner and clipboard dump (LG_DEBUG = 0)
- Log-only controller hooks
- Position-based UIView fallback
- Generic bottom UIToolbar hook (it could restyle toolbars inside Safari sheets)

## Notes
- Stock blur views that contain text are no longer hidden (that was hiding the URL text).
  Empty stock blurs are hidden, blurs with content just lose their blur, vibrancy views are untouched.

## Compact row (3.0.0)  -  LG_COMPACT in Tweak.xm
Like iOS 26: [back] [address pill] [... menu] on one row.
- The old second row (back/forward/share/bookmarks/tabs) is hidden with an empty layer mask and made untouchable.
- The pill is narrowed (it is NOT moved vertically any more, so Safari's tap handling keeps working).
- The round buttons reuse the toolbar's OWN actions (UIBarButtonItem target/action), so nothing is re-implemented:
  back = first item, "..." menu = forward / share / bookmarks / tabs.
- Safety: compact mode only turns on if the toolbar has at least 4 buttons with an action. Otherwise Safari's
  normal toolbar stays visible (with frosted glass). It also switches off while the keyboard is up (typing in the address bar).
- Pill and round buttons use the clear style (no blur, specular rim + inner edge glow). Set LG_COMPACT to 0 to go back to two rows.

### 3.1.0 fixes
- The toolbar is now found directly (not only through its own layout pass), and the layout is re-run at 0/1/3/6s after
  start, so compact mode starts on launch instead of after the first keyboard.
- The hidden toolbar stays untouchable even if Safari turns user interaction back on (setUserInteractionEnabled: override).
- The pill is no longer moved down into the toolbar row (suspected cause of the dead taps).

## 3.3.0 - Jelly touch (smooth sensitivity)
Added one self-contained block (LGJelly) and two attach lines (one on the pill, one on the round buttons).
Nothing else in the code was changed.
- The glass leans toward your finger while you press and drag, stretches a little, then springs back with a small overshoot.
- Soft haptic tap on touch-down.
- Knobs at the top of the block in Tweak.xm: LG_JELLY (on/off), LG_JELLY_HAPTIC (haptic on/off), LG_JELLY_SMOOTH (0.30; lower = lazier).
- Only layer.sublayerTransform is used, so the existing grow-on-press, finger glow and icon bounce are not affected.
