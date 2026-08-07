# StrikeShot

An iOS app that photographs lightning **for** you.

Pointing a phone at a storm and tapping the shutter never works — by the time you
react, the bolt is gone. StrikeShot keeps a rolling buffer of the last few seconds
of camera frames and watches their brightness. When a flash spikes, it saves the
frames from *before* the trigger too. You cannot be too late.

Around that sits everything a storm chaser wants: a live lightning map fed by
Blitzortung.org, storm cells with drift and ETA, proximity warnings, a Live
Activity on the Lock Screen, and a session log of every storm you have chased.

## Features

**Capture**
- Auto-trigger on lightning in photo, video or slow-motion (240 fps where the hardware allows)
- Pre-roll ring buffer — the frames before the flash are kept, not lost
- Camera assistant: night/day exposure profiles, focus locked to infinity
- Automatic thunder ranging — the mic hears the thunder, the app computes the distance
- Storm simulator so the trigger can be tuned without a storm (or a camera)

**Storm awareness**
- Live strike map with an adjustable radius (10–250 km)
- Storm cells with travel direction and arrival time
- Approach alerts and safety warnings under 10 km / 3 km, with the 30/30 rule
- Live Activity and Home Screen widget
- Optional push server for warnings while the app is closed

**After the storm**
- Storm log: every session as a diary entry with map, counts and captures
- Best-shot ranking scored on brightness peak and edge energy
- Composite stacking — several bolts merged into one frame
- Personal statistics, spot heatmap and achievements

**Look**
- Storm-chaser dark theme whose accent charge rises with lightning activity
  and whose palette follows the time of day
- Stroke-animated bolt on cold start

## Building

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open StrikeShot.xcodeproj
```

Set your signing team on both targets, then run on a real device — the camera
trigger needs one. See `MORGEN-CHECKLISTE.md` (German) for the full setup
walkthrough and `Server/README.md` for the optional push server.

## Data source

Lightning data comes from [Blitzortung.org](https://www.blitzortung.org), a
volunteer-run network. **Their data is free for non-commercial use only.**

## Safety

StrikeShot is not a warning service. It tells you where lightning has struck; it
does not keep you safe. Under 30 seconds between flash and thunder means get
inside, and stay there for 30 minutes after the last thunder.

## License

MIT
