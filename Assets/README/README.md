# README assets

Screenshots and GIFs referenced by the root [`README.md`](../../README.md) live here.

| File | Shows |
| --- | --- |
| `dashboard.png` | Overview tab — fleet health gauge, status counts |
| `fleet.png` | Devices tab — search / filter / grouped list |
| `device-detail.png` | Device Detail — live temperature chart + current telemetry |
| `insights.png` | Insights tab — on-device AI observations |
| `signalflow-demo.gif` | Walkthrough: Overview → Device Detail → Insights |

How they were captured (so they can be regenerated after UI changes):
- iPhone 17 Pro simulator, light appearance, status bar overridden to 9:41
  (`xcrun simctl status_bar <udid> override --time 9:41 …`).
- App launched in English: `xcrun simctl launch <udid> com.signalflow.SignalFlow -AppleLanguages "(en)"`.
- Stills: `xcrun simctl io <udid> screenshot`, downscaled with `sips -Z 1311`.
- GIF: `xcrun simctl io <udid> recordVideo`, converted with ffmpeg at 12 fps / 320 px wide
  (palette-optimized). Keep it under ~8 MB.
