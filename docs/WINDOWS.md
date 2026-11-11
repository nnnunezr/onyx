# Onyx for Windows: plan (not started)

_Written 2026-11-10. Nothing here is built. Natan chose: plan only, Rust + WebView2, someone else tests. Revisit when Dilenia or Veylo pays, not before._

## Decision and cost

- A Windows port is a new project. Onyx is a side project and runway is short, so every hour here is an hour not spent on paid work. The roadmap already says stop after Tier 0.
- The Android port was frozen (ARCH-17) because every bridge change had to be done twice. Windows repeats that cost unless the bridge is shimmed once (see "Bridge").
- Nobody has asked for it yet. Write down who the first Windows user is before building anything.

## Stack

| Piece | Choice | Why |
|---|---|---|
| Window | `tao` | Rust windowing, pairs with `wry`. |
| Web engine | `wry` on WebView2 | Uses the Edge runtime Windows already ships, so no bundled browser and low RAM. Fits the "optimized" goal. |
| Raw WebView2 access | `webview2-com`, reached through `wry`'s `WebViewExtWindows` | For what `wry` does not expose: `TrySuspend`, find, profiles, accelerator keys. |
| Chrome (tab row, toolbar) | One small HTML page in its own WebView | Tab drag, bookmarks bar and toolbar are easier in HTML than hand-built Win32. |
| Pages | One child WebView per tab (`build_as_child`), inactive ones hidden | Same model as macOS (one `WKWebView` per tab). |

Rejected: Electron (bundles Chromium, 100 MB+, much more RAM, opposite of "optimize"). WPF/WinUI + WebView2 (needs the .NET SDK, not installed, and a Windows machine to do properly).

## Reuse unchanged

- `startpage.html`, `settings.html`, `anime.min.js`, `logo.svg`. Android already shares them, so they are platform-neutral apart from the bridge.
- `YouTubeAdBlockScript` and the search-theme scripts: plain JS and CSS, injected as initialization scripts, scoped by host exactly as on macOS (PERF-1 lesson: never inject into every frame of every site).
- Pure logic to port to Rust with the same tests as `tests/main.swift`: `URLClassifier`, `DownloadPolicy`, `ExternalAppPolicy`, `StartLayout` validation, `TabReorder`.

## Bridge

The start page and settings talk to the host through `window.webkit.messageHandlers.<name>.postMessage(body)` on macOS and `window.OnyxAndroid.*` on Android. On Windows, inject one initialization script that defines `window.webkit.messageHandlers.<name>` to forward to `window.chrome.webview.postMessage({handler, body})`. Both pages then run unchanged with `isMac` true.

Handlers the pages call (from `startpage.html` and `BrowserController+Settings.swift`):

| Handler | Payload | Windows host does |
|---|---|---|
| `onyxNavigate` | `{url}` | Open the URL in the active tab. |
| `onyxSwitchWorkspace` | `{id, url}` | Switch workspace, then open the URL. |
| `onyxOpenSettings` | `{}` | Open the settings tab. |
| `openProfileManager` | `{}` | Show the workspace switcher. |
| `onyxFetchSuggestions` | `{query, reqId}` | Fetch suggestions, reply with the page's callback. |
| `onyxFetchFeed` | `{url, reqId}` | Allow-listed news fetch, reply with the callback. |
| `onyxSettings` | `{action, ...}` | `getSettings`, `setSearchEngine`, `setPins`, `setStartLayout`, `setStartup`, `setShowBookmarksBar`, `setAdBlockEnabled`, `setNewsEnabled`, `setOfferSavePasswords`, `switchWorkspace`, `createWorkspace`, `deleteWorkspace`, `clearCache`, `openDownloads`, `openPasswords`, `makeDefaultBrowser` (Windows: open Settings > Default apps; it cannot be set from code). Read `bypassBotChallenge` before porting it. |

The host replies by calling named functions on the page: `window.renderSettings`, `setPins`, `setStartLayout`, `setSearchEngine`, `setNewsEnabled`, `updateActiveProfile`. Read the exact signatures from the Swift senders when starting.

Trust rule carried over from macOS: bridges answer only Onyx's own pages. Serve them from a WebView2 virtual host (`SetVirtualHostNameToFolderMapping`, for example `https://onyx.local/`), check the sender origin on every message, and never load them from `file://`.

## Feature map

| macOS | Windows |
|---|---|
| `WKWebsiteDataStore` per workspace | One `wry` `WebContext` data directory per workspace, or a WebView2 profile name. Pick one in the first spike and measure the process cost. |
| Tabs, drag to reorder | HTML tab row with pointer-event drag. Port `TabReorder` and its tests. |
| Downloads (`WKDownload`) | `DownloadStarting` event, same `DownloadPolicy`. |
| Content blocking (`WKContentRuleList`) | `WebResourceRequested` filter against the same rule list. Cost per request is the risk: measure it. |
| Context menu | `ContextMenuRequested`. |
| Find in page | WebView2 find API (newer SDKs) or an injected fallback. |
| Password vault (Keychain) | Windows Credential Manager or a DPAPI-protected file. Keep the CSV import and export and the strict host matching (PRIV-3). |
| Default browser | Register URL handlers and file types in the registry, then open Settings. |
| Session restore, bookmarks, history | Same JSON, in `%APPDATA%\Onyx`. |
| ⌘ shortcuts | Ctrl. WebView2 swallows keys when it has focus, so handle them in `AcceleratorKeyPressed`. Tooltips that say ⌘ need a platform substitution. |
| App icon | Generate an `.ico` from the existing icon sources. |

## Window chrome (lesson from macOS 1.2.0)

On macOS a tab inside the system's window-drag band dragged the whole window, and five fixes aimed at the tab view did nothing. Moving the tab row out of the band fixed it. On Windows: start with the **native title bar**, with the tab row and toolbar below it, so no tab can ever sit in a drag region. Only consider a custom title bar later, and then define drag and no-drag regions explicitly.

## Scope

1. **v1, core shell:** tabs with drag reorder, address bar using the same query resolver, back/forward/reload, start page and settings, workspaces, bookmarks bar, downloads list, find, session restore, search engines, basic ad blocking.
2. **v2:** password vault with import and export, YouTube shield, context menu extras, search-page theming.
3. **v3, parity extras:** the rest of the macOS menu and popovers.

Skip: Android bridge changes, anything not listed.

## Optimization (the Windows build)

- No bundled browser. Use the Evergreen runtime and have the installer bootstrap it if missing.
- Suspend background tabs (`TrySuspend` after they have been hidden for a while), resume on select.
- Create a tab's WebView lazily. Keep the chrome page small and framework-free.
- Inject scripts only on the hosts that need them, once per page.
- Release profile: `opt-level = "z"`, `lto = "fat"`, `codegen-units = 1`, `panic = "abort"`, `strip = true`.
- Baseline first, then set budgets. Measure cold start to first paint, idle RAM at 1, 5 and 10 tabs, and background CPU, against Edge with the same pages. Put the numbers in this file. No targets until there is a baseline.

## Build and test

- **CI is the first tester.** GitHub Actions on `windows-latest` builds on every push, runs the ported unit tests, and uploads the zip. Public repos get these runners free. Whether the runner has the WebView2 runtime, and so whether a smoke launch is possible, is unknown until the first run.
- Cross-building from the Mac with `cargo-xwin` is possible but unproven and needs Microsoft's SDK license accepted. Prefer CI.
- No code signing at first, so Windows SmartScreen will warn, the same as the unnotarized macOS build. Say so in the release notes.
- Never publish a Windows release that nobody has launched.

### Handoff for the tester

Ask for: Windows version, WebView2 runtime version (`edge://version` in Edge), then these checks, reporting pass or fail with a screenshot of any failure.

1. App starts, start page shows, search and a pinned site open.
2. Open 5 tabs. Drag one to reorder. The window must not move.
3. Drag the empty title area. The window moves.
4. Create a workspace. Log in to a site in it. Confirm the other workspace is still logged out.
5. Download a file. It lands in Downloads and shows in the list.
6. Quit and relaunch. Tabs, bookmarks and settings are back.
7. Idle for 10 minutes with 10 tabs. Note RAM in Task Manager.

## Risks and unknowns

- `wry` child WebViews on Windows: z-order, focus and resize behavior. Spike this first.
- Per-workspace isolation: separate data directories spawn separate browser process groups. Measure RAM before committing to it.
- Keyboard shortcuts, IME and high DPI when WebView2 owns focus.
- API availability depends on the WebView2 SDK and runtime version. Check each call against the pinned version.
- Cross-build and CI behavior are untested.

## First three steps when this resumes

1. `cargo new` plus a CI workflow that builds a `wry` window on `windows-latest` and uploads the artifact. Green before anything else.
2. A `core` crate with the ported pure logic and tests, run in CI.
3. The shell: one window, the start page from a virtual host, the bridge shim, one tab. Hand that build to the tester with the checklist above.
