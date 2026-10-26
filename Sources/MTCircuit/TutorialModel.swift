import CircuitCore
import Combine
import Foundation

/// Per-window tutorial state: checks the current lesson's goals whenever the circuit changes.
@MainActor
final class TutorialModel: ObservableObject {
    let document: CircuitDocument

    /// Status of each goal of `checkedLessonID`'s lesson, from the latest check.
    @Published private(set) var statuses: [GoalStatus] = []
    @Published var hintsShown = 0
    @Published var showsAnswer = false

    private var checkedLessonID: String?
    private var checkTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(document: CircuitDocument) {
        self.document = document
        document.$circuit
            .receive(on: RunLoop.main)
            .sink { [weak self] circuit in self?.circuitDidChange(circuit) }
            .store(in: &cancellables)
    }

    /// The lesson the document is in, if any.
    var lesson: Lesson? {
        document.circuit.lesson.flatMap(Tutorial.lesson(withID:))
    }

    /// Goal statuses for `lesson`, or nil for goals not checked yet.
    func statuses(for lesson: Lesson) -> [GoalStatus?] {
        guard checkedLessonID == lesson.id, statuses.count == lesson.goals.count else {
            return Array(repeating: nil, count: lesson.goals.count)
        }
        return statuses
    }

    func isComplete(_ lesson: Lesson) -> Bool {
        statuses(for: lesson).allSatisfy { $0?.isMet == true }
    }

    private func circuitDidChange(_ circuit: Circuit) {
        if circuit.lesson != checkedLessonID {
            checkedLessonID = circuit.lesson
            statuses = []
            hintsShown = 0
            showsAnswer = false
            check(circuit, after: nil)
        } else {
            // Like auto-run, wait for a pause in editing.
            check(circuit, after: .milliseconds(300))
        }
    }

    private func check(_ circuit: Circuit, after delay: Duration?) {
        checkTask?.cancel()
        guard let id = circuit.lesson, let lesson = Tutorial.lesson(withID: id) else { return }
        checkTask = Task { [weak self] in
            if let delay {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            let statuses = await Self.evaluate(lesson, circuit)
            guard !Task.isCancelled, let self else { return }
            self.statuses = statuses
            if isComplete(lesson) { TutorialProgress.shared.markCompleted(lesson) }
        }
    }

    @concurrent
    private nonisolated static func evaluate(_ lesson: Lesson, _ circuit: Circuit) async -> [GoalStatus] {
        lesson.evaluate(circuit)
    }
}

/// Which lessons the learner has completed, shared by every window and kept across launches.
@MainActor
final class TutorialProgress: ObservableObject {
    static let shared = TutorialProgress()
    private static let defaultsKey = "completedLessons"

    @Published private(set) var completed: Set<String>

    private init() {
        completed = Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    var completedCount: Int {
        Tutorial.lessons.filter { completed.contains($0.id) }.count
    }

    /// The first lesson not completed yet, or the first lesson when all are.
    var nextLesson: Lesson {
        Tutorial.lessons.first { !completed.contains($0.id) } ?? Tutorial.lessons[0]
    }

    func isCompleted(_ lesson: Lesson) -> Bool { completed.contains(lesson.id) }

    func markCompleted(_ lesson: Lesson) {
        guard completed.insert(lesson.id).inserted else { return }
        save()
    }

    func reset() {
        completed = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(completed.sorted(), forKey: Self.defaultsKey)
    }
}
