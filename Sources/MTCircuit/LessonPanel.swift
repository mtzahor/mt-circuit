import AppKit
import CircuitCore
import SwiftUI

/// The tutorial's side panel: the lesson's explanation, its challenge with live goal checks,
/// hints, and the answer.
struct LessonPanel: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var tutorial: TutorialModel
    @ObservedObject private var progress = TutorialProgress.shared
    let lesson: Lesson

    private var index: Int { Tutorial.lessons.firstIndex { $0.id == lesson.id } ?? 0 }
    private var previous: Lesson? { index > 0 ? Tutorial.lessons[index - 1] : nil }
    private var next: Lesson? { index + 1 < Tutorial.lessons.count ? Tutorial.lessons[index + 1] : nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LessonText(lesson.introduction)
                    challenge
                    help
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A new lesson starts at the top.
            .id(lesson.id)
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lesson \(index + 1) of \(Tutorial.lessons.count) · \(lesson.chapter)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(lesson.title)
                        .font(.title2.weight(.semibold))
                }
                Spacer(minLength: 8)
                lessonMenu
            }
            ProgressView(value: Double(progress.completedCount), total: Double(Tutorial.lessons.count))
                .progressViewStyle(.linear)
                .controlSize(.small)
                .help("\(progress.completedCount) of \(Tutorial.lessons.count) lessons completed")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var lessonMenu: some View {
        Menu {
            ForEach(Tutorial.chapters, id: \.title) { chapter in
                Section(chapter.title) {
                    ForEach(chapter.lessons) { item in
                        Button { editor.startLesson(item) } label: {
                            Label(item.title, systemImage: menuSymbol(item))
                        }
                    }
                }
            }
            Divider()
            Button("Reset Progress…", action: confirmReset)
            Button("Leave Tutorial") { editor.leaveTutorial() }
        } label: {
            Image(systemName: "list.bullet")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("All lessons")
    }

    private func menuSymbol(_ item: Lesson) -> String {
        if progress.isCompleted(item) { return "checkmark.circle.fill" }
        return item.id == lesson.id ? "smallcircle.filled.circle" : "circle"
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset your tutorial progress?"
        alert.informativeText = "Every lesson will be marked as not completed."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { progress.reset() }
    }

    private var footer: some View {
        HStack {
            Button { previous.map(editor.startLesson) } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(previous == nil)
            Spacer()
            Button("Start Over") { editor.startLesson(lesson) }
                .help("Go back to this lesson's starting circuit")
            Spacer()
            Button { next.map(editor.startLesson) } label: {
                HStack(spacing: 4) {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
            }
            .disabled(next == nil)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Challenge

    private var challenge: some View {
        let statuses = tutorial.statuses(for: lesson)
        let complete = tutorial.isComplete(lesson)
        let tint = complete ? Color.green : Color.accentColor
        return VStack(alignment: .leading, spacing: 12) {
            Label("Challenge", systemImage: "target")
                .font(.headline)
            LessonText(lesson.challenge)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lesson.goals.enumerated()), id: \.offset) { index, goal in
                    GoalRow(title: goal.title, status: statuses[index])
                }
            }
            if complete { completion }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.35)))
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Challenge complete!", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            if let next {
                Button("Next: \(next.title)") { editor.startLesson(next) }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("That was the last lesson: you've finished the tutorial. File ▸ New from Example has more circuits to explore.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Hints and answer

    private var help: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<min(tutorial.hintsShown, lesson.hints.count), id: \.self) { index in
                Callout(systemImage: "lightbulb", tint: .orange) {
                    LessonText(lesson.hints[index])
                }
            }
            if tutorial.showsAnswer {
                Callout(systemImage: "key", tint: .accentColor) {
                    VStack(alignment: .leading, spacing: 10) {
                        LessonText(lesson.answer)
                        Button("Load the Solution") { editor.loadSolution(of: lesson) }
                            .controlSize(.small)
                            .help("Replace your circuit with a working one (you can undo this)")
                    }
                }
            }
            HStack {
                if tutorial.hintsShown < lesson.hints.count {
                    Button(tutorial.hintsShown == 0 ? "Show a Hint" : "Another Hint") { tutorial.hintsShown += 1 }
                }
                if !tutorial.showsAnswer {
                    Button("Show the Answer") { tutorial.showsAnswer = true }
                }
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Pieces

private struct GoalRow: View {
    let title: String
    let status: GoalStatus?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let detail = status?.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .met: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .notMet: Image(systemName: "circle").foregroundStyle(.secondary)
        case .unavailable: Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
        case nil: Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        }
    }
}

/// A tinted box with an icon, for hints and the answer.
private struct Callout<Content: View>: View {
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Lesson prose: paragraphs separated by blank lines, with Markdown emphasis. A paragraph that
/// starts with "> " is a formula, set apart on its own.
struct LessonText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                if paragraph.hasPrefix("> ") {
                    Text(paragraph.dropFirst(2))
                        .font(.system(size: 15, design: .serif))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(Self.markdown(paragraph))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
