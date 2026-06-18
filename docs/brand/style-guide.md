# Sports Manager family — brand style guide

Locked 2026-06-18. Covers the cross-app icon system (LMS, darts, pool,
football community, sweepstake — and future apps). Source of truth for
hex codes, font, and how to generate a new app's icon without drifting
from the established look.

## Palette

| Role | Hex |
|---|---|
| Background navy | `#0B1220` |
| Background navy, lighter panel | `#121C2E` |
| Master/chrome neon (shield base render) | `#3DA8FF` |
| Darts League | `#A855F7` |
| Pool League | `#22D3EE` |
| Football Community | `#22C55E` |
| Sweepstake Manager | `#EAB308` |
| Last Man Standing (LMS) | `#F97316` |
| Text / line art | `#F8FAFC` |

## Font

Wordmark text (e.g. "SPORTS MANAGER", in-app headers) is rendered as real
text, NOT an image — use **Montserrat ExtraBold/Black** (Google Fonts,
free, works identically in SwiftUI and CSS) so it's pixel-reproducible
across apps and platforms without re-generating an image each time.

## App icon system

Each app icon = one shared **shield** render + one **per-app glyph**,
both tinted to that app's accent colour, composited onto a shared
**stadium-light background**. This is what makes 5 different app icons
look like one family instead of five unrelated designs.

**Source renders** (in `sources/`, generated once via ChatGPT, reused
forever): `shield_chrome.png`, `background_floodlights.png`, and one
`glyph_<app>_chrome.png` per app. All are **neutral chrome/silver 3D
renders on a pure black background** — glossy, dramatic studio lighting,
NOT flat outline art, NOT pre-coloured. Neutral chrome is what lets the
same source be recoloured per app without regenerating it.

**Generating a NEW glyph for a future app** — reuse this exact prompt
template, only swapping the subject description:

> A single 3D glossy icon of [SUBJECT], rendered in glossy chrome/silver
> metallic material with a bright neon blue glow outline, dramatic studio
> lighting with a highlight reflection, subtle drop shadow, centered on a
> pure solid black background, no text, no shield, 1024x1024. Photoreal
> premium 3D icon style matching a high-end sports app icon — must have
> real depth and shading, NOT flat outline art.

If the generator produces an inconsistent/wrong result for an obscure
subject (happened with pool's ball+cue combo — kept rendering the cue as
a dart), simplify the subject rather than fighting the prompt (we dropped
to "8-ball alone" and that worked first try).

**Compositing** — `compose_icon.py` in this folder does the recolor +
layout. Two recolor strategies, pick per glyph:

- `colorize_metal(shadow_hex, mid_hex, highlight_hex)` — full
  luminance-preserving tint. Use when the glyph has no fixed colour
  identity to protect (shield itself, person+checkmark, dartboard,
  ticket). This is what makes the chrome shading/highlights survive
  becoming "the app's colour" instead of looking flat.
- `selective_recolor(target_hue_deg)` — only re-hues already-saturated
  pixels (the neon glow rim); leaves near-grayscale pixels untouched. Use
  when the source object has its own black/white identity that must
  survive recoloring — e.g. the pool 8-ball (needs to stay recognisably
  black ball + white "8", not turn into a solid cyan ball) and football
  (needs to stay a recognisable black/white-panelled ball). A `colorize_metal`
  pass on these wrecked the readability — the ramp mapped the ball's mid
  tones too light and it stopped looking like an 8-ball.

Run `python3 docs/brand/compose_icon.py` (after `pip install Pillow
numpy` into a throwaway venv — don't install globally, see project
tooling convention) to regenerate all 5 current icons from the locked
sources/palette. Output lands in `composited/`.

**Layout constants** (in the script, tune here if a future glyph needs a
different scale): canvas 1024×1024, shield 820px, glyph 440px, shield
y-offset +20, glyph y-offset +10 from center, background darkened to 55%
brightness behind the shield so the glow pops.

## What's NOT solved yet by this system

- The splash screen / launch animation (background + shield + wordmark,
  staged) is still TODO — see `Features/Splash/SplashView.swift` in the
  iOS app and [[lms-todo-next-session]] memory. The empty `shield`,
  `background`, `sports_manager_wordmark` imagesets in
  `Assets.xcassets` were prepared for this v2 staged splash; only
  `background` and a recolored `shield` need populating from
  `sources/` — the wordmark should be live SwiftUI Text in Montserrat,
  not a generated image (per the font decision above).
- Darts/pool/football/sweepstake icons are composited and proven here but
  not yet wired into their own (separate, not-yet-built) app projects —
  this repo just holds the shared source of truth until those projects
  exist.
