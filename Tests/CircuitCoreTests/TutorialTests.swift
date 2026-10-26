import Foundation
import Testing
@testable import CircuitCore

private func lesson(_ id: String) -> Lesson {
    Tutorial.lesson(withID: id)!
}

private func settingValue(_ circuit: Circuit, _ name: String, _ value: Double) -> Circuit {
    var circuit = circuit
    let index = circuit.components.firstIndex { $0.name == name }!
    circuit.components[index].value = value
    return circuit
}

@Suite struct TutorialTests {
    @Test func lessonIDsAreUnique() {
        let ids = Tutorial.lessons.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Tutorial.chapters.flatMap(\.lessons).map(\.id) == ids)
    }

    @Test(arguments: Tutorial.lessons.map(\.id))
    func solutionMeetsEveryGoal(id: String) {
        let lesson = lesson(id)
        let statuses = lesson.evaluate(lesson.solution)
        for (goal, status) in zip(lesson.goals, statuses) {
            #expect(status.isMet, "\(goal.title): \(status)")
        }
        #expect(lesson.solvedCircuit.lesson == id)
    }

    @Test(arguments: Tutorial.lessons.map(\.id))
    func starterLeavesWorkToDo(id: String) {
        let lesson = lesson(id)
        let solved = lesson.evaluate(lesson.starter).allSatisfy(\.isMet)
        #expect(!solved)
        #expect(lesson.startingCircuit.lesson == id)
    }

    /// The starters simulate cleanly, except the first, which is empty.
    @Test(arguments: Tutorial.lessons.dropFirst().map(\.id))
    func starterSimulates(id: String) throws {
        let result = try Simulator.run(lesson(id).starter)
        let unconnected = result.netlist.warnings.filter { !$0.contains("not connected") }
        #expect(unconnected.isEmpty, "\(result.netlist.warnings)")
    }

    @Test func lessonIsSavedWithTheCircuit() throws {
        let circuit = lesson("ohms-law").startingCircuit
        #expect(try Circuit.decoded(from: circuit.encoded()).lesson == "ohms-law")
        // Documents from before the tutorial have no lesson key.
        let old = try JSONSerialization.jsonObject(with: Examples.voltageDivider.circuit.encoded()) as! [String: Any]
        #expect(old["lesson"] == nil)
        #expect(try Circuit.decoded(from: JSONSerialization.data(withJSONObject: old)).lesson == nil)
    }

    @Test func wrongAnswersFail() {
        let power = lesson("power")
        // 500 Ω draws enough current but overheats; 700 Ω is cool but draws too little.
        #expect(power.evaluate(settingValue(power.starter, "R1", 500)).map(\.isMet) == [true, false, true])
        #expect(power.evaluate(settingValue(power.starter, "R1", 700)).map(\.isMet) == [false, true, true])
        // Changing the source instead of the resistor breaks the "keep" goal.
        let ohms = lesson("ohms-law")
        #expect(ohms.evaluate(settingValue(ohms.starter, "V1", 2)).map(\.isMet) == [true, false])
    }

    @Test func missingLabelAndShortedPartsAreExplained() {
        let divider = lesson("voltage-divider")
        var unlabeled = divider.solution
        unlabeled.components.removeAll { $0.kind == .netLabel && $0.name == "out" }
        guard case let .unavailable(reason) = divider.evaluate(unlabeled)[0] else {
            Issue.record("expected the goal to be unavailable")
            return
        }
        #expect(reason.contains("labeled “out”"))

        // A resistor dropped onto the top wire of the series lesson is shorted.
        var shorted = lesson("series-resistors").starter
        shorted.components.append(Component(kind: .resistor, name: "R2", position: GridPoint(18, 6), rotation: 0))
        let status = Goal.current("R2", .atLeast(0)).check(shorted, try? Simulator.run(shorted))
        #expect(status == .unavailable(
            "R2 is shorted: all of its pins are on the same net. A part placed on top of a wire is shorted by it."))
    }

    @Test func emptyCircuitCannotBeMeasured() {
        let statuses = lesson("first-circuit").evaluate(Circuit())
        #expect(Array(statuses.prefix(3)) == Array(repeating: .notMet(""), count: 3))
        #expect(statuses[3] == .unavailable(NetlistError.empty.localizedDescription))
    }

    @Test func cutoffMatchesTheAnalyticValue() throws {
        let low = lesson("low-pass-filter")
        for (r, c) in [(1e3, 100e-9), (4.7e3, 33e-9)] {
            let circuit = settingValue(settingValue(low.starter, "R1", r), "C1", c)
            let measured = try #require(measure(low.goals[0], circuit))
            #expect(abs(measured / (1 / (2 * .pi * r * c)) - 1) < 2e-3)
        }
        let high = lesson("high-pass-filter")
        let measured = try #require(measure(high.goals[0], high.solution))
        #expect(abs(measured / (1 / (2 * .pi * 1e3 * 1.59e-6)) - 1) < 2e-3)
        // A low-pass filter has no high-pass cutoff.
        #expect(high.evaluate(high.starter) == [.notMet("V(out) never falls 3 dB below its high-frequency level.")])
    }

    @Test func peakMatchesTheResonantFrequency() throws {
        let resonance = lesson("resonance")
        let measured = try #require(measure(resonance.goals[0], resonance.starter))
        #expect(abs(measured / (1 / (2 * .pi * (1e-3 * 1e-6).squareRoot())) - 1) < 2e-3)
    }

    @Test func gainHasTheSignOfTheOutput() throws {
        let inverting = lesson("inverting-amplifier")
        let gain = try #require(measure(inverting.goals[0], inverting.starter))
        #expect(abs(gain + 10) < 1e-2)
        let nonInverting = lesson("non-inverting-amplifier")
        #expect(abs(try #require(measure(nonInverting.goals[0], nonInverting.solution)) - 11) < 1e-2)
    }

    @Test func requirementsDescribeThemselves() {
        #expect(Requirement.near(3.3, tolerance: 0.01).description(unit: "V") == "= 3.3 V ± 1 %")
        #expect(Requirement.atLeast(20e-3).description(unit: "A") == "≥ 20 mA")
        #expect(Requirement.atMost(0.25).description(unit: "W") == "≤ 250 mW")
        #expect(Goal.voltage("out", .near(3.3, tolerance: 0.01)).title == "V(out) = 3.3 V ± 1 %")
        #expect(Goal.onlyUses(.resistor, value: 1e3).title == "Use only 1 kΩ resistors")
    }

    /// The number a goal measured, parsed back from its "Now: …" detail.
    private func measure(_ goal: Goal, _ circuit: Circuit) -> Double? {
        var copy = circuit
        copy.simulation = goal.analysis!
        let detail = goal.check(circuit, try? Simulator.run(copy)).detail
        guard detail.hasPrefix("Now: ") else { return nil }
        return SIFormat.parse(String(detail.dropFirst(5)))
    }
}
