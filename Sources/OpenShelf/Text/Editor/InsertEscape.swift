import Foundation

/// A two-key sequence typed quickly in insert mode means Esc (ROADMAP C12 item 2), as
/// Doom's evil-escape does with `jk`. The first key goes in as text; when the second
/// follows within `delay`, the first is taken back and insert mode ends.
struct InsertEscape {
    static let sequenceKey = "VimEscapeSequence"
    static let delayKey = "VimEscapeDelay"

    /// Two characters; empty turns it off.
    var sequence: [Character]
    var delay: TimeInterval
    private var first: (character: Character, time: TimeInterval)?

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.string(forKey: Self.sequenceKey) ?? "jk"
        sequence = stored.count == 2 ? Array(stored) : []
        let delay = defaults.double(forKey: Self.delayKey)
        self.delay = delay > 0 ? delay : 0.15
    }

    /// Notes a typed character at `time` (seconds); true when it completes the sequence.
    mutating func typed(_ character: Character, at time: TimeInterval) -> Bool {
        guard sequence.count == 2 else { return false }
        if character == sequence[1], let first, time - first.time <= delay {
            self.first = nil
            return true
        }
        first = character == sequence[0] ? (character, time) : nil
        return false
    }
}
