# BodyMode App Review Notes (en-US)

Updated: August 24, 2026

BodyMode is a health and fitness record and guidance app. It is not a medical device and does not diagnose, treat, prevent, or determine disease.

## Access

- Manual records and workouts require no account.
- Sign in with Apple is required only for AI, rewarded AI credits, and AI-credit purchases.
- No subscription or automatic renewal is offered.
- Apple Health, Apple Watch, and AI are optional. Manual records, history, charts, workouts, Watch sync, and on-device daily recommendations remain available without AI.

## Advertising and ATT

The iPhone app shows a non-personalized AdMob banner outside active workouts, data entry, camera, purchase, and consent screens. The AI tab offers an optional rewarded video for 5 AI credits, up to three grants per UTC day. Video never starts automatically. Health, meal, photo, location, goal, and workout records are not used for ad selection.

Before Google Mobile Ads starts, BodyMode requests App Tracking Transparency authorization. If permission is granted, the advertising identifier may be used for ad frequency control and performance measurement. If the user declines, BodyMode continues with non-personalized ads and does not restrict any feature. Ad personalization and publisher first-party identifiers remain disabled.

Review path: complete legal consent and initial setup. The ATT prompt appears before advertising starts. Controls remain at Settings > Ads & Privacy.

## AI Credits and In-App Purchases

1. Open the AI tab and choose Continue with Apple.
2. A new account receives 20 AI credits once.
3. Tap Buy Credits to open the consumable credit store.

Products:
- `com.yukitoshim.gymtrainingapp.credits50`
- `com.yukitoshim.gymtrainingapp.credits150`
- `com.yukitoshim.gymtrainingapp.credits500`

StoreKit supplies localized prices. The server verifies Apple's signed transaction and prevents duplicate grants before the app finishes it. Purchased credits do not expire, transfer, remove ads, or support Restore Purchases because they are consumables.

AI requests reserve the displayed credits before processing. Success consumes them; server or model failure releases the reservation. App Store Server Notifications V2 are signature-verified and processed idempotently. Refunds remove unused credits without making the balance negative.

## Apple Health (HealthKit)

Apple Health use is optional and is identified before authorization.

Review path:
1. Complete initial setup.
2. On Home, tap the Condition card.
3. The always-visible `Apple Health (HealthKit)` card explains the data read and written.
4. Tap `Select the items to sync.` to open Apple's authorization sheet.

The same disclosure is at Settings > Apple Health (HealthKit) & Apple Watch. BodyMode reads permitted steps, activity, sleep, heart-rate, and recovery data. It writes user-authorized Apple Watch workouts and body measurements. Manual logging remains available without HealthKit.

## Data and AI Controls

- Export records: Settings > Data > Export all records as JSON
- Delete app data, account, and unused credits: Settings > Data > Delete all data
- Export/delete diagnostics: Settings > Support and Diagnostics
- Usage analytics: off by default and controlled in Settings

Records are stored primarily on-device. Diagnostics are never sent automatically. Users choose AI record categories, and photos are sent only when analysis starts. AI output remains editable reference information.

## Apple Watch

Create or select a plan on iPhone and sync it from Record. On Watch, choose today's menu, start a set, adjust weight or reps, complete it, use tempo haptics and the rest timer, then finish. Results sync to iPhone.

## Export Compliance

BodyMode implements no proprietary or non-exempt encryption. `ITSAppUsesNonExemptEncryption` is `false`.
