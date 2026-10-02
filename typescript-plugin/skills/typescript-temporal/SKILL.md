---
created: 2026-09-29
modified: 2026-09-29
reviewed: 2026-09-29
name: typescript-temporal
description: "Temporal API for TS/JS dates and times. Use when parsing, formatting or comparing dates, computing today, time zones, durations or working days."
user-invocable: false
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch
---

# Temporal for Dates and Times

New TypeScript and JavaScript code handles dates and times with `Temporal`.
`Date` packs a calendar date, an instant and the host time zone into one
mutable object. The bugs that follow all type-check: yesterday's date just
after midnight, every date shifted a day west of UTC, weekday indexes off by
one. Temporal gives each meaning its own type, so mixing them becomes a compile
error.

## Pick the type by what the value means

| The value is… | Type | Example |
|---|---|---|
| A calendar date with no time or zone (due date, holiday, timesheet day) | `Temporal.PlainDate` | `Temporal.PlainDate.from("2026-06-15")` |
| A month (billing or reporting period) | `Temporal.PlainYearMonth` | `Temporal.PlainYearMonth.from("2026-02").daysInMonth` is `28` |
| A wall-clock time, or date and time, with no zone ("09:00 every weekday") | `Temporal.PlainTime` / `Temporal.PlainDateTime` | `Temporal.PlainTime.from("09:00")` |
| A moment in time (log timestamp, `created_at`) | `Temporal.Instant` | `Temporal.Now.instant()` |
| A moment shown or bucketed in a place | `Temporal.ZonedDateTime` with an explicit IANA zone | `instant.toZonedDateTimeISO("Europe/Helsinki")` |
| A length of time | `Temporal.Duration` | `Temporal.Duration.from({ hours: 7, minutes: 15 }).total("hours")` is `7.25` |

If answering "which day is this?" needs a time zone, the value is not a
`PlainDate` yet.

## Convert a timestamp to a date once, at the boundary, in a named zone

```ts
// Wrong: the UTC calendar date, not the user's. In Finland (UTC+2/+3) this is
// yesterday from 00:00 to 02:00 local in winter and to 03:00 in summer.
const utcToday = new Date().toISOString().slice(0, 10); // or .split("T")[0]

// Right: one "today" seam for the whole codebase (see Testing for why it
// reads Date.now())
const TZ = "Europe/Helsinki";
export const today = (tz = TZ): Temporal.PlainDate =>
  Temporal.Instant.fromEpochMilliseconds(Date.now()).toZonedDateTimeISO(tz).toPlainDate();
const day = Temporal.Instant.from(apiTimestamp).toZonedDateTimeISO(TZ).toPlainDate();
```

Pass the zone explicitly. With no argument, `Temporal.Now.plainDateISO()` uses
the host zone, which on servers and CI runners is usually UTC. An unknown zone
ID throws `RangeError`.

## Keep calendar dates out of `Date`

The "UTC-midnight `Date`" pattern (`new Date("2026-06-15")` read back with
`getUTC*`) stays correct only while every caller remembers the UTC getters. A
single `getDate()`, `getDay()` or `toLocaleDateString()` reads it in local time,
and west of UTC the date moves back a day: with `TZ=America/New_York`,
`new Date("2026-06-15").getDate()` is `14`. Both getters return `number`, so
the type checker cannot see the mistake. A `PlainDate` has no time or zone to
misread.

## Store and transmit ISO strings

Keep ISO 8601 strings (`"2026-06-15"`, `"2026-06-15T09:00:00Z"`) in JSON,
databases, `chrome.storage` and URLs. Parse at the edge with
`Temporal.<Type>.from(str)`, emit with `.toString()`; `JSON.stringify` produces
the same string through `toJSON`. String input with an impossible date throws
(`PlainDate.from("2026-02-30")` is a `RangeError`), but property-bag input
clamps by default (`{ year: 2026, month: 2, day: 30 }` becomes `2026-02-28`),
so pass `{ overflow: "reject" }` when validating user input.

Interop with legacy `Date` and libraries happens at that same boundary:

| Direction | Call |
|---|---|
| `Date` to `Instant` | `date.toTemporalInstant()` |
| `Instant` to `Date` | `new Date(instant.epochMilliseconds)` |
| Epoch ms to `Instant` | `Temporal.Instant.fromEpochMilliseconds(ms)` |

## Porting from `Date`

| `Date` habit | Temporal |
|---|---|
| `getDay()`: 0 = Sunday … 6 = Saturday | `dayOfWeek`: 1 = Monday … 7 = Sunday; weekend is `d.dayOfWeek >= 6` |
| `getMonth()` is 0-based | `month` is 1-based |
| `a < b`, `a - b` | `Temporal.PlainDate.compare(a, b)`, `a.until(b)`; `<`, `-` and `"" + d` throw `TypeError` because `valueOf` throws |
| `a.getTime() === b.getTime()` | `a.equals(b)`; `===` compares object identity |
| `d.setDate(d.getDate() + 1)` mutates | `d.add({ days: 1 })` returns a new value |
| Jan 31 + 1 month rolls into March | `PlainDate.from("2026-01-31").add({ months: 1 })` is `2026-02-28` |

Template literals call `toString()` and are safe: `` `${date}` ``.

## Testing

A pinned test clock reaches `Temporal.Now` only if the fake-timer library fakes
it. `@sinonjs/fake-timers` added `Temporal.Now.*` faking in 15.4.0
(2026-05-05). Measured on Node 26 after pinning the clock to 2020-01-15:

| Runner | `Temporal.Now.instant()` |
|---|---|
| Vitest 4.1.4, 4.1.6, 4.1.11, `vi.useFakeTimers()` + `vi.setSystemTime()` | real time; only `Date` is pinned |
| Vitest 5.0.0 and 5.0.2 (5.0.0 release notes: "support mocking `Temporal`") | pinned |
| Jest 30.5.2, `jest.useFakeTimers({ now })` | pinned; `@jest/fake-timers` 30.4.0+ requires fake-timers `^15.4.0` |
| Bun 1.4.2, `setSystemTime()` | pinned |

An explicit `toFake` list that leaves out `"Temporal"` also leaves it real. On
runners that do not fake it, code that calls `Temporal.Now.*` directly ignores
the pinned clock and nothing fails loudly. The `today()` seam above reads
`Date.now()`, which every fake-timer version pins, so it behaves the same on
every runner; injecting a clock (`now: () => Temporal.Instant`) works as well.

`bun test` runs in UTC unless `TZ` is set. In UTC, UTC slicing and local
getters agree, so both off-by-one-day bugs above pass. Run date tests under a
zone east and a zone west of UTC.

## Availability

Native support per MDN browser-compat-data (8.1.3, 2026-09-24):

| Runtime | Native from |
|---|---|
| Chrome, Edge | 144 |
| Firefox | 139 |
| Safari | Technology Preview only; not in stable Safari or iOS |
| Node.js | 26.0.0 (earlier majors: polyfill) |
| Deno | 2.7 |
| Bun | 1.4.0 |

- **Older targets**: `temporal-polyfill` (FullCalendar, ~20 kB, defers to native
  Temporal when present). Import `"temporal-polyfill/global"` once at the entry
  point. MDN also lists `@js-temporal/polyfill`; its latest release (0.5.1,
  March 2025) predates Stage 4.
- **Chrome extensions**: set `"minimum_chrome_version": "144"` in the manifest.
  The Web Store then shows older Chrome "Not compatible" instead of the
  extension failing with `ReferenceError: Temporal is not defined`. Existing
  users on older Chrome stop receiving updates.
- **TypeScript**: types ship from TypeScript 6.0. Add `"ESNext"` to `lib`, or
  the granular `"esnext.temporal"` plus `"esnext.date"` (for
  `toTemporalInstant`). TypeScript 5.x has no Temporal types; with the polyfill,
  add `import "temporal-polyfill/types/global"`. The rest of the tsconfig
  belongs to `typescript-strict`.

## When `Date` still appears

New code that reaches for `new Date(`, `Date.now()`, moment, date-fns, dayjs or
luxon uses Temporal instead. The exception is an external API that takes or
returns `Date` (a library signature, `valueAsDate`, a database driver): convert
at that call site and keep Temporal on both sides. The `today()` seam's
`Date.now()` is the other exception. Migrate existing `Date` code
when it is touched for a date bug, not as a drive-by sweep.

## Agentic Optimizations

| Context | Command |
|---|---|
| Runtime has native Temporal | `node -p 'typeof Temporal'` (`object`) |
| Types resolve | `bunx tsc --noEmit` |
| Reproduce a zone bug | `TZ=America/New_York bun test` |

Find the patterns this skill replaces:

```bash
rg -n "toISOString\(\)\.(slice\(0, ?10\)|split\(['\"]T['\"]\))" src
rg -n 'new Date\(|Date\.now\(\)|from "(moment|date-fns|dayjs|luxon)' src
rg -n '\.get(Day|Date|Month|FullYear)\(\)' src
```

## References

- MDN Temporal: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Temporal
- Proposal docs and cookbook: https://tc39.es/proposal-temporal/docs/
- `temporal-polyfill`: https://github.com/fullcalendar/temporal-polyfill
- `minimum_chrome_version`: https://developer.chrome.com/docs/extensions/reference/manifest/minimum-chrome-version
