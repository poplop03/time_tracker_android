# Tally — Flutter implementation plan

Agent-ready build plan for the time tracker prototyped in `Tally Time Tracker.dc.html`.
Read that file's logic class first: it is the behavioural spec (state shape, handlers, formatting rules).

**Product in one line:** track where the day went with a live timer, fill in blocks you missed, group activity names, see stats, and push blocks to Google Calendar.

---

## 0. Ground rules for the agent

- Flutter stable, Dart 3, Material 3, **Android first** (min SDK 24, target 35). Don't add iOS-only work.
- No web/desktop targets. Delete unused platform folders.
- Feature-first folders, `riverpod` for state, `drift` for storage. Do not introduce a second state or DB library.
- Every screen must work with an empty database (day one) and with 6 months of blocks (no full-table loads in build methods).
- Timer correctness is the top priority: **never accumulate elapsed time in memory** — persist `startedAt` and derive.
- Write widget tests for the four pure functions in §5 and one golden test per screen. Do not chase coverage elsewhere.

---

## 1. Packages

| Concern | Package |
| --- | --- |
| State | `flutter_riverpod`, `riverpod_annotation` |
| DB | `drift`, `sqlite3_flutter_libs`, `path_provider` |
| Foreground timer | `flutter_foreground_task` |
| Background sync | `workmanager` |
| Google auth | `google_sign_in` (scope `https://www.googleapis.com/auth/calendar.events`) |
| Calendar API | `googleapis` (`calendar/v3`) + `extension_google_sign_in_as_googleapis_auth` |
| Prefs | `shared_preferences` |
| Fonts | `google_fonts` (Caprasimo, Figtree) |
| Icons | `lucide_icons` |
| Time formatting | `intl` |

---

## 2. Data model (drift)

```dart
// activities
id            int pk autoincrement
name          text unique collate nocase   // free text — the user types anything
groupName     text nullable                // user-specified group, e.g. "Entertainment"
colorSeed     int                          // stable dot colour index
createdAt     datetime
lastUsedAt    datetime nullable

// blocks
id            int pk autoincrement
activityId    int fk -> activities.id
startedAt     datetime                     // UTC stored, local displayed
endedAt       datetime nullable            // null == currently running
note          text nullable
calendarEventId text nullable              // set once pushed to Google
syncDirty     bool default true            // needs push
```

Rules:
- **At most one row with `endedAt == null`.** Enforce in the repository, not just the UI.
- Groups are a string on `activities`, not a table. Renaming a group = bulk update of that string. `null`/`'Ungrouped'` is the catch-all bucket.
- Indexes: `blocks(startedAt)`, `blocks(activityId)`, `blocks(syncDirty)`.
- Migrations from schema 1 onward via drift's `MigrationStrategy`; never wipe user data.

---

## 3. Screens (bottom nav, 5 tabs — mirrors the prototype)

### 3.1 Today
- Header: date kicker, **live total tracked today** (completed blocks + running elapsed), recomputed each second.
- **Running state:** accent-tinted card — pulsing dot, "Tracking now", group pill, activity name, `HH:MM:SS`, "since <start>", **Stop**.
- **Idle state:** free-text field ("What are you doing?"), **group chips** (existing groups + "No group") to pick *before* starting, then the round Start button.
- Timeline of today's blocks: time gutter, name, duration + span, sync tick. **Untracked gaps ≥ 10 min render as dashed tappable rows** that open the fill-in sheet prefilled with the gap's bounds.
- "Add a block you missed" opens the same sheet with ±15-minute steppers and a live duration readout.

Acceptance: kill the app mid-run and reopen → timer still running with correct elapsed. Stop → block appears in the timeline, activity's total and block count increase, `syncDirty = true`.

### 3.2 Stats
- 7-day bar chart of daily totals (today highlighted).
- **Donut by group** (`CustomPainter`, sweep angles from group totals) with total in the hole and a legend: dot, group, duration, percent, share bar.
- Copy line naming the biggest group and its percent.

Acceptance: percentages sum to 100 %; regrouping on Names immediately changes the donut; empty DB shows an honest empty state, not a zero-division crash.

### 3.3 Insights
- Average tracked day, longest unbroken stretch, untracked share of waking hours, deep-work-by-hour bars, one plain-language observation.
- All derived from real queries — no hardcoded numbers.

### 3.4 Names (activities + grouping)
- List sectioned by group, each header showing group total and name count, with **Ungroup**.
- **Group** enters select mode: tap names → "Group N names" → bottom sheet with a **user-typed group name** plus chips for existing groups → Save moves them, drops emptied groups, and adds the new group to the order.
- Add-activity field appends to Ungrouped; duplicate names (case-insensitive) are rejected silently.

### 3.5 Sync (4 steps)
0. Intro — what sync does, what it touches, **Connect Google Calendar**.
1. Pick calendar — radio list from `calendarList.list()`, plus "Time tracked (new)" which creates a dedicated calendar.
2. Direction — push / pull / both.
3. Connected — status card, "Only sync blocks over 15 minutes" and "Include activity name in event title" toggles, Sync now, Disconnect.

---

## 4. Timer architecture (get this right first)

1. Start: insert a block with `endedAt = null`, write `startedAt` to prefs, start `flutter_foreground_task` with an ongoing notification (activity name + elapsed, Stop action).
2. UI elapsed = `DateTime.now().difference(startedAt)`, ticked by a 1-second `Timer.periodic` **only while the Today tab is visible**. The tick never mutates stored duration.
3. Stop (from UI or notification): set `endedAt = now`, `syncDirty = true`, stop the service, clear prefs.
4. On cold start, reconcile: an open block in the DB means the timer is still running — resume the notification.
5. Guard the pathological case: an open block older than 12 hours prompts "Still tracking *X*?" with Keep / End at last activity.

---

## 5. Pure functions to unit-test

```dart
String formatDuration(Duration d);            // "1h 40m", "45m", "18h 05m" (minutes zero-padded when hours present)
String formatClock(DateTime t, bool use24h);  // "11:15am" / "11:15"
List<TimelineRow> buildTimeline(List<Block>, {Duration minGap = const Duration(minutes: 10)});
List<GroupSlice> groupBreakdown(List<Activity>, List<Block>); // sorted desc, percents sum to 100
```

`buildTimeline` emits entry rows and gap rows in chronological order — port it from the prototype's `rows` builder.

---

## 6. Google Calendar sync

- Auth: `google_sign_in` with the `calendar.events` scope → authenticated client via `extension_google_sign_in_as_googleapis_auth`. Persist the chosen `calendarId` and direction.
- **Push:** for each `syncDirty` block, `events.insert` (or `events.patch` when `calendarEventId` exists). Summary = activity name (or group when the title toggle is off), description = "Tracked in Tally", `start`/`end` with the device timezone. Store the returned id, clear `syncDirty`. Skip blocks under 15 minutes when that toggle is on.
- **Pull:** `events.list` with `singleEvents: true`, `timeMin`/`timeMax` = the visible week → surface as *suggestions the user confirms*; never write blocks silently. Skip all-day and declined events.
- Run pushes in a WorkManager periodic task (~15 min) plus one on Stop; exponential backoff, and treat 401 as "reconnect required" surfaced on the Sync tab.
- Never touch calendars other than the selected one.

---

## 7. Design system (Organic) → Flutter theme

Wire these as a `ThemeExtension`; do not re-pick colours per widget.

```
bg #f5ead8   surface #ebddc5   text #201e1d   accent #c67139   accent2 #7a8a5e
accent ramp   200 #ffe1d0  400 #f6a06b  700 #8c491a  800 #643312  900 #402310
sage ramp     100 #f0fae1  300 #ccdbb2  500 #8fa073  600 #728157  800 #3d472b
neutral ramp  200 #eee7db  300 #dcd3c4  400 #c0b6a5  600 #82796a  700 #645c50
```

- Headings **Caprasimo**; body **Figtree** (400/600/700).
- Radii: cards 32, rows 24, buttons/inputs/chips fully pill (`StadiumBorder`).
- Lucide icons at stroke width 2.75.
- Small text on cream or surface must use `neutral-700` or darker (4.5:1); accent text at body size uses `accent-700`, never `accent`.
- Minimum tap target 44 dp everywhere, including the Ungroup button.

---

## 8. Milestones

1. **Skeleton** — project, theme extension, fonts, 5-tab shell, drift schema + seed-free empty states.
2. **Timer** — start/stop, foreground service, cold-start reconciliation, live Today total. *Ship-worthy on its own.*
3. **Timeline + retroactive** — gap detection, fill-in sheet, overlap resolution (trim the earlier block; reject a full containment with a snackbar).
4. **Names + grouping** — sectioned list, select mode, user-named groups, ungroup, add activity.
5. **Stats + Insights** — daily bars, donut painter, derived insight queries.
6. **Calendar sync** — auth, 4-step setup, push, WorkManager, then pull-as-suggestions.
7. **Polish** — notification actions, app widget showing the running timer, CSV export, TalkBack labels, 12/24-hour setting.

Each milestone ends green: `flutter analyze` clean, tests passing, no debug prints.

---

## 9. Out of scope (don't build)

Accounts or a server, teams/sharing, billing or invoicing, idle detection or automatic tracking, iOS, tags beyond the single group field, per-block manual editing beyond name and times.
