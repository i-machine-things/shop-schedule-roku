# Coding Best Practices & Reminders

> **Style rule:** Notes must be clear and concise — 300 characters or less each. Group by topic, not by date. Whenever a PR review (CodeRabbit or human) catches a mistake, add or amend a note here right away so it isn't repeated.

## Architecture

- **Roku has no web-view component in the public SDK.** This channel can't display `shop-schedule`'s `kiosk.html` directly — it polls a JSON export (`/schedule.json`, same shape as the Python `data` dict) and renders the table natively in SceneGraph instead.
- **`ScheduleScreen.brs`'s scroll loop is a visible reset, not a seamless wrap.** The web kiosk doubles its content and loops the scroll position for a seamless effect; replicating that in SceneGraph (duplicate the content tree, track two scroll positions) is meaningfully more complex for a cosmetic difference. Scroll-to-bottom → pause → snap-to-top → pause → repeat reads fine on a kiosk display and is far simpler to get right.
- **`Rem Hrs`/`#Ops` are per-row, not per-job.** Mirrors `jobboss_db.py`'s SQL: they're the sum/count of everything queued ahead of *that specific operation*, which is why the same job can show different values across its different open-operation rows. Don't "simplify" this to a single per-job value — it would be wrong, not simpler (see the `shop-schedule` PR description's job-30180 worked example for why).
- **No login screen.** Unlike `seerr-roku`, this channel doesn't authenticate against anything — `shop-schedule`'s server has no auth of its own. `SetupScreen` only collects a server URL, once, into the `ScheduleConfig` registry section.
- **Two stacked labels need real vertical separation, not just a few px.** The app header's clock (`clockLabel`) overlapped the report/thru date line (`metaLabel`) above it on real hardware with only a 22px gap between their `translation` y-values -- `font:SmallSystemFont` renders taller than that. Confirmed via screenshot, not guessed; widened the gap to 38px.
- **Only 5 fields are actually shown per job** (job, customer, description, oper, current WC) — an explicit scope decision, not an oversight. An earlier version showed all 11 fields from `schedule.json` on one line and truncated badly on real hardware (Roku's system fonts render much larger than that layout assumed). `schedule.json` itself still carries every field; this screen just doesn't render most of them.

## BrightScript / Roku Patterns

- **Standalone `TextEditBox` doesn't work for real text entry on Roku hardware** (same finding as `seerr-roku`) — `SetupScreen` uses a focusable row that opens `KeyboardDialog` on OK instead.
- **A top-level bare assignment statement outside any `sub`/`function` is invalid BrightScript** — `m.COLS = [...]` has to be built inside `init()`, not at file scope above it, even with a comment implying it's "set below." Caught this in `ScheduleScreen.brs` before it ever reached CI.
- **No Node.js available in this dev environment to run `bslint` locally** — written and manually re-reviewed carefully against BrightScript syntax, but CI's lint job is the first real syntax check these files get. Expect to iterate on CI failures for the first PR.
- **A plain `Group` does not clip its children — confirmed on real hardware, not just a guess.** The first version had no `clippingRect` on the scroll viewport; scrolled-up rows rendered on top of/behind the fixed header above instead of disappearing, since nothing told SceneGraph to stop drawing them outside that region. Fix: set `clippingRect="[x, y, w, h]"` (local coordinates) on the viewport `Group` — it's a real, documented field, not something you need a different node type for.
- **Simulating a "sticky header" (web `position:sticky` equivalent) needs both a real inline header AND a fixed overlay, not just one or the other.** First attempt skipped the inline header (divider line only) and just swapped the overlay's text at the boundary — worked, but had no scroll motion, reading as an instant jump-cut instead of the header scrolling up and *then* locking in place. Real fix: render the section header inline, at its normal scrolled position (identical appearance to the overlay) so it scrolls normally and clips away at the viewport top like anything else; the fixed `stickyHeader` overlay only becomes `visible` once `scrollY` has passed that section's recorded start `y` (i.e. the moment the real one would've vanished) and hides again once the *next* section's own inline header is still naturally within the viewport. Showing the overlay unconditionally once a section is "current" (rather than gated on `scrollY > startY`) causes a visible duplicate: overlay and real header both on screen, stacked, right as each section arrives.
- **Roku's OS-level screensaver/idle timeout is driven by remote-control input, not app activity — an auto-scrolling kiosk with no button presses still goes idle.** There's no manifest flag or public SceneGraph API to disable it for a normal (non-screensaver-category) sideloaded channel. The documented workaround: periodically fire a harmless local ECP keypress (`http://localhost:8060/keypress/<key>`) from within the app — this resets the same idle timer a real remote press would. Picked `Up` for the key specifically because neither `ScheduleScreen` nor `AppScene` handles it, so it's a true no-op (unlike `options`, used for reconfigure, or `rewind`, the easter egg trigger). See `onHeartbeat()`.
- **Column header label x-offsets in `ScheduleScreen.xml` are hand-duplicated from `m.COLS` in the `.brs`, not computed from it.** XML can't reference BrightScript variables at parse time. If `m.COLS` positions/columns ever change, the `columnHeaderRow` labels need the same edit or they'll silently drift out of alignment with the data cells below them.
- **A fetch failure must not blank the kiosk.** `onScheduleData()` only shows an error banner and leaves the last-rendered schedule in place on failure — matches `update_schedule.py`'s own "keep last displayed schedule" behavior on the Python side for the same reason (an unattended shop-floor display going blank on a transient network blip is worse than showing slightly stale data with a visible warning).

## CI / GitHub Actions

- **Never interpolate a GitHub Actions expression directly into a `run:` shell block** — pass it through `env:` and reference the env var instead (ref/branch/tag names can contain shell metacharacters).
- A job using `softprops/action-gh-release` needs an explicit `permissions: contents: write` block.

## Easter Eggs

- `components/AppScene.brs::onKeyEvent` — press the remote's "rewind" key 5 times within 2 seconds, from any screen. Shows a small credit dialog. Not mentioned anywhere user-facing.
- Not an easter egg, but similarly undocumented on purpose: pressing "options" on `ScheduleScreen` clears the configured server URL and returns to `SetupScreen`, for re-pointing the kiosk at a different server without a factory reset. Deliberately not advertised in the UI — this runs unattended on a shop floor TV.

## General Style Notes

- Keep lines under 120 characters where practical.
- This project has no automated test framework for BrightScript — Rule 3's "run tests" step means manually sideloading the build and exercising the changed screen before pushing.
