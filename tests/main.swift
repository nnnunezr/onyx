// Table-driven checks for URL classification and vault host matching. Run: tests/run.sh
import Foundation
var fails = 0
func check(_ cond: Bool, _ name: String) { if !cond { fails += 1; print("FAIL:", name) } else { print("ok:  ", name) } }
func u(_ s: String) -> URL { URL(string: s)! }
// Search / research classification
check(URLClassifier.isSearch(u("https://www.google.com/search?q=x")), "google search")
check(URLClassifier.isSearch(u("https://www.google.com.do/search?q=x")), "google.com.do search")
check(!URLClassifier.isSearch(u("https://google.zz.io/search?q=x")), "google.zz.io is not google")
check(!URLClassifier.isSearch(u("https://google.tradesea.ai-login.io/search?q=https://app.tradesea.ai/login")), "lookalike google host")
check(!URLClassifier.isSearch(u("https://mail.google.com/mail/u/0/")), "gmail not themed")
check(!URLClassifier.isSearch(u("https://docs.google.com/document/d/1")), "docs not themed")
check(URLClassifier.isSearch(u("https://duckduckgo.com/?q=x")), "ddg search")
check(URLClassifier.isSearch(u("https://search.brave.com/search?q=x")), "brave search")
check(!URLClassifier.isSearch(u("https://brave.com/download")), "brave.com home not search")
check(URLClassifier.isResearch(u("https://duck.ai/chat")), "duck.ai research")
check(URLClassifier.isResearch(u("https://duckduckgo.com/?q=x&ia=chat")), "ddg ia=chat research")
check(!URLClassifier.isResearch(u("https://evil.example/?via=chat")), "?via=chat not research")
check(!URLClassifier.isResearch(u("https://evil.example/?ia=chat")), "ia=chat on other host not research")
check(!URLClassifier.isSearch(u("https://notduckduckgo.com/?q=x")), "notduckduckgo.com")
check(URLClassifier.isSearch(u("https://www.google.com/search?q=x")) && !URLClassifier.isThemedSearch(u("https://www.google.com/search?q=x")), "google is search but not themed")
check(URLClassifier.isThemedSearch(u("https://duckduckgo.com/?q=x")), "ddg themed")
check(URLClassifier.isThemedSearch(u("https://search.brave.com/search?q=x")), "brave themed")
// Password host matching
func entry(_ url: String) -> OnyxPasswordEntry { OnyxPasswordEntry(title: "t", urlString: url, username: "u", password: "p") }
check(entry("https://tradesea.ai").matches(host: "app.tradesea.ai"), "tradesea subdomain matches")
check(!entry("https://tradesea.ai").matches(host: "tradesea.ai-secure.net"), "tradesea lookalike blocked")
check(!entry("https://netflix.com").matches(host: "x.com"), "x.com vs netflix.com")
check(!entry("https://ithub.com").matches(host: "github.com"), "ithub.com vs github.com")
check(entry("https://github.com/login").matches(host: "github.com"), "github exact")
check(entry("https://www.github.com").matches(host: "github.com"), "www stripped")
check(!entry("https://accounts.google.com").matches(host: "google.com"), "no reverse match")
// Loopback detection (autofill over http allowed only here or for http-saved logins)
check(URLClassifier.isLoopback("localhost"), "localhost loopback")
check(URLClassifier.isLoopback("app.localhost"), "*.localhost loopback")
check(URLClassifier.isLoopback("127.0.0.1"), "127.0.0.1 loopback")
check(!URLClassifier.isLoopback("localhost.evil.com"), "localhost.evil.com not loopback")
check(!URLClassifier.isLoopback("192.168.1.1"), "LAN is not loopback")
// Safe loading (ARCH-4): unreadable stored lists are backed up, good items are salvaged
let suite = "onyx.tests.\(ProcessInfo.processInfo.processIdentifier)"
let d = UserDefaults(suiteName: suite)!
d.set(Data("not json".utf8), forKey: "OnyxBookmarks")
let broken = Persistence.loadList(BookmarkItem.self, key: "OnyxBookmarks", defaults: d)
check(broken.problem != nil && broken.items.isEmpty, "garbage bookmarks flagged, nothing salvaged")
check(broken.problem?.backupURL.map { FileManager.default.fileExists(atPath: $0.path) } == true, "garbage bookmarks backed up")
check(d.data(forKey: "OnyxBookmarks") == Data("not json".utf8), "stored value not overwritten by load")
if let url = broken.problem?.backupURL { try? FileManager.default.removeItem(at: url) }
let mixed = #"[{"urlString":"https://github.com","title":"GitHub"},{"title":"no url"},{"id":"x","urlString":"https://a.com","extraFutureField":1}]"#
d.set(Data(mixed.utf8), forKey: "OnyxBookmarks")
let partial = Persistence.loadList(BookmarkItem.self, key: "OnyxBookmarks", defaults: d)
check(partial.items.map { $0.urlString } == ["https://github.com", "https://a.com"], "bad element skipped, others kept")
check(partial.problem?.recoveredCount == 2, "partial decode reported")
if let url = partial.problem?.backupURL { try? FileManager.default.removeItem(at: url) }
d.set(Data(#"[{"id":"p","name":"Personal"}]"#.utf8), forKey: "OnyxProfiles")
let profilesOld = Persistence.loadList(BrowserProfile.self, key: "OnyxProfiles", defaults: d)
check(profilesOld.problem == nil && profilesOld.items.first?.colorHex == "#FFFFFF", "missing profile fields get defaults")
check(Persistence.loadList(BookmarkItem.self, key: "missingKey", defaults: d).problem == nil, "missing key is not a problem")
check(DP.decideResponse(mimeType: "text/html; charset=utf-8", statusCode: 200, contentDisposition: nil, isMainFrame: true, canShowMIMEType: false) == .allow, "html page never downloads (youtube.com)")
check(DP.decideResponse(mimeType: "text/html", statusCode: 200, contentDisposition: "attachment; filename=r.html", isMainFrame: true, canShowMIMEType: true) == .download, "html attachment still downloads")
// Error page
check(ErrorPage.escape("<a href=\"x\">&'") == "&lt;a href=&quot;x&quot;&gt;&amp;&#39;", "error page escapes HTML")
check(ErrorPage.content(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, host: "node.js", fallback: "").title == "Can't find node.js", "cannot find host title")
check(!ErrorPage.html(ErrorPage.content(domain: "x", code: 1, host: "<b>", fallback: "<script>"), failedURL: u("https://a.com/?q=<x>"), searchURL: nil).contains("<script>"), "error page never injects markup")
// Download policy: attachments and unrenderable main-frame responses are saved, not dropped
typealias DP = DownloadPolicy
check(DP.isAttachment("attachment; filename=\"a.pdf\""), "attachment with filename")
check(DP.isAttachment(" Attachment"), "attachment any case")
check(!DP.isAttachment("inline; filename=a.pdf"), "inline is not attachment")
check(!DP.isAttachment("attachmentx"), "attachmentx is not attachment")
check(DP.decideResponse(mimeType: "application/octet-stream", statusCode: 200, contentDisposition: "attachment; filename=r.pdf", isMainFrame: true, canShowMIMEType: true) == .download, "Gmail PDF attachment downloads")
check(DP.decideResponse(mimeType: "application/octet-stream", statusCode: 200, contentDisposition: "attachment", isMainFrame: false, canShowMIMEType: true) == .download, "iframe attachment downloads")
check(DP.decideResponse(mimeType: "application/octet-stream", statusCode: 200, contentDisposition: nil, isMainFrame: true, canShowMIMEType: false) == .download, "octet-stream main frame downloads")
check(DP.decideResponse(mimeType: "application/octet-stream", statusCode: 200, contentDisposition: nil, isMainFrame: false, canShowMIMEType: false) == .cancel, "unrenderable iframe dropped")
check(DP.decideResponse(mimeType: "application/octet-stream", statusCode: 200, contentDisposition: nil, isMainFrame: true, canShowMIMEType: true) == .allow, "normal page renders")
check(DP.decideResponse(mimeType: "application/octet-stream", statusCode: 302, contentDisposition: "attachment", isMainFrame: true, canShowMIMEType: false) == .allow, "redirect never downloads")
check(DP.decideResponse(mimeType: "application/octet-stream", statusCode: 204, contentDisposition: nil, isMainFrame: true, canShowMIMEType: false) == .allow, "204 never downloads")
// External app requests: unknown schemes prompt, web schemes never do, drive-by launches are dropped
typealias EP = ExternalAppPolicy
check(EP.decide(scheme: "zoommtg", handledByWebKit: false, isMainFrame: true, userInitiated: false) == .prompt, "main-frame zoommtg prompts")
check(EP.decide(scheme: "SLACK", handledByWebKit: false, isMainFrame: false, userInitiated: true) == .prompt, "clicked iframe link prompts (any case)")
check(EP.decide(scheme: "spotify", handledByWebKit: false, isMainFrame: false, userInitiated: false) == .block, "hidden iframe launch dropped")
check(EP.decide(scheme: "https", handledByWebKit: true, isMainFrame: true, userInitiated: true) == .notExternal, "https stays in WebKit")
check(EP.decide(scheme: nil, handledByWebKit: false, isMainFrame: true, userInitiated: true) == .notExternal, "no scheme is not external")
check(EP.decide(scheme: "applescript", handledByWebKit: false, isMainFrame: true, userInitiated: true) == .block, "applescript always blocked")
d.removePersistentDomain(forName: suite)
print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
