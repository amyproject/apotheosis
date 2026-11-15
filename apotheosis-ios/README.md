# Apotheosis for iPhone

The band39-live care app (github.com/suarezc/band39-live, `care/web`, Charles Suarez's code) as an iPhone app.
**Content and behaviour are the original's; only design and UI change.** `web/` is an exact copy of `care/web`
(`tools/sync-web.sh`, checked with `diff -r`); the redesign is one extra stylesheet, `theme/apotheosis.css`
(copied to `web/apotheosis/`), scoped to `html.apo`. Look: the CareLink elderly-care Dribbble reference.
Navigation follows `band39-care/ios/Band39Care.xcodeproj`.

| Tab | What it shows (all original parts of the page) |
|---|---|
| **Margaret** | her screen: greeting, Pip, Ask Pip, band line, prompts, Talk to Lisa, replies, I need help |
| **Lisa** | the caregiver app: scores, live transcript, today's summary, alerts, safe card, signals, shop, doctor, messages |
| **Band** | Connect band 39 / Pretend band, and "Try it without a band"; gear = server address |

One WKWebView, one copy of the page, so all tabs share one live state. Lisa's in-page badge drives a native tab badge.

## Run
Open `ios/Apotheosis.xcodeproj` (Xcode 27, team `5GX36K3U7Y`, bundle `com.amyli.apotheosis`), pick an iPhone, Run.
- **No server**: the page loads from the app (apotheosis://app/); pretend band, motion signals, safe card and demo buttons work.
- **Server** (Band tab, gear): e.g. `http://<laptop-ip>:8039` running `care/server/server.py`; the page then loads from it,
  so the live transcript, Ask Pip, alerts and the summary work too.
- Real band: CoreBluetooth bridge (`BLEBridge.swift` + `native-ble.js`, from Band39Care); the page already uses `window.VexoNativeBle`.

## Update
    cd ../band39-live && git pull && cd ../apotheosis && tools/sync-web.sh

Browser check of the design: serve `web/` and open `apotheosis-preview.html?view=margaret|lisa|band`
(the original index.html plus the stylesheet; index.html itself is untouched).
Debug launch arguments: `-tab margaret|lisa|band`, `-snapshot /path.png`.
