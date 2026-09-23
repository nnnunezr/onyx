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
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "a" {
                self.currentEditor()?.selectAll(nil)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChanged?(true) }
        return result
    }
}
