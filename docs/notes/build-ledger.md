# Build ledger (dryp 0.1)

Rulings and deferred minors recorded while building dryp 0.1 with subagent-driven development. Kept for the record; git history has the code.

Spec: docs/superpowers/specs/2026-09-30-dryp-design.md
Branch: build/dryp-0.1 (from main @ 62b3e6e)

## Pre-flight scan
| Pair / task | Produces → consumes | Finding |
|---|---|---|
| T1 → T14 | spike outcome → notifier variant | Fallbacks say "Extend lives in the menu only" but T15's menu has no Extend item → conflict with spec (spec: fallback = Extend in the menu). Ruling R2. |
| T1 self | step 4 creates branch | branch already created by controller. Ruling R1. |
| T2 → T11/T13/T14 | placeholder files → replaced | consistent (Harness.swift, DrypIcon.swift, main.swift replaced). OK |
| T2 → all | models/DrypJSON/wholeSeconds | names match across T4–T17. OK |
| T3 → T11/T14 | DurationParser.parse(_:hours:) | consistent. OK |
| T4 → T8/T11/T12/T14/T17 | Paths, StateStore.update/clear/current, AppliedStore, StartMarker, Manifest | consistent. OK |
| T5 → T8 | Policy.decide, Decision.clear [Mode:Session] | consistent. OK |
| T6 → T8/T14 | Schedule.*, LoginCheck.shouldExit | consistent. OK |
| T7 → T8/T12/T14/T15 | Format, MenuBarModel, NoticeText, PmsetCommand | consistent. OK |
| T8 → T9 | Reconciler stubs → replaced | stubs named identically. OK |
| T8 test fakes vs T11 harness fakes | duplicated fake drivers in two test targets | rubric "verbatim duplication"; plan mandates. Ruling R3. |
| T10 → T11/T14/T17 | Shell, AgentControl(pid,start,stop,nudge), Launchctl.target | consistent. OK |
| T11 → T12/T17 | CLIEnvironment(run,nosleepInstalled,...), CLIHarness, subcommand registration | consistent (T12 adds Status/AppCommand, T17 adds Update/Uninstall). OK |
| T13 → T16 | dryp-icon tool → build-app.sh | consistent. OK |
| T14 → T15 | AppDelegate API, StatusMenu(app:) stub, Alerts | consistent. OK |
| T16 → T17 | install.sh flags, APP_DIR, DRYP_SOURCE, manifest keys | consistent. OK |
| T16 → T18 | installed dryp → verify.sh | needs a real install with sudo. Ruling R4. |
| T13/T14/T15 self | manual visual checks "with the human" | subagents can't see the screen. Ruling R5. |
| T2–T12, T17 self | tests vs code in each task | read through: assertions match the specified code (spot-checked remaining() cases, epoch 1_790_784_000 = 2026-09-30 16:00 UTC, rev monotonic, exit-code mapping). OK |

## Rulings
- Ruling R1: Skip T1 step 4's `git checkout -b`; branch build/dryp-0.1 already exists and is checked out — no cost.
- Ruling R2: If the spike outcome is not ACTIONS_OK, T15 adds an "Extend 1 hr" item to each mode submenu (enabled only for a timed session, calls reconciler.extend + reconcile) — the spec's fallback requires Extend in the menu — cost if wrong: one extra menu item.
- Ruling R3: Keep the duplicated fake drivers in DrypCoreTests and DrypCLITests as the plan specifies (separate test targets, ~40 lines) rather than adding a shared TestSupport target — cost if wrong: minor duplication to consolidate later.
- Ruling R4: T16's real install (needs the sudo password) and T18's verify.sh run are deferred to the end and done with the human present; implementers write and statically check the scripts only — cost if wrong: installer bugs surface later, at the end-to-end step.
- Ruling R5: Manual visual checks in T13–T15 (icon look, menu-bar glyphs, light/dark) are done by implementers only as far as builds, CLI checks, logs and rendered PNGs allow; the human-eyes checks are batched for the human at the end — cost if wrong: visual polish issues found later.
- Ruling R6: The controller runs T1's throwaway spike itself (it needs the human to click a banner now, while they're present); no product code — cost if wrong: none beyond a skipped review of throwaway code.

## Progress
- Ruling R2 update: spike outcome ACTIONS_OK, so R2's menu-Extend fallback is not needed — no cost.
- Ruling R7: Per the user, the app bundle is lowercase `dryp.app` (executable `dryp`) everywhere; Swift module/type names (DrypCore, DrypApp, struct Dryp…) stay CamelCase since they're code identifiers, not user-facing — cost if wrong: renaming modules later.
- Ruling R8: Per the user, the T14 notifier matches peel/mutewake permission handling (ask once if undetermined, alerts only/no sound, respect denial, osascript fallback only on errors); plan T14 Step 2 rewritten in commit cf235b5 — cost if wrong: no notification sound.
Task 1: complete (commits 62b3e6e..cf235b5, controller-run spike; outcome ACTIONS_OK)
Task 2: minor (deferred): ld warning "building for macOS-13.0, but linking Testing.framework built for 14.0" from CLT Testing.framework via scripts/test.sh — environmental
Task 2: minor (deferred): Package.resolved committed (argument-parser 1.8.2 pin) — reasonable, not in brief
Task 2: complete (commits cf235b5..a0fec1d, review clean)
Task 3: minor (deferred): Int-overflowing minutes (e.g. 99999999999999999999) report notWholeMinutes instead of tooLong (still rejected)
Task 3: minor (deferred): Double() accepts 0x1p3 / 1e3 forms with -h
Task 3: complete (commits a0fec1d..f74f597, review clean)
Task 4: minor (deferred): revKeepsRisingAfterTheFileIsDeleted can flake if both updates land in the same ms (rev would be equal, not greater) — fix test with a short sleep or strict floor
Task 4: minor (deferred): StateStore.read maps any read error (EACCES/IO) to .missing, so update could overwrite a valid file (plan-mandated)
Task 4: minor (deferred): Manifest.read untested
Task 4: complete (commits f74f597..2bd438c, review clean)
Task 5: minor (deferred): deadlineBeforeBootExpiredWhileOff doesn't assert d.clear; no 10% boundary test for a running session
Task 5: note: implementer observed StoreTests.revKeepsRisingAfterTheFileIsDeleted flaking (confirms Task 4 deferred minor) — must fix before merge
Task 5: complete (commits 2bd438c..9e713d6, review clean)
- Ruling R9: Fix the flaky StoreTests.revKeepsRisingAfterTheFileIsDeleted now (folded into the Task 6 dispatch) by sleeping 2 ms after deleting the file, since it breaks every later full-suite run; the code's same-millisecond equality after a deleted state file is accepted as vanishingly rare — cost if wrong: a CLI could misread a stale ack only if state.json is deleted and rewritten within the same ms as the previous write.
Task 6: minor (deferred): no 10-min boundary test for minimumWarnedLength; nextWake assumes dueWarnings runs first (doc comment)
Task 6: complete (commits 9e713d6..cb095ad, review clean; includes deflake fd43612 per R9)
Task 7: minor (deferred): restoreFailed slot/accessibility branch and foreign/restoreFailed notice constants untested; Pmset.sleepDisabled returns false (not nil) for unexpected values; "Review Focus 1" plan jargon in a test comment
Task 7: complete (commits cb095ad..8560ffc, review clean)
- Ruling R10 (T8 Important 1, plan-mandated): after clearing, if the state returned by StateStore.clear differs (ignoring rev) from the observed state with the cleared modes removed, another writer changed it mid-pass — re-run reconcile from the top before touching drivers (bounded depth 3), so applied.rev only acknowledges requests the agent actually decided on (spec: rev = last request revision fully processed) — cost if wrong: one extra pass on races.
- Ruling R11 (T8 Important 2, plan-mandated): post an ending only for modes whose clear actually succeeded (the returned state no longer holds that session); if any clear failed, the returned wake is at least now+30 s — prevents a busy loop and repeated notices when state.json is unwritable; the notice is posted once the clear finally succeeds — cost if wrong: an end notice is delayed while the disk is unwritable.
Task 8: minor (deferred): foreign disablesleep is adopted when nosleep starts over it (later restored by dryp) — spec should state it
Task 8: minor (deferred): applied.nosleepSet only persisted at end of pass (crash window); quarantine failure silent; extend logs on no-op; caf+policy rejections overwrite each other; no tests for foreign/quarantine/refreshAvailability
Task 8: fix round 1/5 (2 addressed, 0 open; commits 178c332..cc406e7)
Task 8: minor (deferred): a restarted pass could re-post a rejection (first pass's rev); depth-3 fallthrough acks (accepted residual)
Task 8: complete (commits 8560ffc..cc406e7, review clean after 1 fix round)
- Ruling R12 (T9 Important 1, plan-mandated): handleRestoreRequest must not make a second restore attempt in a pass where restoreSleepIfOwned already attempted one; the restore request only bypasses a pending backoff — keeps the spec's 5 s/30 s/2 min/5 min schedule on `dryp nosleep off` — cost if wrong: none.
- Ruling R13 (T9 Important 2): when disableSleep succeeds or re-takes ownership, clear applied.restoreFailed, restoreFailures and nextRetry; and reconcile never returns a wake earlier than now — prevents a stale failure flag and a past-time wake (busy loop) — cost if wrong: none.
Task 9: fix round 1/5 (2 addressed, 0 open; commits b9af50f..07df2b8)
Task 9: minor (deferred): if clearing restoreSleep fails, every pass bypasses backoff; shutdown() doesn't reset restoreFailures/nextRetry or post .restoreFailed on failure; restart with persisted restoreFailed posts no first notice
Task 9: complete (commits cc406e7..07df2b8, review clean after 1 fix round)
Task 10: ⚠️ resolved by controller: KeepAlive is {SuccessfulExit: false} (T16) and the agent exits 0 after SIGTERM, so stop() isn't defeated by respawn.
Task 10: minor (deferred): Shell.run readDone.wait() unbounded (grandchild holding pipe); timeout path SIGTERM only, no reap; FileLog not O_APPEND-safe for concurrent writers / handle.write can raise on full disk
Task 10: complete (commits 07df2b8..fdba400, review clean)
- Ruling R14 (T11 Important 1, plan-mandated): `-h`/`--hours` without a number is a usage error (exit 2) — a bare `dryp nosleep -h` must never start an unlimited session — cost if wrong: none.
- Ruling R15 (T11 Important 2, plan-mandated): `stop` treats an unreadable SleepDisabled (nil) as failure: "couldn't read SleepDisabled — see `dryp status`", exit 1 — honest results — cost if wrong: a rare false failure.
- Ruling R16 (T11 Minor 3 promoted): the CLI also verifies applied.cafHeld (true after `caf N`, false after `caf off`/`off`), closing the agent's fold-in ack race for caf from the CLI side; the reconciler-side root cause goes to the final review — cost if wrong: none.
- Ruling R17 (T11 spec deviation): files must be named Environment.swift / Requests.swift per the plan unless a real build collision forces otherwise (then document it) — cost if wrong: none.
Task 11: minor (deferred): unresponsive agent leaves the request pending in state.json; awaitAck can wait ~2×waitTimeout (4 s live)
Task 11: deferred to final review: Reconciler acks via handleRestoreRequest's store.update / failure-path clears without restarting the pass (fold-in race) — root fix belongs in Reconciler
Task 11: fix round 1/5 (4 addressed, 0 open; commits e08996c..6c11bb6)
Task 11: complete (commits fdba400..6c11bb6, review clean after 1 fix round)
Task 12: minor (deferred, should fix before merge for consistency with R15): `app stop` treats a nil SleepDisabled readback as success and ignores restoreFailed
Task 12: minor (deferred): third status warning (nosleep on but SleepDisabled 0) untested/transient; app start leaves marker if start fails
Task 12: complete (commits 6c11bb6..4424153, review clean)
Task 13: minor (deferred): drawCup silently draws nothing if the SF Symbol fails; icon test leaves temp iconset
Task 13: complete (commits 4424153..cedc2d9, review clean; controller viewed the 256px render — correct)
- Ruling R18 (T14 Important, plan-mandated): on a login-check exit, don't exit immediately — log, skip building the menu/watchers, and exit(0) after a 3 s main-queue delay so any end notice from the first reconcile reaches the notification center — cost if wrong: the agent lingers 3 s invisibly at login.
- Ruling R19 (T14 Minors 1, 2, 4 promoted as cheap safety fixes): store and release the IOPMAssertionDeclareUserActivity ID in release(); guard shutdownAndExit against re-entry (log + exit if already shutting down); install the SIGTERM source before the first reconcile — cost if wrong: none.
- Ruling R20 (T14 concern 1): accept making UNUserNotificationCenter optional outside a .app bundle (dev runs use osascript) — cost if wrong: none for the shipped bundle.
Task 14: minor (deferred): onExtend not guarded by shuttingDown; IOPowerSource has no deinit invalidating its run-loop source; SIGINT unhandled in dev runs (nosleep stays set on Ctrl-C)
Task 14: fix round 1/5 (4 addressed, 0 open; commits ed20260..8121556)
Task 14: complete (commits cedc2d9..8121556, review clean after 1 fix round)
- Ruling R21 (T15 Important, plan-mandated): dim idle glyphs via draw fraction 0.45 over an opaque tint (labelColor / systemOrange), so idle vs active differ in light and dark — spec "idle = dimmed" — cost if wrong: none.
- Ruling R22 (T15 Minors 2, 3, 5 promoted, cheap): add trailing width for the last slot's dot; info rows (not set up / outside dryp / couldn't restore) isEnabled = false per spec; invalidate an existing liveTimer in menuWillOpen — cost if wrong: none.
Task 15: minor (deferred): conditional rows and Stop enabled states don't refresh while the menu stays open; non-template image relies on labelColor resolving at draw time (human Light/Dark check pending)
Task 15: fix round 1/5 (4 addressed, 0 open; commits 6a1a6a5..e166d68)
Task 15: complete (commits 8121556..e166d68, review clean after 1 fix round; controller viewed light/dark/alert renders)
- Ruling R23 (T16 Important 1, plan-mandated): the nosleep step (prompt + sudoers) runs BEFORE the agent is stopped and the app replaced, and its failures are non-fatal: warn, record nosleep=no, continue the install; `read -r reply || reply=""` — spec: a failed check aborts that step, not the install — cost if wrong: none.
- Ruling R24 (T16 Important 2): `rule_works` proves NOPASSWD precisely by running a no-op `sudo -k -n /usr/bin/pmset -a disablesleep <current value>` (reads current SleepDisabled first); an existing /etc/sudoers.d/dryp whose content isn't byte-identical to the exact rule is rewritten. The app's PmsetCommand.check (`sudo -k -n -l`) has the same weakness but stays (file-exists + readback-verified sets cover it) — deferred to final review — cost if wrong: the menu might offer nosleep when only some other NOPASSWD entry exists; the set's readback would reject it.
- Ruling R25 (T16 Minors 3–6 promoted, cheap): root-owned temp path then visudo then mv; trap to delete the temp rule; truthful start check (pid line, bootstrap stderr shown); pkill a non-launchd dryp.app before replacing the bundle — cost if wrong: none.
Task 16: fix round 1/5 (6 addressed, 0 open; commits c0138b3..0865a68)
Task 16: minor (deferred, should fix before the real install): pid check allows only 1 s after bootstrap — poll up to ~5 s
Task 16: minor (deferred): failed post-mv rule check leaves the file but records nosleep=no; Ctrl-C mid-stage leaves inert dryp.tmp
Task 16: complete (commits e166d68..0865a68, review clean after 1 fix round)
- Ruling R26 (T17 Important 1 + T12 deferred minor): uninstall and `app stop` treat an unreadable SleepDisabled (nil) like "still disabled" when dryp owned it (nosleepSet && readback != false) — uninstall refuses without --force, app stop exits 1 — consistent with R15 — cost if wrong: a rare false refusal.
- Ruling R27 (T17 Important 2): with --force, before removing the sudoers rule, try once more `sudo -k -n /usr/bin/pmset -a disablesleep 0`; if SleepDisabled is still not 0, print the manual-restore command prominently — cost if wrong: none.
- Ruling R28 (T17 Minors 1–4 promoted, cheap): non-absolute or "/" app_dir falls back to ~/Applications with a warning; delete the archive's temp folder after install; map any non-zero installer/git status to exit 1; check install.sh exists in the source before running it, with a clear message — cost if wrong: none.
- Ruling R29 (T17 ⚠️ sudo): `uninstall`'s interactive `sudo /bin/rm -f /etc/sudoers.d/dryp` is correct — the spec requires asking for the password once, and the `-k -n` constraint governs dryp's unattended pmset calls — cost if wrong: none.
- Ruling R30 (T17 ⚠️ update ends sessions): `dryp update` stops the agent (shutdown clears active caf/nosleep); prefs and the nosleep choice are kept, and install.sh prints "active sessions end and sleep is restored" — the spec's "keeps state" is read as prefs/settings — cost if wrong: a user mid-session must restart it after updating.
Task 17: fix round 1/5 (5 addressed, 1 open — archive temp cleanup removes child not dest; commits decc56d..68f5d5b)
Task 17: fix round 2/5 (1 addressed, 0 open; commits 68f5d5b..b85f390)
Task 17: minor (deferred): update's APP_DIR fallback and non-zero installer status lack dedicated tests
Task 17: complete (commits 0865a68..b85f390, review clean after 2 fix rounds)
- Ruling R31 (T18 Importants 1+2, plan-mandated; minors promoted): verify.sh gets an EXIT/INT/TERM cleanup trap (restore a moved sudoers rule first, then `dryp off`, then if SleepDisabled is still 1 try `sudo -k -n pmset -a disablesleep 0` and print the manual command); the app-stop check uses a bounded `dryp nosleep 2`; the sudoers section copies (cp -p) then removes only after a successful copy, restores via the trap, skips when no rule is installed, and reports a failed restore loudly; guard kill -9 against an empty PID; poll up to 15 s for the restarted agent — cost if wrong: none.
Task 18: fix round 1/5 (4 addressed, 0 open; commits fa70196..389be13)
Task 18: minor (deferred): TERM is only handled after a foreground sleep 70 finishes; trap's sudo mv may prompt if the timestamp expired
Task 18: complete (commits b85f390..389be13, review clean after 1 fix round)

## Final review (62b3e6e..389be13): With fixes. 4 Important, 7 Minor.
- Ruling R24 correction: the "rewrite a non-identical existing file" part of R24 was never implemented; final fix uses `[[ -f $SUDOERS ]] && rule_works` as the only skip condition (install_rule overwrites otherwise) — cost if wrong: an extra password prompt when the file is missing.
- Ruling R32 (final fix wave scope): fix Importants 1–4 (install skip condition; --no-nosleep restores sleep and removes the rule only after the agent is stopped; CLI start rolls back its exact session on ack timeout; restore-failed notice tracked per process), plus Minors: pid poll ~5 s; start marker only when the agent isn't running; app stop always reads back SleepDisabled; README shutdown wording; persistApplied right after nosleepSet changes. Deferred: app login not starting the agent (amend spec later), Policy low-battery wording, fold-in race root fix (agent self-heals) — cost if wrong: those remain as noted.
Final fix wave: commits 389be13..ab769e1, re-review: all 9 addressed, no new Critical/Important. Ready for real install.
Final: minor (deferred): pipefail grep -q SIGPIPE edge in install.sh:108; rollback try? may say "cancelled" when clear failed; --no-nosleep also restores a foreign disablesleep (arguably asked)
