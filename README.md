# Personal Feed

Your own feed. Your own videos. Nothing else.

## Design rules
- **Zones.** Controls live only in the top 14% and bottom 35% of the screen,
  the same bands TikTok, Instagram, Facebook and YouTube Shorts keep clear.
  They always clear the system inset by 16 and the screen edge by 16.
- **Spacing.** 4pt scale: 4, 8, 12, 16, 24, 32. Share and Like are 52 buttons,
  24 apart, bottom center. Sources is 44, top right.
- **Fit.** Smart: fill the screen only when at most 10% would be cropped
  (broadcast safe-action margin), otherwise show the whole video. Bars split
  40 / 60 so the video sits slightly above center. The ambient blur is
  strongest next to the video and fades to black at the screen edges.
  Settings: Smart, Fill, Fit.
- **Glyphs.** Original vector drawings in the style of SF Symbols (SF Symbols
  cannot be bundled on Android).
- **Glass.** Real backdrop blur, solid fallback for Reduce transparency.
- **Motion.** Durations 150 / 250 / 350 ms, one easing curve. Reduce Motion
  turns everything into a plain fade.
- **Icon.** 1024 master without baked corners, adaptive background and
  foreground layers, and a monochrome layer for Android themed icons.

## Gestures
Tap pauses. Double-tap likes (resets zoom when zoomed). Hold and drag sideways
to scrub. Pinch to zoom, with detents at fit and fill.

## Manifest formats (any one works)
1. JSON: {"videos":[{"url":"https://...mp4","title":"Name","date":"2025-10-22"}]}
2. JSON list of URLs: ["https://...mp4", "https://...mp4"]
3. Sitemap XML with <loc> or <video:content_loc>
4. Plain text, one URL per line

## Build
CI generates the Android scaffold (`flutter create`), patches the manifest and
compileSdk (`tool/patch_android.py`), creates the launcher icons
(`dart run flutter_launcher_icons`) and builds the APK.
