# Onyx Roadmap

_Written 2026-09-23 from five audits (performance, architecture, privacy, features, design). A second pass checked each audit, and a critique pass revised the plan. Paths are repo-relative. "Unverified" means nobody tested it at runtime._

## Read this first

- Natan, Onyx is a side project and your cash runway is a few weeks. Every hour you spend here is an hour you don't spend on paid work.
- Recommendation: this month, do **Tier 0 only**. That is about 6.5 hours over 5 sessions (Sessions 0 to 4 below). Then stop.
- Tier 0 fixes what hurts you every day: tabs lost on every relaunch, CPU burned on every site, keyboard shortcuts taken from Canvas and GitHub, a phishing hole in password autofill, and no off-machine copy of the code.
- Skip Tier 2, Tier 3 and all refactoring until the runway is longer. Tier 1 works as one-off 1 to 2 hour sessions, but only when a specific item annoys you in daily use.
- Rebuilding replaces the running app (`build.sh:96-97`). Do coding sessions outside market hours, and expect to lose open tabs until ARCH-5a lands in Session 1.
- Each session stands on its own. If you stop after any of them, Onyx is still better than it was.

## Where Onyx stands

**Solid**
- Today's security work is in `git log` (commits 2743738 to 08748d3): bridge gating, JS escaping, folder-scoped file access, the Keychain vault and signed builds.
- The vault migration finished on this machine. The legacy `OnyxVaultPasswords` key is gone, and the Keychain item was written 8 s after the 15:00 launch.
- Onyx does not turn off Safe Browsing or the known-host HTTPS upgrade. Each workspace has its own `WKWebsiteDataStore`. ITP defaults inside a WKWebView app are **unverified** on this build. A one-time visit to a third-party-cookie test page would settle it.
- The build uses `-O -wmo`. There is exactly one Networking process and one GPU process. The start-page orb already pauses when the page is hidden.
- The Views layer talks to the controller through closures. Only `Sources/Views/BookmarkViews.swift:591` holds a controller reference, so a later refactor only touches `Sources/Browser`.

**Fragile**
- **Tabs do not survive a relaunch.** `saveSession` returns early unless `OnyxStartupBehavior` is `restore` (`Sources/Browser/BrowserController+Session.swift:35`). On your machine that key is unset, so nothing is saved. With restore turned on, only Personal comes back. Onyx always launches into Personal (`Sources/Browser/BrowserController.swift:39`, `Sources/Browser/BrowserController+Profiles.swift:319-320`). The first `didFinish` then calls `saveSession` (`Sources/Browser/BrowserController+WebKitDelegates.swift:59`), and that function writes only the active and already-visited workspaces (`Session.swift:36-43`). That wipes the saved Research, Markets and Campus tabs. This is a bug in a feature marked done today.
- **Onyx's own injected scripts cost more than WebKit does.** The YouTube ad-block script runs in every frame of every site, including NinjaTrader, Tradesea and Canvas. It uses a 150 ms timer and a document-wide observer, and it patches `fetch` and `JSON.parse`. The 76 KB search stylesheet is applied up to 7 times per search. A private stylesheet API also applies it to every `*.google.com` page (Gmail, Docs, sign-in).
- **Memory is higher than the earlier audit said.** At about 19:41, WebContent pid 93231 (started 17 s after Onyx pid 93192) was at about 1.2 GB RSS. A later read showed about 1.1 GB. It has used 36.5 min of CPU over about 4h47m, which averages about 13% of a core. The last 15 minutes averaged about 4.6%. Two newer WebContent processes sit at about 330 MB and 457 MB (owner unverified). `memory_pressure` reported 62% free. Which page drives this is not yet known.
- **The input layer is hostile to web apps.** A global key monitor swallows Escape and takes Cmd+K, Cmd+B and Cmd+[ ] from pages. It can also delete a bookmark while you type in a web form.
- **Trust checks use substring matching.** Password autofill lights up on lookalike domains, and any host containing `google.` can put a fake URL in the address bar.
- **Other reliability gaps.** Nothing handles a WebContent crash. A failed load shows no error page. A failed decode silently overwrites bookmarks and history.
- **No backup.** The repo has no git remote, and Time Machine has no destination.
- **Some UI shows fake data.** The "Live News" headlines have made-up ages. Several strings make RAM claims ("30 MB", "Ultra-low RAM"). The Shield report says "Active" even when blocking is off.
- **No tests.** A Swift test runner is cheap to add, but it only pays off in Tier 2.

Legend: Effort S = under 1 h, M = about half a day, L = 1 to 2 days, XL = several days. Impact is 1 to 5. "(partial: ...)" means the verifier confirmed the item with that caveat.

---

## Tier 0: Keep it fast and solid (about 6.5 h)

| ID | What | Why it matters to you | Where | Effort | Impact | Done when |
|---|---|---|---|---|---|---|
| ARCH-1 | Create a private GitHub repo and push: `gh repo create onyx --private --source=/Users/nata/Company/Browser --push`. gh is already logged in, and a secrets grep found nothing. | Everything, including today's fixes, exists only on this disk. There is no Time Machine. | repo | S | 4 | `git remote -v` shows origin, and `git status` says up to date. |
| PRIV-1a | Zero code: rotate the NinjaTrader, Tradesea and bank passwords. | The old plaintext vault sat in a user-readable plist for an unknown period. | the sites themselves | S | 3 | Each account shows a recent password change, and the Onyx vault holds the new values. |
| PERF-18-V (+ PERF-10) | Take a 10 min baseline. Safari > Develop > [this Mac] > Onyx > each tab > Timelines, 30 s recording. Note which page and script burn CPU, and which tabs live in pid 93231. Inspection is already on (`Sources/Models/BrowserTab.swift:24-26`). | Tells you whether PERF-2, PERF-6, PERF-8, PERF-9 or PRIV-11 deserve any hours. No code needed. | none | S | 3 | You have written down "page X, script Y, N% CPU, pid P at M MB", plus a background-tab CPU line. |
| ARCH-5a (minimal session fix, pulled forward from ARCH-5) | (1) Remove the guard at `Session.swift:35` so the session is always saved. The startup mode then only decides whether to restore. (2) In `saveSession`, start from the previously saved blob and keep its entries for workspaces that are neither active nor in `profileTabs`. Overwrite only the visited ones. (3) At launch, before the first save, copy `OnyxSessionTabs` to an `OnyxLastSession` key. (4) Debounce saves by 2 s (the session half of PERF-13). `applicationWillTerminate` already flushes (`Sources/App/AppDelegate.swift:52-54`). Then set the startup mode to Restore in Settings. | Every rebuild and every Cmd+Q currently loses the tabs in all 4 workspaces, including a live trading session. Always saving without the debounce would re-encode every workspace on each `didFinish` and `closeTab` (`WebKitDelegates.swift:59`, `Sources/Browser/BrowserController+Tabs.swift:125`). | `Sources/Browser/BrowserController+Session.swift:33-44`, `Sources/Browser/BrowserController+WebKitDelegates.swift:59`, `Sources/App/AppDelegate.swift:52-54` | S | 5 | Open tabs in all 4 workspaces, Cmd+Q, relaunch, let the Personal start page finish loading, then switch to Markets and Campus: their tabs are there. |
| PERF-1 / ARCH-2 / PRIV-2 | Make the hostname guard below the first line of the YouTube script IIFE, before the install flag. Keep `forMainFrameOnly: false` so embedded players still work. Delete the redundant `evaluateJavaScript` re-injection. On YouTube only, optionally swap the 150 ms interval for video events plus a 1 s fallback. | Stops 4 whole-document queries every 150 ms, in every frame, on every site. Also stops the `fetch`/`JSON.parse` patches, which anti-bot scripts on broker sites can fingerprint, and the fake 200 response for any `/pagead/` URL. | `Sources/InjectedScripts/YouTubeAdBlockScript.swift:6-8`, `Sources/Browser/BrowserController+WebKitDelegates.swift:28,43` | S | 5 | On a Tradesea tab, `typeof window.__onyx_yt_adblock_installed` is `"undefined"`. YouTube pre-roll, mid-roll and the anti-adblock modal are still handled. CPU check: with the same tabs open, take two `ps -o etime,time,rss -p <pid>` samples 10 min apart, before and after the change. (delta TIME / delta ETIME) is lower after. Write both figures down. |
| ARCH-19-V / PERF-16-V (+ ARCH-7) | Delete the `installSearchThemeStyleSheets` call. The document-start user script already themes real search pages. In the same pass, guard the private KVC keys (`drawsBackground`, `developerExtrasEnabled`) with `responds(to:)` checks for `_setDrawsBackground:` and `_setDeveloperExtrasEnabled:`, plus an `OnyxDisablePrivateAPIs` default. | Stops the 76 KB dark search theme from landing on Gmail, Docs, Drive and Google sign-in. Also removes a hand-typed `unsafeBitCast` private call that could crash Onyx at launch after a macOS update. | `Sources/Browser/BrowserController+Profiles.swift:59`, `:51`, `Sources/Models/BrowserTab.swift:32` | S | 4 | mail.google.com and docs.google.com look normal. Google (your default engine) and DuckDuckGo results are still themed. If a flash of unthemed content on Google or DuckDuckGo bothers you, re-add the stylesheet later with narrow `/search` patterns. |
| PERF-3 / DSGN-20-V (steps 1, 2, 5) | In both `didFail` handlers, always stop the orb and reset the reload icon when the web view is the active one. Skip only the error UI for -999/101/102. On research pages, stop the orb at `didFinish` instead of starting it there. Don't restart it in `selectTab` for tabs that aren't loading. Stop it automatically after 15 s. | On duck.ai, after Stop, or after a download, the main thread redraws at 60 Hz forever, even with the window minimized. | `Sources/Browser/BrowserController+WebKitDelegates.swift:73-76,137-161`, `Sources/Browser/BrowserController+Tabs.swift:82-84`, `Sources/Views/ThinkingOrbView.swift:39-48` | S | 3 | After a duck.ai answer loads, the orb is still. After you press Stop, the reload icon comes back. |
| PERF-4 | Add `profileTabs[profile.id] = nil` after `tabs = savedTabs`. Call `pauseAllMediaPlayback` in `closeTab`. Change the `asyncAfter` blocks to capture `[weak self, weak webView]`. | Tabs you close stay alive, and may keep playing audio (unverified), until your next workspace switch. | `Sources/Browser/BrowserController+Profiles.swift:86,101-104`, `Sources/Browser/BrowserController+Tabs.swift:108-125`, `Sources/Browser/BrowserController+WebKitDelegates.swift:67-84` | S | 3 | Switch workspaces, come back, close a YouTube tab: the audio stops. |
| PERF-17-V / DSGN-21-V (crash part of ARCH-5) | Implement `webViewWebContentProcessDidTerminate`. For the active tab: reset the orb and progress bar, reload, and show a toast. For a background tab: set a `needsReload` flag and reload when it's selected. After 2 crashes in 60 s, show "click to reload" instead of looping. | When macOS kills a trading or LMS page's process, you currently get a blank tab and stale UI. | `Sources/Browser/BrowserController+WebKitDelegates.swift`, `Sources/Browser/BrowserController+Tabs.swift:41` | S | 3 | Outside market hours, with nothing open that you can't reload, kill a WebContent process in Activity Monitor: the affected tab reloads and a toast appears. One WebContent process can host several tabs, so never run this with a live trading tab open. |
| FEAT-1 / ARCH-3 / ARCH-20-V / FEAT-19-V / DSGN-22-V | One pass over the key monitor. (1) First line: `guard let win = self.window, event.window === win, win.attachedSheet == nil else { return event }`. (2) Guard `menuCloseTab` (and other tab-changing menu actions) with `window?.attachedSheet == nil`. Once the monitor passes Cmd+W through, File > Close Tab would otherwise close the tab under the sheet. Grep finds no `validateMenuItem` or `attachedSheet` check anywhere in Sources today. (3) Delete the Escape branch and handle omnibox Escape in the existing `cancelOperation` branch. (4) Delete the Cmd-only cases the menu already defines (T, W, O, J, R, [ ], ","). Move Cmd+B, D, L, K and 1-9 to menu items so a page that handles the key keeps it. Cmd+L lives in the menu only. (5) Keep in the monitor: Ctrl(+Shift)+Tab, the Cmd+Opt cases (workspaces 1-4, P, N, O, and L for Downloads, which exists only there), and Cmd+= for zoom (the menu item uses "+", and whether that matches Cmd+= is unverified). (6) Remove the bare Delete/`e` bookmark-hover keys and fix the tooltip. (7) Make Ctrl+Shift+Tab go to the previous tab. (8) Fix the Cmd+7-9 labels. | Escape closes NinjaTrader order dialogs, Canvas modals and GitHub palettes. Cmd+B/K are bold and link in Canvas and GitHub, and Cmd+K is GitHub's command palette. Today, typing in a login field with the pointer over a bookmark deletes the bookmark with no undo. | `Sources/Browser/BrowserController+Shortcuts.swift:8-143`, `Sources/Browser/BrowserController+Menu.swift:11-13`, `Sources/Browser/BrowserController+Passwords.swift:502-506`, `Sources/Browser/BrowserController+Bookmarks.swift:93-94`, `Sources/Views/BookmarkViews.swift:143`, `Sources/App/AppDelegate.swift:69-233` | S | 4 | By hand: Escape closes a GitHub modal. Cmd+B bolds text in a Canvas editor. Cmd+K opens GitHub's palette. Escape cancels the Edit Bookmark sheet. Cmd+W with that sheet open leaves the tab open. Cmd+Opt+L opens Downloads. Cmd+= zooms in. |
| PRIV-MISS-1-V (+ ARCH-9 helper, PRIV-13 gating) | Replace `isSearchURL`/`isResearchURL` with exact host rules: `host == d \|\| host.hasSuffix("." + d)`. Read `ia == "chat"` from `URLComponents` query items. Treat Google as a search page only when the host is exactly `google.<tld>` or `www.google.<tld>` for a TLD in the explicit set already at `Sources/Browser/BrowserController+SearchTheme.swift:19-27` (google.com, .ca, .co.uk, .de, .fr, .es, .it, .co.jp, ...), and the path is `/search`. A pattern like `google\.[a-z.]{2,6}` still accepts hosts such as `google.zz.io`. Apply the same rules to the JS host checks. When the host is not an exact match, show the real host in the address bar. | Today `google.tradesea.ai-login.io/search?q=https://app.tradesea.ai/login` shows a fake Tradesea URL. Any URL containing `ia=chat` (for example `?via=chat`) makes Onyx click the page's first submit button up to 4 times, using your cookies. | `Sources/Browser/BrowserController+SearchTheme.swift:19-27,73-78,166-172,813-829`, `Sources/Browser/BrowserController+Navigation.swift:88-99`, `Sources/Browser/BrowserController+Settings.swift:165-169` | S | 4 | A `?via=chat` link submits nothing. `google.zz.io/search?q=x` shows its real host. Google, DuckDuckGo and duck.ai are still themed. |
| PRIV-3 | Strict password host matching: lowercase, strip only a leading `www.`, then `h == d \|\| h.hasSuffix("." + d)`. Remove the `contains` fallback (`Sources/Passwords/PasswordVault.swift:55`) and the reverse `d.hasSuffix("." + h)` (`:52`). In `autofillActiveTab`, re-check the host and require https before filling. | A saved tradesea.ai login currently matches `tradesea.ai-secure.net`, and visiting `x.com` matches a saved `netflix.com`. This is the phishing case a vault exists to stop, on accounts with money behind them. | `Sources/Passwords/PasswordVault.swift:47-56`, `Sources/Browser/BrowserController+Passwords.swift:1043-1095` | S | 4 | Add a dummy vault entry for `ithub.com` and visit github.com. Today it matches through `contains`. After the fix the key badge stays dark for that entry, and your real GitHub login still autofills. Then delete the dummy entry. |
| ARCH-17 | Decision only, no code: freeze Android at bug fixes only. | Otherwise every bridge change on the start page has to be done twice. | none | S | 2 | Recorded in this file (done). |

The exact PERF-1 guard line (copy it from here, not from the table, where the pipes are escaped):

```js
if (!/(^|\.)(youtube\.com|youtube-nocookie\.com)$/.test(location.hostname)) return;
```

If the script is in a regular (non-raw) Swift string literal, double each backslash. Whether it is a raw string is unverified.

---

## Tier 1: Daily-driver quality (about 2 to 2.5 days in total, in small pieces)

**Reliability and state**

| ID | What | Why it matters to you | Where | Effort | Impact | Done when |
|---|---|---|---|---|---|---|
| ARCH-5 (rest) | Add a File > "Reopen Last Session" item that restores from the `OnyxLastSession` snapshot written by ARCH-5a. Add `os.Logger` only to persistence fallbacks and crash paths (not to every `try?`). | Recovers from a crash or an accidental Cmd+Q even when the startup mode isn't Restore. | `Sources/Browser/BrowserController+Session.swift`, `Sources/App/AppDelegate.swift` | S | 3 | With the startup mode set to start page: Cmd+Q, relaunch, and Reopen Last Session brings back tabs in all 4 workspaces. |
| ARCH-4 | Add a `loadCodable` helper. When a decode fails, it writes the raw data to `~/Library/Application Support/Onyx/recovery/`, logs the failure, and blocks autosave until you edit something. Use `decodeIfPresent` for new fields. | Today a failed decode replaces your bookmarks with the defaults, and the next page load wipes your history. | `Sources/Browser/BrowserController+Bookmarks.swift:42-62`, `Sources/Browser/BrowserController+Profiles.swift:315-323` | S | 3 | First run `defaults export com.company.onyx ~/onyx-prefs-backup.plist`. Onyx has no test domain, so this test touches your real data. Write a corrupt `OnyxBookmarks` value: a recovery file appears and the stored value is not overwritten. Restore with `defaults import`. |
| ARCH-21-V / DSGN-10 | Error page, shown only from `didFailProvisionalNavigation` (never from `didFail` after commit). Load it with `loadSimulatedRequest(URLRequest(url: failingURL), responseHTML:)`, with the escaped error text and a Retry link. `webView.url` becomes the failing URL, so no KVO guard is needed. Set a per-tab `showingErrorPage` flag before loading. In `didFinish`, skip the history write (`WebKitDelegates.swift:47-48`) and the search/research injection (`:50-52`, `:65-72`) while the flag is set. Clear it on the next navigation. For typed bare tokens that fail with `CannotFindHost`, fall back to a search. | DNS, TLS or offline failures currently show a blank or stale page with no reason. Without the flag, history fills up with error-page titles, and a failed duck.ai URL runs the auto-submit script on the error page. | `Sources/Browser/BrowserController+WebKitDelegates.swift:44-72,135-171`, `Sources/Browser/BrowserController.swift:298` | S | 3 | With Wi-Fi off, loading a site shows the error page with the failed URL in the address bar, Retry works, and History has no error-page entry. |
| DSGN-18-V | At the end of `selectTab`, set the progress bar and the reload/stop icon from the new tab's `isLoading` and `estimatedProgress`. | After a tab switch, a stale half-filled bar and a stop icon stay on screen. | `Sources/Browser/BrowserController+Tabs.swift:41-100` | S | 3 | Switch from a loading tab to a loaded one: the loaded tab shows no bar and shows a reload icon. |
| DSGN-19-V | Move `progressBar` to `contentView` and pin it to `webContainerView.topAnchor`. Set its height to 2 (it is 1.5 today, `BrowserController+UI.swift:305`). | With the bookmarks bar hidden (Cmd+Shift+B), there is no progress bar at all. | `Sources/Browser/BrowserController+UI.swift:203,303-306` | S | 2 | Hide the bookmarks bar and load a page: the progress bar still shows. |
| DSGN-23-V | After Cmd+T or the + button, make the search field (or the new web view) first responder. (partial: that focus is lost today is unverified, so check first.) | Typing right after Cmd+T may go nowhere. | `Sources/Browser/BrowserController+Shortcuts.swift:87-89`, `Sources/Browser/BrowserController+Tabs.swift:269-271` | S | 3 | Cmd+T and then typing puts the text in the field. |
| PRIV-1 | In the `didLoadNotification` observer, check `passwordStore.isLoaded`. If it is false, show the toast "Vault locked, Keychain access denied; saving disabled". (partial: the plaintext copy on disk is already gone, so this only fixes the silent failure. Password rotation is PRIV-1a in Tier 0.) | A failed Keychain read is invisible today. | `Sources/Browser/BrowserController.swift:186-192` | S | 2 | Deny Keychain access once: the toast appears. |
| PERF-2 (gated on the PERF-18-V baseline) | Only if the baseline shows background tabs using CPU: in `configuration(for:)`, set `config.preferences.inactiveSchedulingPolicy = (profile.id == "trading") ? .throttle : .suspend`. Use `.none` for trading if NinjaTrader shows reconnect banners. The macOS default is unverified and may already be `.throttle`. The real change is `.suspend` for Research, Campus and Personal. | Background tabs and inactive workspaces would stop running JS and layout. Pages playing media or still loading are exempt. | `Sources/Browser/BrowserController+Profiles.swift:44-51` | S | 3 | With the change in place, all of these hold: a duck.ai or Perplexity answer started and then backgrounded is complete when you return after 10 min. A Canvas quiz timer or autosave is correct after 10 min in another workspace. A NinjaTrader tab in Markets is still connected after 10 min. |

**Input, navigation and honest UI**

| ID | What | Why it matters to you | Where | Effort | Impact | Done when |
|---|---|---|---|---|---|---|
| FEAT-2 | Find in page: Edit > Find menu items (Cmd+F/G/Shift+G/E, not in the key monitor), a compact bar using the public `WKWebView.find`, and a match count labeled "about n". | Cmd+F does nothing on most sites today. You need it for Canvas readings, GitHub, long AI answers and Finviz tables. | `Sources/App/AppDelegate.swift:127-145`, new find bar view | M | 5 | Cmd+F on a GitHub file highlights matches, Cmd+G steps through them, and Escape closes the bar. |
| FEAT-3 | Reopen closed tab (Cmd+Shift+T). Keep an in-memory stack of 25 entries using `interactionState`. Skip the start page and flagged popups, and restore at the original index. Add History > Recently Closed. | A mistaken Cmd+W on NinjaTrader or Canvas currently loses the page and its history. | `Sources/Browser/BrowserController+Tabs.swift:108-142,177-182`, `Sources/Browser/BrowserController+WebKitDelegates.swift:304-312` | S | 4 | Close a tab after navigating inside it: Cmd+Shift+T restores it and Back works. |
| FEAT-4 | One Cmd-number map. Push the bookmarks to the start page (build `[[String: String]]` before `JS.literal`, because passing `[BookmarkItem]` directly crashes). Keep the start page's static shortcut grid as the fallback when no native push arrives. The Android build (frozen by ARCH-17) never sends it. Fix the popover labels and the ⌘⌥P pill (it should say ⌘⌥O). Delete the fake "Live News" segment. | Three different shortcut maps teach you the wrong muscle memory, and a trader should never see made-up market headlines. | `Sources/Browser/BrowserController+Shortcuts.swift:111-128`, `startpage.html:1619,1698-1812`, `Sources/Browser/BrowserController+Tabs.swift:284-299` | S | 3 | The start page, the popover and the bar all show the same ⌘1-6 targets. Opening `startpage.html` directly in a browser, with no native push, still shows a shortcut grid. |
| ARCH-16 / DSGN-11 / PRIV-17 / FEAT-22-V | Honest Shield and RAM text. Build the Shield report from `isAdBlockEnabled`. Remove or rewrite these strings: the shield tooltip "(30 MB RAM)" (`BrowserController+UI.swift:135`), the Shield alert "(~30 MB RAM)" (`BrowserController+Menu.swift:86`), the About text "Ultra-low RAM browser" (`BrowserController+Menu.swift:98`), and `settings.html:1133` ("Ultra-low RAM") and `:1160` ("~30-50 MB RAM at idle"). Label the RAM value "Onyx app process" and return nil instead of 38.4 (`BrowserController+Settings.swift:74`). Optional: "Disable on this site" via an `ignore-previous-rules` rule. | The UI reports blocking as active when it is off, and claims 30 MB while WebContent sits at about 1.1 GB. | `Sources/Browser/BrowserController+Menu.swift:83-98`, `Sources/Browser/BrowserController+UI.swift:135`, `Sources/Browser/BrowserController+Settings.swift:63-75`, `settings.html:1079,1133,1160` | S | 2 | Turn blocking off: the Shield says Off. `grep -rn "30 MB\|30-50\|Ultra-low\|38.4" Sources settings.html` returns nothing. |
| FEAT-20-V | File > Print (Cmd+P as a menu key equivalent) via `printOperation(with:)`, with `op.view?.frame = activeWebView.bounds`. | For Canvas pages, receipts and broker statements. It also gives you paginated Save as PDF. | `Sources/App/AppDelegate.swift:97-125` | S | 3 | Cmd+P on a Canvas page shows the print panel with content (not blank pages). |
| FEAT-21-V | Treat a middle-click on a link like Cmd-click: open a background tab. Check the `buttonNumber` value with a log line first. | Middle-click probably navigates in place today and loses the page you were on. | `Sources/Browser/BrowserController+WebKitDelegates.swift:176-182` | S | 2 | Middle-clicking a GitHub link opens a background tab. |
| FEAT-5 | Per-site zoom. One `setZoom` function, clamped to 0.5 to 3.0, stored per host in `OnyxSiteZoom`, applied in `didCommit` when the host changes, with a 900 ms toast. Skip file URLs. | Stops you re-zooming Finviz tables or trading layouts every session (assumed use). | `Sources/Browser/BrowserController+Shortcuts.swift:129-137`, `Sources/Browser/BrowserController+Menu.swift:43-53`, `Sources/Browser/BrowserController+WebKitDelegates.swift:27-40` | S | 2 | Zoom Finviz to 90% and relaunch: it stays at 90%. |
| PERF-7 / DSGN-3 step 1 / ARCH-11 (cheap part) | In-place title updates: from the title KVO, call `TabItemView.updateTitle` (it has zero callers today). Remove the `renderTabs` calls in `didFinish`. In `selectTab`, flip `isSelected` on only the old and new tab **only when the set of tab ids matches the current views**. Otherwise keep the full `renderTabs` (`Tabs.swift:67`), which is the only strip rebuild for `createNewTab(switchTo: true)` (`Tabs.swift:22`), `switchToProfile` (`Profiles.swift:113`), closing the active tab (`Tabs.swift:135`) and session restore. | Every title change rebuilds the whole tab strip, which resets hover and hides the close button under your cursor. | `Sources/Browser/BrowserController.swift:249-293`, `Sources/Browser/BrowserController+Tabs.swift:22,41-100,135,144-171`, `Sources/Views/TabViews.swift:170-172` | S | 2 | Hovering a tab while its page changes the title keeps the close button visible. Cmd+T shows the new tab. A workspace switch shows only that workspace's tabs. |
| FEAT-12 (cheap part) | Lower the priority of the 110 pt minimum tab width (or allow favicon-only pills of about 72 pt) so the strip compresses instead of hitting unsatisfiable constraints. | Only about 6 tabs fit at the 900 px minimum window width. | `Sources/Views/TabViews.swift:122-124`, `Sources/Browser/BrowserController+UI.swift:236-238` | S | 2 | 15 tabs at 900 px: no constraint warnings in the log, and no overlap. |

**Privacy and security one-liners (batch them in one session)**

| ID | What | Why it matters to you | Where | Effort | Impact | Done when |
|---|---|---|---|---|---|---|
| PRIV-MISS-3-V | For a JS alert, confirm or prompt from a web view that isn't active: complete it immediately with the default result, or select that tab first. Auto-dismiss after 3 dialogs in 10 s. | A background tab can put a fake "re-enter your password" sheet over your bank or NinjaTrader tab. | `Sources/Browser/BrowserController+WebKitDelegates.swift:351-413` | S | 2 | `setTimeout(()=>prompt('x'),3000)` in a background tab shows nothing over the active tab. |
| PRIV-5 | Set `config.preferences.javaScriptCanOpenWindowsAutomatically = false`. | Scripts can currently open unlimited foreground tabs without a click. Sign-in popups opened by a click keep working. | `Sources/Browser/BrowserController+Profiles.swift:44-66` | S | 2 | "Sign in with Google" on GitHub and Canvas still opens its popup. Test Tradesea and NinjaTrader once. |
| PRIV-MISS-2-V | URL-scheme policy. For a clicked `mailto:`, `zoommtg:`, `msteams:` or `tel:` link, show an "Open in <app>?" prompt, then call `NSWorkspace.open`. Silently cancel external schemes started by scripts. Cmd-click opens background tabs for http(s) only. | Meeting and mail links do nothing today, and nothing tells you why. | `Sources/Browser/BrowserController+WebKitDelegates.swift:174-214` | S | 2 | A Zoom invite link offers to open Zoom. |
| PRIV-12 / FEAT-16 | Add `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` to the Info.plist heredoc. WebKit's own prompt covers per-request consent. | Meet, Zoom web, Teams classes and voice mode probably fail today (unverified). | `build.sh:29-80` | S | 2 | Google Meet's preview shows your camera. |
| PRIV-4 (+ PERF-14 interim) | Anchor the 39 existing rules as `^[^:]+://+([^:/]+\\.)?<domain>[:/]` with `"load-type": ["third-party"]`. Keep the `OnyxFastRules` identifier. Show a toast when a main-frame load fails with WebKit error 104. | The unanchored `.*domain.*` patterns can block any page whose URL merely contains a tracker domain, and you get no feedback. | `Sources/Browser/BrowserController+ContentBlocking.swift:56-101` | S | 2 | A Google search for "doubleclick.net" loads. |
| ARCH-23-V / PRIV-10 | Remove `customUserAgent`. Read Safari's `CFBundleShortVersionString` once (fall back to a constant) and set `applicationNameForUserAgent = "Version/\(v) Safari/605.1.15"`. Reuse it in FaviconManager. | You are sending a Safari 18.3 user agent from a Safari 27 engine. That risks compatibility problems and is a plausible bot-challenge signal (unverified). | `Sources/Models/BrowserTab.swift:23`, `Sources/Browser/BrowserController+Profiles.swift:50`, `Sources/Support/FaviconManager.swift:99` | S | 2 | `navigator.userAgent` in Onyx matches Safari's on this Mac. |
| PRIV-9 | A `copySecret` helper: `.currentHostOnly`, the `org.nspasteboard.ConcealedType` marker, and a clear after 60 s if `changeCount` hasn't moved. Route all 4 password copy sites through it, and change the autofill-fallback toast text. | Copied passwords currently stay on the clipboard indefinitely and reach clipboard history and your iPhone. | `Sources/Browser/BrowserController+Passwords.swift:449,529,773,1092` | S | 2 | Copy a password and wait 60 s: the clipboard is empty. |
| PRIV-6 | A 2-minute test only: download a GitHub release .zip in Onyx, then run `xattr -p com.apple.quarantine` on it. Add `quarantineProperties` code only if the attribute is missing. (partial: WebKit's Networking service has `LSFileQuarantineEnabled`, so this is probably already fine.) | Unquarantined downloads would bypass Gatekeeper. | `Sources/Browser/BrowserController+Downloads.swift:327-359` | S | 1 | `xattr` shows a quarantine value. |
| PRIV-7 | Zero code, about 15 min: install an encrypted-DNS resolver with blocklists as a macOS profile, and set the same resolver as Android Private DNS. Know how to pause it before market hours. | Blocks more trackers per minute of work than anything in-app, and it covers Android too. | System Settings | S | 3 | The resolver's test page shows it active. NinjaTrader, Tradesea and Finviz still work. |

**Build hygiene**

| ID | What | Why it matters to you | Where | Effort | Impact | Done when |
|---|---|---|---|---|---|---|
| ARCH-6 | Regenerate the icon and run `killall Dock` only when `generate_icon.swift` is newer than `AppIcon.icns`. Warn (never auto-relaunch) when `pgrep -x Onyx` finds a running build. Use `java_home -v 17` in `build_android.sh`. Add a short repo `CLAUDE.md` with the build commands, a pointer to AGENTS.md and the design exceptions. (partial: the stale-process mismatch is gone. Auto-relaunch stays off because it would kill a trading session.) | Faster builds, no Dock restart on every build, and a warning before `build.sh` replaces the app under your open tabs. | `build.sh:11-13,96-103`, `build_android.sh:9-10` | S | 2 | A second `build.sh` in a row skips the icon step. With Onyx running, `build.sh` prints the warning. |
| ARCH-22-V | Set `CFBundleVersion` to the short commit hash, plus `-dirty` and a timestamp. Show it in About and in the settings payload. | Lets you tell which build a bug belongs to. | `build.sh:50-53`, `Sources/Browser/BrowserController+Menu.swift:98`, `Sources/Browser/BrowserController+Settings.swift:53` | S | 2 | About shows the commit hash. |
| PERF-5 (+ ARCH-15 delivery part) | Keep one delivery path for the search CSS. Delete the `didCommit`, double-`didFinish` and 0.4 s/1.2 s re-injections, and the 4 research re-injections (their `innerText` scan goes with them). Decide whether Kagi and Bing stay themed: today only the evaluated script themes them. | About 7 parses of a 76 KB stylesheet per search, 15 escaping passes on the main thread, and 5 whole-page style recalculations. | `Sources/Browser/BrowserController+WebKitDelegates.swift:35-39,50-52,65-84`, `Sources/Browser/BrowserController+SearchTheme.swift:858-887` | S | 3 | One Google search and one DuckDuckGo search each run the injection once (Web Inspector breakpoint). Results stay themed, and duck.ai still auto-submits. |
| DSGN-6 (cheap pass) | Make `OnyxToastHUD.hitTest` return nil. Use `.withinWindow` blur. Move the save-HUD shadow to an unmasked wrapper. Host the save HUD in `contentView` so switching tabs doesn't kill it. | HUDs over the bottom of a trading page can currently intercept clicks for up to 4.5 s. | `Sources/Views/ToastHUD.swift:23`, `Sources/Downloads/DownloadViews.swift:442,522-525`, `Sources/Passwords/PasswordViews.swift:340-347`, `Sources/Browser/BrowserController+Passwords.swift:1224` | S | 3 | Clicking where a toast is showing hits the page underneath. |

---

## Tier 2: Power features (ranked, only if the runway extends)

**Top 3**
1. **FEAT-7: find tabs from the address bar.** Switch tabs across all workspaces, plus recently closed tabs when the query is empty. Skip the `>` actions.
2. **FEAT-6: workspace routing.** First answer for yourself which sites you are logged into in which workspace.
3. **FEAT-11: delight pack.** About 2 h of small, visible wins.

| Rank | ID | What | Why it matters to you | Where | Effort | Impact | Done when |
|---|---|---|---|---|---|---|---|
| 1 | FEAT-7 | Add `.tab` and `.action` cases to the suggestions. Match the query against `tabs` (active workspace) and `profileTabs` (other workspaces only, because the active entry is stale), ordered by a new `lastActiveAt`. When the field is focused with an empty query, show 6 recent tabs plus 3 recently closed. (partial: drop the `>` action list; the value depends on how many tabs you keep.) | Finding "that Tradesea tab" in another workspace is currently a manual hunt. | `Sources/Browser/BrowserController+Suggestions.swift:67-71,89-209`, `Sources/Views/BrowsingSuggestionViews.swift:14-20`, `Sources/Browser/BrowserController+UI.swift:120-129` | M | 3 | Typing "trade" in Personal switches to the Markets Tradesea tab. |
| 2 | FEAT-6 | Route your sites to the workspace that holds their login. Reuse the blank start-page tab that `switchToProfile` creates. Apply routing to bookmark and history suggestions too. The override is Option-click on bookmark bar or omnibox entries only. (partial: the start page's `onyxSwitchWorkspace` is dead code on macOS, and whether you keep separate logins per workspace is unverified.) | Cmd+1 for NinjaTrader in Personal currently opens it in the wrong cookie jar. | `Sources/Browser/BrowserController+Bookmarks.swift:7-18`, `Sources/Browser/BrowserController+Navigation.swift:288-289`, `Sources/Browser/BrowserController+Profiles.swift:105-110` | M | 3 | Cmd+1 from Campus opens NinjaTrader in Markets, logged in. |
| 3 | FEAT-11 (+ PRIV-18) | Middle-click on a tab closes it. Duplicate keeps history via `interactionState`. Cmd+Shift+R does `reloadFromOrigin`. Cmd+Shift+C copies a clean link (strips utm_*, fbclid, gclid). A 180 ms crossfade on workspace switch (M14). Animations are gated on Reduce Motion. Skip automatic parameter stripping in `decidePolicyFor`. | Visible polish that is cheap. | `Sources/Views/TabViews.swift`, `Sources/Browser/BrowserController+Tabs.swift:165-175`, `Sources/Browser/BrowserController+Navigation.swift:466-472`, `Sources/Browser/BrowserController+Profiles.swift:113-116` | S | 2 | Middle-clicking a tab closes it. Duplicate, then Back, returns to the earlier page. Cmd+Shift+R on a GitHub page shows no cached responses in the Network tab. Cmd+Shift+C on a URL with `utm_source` pastes without it. With Reduce Motion on, a workspace switch has no fade. |
| 4 | ARCH-8 | A swiftc test runner: `tests/run.sh` compiles Foundation-only files plus `Tests/main.swift` (table-driven `precondition` checks) into a scratch binary. No Package.swift, and no change to build.sh. (partial: moving the release build to SwiftPM is optional.) | Makes ARCH-9 and ARCH-10 safe to change. | new `tests/`, extracted `QueryResolver`/`URLClassifier` | M | 3 | `tests/run.sh` exits 0, and exits non-zero on a deliberately broken case. |
| 5 | ARCH-9 (rest) | Fix `resolveQuery`. The current dotted-token branch (`Sources/Browser/BrowserController+Navigation.swift:358-361`) makes anything with a dot a URL. Send input to search when the last label is numeric (`3.5`) or is a common file extension (js, ts, py, md, pdf, txt, json, sh, swift, kt). A rule like "last label alphabetic, 2 or more characters" would still treat `node.js` and `file.pdf` as URLs. Rely on the ARCH-21-V `CannotFindHost` fallback for everything else. Use http for localhost and private IPs. Match bangs case-insensitively. | `node.js`, `3.5` and `file.pdf` currently become failed https loads. | `Sources/Browser/BrowserController+Navigation.swift:293-399` | M | 3 | Test cases pass: `node.js`, `file.pdf` and `3.5` go to search, `github.com` is a URL, `localhost:3000` loads over http, and `!G foo` goes to Google. |
| 6 | PRIV-11 / PERF-14 (gated) | Only if Finviz clutter still annoys you after PRIV-7 (it overlaps a lot with the system DNS blocklist, and PERF-14 itself called it optional). Convert EasyList and EasyPrivacy once, offline (converter choice unverified). Commit the JSON (under 150k rules each). Cache via `lookUpContentRuleList` with a version key (PERF-11). Ship an allowlist for ninjatrader.com, tradesea.ai, unapec.edu.do, conflictly.app and github.com. Refresh monthly by hand. Cosmetic rules add per-page cost and can break broker and LMS pages. | Less clutter on Finviz and news sites. | `Sources/Browser/BrowserController+ContentBlocking.swift:56-131`, `build.sh` step 3 | M | 2 | Finviz ads are gone. Tradesea, NinjaTrader and Canvas logins still work. Tradesea's load time in Web Inspector is no slower than before. |
| 7 | ARCH-10 | A Swift `SearchEngine` enum and bang table, so the UI switches become lookups. Keep the JS `resolveQuery` for Android. Pick one order for research intent versus engine chip. (partial: impact is low because you rarely add engines.) | The same question can currently go to Google from the start page and to duck.ai from the address bar. | `Sources/Support/JavaScript.swift:28-40`, `Sources/Browser/BrowserController+UI.swift:318-448`, `startpage.html:2103,2251` | M | 2 | A new bang is one line in the bang table, and no `switch` on engine names remains in `BrowserController+UI.swift`. The same query from the start page and the address bar goes to the same engine. |
| 8 | PERF-6 | Search-page observer: trailing throttle, skip when `document.hidden`, `textContent` over added nodes, HUD rAF only while synthesizing, and `textContent` instead of `innerHTML` for summaries (`SearchTheme.swift:526,1207`). Fix the brand-header ping-pong (remove the create or the remove). Never move hide rules into the Google-wide sheet. (partial: impact unmeasured; do it only if PERF-18-V points here.) | Possible CPU burn while duck.ai answers stream. | `Sources/Browser/BrowserController+SearchTheme.swift:225-282,446-447,630-747,1142-1158` | M | 3 | CPU for duck.ai streaming in Timelines is lower than the baseline figure. |
| 9 | FEAT-8 | Trade-journal snapshot: PNG to `~/Pictures/Onyx` and the clipboard via `takeSnapshot`. Use FEAT-20-V Print for PDFs. (partial: whether WebGL charts render in the snapshot is unverified.) | One key per chart screenshot. | new, `Sources/Views/ToastHUD.swift` | S | 2 | The snapshot of a NinjaTrader chart is not blank. |
| 10 | FEAT-23-V | Ephemeral workspace (Cmd+Shift+N) on `WKWebsiteDataStore.nonPersistent()`, excluded from session and history. | Check a site logged out, or use a second account. | `Sources/Browser/BrowserController+Profiles.swift:7-38` | S | 2 | Cookies are gone after its last tab closes. |
| 11 | PRIV-8 | Vault gate: `LAContext` `.deviceOwnerAuthentication`, valid for 5 minutes, required for reveal, copy, edit and export. Export always rechecks. Relock on screen sleep. | Someone at your unlocked Mac can currently export every password. | `Sources/Passwords/PasswordViews.swift:191-207`, `Sources/Browser/BrowserController+Passwords.swift:447-451,1002-1041` | S | 2 | Export asks for Touch ID. |
| 12 | FEAT-10 | Per-site user styles from a folder (dark Canvas, decluttered Finviz), injected at documentStart in `.defaultClient`, appended to `documentElement`. (partial: CSP behavior in the isolated world is unverified.) | Pitch-black Canvas. | `Sources/Browser/BrowserController+ContentBlocking.swift:136-154` | S | 2 | Canvas renders dark. |
| 13 | PRIV-13 (+ PERF-13 history half) | Install the password listener once, as a user script in an `OnyxAutomation` content world, with the handler registered there. Capture only on submit, and prompt after navigation. Drop the extra anomaly evaluate. Debounce history saves (2 s). The session debounce is already in ARCH-5a. (partial: the performance part is minor; the value is correctness.) | Catches fast logins, stops prompts from appearing before a login succeeds, and hides the listener from pages. | `Sources/Browser/BrowserController+Passwords.swift:1133-1182`, `Sources/Browser/BrowserController+WebKitDelegates.swift:47-49,86-90,132`, `Sources/Browser/BrowserController+Profiles.swift:62-65` | M | 2 | Page JS cannot see `__onyxPasswordSaveListenerAttached`. The prompt appears only after a successful login. |
| 14 | PERF-12 + PRIV-14 | Favicon negative cache (24 h), remove the Google S2 fallback, fetch in parallel with a 3 s timeout, use an ephemeral `URLSession` without cookies, and skip the network fallback for localhost and LAN hosts. (partial: mostly a privacy gain.) | Stops repeated lookups and hostname leaks for sites without an icon. | `Sources/Support/FaviconManager.swift:16-19,41-49,92-113`, `Sources/Browser/BrowserController+Tabs.swift:197-255` | S | 1 | A host without an icon is fetched at most once per day. |
| 15 | PERF-11 | Look up the compiled rule list before compiling, with a version key. Add or remove only the list, without `removeAllUserScripts`. Delete the icon decode at launch. (partial: near-zero visible gain; do it together with rank 6.) | Tidiness, and a prerequisite for rank 6. | `Sources/Browser/BrowserController+ContentBlocking.swift:123-147`, `Sources/App/AppDelegate.swift:12-18` | S | 1 | The ContentRuleList file's mtime does not change across relaunches. |
| 16 | PRIV-16 | `preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP` behind `#available(macOS 15.2, *)`. | Cheap insurance for http links you click. | `Sources/Browser/BrowserController+Profiles.swift:48` | S | 1 | An http link to an https-capable site loads over https, and localhost still works. |
| 17 | PRIV-19 | Android: `allowBackup="false"`, and require `request.hasGesture()` before launching external schemes. (partial: only if you use Onyx on Android daily.) | Keeps logged-in cookies out of phone backups, and stops pages from launching apps without a tap. | `android/app/src/main/AndroidManifest.xml:9`, `OnyxWebViewClient.kt:18-33` | S | 2 | A script-driven `market:` link does nothing. |
| 18 | FEAT-9 | Markets live mode: run the PERF-2 10-minute background test first. Only if alerts lag, set the guarded private prefs on the trading configuration. Skip the display-sleep activity. (partial: whether alerts actually lag is unverified.) | Trading alerts arrive on time. | `Sources/Browser/BrowserController+Profiles.swift:40-69` | S | 3 | A NinjaTrader alert fires on time while you're in Campus. |

---

## Tier 3: Design and motion (only when the runway lengthens)

Same rule as "Read this first": skip this tier for now. When you start it, do the P0 rows of the **Motion catalog** first (DSGN-1, then DSGN-8). Then follow this order:

| ID | What | Where | Effort | Impact | Done when |
|---|---|---|---|---|---|
| DSGN-1 | `Motion.animate` helper: sets `allowsImplicitAnimation = true` and applies changes instantly under Reduce Motion. Swap the 37 groups mechanically in one commit. Add `Motion.centerScale` for the two keyframe bounces (`transform.scale` becomes `transform` with center-pivot matrices). Skip the HoverTracking mixin. | 37 call sites listed in DSGN-1, `Sources/Downloads/DownloadViews.swift:184-191`, `Sources/Browser/BrowserController+Navigation.swift:402-413` | S | 3 | With a temporary `ctx.duration = 2.0`, hover fades are visibly animated. The download bounce pulses in place. |
| DSGN-9 + PERF-8 | Start-page diet. Shorten or skip the entrance on repeat visits. Animate the aura on opacity and transform over a statically blurred layer. Cap the orb at 30 fps and stop it after 8 s idle. Add a `document.hidden` check on the 10-minute interval. When removing `anime.min.js`, also delete `build.sh:25` (a `cp` under `set -e`, so the build fails without it), `build_android.sh:16`, the Android asset, the comment at `BrowserController+Navigation.swift:47-48` and the "Anime.js inspired" copy at `settings.html:1077`. (partial: the blur pulse runs only with focus or `.has-engine`, and the orb canvas is 64 px.) | `startpage.html:92-99,357-394,2899-2966,3908-3920`, `build.sh:25`, `build_android.sh:16` | S | 3 | `./build.sh` passes. Cmd+T shows a ready search field with no visible entrance delay. The Android build still passes. The 768 px layout still works. |
| DSGN-2 | Global `prefers-reduced-motion` CSS in both pages, plus a `matchMedia` guard on the orb rAF. The native side goes through `Motion`. Defer the settings control and per-workspace calm mode. | `startpage.html:123-129`, `settings.html` | S | 2 | With Reduce Motion on, nothing loops on the start page. |
| DSGN-7 | Run the back/forward transition after commit (or from the URL KVO for same-document navigations), skip it after 600 ms, and cap the edge glow alpha at 0.22. (partial: the glow is a gradient, not a solid band, but it is still a bright white flash for Personal.) | `Sources/Browser/BrowserController+Navigation.swift:427-464`, `Sources/Views/EdgeGlowView.swift:44-60` | S | 3 | Back on GitHub animates the incoming page, not the outgoing one. |
| DSGN-12 | The bookmark delete button becomes an overlay with reserved width. Animate alpha only, and never toggle `isHidden` on hover. | `Sources/Views/BookmarkViews.swift:149,170-190,227-232` | S | 2 | Moving the pointer across the bar shifts nothing sideways. |
| DSGN-15 (cheap part) | Check `!gh` before `!g` for the tint. Route hover through `selectedIndex` so only one row is ever highlighted. Replace the NSPopover only if it actually opens upward. (partial: the upward opening is unverified.) | `Sources/Browser/BrowserController+Navigation.swift:126-136`, `Sources/Views/BrowsingSuggestionViews.swift:98-149` | S | 2 | `!gh` glows purple. Hover plus arrow keys highlight exactly one row. |
| DSGN-8 (subset) | Orb on a display link at 30 fps, paused when the window is occluded. Delete the `isResearch ? .orbits : .orbits` ternaries. Add an error state only together with the error page. | `Sources/Views/ThinkingOrbView.swift:39-48`, `Sources/Browser/BrowserController+Navigation.swift:68`, `Sources/Browser/BrowserController+WebKitDelegates.swift:22`, `Sources/Browser/BrowserController+Tabs.swift:80` | S | 2 | With Onyx hidden during a load, the orb uses no CPU in Activity Monitor's main-thread sample. |
| DSGN-16 (a, b, d, e) | Progress trickle, leading-edge shimmer, smooth download ring, centered press on nav buttons. Skip fly-to-button. | `Sources/Browser/BrowserController.swift:211-235`, `Sources/Downloads/DownloadViews.swift:177-182` | M | 2 | The bar moves during a slow time-to-first-byte. The ring fills without steps. |
| DSGN-14 | Workspace switch transition with color identity (300 ms or less). First pick a distinct Research accent yourself: #E2E8F0 is nearly identical to Personal's #FFFFFF. | `Sources/Browser/BrowserController+Profiles.swift:90-116`, `Sources/Browser/BrowserController.swift:34-37` | M | 2 | The Research accent is a non-gray hue that differs from the other three. A screen recording of a switch shows the transition finishing within 300 ms. |
| DSGN-24-V | Double-click on the tab bar zooms the window (honoring `AppleActionOnDoubleClick`). The leading inset goes from 78 to 12 in fullscreen. | `Sources/Views/TabViews.swift:6-10`, `Sources/Browser/BrowserController+UI.swift:239` | S | 1 | Double-clicking the tab bar zooms the window. In fullscreen the first tab starts 12 pt from the edge. |
| DSGN-13 (a only) | Sliding active-tab indicator, only after the Tier 1 PERF-7 work. Re-sync without animation after other renders. Skip the content crossfade, or cap it at 80 ms. (partial: fiddlier than it looks.) | `Sources/Views/TabViews.swift:197-227`, `Sources/Browser/BrowserController+Tabs.swift` | M | 2 | Cmd+1..6 slides one pill smoothly, and a workspace switch shows no stray pill. |

---

## Later / only if Onyx becomes a real product

| ID | What | Effort | Why it waits |
|---|---|---|---|
| PERF-9 | Tab hibernation and memory-pressure handling (partial: L effort for the full version). | L (1 h subset) | **Trigger for the 1 h subset:** a WebContent process stays above 1.5 GB RSS across a day, or the PERF-17-V crash toast fires more than once a week. pid 93231 is already at about 1.1 to 1.2 GB, so check it after PERF-1 and PERF-18-V. The subset is a memory-pressure handler that unloads only inactive-workspace tabs, plus lazy loading of restored tabs. |
| ARCH-11 / DSGN-3 step 2 / FEAT-12 (rest) | Keyed tab strip, block-based KVO, pinned tabs, drag reorder. | L | Build it only when you start pinned tabs. |
| ARCH-12 | TabStore / WorkspaceStore with computed shims. | L | None of today's features need it. You have no custom workspaces. |
| ARCH-13 + PRIV-15 (history part) | SettingsStore key enum, history as a JSON file with a workspace id, cap raised to about 5000, a clear-history action (partial: the write-cost framing is overstated). | M | Worth it only if history leaking between workspaces bothers you. |
| ARCH-14 + PRIV-15 (store part) | Remove a workspace's data store on delete (`WKWebsiteDataStore.remove(forIdentifier:)`) (partial: zero impact today, since you have no custom workspaces). | S | Do it the day you create and delete a custom workspace. |
| ARCH-15 (rest) | Move the injected CSS/JS to resource files. Remove the consent auto-click (`SearchTheme.swift:549-556`) and the PREF cookie write. | M | High-churn, low-value code. Stop investing after PERF-5. This is the single position on it (the Target structure section agrees). |
| FEAT-13 | Side panel per workspace (partial: L effort, and macOS Split View covers most of it). | L | L effort on a short runway. |
| FEAT-14 | Web Notification bridge (partial: first check `Notification.permission`, and whether the platforms use it at all). | M | Need unverified. |
| FEAT-17 | Canvas due-date card from the iCal feed (partial: whether UNAPEC enables the feed is unverified). | M | Only if you actually miss a deadline. |

## Do not do

| Item | Reason |
|---|---|
| PERF-15 prewarmed start-page tab | WebKit already appears to prewarm a WebContent process. Measuring would probably show nothing to fix. |
| PERF-10 in-app memory readout / signposts | Web Inspector Timelines already attributes CPU and memory for free. Instruments isn't installed. |
| FEAT-15 market-session pill | You already know the session times, and a holiday list goes stale. |
| SwiftUI, TCA or MVVM rewrite, DI container, Combine everywhere | No user-visible gain, and a high risk of breaking your daily browser. |
| Core Data, SwiftData, GRDB, sync, CI, crash-reporting SDK | One user: UserDefaults, JSON files and the unified log are enough. |
| Kotlin Multiplatform or a shared native core | Sharing the HTML is already the right amount of sharing. |
| Multi-window | BrowserController is built around one window, and you haven't asked for it. |
| In-app DNS-over-HTTPS, custom cookie policy, referrer trimming, fingerprint randomization | WebKit defaults plus a system DNS profile cover these. Randomizing the fingerprint of a one-user browser does nothing. |
| Clear-on-quit per workspace | You would redo 2FA on NinjaTrader and Tradesea every morning. |
| Data-protection keychain, hardened runtime, Lockdown Mode | Costs compatibility for a threat model of one. The LAContext gate (PRIV-8) covers the real risk. |
| On-device AI summaries, reader mode, PiP, quick notes, vertical tabs, a history page, link hints, true split view | Better tools are one keystroke away (Perplexity, duck.ai, Obsidian), or FEAT-7 plus FEAT-12 already solve the same problem. |
| Separate command-palette window, a `>` action list beyond a handful | The omnibox popover already has keyboard navigation. |
| Light mode | Dark-only is deliberate (`.darkAqua`). |
| Tab open/close/drag springs, download fly-to-button, HoverTracking mixin | L effort, or a pure refactor, for delight only. |
| A Theme.swift migration pass, unifying the start page and settings web tokens | No user-visible payoff. The deltas are 1 to 2 px or a few percent of alpha. Fix literals only in files you already touch. |
| A "dangerous file type" confirmation and filename sanitizing for downloads | Quarantine is what matters here, and WebKit probably applies it already. |

---

## Target structure

**The realistic end state**
- `Sources/Core/`: Foundation-only code that the test runner can compile: `URLClassifier`, `QueryResolver`, `SearchEngine` plus the bang table, `JS`, the session snapshot, the data-store ID, and the CSV parser moved out of `PasswordVault.swift`.
- `Sources/Browser/`: BrowserController stays as the coordinator for the window, toolbar and WebKit delegates. Stores (`TabStore`, `WorkspaceStore`, `SettingsStore`) arrive only when a feature needs them.
- Injected CSS/JS stays as Swift strings. After PERF-5 there is one delivery path, and moving it to resource files is not worth the hours (ARCH-15 rest, Later).
- `startpage.html` and `settings.html` stay at the repo root, because `build_android.sh` copies them from there.
- `build.sh` keeps packaging, signing and installing. The swiftc pipeline stays as it is.

**Refactor order.** Each step builds, runs and gets committed on its own.

| Step | What | Effort | Impact | Done when |
|---|---|---|---|---|
| 1 | Nothing structural until Tier 0 and the Tier 1 items you choose are done. | none | none | Tier 0 is checked off below. |
| 2 | Extract `URLClassifier` (the host-suffix helper that PRIV-MISS-1-V and PRIV-3 need anyway) into a Foundation-only file. Call sites keep the same method names. | S | 2 | `./build.sh` passes, and `grep -rn "contains(\"google\\.\")" Sources` returns nothing. |
| 3 | Add `tests/run.sh` (ARCH-8). It compiles `Sources/Core/*.swift` plus `Tests/main.swift` with swiftc and runs the binary. build.sh is untouched. | M | 3 | `tests/run.sh` exits 0 with the URLClassifier cases from PRIV-MISS-1-V and PRIV-3. |
| 4 | Extract `QueryResolver` and `SearchEngine` behind tests, then change behavior (ARCH-9, ARCH-10). | M | 3 | The ARCH-9 test cases pass, and `./build.sh` passes. |
| 5 | Only for pinned tabs: keyed tab views with block KVO (ARCH-11), then `TabStore` with computed `tabs`/`activeTabIndex` shims so every call site still compiles, then migrate callers file by file (ARCH-12). | L | 1 | Each file migration builds on its own, and the manual smoke test passes. |

**Refactors not worth it now:** moving the release build to SwiftPM (only if you want incremental debug builds, and confirm `swift test` works under Command Line Tools first), moving injected CSS/JS to resources, splitting into more modules, `WeakScriptMessageHandler` (the retain cycle is harmless with one controller), a Theme.swift migration, and anything in the Do not do list.

---

## Motion catalog

House curve: `cubic-bezier(0.16, 1, 0.3, 1)`. Springs use `CASpringAnimation(perceptualDuration:bounce:)` (macOS 14). The derived values assume mass 1: stiffness = (2π/d)^2, damping = 4π/d x (1 - bounce).

Priority: **P0** = foundation or bug, do first when you start Tier 3. **P1** = top value. **P2** = worthwhile. **P3** = nice to have. P4 rows (tab open/close/drag springs, download fly-to-button) were cut. See Do not do.

| # | Trigger | Motion | Duration (ms) | Curve / spring | API | Reduced-motion fallback | Effort | Priority |
|---|---|---|---|---|---|---|---|---|
| M1 | Hover or press on any native control (37 existing groups) | Background, border and shadow tint | 120 in / 180 out | House curve | `NSAnimationContext` with `allowsImplicitAnimation`, via `Motion.animate` | Instant | S (DSGN-1) | P0 |
| M2 | Download finished; nav button press | Centered scale pulse (1 -> 1.28 -> 1; 0.88 squash) | Existing keyframe timings | Existing | `CAKeyframeAnimation` on `transform` with center-pivot matrices (`Motion.centerScale`) | Skip | S (DSGN-1) | P0 |
| M3 | Toast, download HUD and save HUD appear | Slide and fade (already coded, snaps today) | Existing | House curve | Fixed by M1 | Fade only | S (DSGN-1) | P0 |
| M4 | Omnibox orb while loading | Orb at 30 fps; stops at `didFinish` and after 15 s | Continuous while loading | Linear frame step | `NSView.displayLink` with `CAFrameRateRange(15, 30, 30)` | One static frame (also in Low Power Mode) | S (PERF-3, DSGN-8) | P0 |
| M5 | Cmd+T start page | Entrance shortened or skipped; aura on opacity and transform over a pre-blurred layer; orb capped at 30 fps and idle after 8 s | Entrance 150 or less (about 570 today) | Expo-out | CSS keyframes, rAF frame skip | No entrance, static orb frame | S (DSGN-9) | P1 |
| M6 | Back / forward | Incoming page slides and fades after commit | 240 | House curve | `CABasicAnimation` group, started from `didCommit` or the URL KVO; skipped after 600 | Instant | S (DSGN-7) | P1 |
| M7 | Back/forward and workspace edge glow | Profile-color gradient, alpha capped at 0.22 | 320 fade | Ease-out | `CALayer` opacity | Instant (no glow) | S (DSGN-7) | P1 |
| M8 | Hover over a bookmark | Delete overlay fades in with no layout shift | 120 | Ease-out | `animator().alphaValue` | Instant | S (DSGN-12) | P1 |
| M14 | Workspace switch (cheap) | Web container crossfade | 180 | House curve | `CATransition` on `webContainerView.layer` | Instant | S (FEAT-11) | P1 |
| M9 | Tab selected | Shared indicator pill slides from the old tab's frame to the new one | about 280 | Spring 0.28, bounce 0 (k about 504, c about 45) | `CASpringAnimation` on position and bounds | 120 crossfade | M, about 3 h (DSGN-13a, needs PERF-7) | P2 |
| M10 | Arrow keys or hover in suggestions | One highlight slides between rows | about 180 | Spring 0.18, bounce 0 (k about 1218, c about 70) | `CALayer` | Instant | S (DSGN-15) | P2 |
| M11 | Slow time to first byte | Progress trickles toward 0.3 if below 0.15 after 300 ms; never moves backward | 1500 | Ease-out | Constraint `animator()` | Width only | S (DSGN-16a) | P2 |
| M12 | Download progress tick | Ring `strokeEnd` interpolates | 250 | Linear | `CABasicAnimation` | Stepped | S (DSGN-16d) | P2 |
| M13 | Nav button mouse-down | Centered scale 0.94, springs back | 90 + spring | Spring 0.25, bounce 0.15 (k about 632, c about 43) | `Motion.centerScale` | Opacity dip to 0.8 | S (DSGN-16e) | P2 |
| M15 | Workspace switch (full) | Outgoing view scales to 0.985 and fades (200, ease-in); incoming fades in (240); top color wash 120 in / 500 out; pill dot pops 1.4 -> 1 | 300 or less in total | Spring 0.3, bounce 0.3 (k about 439, c about 29) for the dot | Animations on live views; `CAGradientLayer` | Color line only | M (DSGN-14) | P3 |
| M16 | Omnibox focus | Glow, plus the container expands 4 pt per side | about 250 | Spring 0.25, bounce 0 (k about 632, c about 50) | `animator().constant` | Glow only | S | P3 |
| M17 | Suggestion list first shown | Opacity 0 -> 1 and translateY -4 -> 0; rows stagger 15 ms each, max 6 | 140 (+ 90 stagger) | House curve | Layer animation (only if the NSPopover is replaced) | Instant | M | P3 |
| M18 | Page loading | Leading-edge shimmer on the progress bar | 1100 loop | Linear | `CAGradientLayer` | Off | S (DSGN-16b) | P3 |
| M19 | Background tab loading | A 12 pt arc spins in place of the favicon; the favicon springs back in when done | 900 loop; spring 0.3, bounce 0.25 | Linear; k about 439, c about 31 | `CAShapeLayer` sublayer | Static half-arc | S | P3 |
| M20 | Tab switch content | Incoming web view fades in | 80 or less, or none | Ease-out | `animator().alphaValue` | Instant | S | P3 (adds latency) |

**Top 5 by perceived quality per hour**
1. **M1 + M2 + M3, `Motion.animate` and `centerScale` (DSGN-1), about 1 h.** About 37 existing transitions start working, and the bounces pivot from the center.
2. **M5, start-page diet (DSGN-9, PERF-8), about 1 h.** Your most-seen screen feels instant and stops burning CPU while idle.
3. **M6 + M7, back/forward after commit plus the glow cap (DSGN-7), about 30 min.** Fixes the most-used transition, which today animates the wrong page.
4. **M8, bookmark hover without layout shift (DSGN-12), about 30 min.** Removes the jitter on a bar you use constantly.
5. **M14, workspace crossfade (part of FEAT-11), about 20 min.** Every workspace switch stops hard-cutting.

M9 (sliding tab indicator) is out of the top 5: about 3 h, fiddly, and it depends on PERF-7.

---

## Design system cleanup

**Scope.** No token-unification project and no migration pass. The rule: when you edit a file for another reason, fix the off-grid literals in the lines you touch. Only the first item below is worth scheduling on its own.

| Item | What | Where | Effort | Impact | Done when |
|---|---|---|---|---|---|
| DC-1 | Add a `:focus-visible` ring to `.slider` (it has no focus indicator) | `settings.html:308-340` | S | 2 | Tabbing onto a settings slider shows a visible ring. |
| DC-2 | Progress bar height 1.5 -> 2 (fractional pixel). Done inside DSGN-19-V. | `Sources/Browser/BrowserController+UI.swift:305` | S | 1 | The height constant is 2. |
| DC-3 | Toolbar leading 12 vs bookmarks leading 14 (2 px misaligned): make both 12 | `Sources/Browser/BrowserController+UI.swift:257`, `:296` | S | 1 | Both constants are 12. |
| DC-4 | Name the specific properties in place of `transition: all` | `startpage.html:646,718,758,782`, `settings.html:168,357,389,434,458,561` | S | 1 | `grep -n "transition: all" startpage.html settings.html` returns nothing. Do it with DSGN-9 when you touch those rules. |
| DC-5 | Off-grid literals, fixed only in files you already touch: `BrowserController+UI.swift:26,140` (6 -> 8); `TabViews.swift:126,135,137-138,22` (10, -6, 15x15, radius 7 -> 8 or 12, -8, 16x16, 8); `ToastHUD.swift:41,67` (1, 10 -> 2 or 4, 12); `BookmarkViews.swift:149,17,36-37,180` (5, 3.5, 15x15, 22 -> 4, 4, 16x16, 24); `SuggestedViews.swift:84`, `ProfileViews.swift:268` (7, 6 -> 8); `DownloadViews.swift:338,346` (9, 3 -> 8, 4); `BrowserController+Tabs.swift:386,391,395` (14, 14, 10 -> 16 or 12, 8 or 12); `BrowserController+Passwords.swift:1130` (42 -> 40 or 44); `startpage.html:176,243,245,706,708,749,1086,1144` and `settings.html:135,634,639` (-> `var(--space-*)`) | as listed | S per file | 1 | For each file touched in a session, a grep for the listed literals finds none left in that file. |

**Native token file (create it only the first time DC-5 needs a name).** `Sources/Support/Theme.swift`, per the AGENTS.md scale. Add names as you use them, never in a migration pass. Effort S, impact 1. Done when the file compiles and every literal you replaced in that session references it.

```swift
enum Theme {
    enum Space {            // AGENTS.md scale
        static let s1: CGFloat = 4,  s2: CGFloat = 8,  s3: CGFloat = 12, s4: CGFloat = 16
        static let s5: CGFloat = 20, s6: CGFloat = 24, s8: CGFloat = 32, s10: CGFloat = 40, s12: CGFloat = 48
    }
    enum Radius {
        static let sm: CGFloat = 4, md: CGFloat = 8, lg: CGFloat = 12, xl: CGFloat = 16
    }
    enum Color {            // existing chrome values, named
        static let chromeBar    = NSColor(red: 14/255, green: 14/255, blue: 17/255, alpha: 1) // tab bar, toolbar
        static let chromeSubbar = NSColor(red: 22/255, green: 22/255, blue: 25/255, alpha: 1) // bookmarks bar, window
        static let content      = NSColor(red:  7/255, green:  7/255, blue:  9/255, alpha: 1) // web area
    }
}
```

**Web tokens.** `startpage.html:28-34` and `settings.html:27-33` disagree slightly (surface 0.04 vs 0.035, hover border 0.18 vs 0.16, focus border 0.35 vs 0.32). Not scheduled. Align them only if you are already editing both `:root` blocks.

**Record the Onyx exceptions in the repo** (in the repo `CLAUDE.md` from ARCH-6, not in the global AGENTS.md). AGENTS.md was written for a Minecraft-style launcher, so for Onyx only its token grid, no-overlap, focus and reduced-motion rules apply. Documented exceptions:
- the 32 px omnibox (browser convention, instead of the 40 px input minimum)
- the 38 px tab bar
- the 78 px traffic-light inset (`Sources/Browser/BrowserController+UI.swift:239`)

**Profile accents.** Personal (#FFFFFF) and Research (#E2E8F0) look the same. Picking a distinct Research color is your call (violet #A78BFA was one suggestion). It feeds DSGN-14.

**Skip:** the omnibox color "drift" fix. The color is overwritten before the first paint, so there is nothing visible to fix.

---

## Sequenced plan

Rules for every coding session:
- Work outside market hours. Quit Onyx before `./build.sh`, because the build replaces the running app (`build.sh:96-97`).
- Until ARCH-5a is in (Session 1), each relaunch loses your tabs, and that includes Session 1's own first relaunch.
- End every session with `./build.sh` passing, a manual smoke test (open a tab, switch workspaces, search on Google, then YouTube, Tradesea, Canvas), a commit and a `git push`.

**Stop after Session 4 unless the runway changes.**

**Tier 0 (this month, about 6.5 h)**
- [ ] **Session 0 (about 30 min, no code).**
  - ARCH-1: create the private remote and push.
  - PRIV-1a: rotate the NinjaTrader, Tradesea and bank passwords.
  - PERF-18-V: Web Inspector baseline, including background-tab CPU and which tabs live in pid 93231. Write it down.
  - Set the startup mode to Restore in Settings now. With today's bug it brings back Personal only, which still beats nothing.
  - ARCH-17: freeze Android (decided above).
  - Commit `docs/ROADMAP.md`.
- [x] **Session 1 (about 1.5 h): keep your tabs, cut the waste.** Done 2026-09-24.
  - ARCH-5a first (always save, merge unvisited workspaces, launch snapshot, 2 s debounce).
  - PERF-1: hostname guard, and remove the `evaluateJavaScript` re-injection.
  - ARCH-19-V: delete the private stylesheet call. ARCH-7: KVC guards.
  - Take the two 10-minute `ps` samples and compare them with Session 0.
- [x] **Session 2 (about 1.5 h): stability.** Done 2026-09-24 (crash test with a live WebContent kill still to do by hand).
  - PERF-3 steps 1, 2 and 5.
  - PERF-4.
  - PERF-17-V, including the crash test with nothing live open.
- [x] **Session 3 (about 1.5 h): keyboard pass.** Done 2026-09-24. Cmd+T/W/Shift+W/L/R/Q stay reserved in the key monitor so pages and crashed tabs cannot block them; everything else is a menu key equivalent.
  - FEAT-1 / ARCH-3 / ARCH-20-V / FEAT-19-V / DSGN-22-V together, including the `menuCloseTab` sheet guard.
  - Test Escape in GitHub, Canvas and Onyx's own sheets. Test Cmd+B in Canvas, Cmd+K on GitHub, Cmd+W with a sheet open, Cmd+Opt+L and Cmd+=.
- [x] **Session 4 (about 1.5 h): trust.** Done 2026-09-24 (`Sources/Core/URLClassifier.swift`, `tests/run.sh`).
  - PRIV-MISS-1-V with the host-suffix helper and the explicit Google host list.
  - PRIV-3, then the `ithub.com` dummy-entry test.

**Tier 1 (only when an item bites)**
- [ ] **Session 5 (about 2 h): data safety.** ARCH-5 rest (Reopen Last Session, minimal logging), ARCH-4 (export the defaults first), PRIV-1 toast.
- [ ] **Session 6 (about 2 h): failure states.** ARCH-21-V error page with the `showingErrorPage` flag, DSGN-18-V, DSGN-19-V (with DC-2), DSGN-23-V (verify it first).
- [ ] **Session 7 (about 3 h):** FEAT-2 find in page.
- [ ] **Session 8 (about 2 h): tabs and nav.** FEAT-3, FEAT-20-V, FEAT-21-V, FEAT-5.
- [ ] **Session 9 (about 2 h): honest UI and tab strip.** FEAT-4 (keep the static fallback grid), ARCH-16 / PRIV-17 / FEAT-22-V, PERF-7 in-place titles with the reconcile check, FEAT-12 compression.
- [ ] **Session 10 (about 2 h): one-liners.** PRIV-MISS-3-V, PRIV-5, PRIV-MISS-2-V, PRIV-12, PRIV-4, ARCH-23-V, PRIV-9, the PRIV-6 test, the DSGN-6 cheap pass, DC-1. Do the PRIV-7 DNS profile on a weekend.
- [ ] **Session 11 (about 2 h): build and CSS consolidation.** ARCH-6, ARCH-22-V, the repo `CLAUDE.md` with the design exceptions, PERF-5 (test Google and DuckDuckGo).
- [ ] **Session 12 (about 1 h, only if the baseline showed background CPU):** PERF-2 and its three 10-minute checks.

**Tier 2 (only if the runway extends)**
- [ ] **Session 13 (about 4 h):** FEAT-7 tab switcher in the omnibox.
- [ ] **Session 14 (about 4 h):** answer the routing question, then FEAT-6.
- [ ] **Session 15 (about 2 h):** FEAT-11 delight pack.
- [ ] **Session 16 (about 4 h):** ARCH-8 test runner, then ARCH-9 `resolveQuery` rules, then ARCH-10.
- [ ] **Later sessions:** PRIV-11 with PERF-11 (only if Finviz still annoys you after PRIV-7), PRIV-8, PRIV-13, FEAT-8, FEAT-23-V, FEAT-10, PERF-12 + PRIV-14, PERF-6 (only if the baseline points there), PRIV-16, PRIV-19, FEAT-9 (only if alerts lag).

**Tier 3 (only when the runway lengthens)**
- [ ] **Session D1 (about 2 h):** DSGN-1 Motion helper, DSGN-2 CSS rule, DSGN-9 + PERF-8 start-page diet (remove `build.sh:25` and `build_android.sh:16` in the same commit).
- [ ] **Session D2 (about 2 h):** DSGN-7, DSGN-12, DSGN-15 cheap part, DSGN-8 subset.
- [ ] **Session D3 (about 2 h):** DSGN-16 a/b/d/e.
- [ ] **Session D4 (optional, about 3 to 4 h):** pick the Research accent, DSGN-14, DSGN-24-V, then DSGN-13a only if you still want it.
