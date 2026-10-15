import Foundation

// Only audio-time evidence can establish a new utterance. Different text alone
// is also a normal ASR correction and must never cause blind concatenation.
struct TranscriptBuffer {
    struct Span {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }
    private(set) var spans: [Span] = []
    private(set) var text = ""

    mutating func update(_ incoming: String, start: TimeInterval?, end: TimeInterval?) {
        guard !incoming.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let start, let end, start.isFinite, end.isFinite, start >= 0, end > start else {
            // Un-timed partial hypotheses can revise the current span. Keep the
            // earlier timed spans, but don't invent a new boundary.
            text = joined(spans.dropLast().map(\.text) + [incoming])
            return
        }
        if let overlap = spans.firstIndex(where: { start < $0.end - 0.05 || abs(start - $0.start) < 0.05 }) {
            spans.removeSubrange(overlap...)
        }
        spans.append(Span(text: incoming, start: start, end: end))
        text = joined(spans.map(\.text))
    }

    private func joined(_ strings: [String]) -> String {
        // A newline distinguishes observed utterances without inventing punctuation.
        strings.joined(separator: "\n")
    }
}
