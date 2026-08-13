# Field feedback implementation status

Updated: 2026-07-25

## iPhone

- [x] Stabilize Condition, Record, History, and History Detail navigation
- [x] Calculate meal calories from PFC values
- [x] Show every completed session on Home and support multiple sessions per day
- [x] Track meal-count completion separately from calorie/PFC achievement
- [x] Collect OSLog, local JSONL diagnostics, and MetricKit reports
- [x] Export diagnostic logs from Settings
- [x] Use focused chart domains so small body-measurement changes remain visible
- [x] Switch body-measurement charts between raw records and weekly averages
- [x] Copy the preceding set when adding a planned set
- [x] Combine integer and fractional workout weight wheels
- [x] Provide manual and wheel input for workout numbers
- [x] Clear the old value on manual-input focus and restore it when left blank
- [x] Open completed workout details from Home and History
- [x] Receive and control an active Apple Watch workout in real time

## Apple Watch

- [x] Add a workout complication/widget extension
- [x] Deliver a local notification when the rest timer completes
- [x] Keep the workout active through HealthKit background execution
- [x] Synchronize the active session and set operations with iPhone
- [x] Show the rest timer on the exercise that started it
- [x] Keep focus on that exercise's timer after set completion
- [x] Cancel a set that was started by mistake
- [x] Change the start action to a completion action while a set is active
- [x] Select any pending exercise when equipment order changes
- [x] Move completed sets to a separate archive screen
- [x] Show recent results and next-session information on the Watch home screen

## Verification

- [x] iPhone UI regression suite: 8 selected flows, 0 failures
- [x] Apple Watch workout UI flow, including cancel, timer restore, and completion
- [x] Simulator build for iPhone, Watch app, and Watch widget
- [ ] Sideload this revision after the Apple Account is available in Xcode
