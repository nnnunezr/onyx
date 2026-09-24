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
print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
