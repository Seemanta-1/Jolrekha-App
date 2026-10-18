# জলরেখা (JolRekha)

Dhaka waterlogging app: predicts where water is likely to collect, lets people report it in one tap, verifies reports with the crowd, sends verified problems to the ward authority, and lets volunteers clear drain inlets before and after rain, recording the plastic removed.

## What is in the app

| Role | Tabs | What they do |
| --- | --- | --- |
| Citizen (phone number login) | Map, Events, Leaderboard, Profile | AI risk map and today/tomorrow banner, report water / live wire / open manhole / blocked drain, vote "still there" or "gone", water depth view (what can pass: walk, rickshaw, car, bus), safe route by vehicle, danger alert within 200 m, join clean-up drives and team chat, points, levels and badges |
| Volunteer (email, admin-approved) | + Tasks | AI clean-up plan for tomorrow's hotspots, claim verified problems, resolve with cause, kg of plastic and drain inlets, create clean-up drives |
| Ward council (email, admin-approved) | + Ward | Only verified or urgent incidents in their areas; forward by WhatsApp/email, acknowledge, start work, resolve; AI weekly report |
| Admin (website) | Overview, Approvals, Users, Ward contacts | Approve volunteers and councils, change roles and areas, suspend users, set ward contacts |

## Review model (how a report becomes action)

1. **Merge:** reports of the same type within 150 m and 2 hours become one incident; the count goes up.
2. **Crowd check:** nearby people vote "still there" / "gone". Water is **verified** at 3 (reporters + "still there" votes); a volunteer's on-site vote verifies immediately.
3. **Danger exception:** live wire and open manhole are **urgent** from the first report, shown to authorities at once, verified at 2.
4. **Forward:** volunteers and authorities send verified incidents to the ward contact by WhatsApp or email with a ready Bangla summary and map link.
5. **Close the loop:** reported → verified → acknowledged → in progress → resolved → closed. After "resolved", one "gone" vote closes it; two "still there" votes or a new report reopen it. 3 "gone" votes close an unresolved incident (water receded).

All thresholds are in `lib/config.dart`.

## Architecture

```
Colab (done)                         App (Flutter)                          Firebase
news dataset -> model.json  ──────>  assets/model.json                      Auth (phone / email)
                                     Open-Meteo forecast ─> risk per area   Firestore:
                                     Map (OSM) + reports + votes  <──────>    users, incidents, reports,
                                     OpenRouteService (avoid water)           cleanups, stats, contacts
                                     WhatsApp / email (url_launcher)        Security rules (firestore.rules)
                                     Gemini (Firebase AI Logic)             AI: photo check, plans, reports
```

No server or paid plan is needed: risk is computed on the phone, and review logic runs in Firestore transactions.

## Run locally

Requirements: Flutter 3.44+ and Chrome.

```bash
flutter pub get
cp env.example.json env.json        # then paste your OpenRouteService key into env.json
dart pub global activate flutterfire_cli
flutterfire configure               # creates lib/firebase_options.dart (not in git: it holds API keys)
```

Citizen / volunteer / ward app:
```bash
flutter run -d chrome -t lib/main.dart --web-port 8080 --dart-define-from-file=env.json
```

Admin website (needs a user whose `users/{uid}` document has `role: "admin"`):
```bash
flutter run -d chrome -t lib/admin/admin_main.dart --web-port 8081
```

Firebase project: `jolrekha-cbaa0`. To use your own project:
enable Email/Password sign-in, create Firestore, run `flutterfire configure`, then
`firebase deploy --only firestore:rules`. Ward contacts can be added from the admin website.

Free OpenRouteService key: openrouteservice.org → Sign up → Dashboard → Request a token (Standard).

## Risk model

`notebooks/JolRekha_Model_Train.ipynb` (Google Colab) trains the model from the news-based dataset in
Drive (`waterlogging_events_dhaka.csv`) and Open-Meteo rainfall history, and writes `jolrekha_model.json`.
Copy it to `assets/model.json`; the app reads features, coefficients, risk thresholds and areas from it.

## Demo script (3 phones, about 3 minutes)

Before the demo: register one volunteer and one ward council account and approve them on the admin website.

1. **Phone A (citizen):** open the map; show the today/tomorrow risk banner and the AI risk zones.
2. **Phones A, B, C:** report "knee-deep" at the same spot. The pin counts up and turns **verified** at 3.
3. **Ward council:** the incident appears in the Ward tab; tap **WhatsApp** to send the Bangla summary; tap **দেখেছি**.
4. **Volunteer:** Tasks → claim it → **সমাধান হয়েছে**, cause "plastic", 3 kg, 2 inlets.
5. **Phone A:** vote "পানি নেমে গেছে" → closed. Open **Impact**: 3 kg plastic, 2 inlets, cause chart.
6. **Danger:** report a live wire near Phone B's location → Phone B gets the 200 m alert.
7. **Route:** turn on **নিরাপদ রুট**, pick a vehicle, tap a destination across the reported spot; a car route bends around knee-deep water, a rickshaw route does not.
8. **Leaderboard / Profile:** points, level progress and badges.

## Prototype vs production

| Prototype (now) | Production |
| --- | --- |
| Phone number login without OTP | Phone OTP sign-in |
| Points written by the client | Points and review logic in Cloud Functions |
| Review logic in client transactions | Cloud Functions, so it cannot be bypassed |
| Forward via WhatsApp/email from a staff phone | Automatic email/SMS digest to ward contacts |
| Danger alert while the app is open | Push notifications (FCM) |
| Area = nearest hotspot | DNCC/DSCC ward boundaries |
| Public OSM tiles | Own tile provider (OSM tile policy limits heavy use) |

## Known limits

- Risk levels are relative (low/medium/high), not exact probabilities: public rainfall data misses many local Dhaka storms.
- The OpenRouteService key is compiled into the web app; fine for a demo, move it behind a server before launch.
