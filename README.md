# SetLog

A Flutter workout tracker built for my Mobile App Development module at Temasek Polytechnic.

## Features
- **Sign-in:** Firebase Auth with email and password, Google Sign-In, email verification and password reset
- **Logging:** start a session, log sets (weight, reps, RPE) with validation, and a rest timer
- **Rest alerts:** scheduled notifications that arrive even when the app is closed
- **History:** past sessions stored in Cloud Firestore, filterable by split (e.g. Push, Pull, Upper body)
- **Stats:** weekly volume, training calendar, training split and all-time totals
- **AI coach:** sends a finished session's weights, reps and RPE to Google Gemini, which recommends whether to increase, maintain or deload. Without a key it falls back to an on-device rule engine
- **Premium:** a paywall with a NETS QR payment flow (sandbox)
- **Security:** Firestore rules so each user can only change their own sessions and sets

## Tech
Dart, Flutter, Riverpod, Firebase Auth, Cloud Firestore, Gemini API, NETS QR (sandbox), flutter_local_notifications

## Running it
```bash
flutter pub get
flutter run --dart-define=GEMINI_API_KEY=your_key --dart-define=NETS_API_KEY=your_key --dart-define=NETS_PROJECT_ID=your_id
```
No keys are stored in this repo. Get a free Gemini key at https://aistudio.google.com/app/apikey. The app still runs without keys: the AI coach uses its rule engine and NETS payments are disabled.
