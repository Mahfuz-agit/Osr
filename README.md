# Personal Feed v2

Your own feed. Your own videos. Nothing else.

## What changed in v2
- Real frosted glass (backdrop blur) for the three controls, with a solid
  fallback for Reduce transparency or high contrast.
- Like and Share in one glass group at the bottom center. Share is optional
  (Sources > Feed > Share button). Sources button sits top right.
- Tap anywhere pauses or plays. Double-tap likes (or resets zoom when zoomed).
  Hold and drag sideways to scrub. No titles or dates on screen.
- Pinch zoom with fit and fill detents. Fit-or-fill is decided by math:
  crop = 1 - min(aV,aS)/max(aV,aS); fill if crop <= 0.25, else fit with a
  blurred ambient copy of the same video behind it.
- Light, Dark and System appearance. iOS-style grouped settings sheet.
- Ambient blur turns itself off if frames start dropping.
- Resumes the last video at the last second.

## Manifest formats (any one works)
1. JSON: {"videos":[{"url":"https://...mp4","title":"Name","date":"2025-10-22"}]}
2. JSON list of URLs: ["https://...mp4", "https://...mp4"]
3. Sitemap XML with <loc> or <video:content_loc>
4. Plain text, one URL per line

## Build
The Android scaffold is generated in CI (`flutter create`), then
`tool/patch_android.py` adds permissions and sets compileSdk 37.
