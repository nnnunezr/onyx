import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Fun Placeholder Messages (Apple-style short & playful)
let funSearchPrompts: [String] = [
    "Where to next?",
    "What's on your mind?",
    "Curiosity starts here...",
    "Seek and find...",
    "Ask away...",
    "Think fast, search faster",
    "What are we exploring?",
    "Beam me up...",
    "Ready when you are",
    "Fire away..."
]

func randomFunPrompt() -> String {
    return funSearchPrompts.randomElement() ?? "Where to next?"
}

// MARK: - Custom Search Bar
class CustomSearchBar: NSTextField {
    var onFocusChanged: ((Bool) -> Void)?
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // NSWindow offers key equivalents to every view, not just the focused one: only claim
        // Cmd+A while this field is being edited, or a focused web page never gets Select All.
        if let editor = currentEditor(),
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "a" {
            editor.selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChanged?(true) }
        return result
    }
}
