import Foundation

class XCTestCase {}
func XCTAssertTrue(_ value: @autoclosure () -> Bool) { precondition(value(), "Expected true") }
func XCTAssertFalse(_ value: @autoclosure () -> Bool) { precondition(!value(), "Expected false") }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T) {
    do { let av = try a(); let bv = try b(); precondition(av == bv, "Values differ: \(av) vs \(bv)") } catch { fatalError("\(error)") }
}
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a != b) }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T) { precondition(a > b) }
func XCTAssertThrowsError<T>(_ body: @autoclosure () throws -> T) { do { _ = try body(); fatalError("Expected refusal") } catch {} }
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw CocoaError(.coderValueNotFound) }; return value }

@main enum JourneyCheckRunner {
    static func main() throws {
        let tests = JourneyTests()
        tests.testReconciliation()
        tests.testLiteralIndexAndProjectIsolation()
        try tests.testReferencesExcludedAndRoundTrip()
        try tests.testPreservesSectionKeysAndMetadata()
        try tests.testSingleSectionAndAmbiguousMarkers()
        tests.testFocusThresholds()
        print("PASS: six portable journey/map checks")
    }
}

final class JourneyTests: XCTestCase {
    func testReconciliation() {
        let chapter = ManuscriptChapter(title: "Chapter 1", content: "1.1 Purpose\n\n" + passage, targetWords: 100)
        var saved = AcademicJourney.extract(projectID: "example", chapters: [chapter])
        saved[0].evidence = "Source page 4"
        XCTAssertEqual(AcademicJourney.reconcile(projectID: "example", chapters: [chapter], saved: saved).current[0].evidence, "Source page 4")
        var changed = chapter; changed.content += " Changed."
        let result = AcademicJourney.reconcile(projectID: "example", chapters: [changed], saved: saved)
        XCTAssertEqual(result.archived.count, 1)
        XCTAssertEqual(result.current[0].evidence, "")
        XCTAssertTrue(result.current[0].evidenceReviewPending)
    }
    func testFocusThresholds() {
        func focus(_ words: Int, _ target: Int) -> ChapterFocus { ChapterFocus(id: UUID(), index: 0, title: "Test", words: words, target: target, share: 0, links: 0, missingEvidence: 0) }
        XCTAssertEqual(focus(79, 100).balance, "Below planned length")
        XCTAssertEqual(focus(80, 100).balance, "Near planned length")
        XCTAssertEqual(focus(120, 100).balance, "Near planned length")
        XCTAssertEqual(focus(121, 100).balance, "Above planned length")
        XCTAssertEqual(focus(50, 0).balance, "No budget set")
    }
    let passage = String(repeating: "Evidence needs examination. ", count: 8)
    func testLiteralIndexAndProjectIsolation() {
        let chapters = [ManuscriptChapter(title: "Chapter 1", content: "1.1 Concept\n\n" + passage, targetWords: 100)]
        let a = AcademicJourney.extract(projectID: "mba", chapters: chapters)
        let b = AcademicJourney.extract(projectID: "phd", chapters: chapters)
        XCTAssertEqual(a.count, 1)
        XCTAssertNotEqual(a.first?.id, b.first?.id)
        XCTAssertEqual(a.first?.passage, passage.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(a.first?.evidence, "")
        XCTAssertEqual(a.first?.missingCount, 3)
        XCTAssertTrue(AcademicJourney.isCurrent(a[0], chapters: chapters))
        XCTAssertFalse(AcademicJourney.isCurrent(a[0], chapters: []))
    }
    func testReferencesExcludedAndRoundTrip() throws {
        let chapters = [ManuscriptChapter(title: "References", content: passage, targetWords: 0)]
        XCTAssertTrue(AcademicJourney.extract(projectID: "p", chapters: chapters).isEmpty)
        var link = JourneyLink(id: "a", chapterIndex: 0, chapterTitle: "1", concept: "A", passage: passage)
        link.evidence = "Source, page 3"; link.decision = "Pilot"; link.priority = true
        XCTAssertEqual(try JSONDecoder().decode(JourneyLink.self, from: JSONEncoder().encode(link)), link)
        XCTAssertTrue(AcademicJourney.markdown([link]).contains("Source, page 3"))
    }
    func testPreservesSectionKeysAndMetadata() throws {
        let sections: [String: [String: Any]] = ["a": ["content": "1.1 First\n\nOriginal", "source_ids": ["s1"]], "b": ["content": "1.2 Second\n\nOriginal", "review": "pending"]]
        let result = try SectionPreservingEdit.apply("1.1 First\n\nEdited\n\n1.2 Second\n\nOriginal", to: sections)
        XCTAssertEqual(Set(result.keys), Set(sections.keys))
        XCTAssertEqual(result["a"]?["source_ids"] as? [String], ["s1"])
        XCTAssertEqual(result["b"]?["review"] as? String, "pending")
        XCTAssertEqual(result["a"]?["content"] as? String, "1.1 First\n\nEdited")
        XCTAssertThrowsError(try SectionPreservingEdit.apply("Sections were removed", to: sections))
    }
    func testSingleSectionAndAmbiguousMarkers() throws {
        let single: [String: [String: Any]] = ["Recovered manuscript": ["content": "Old", "keep": 7]]
        XCTAssertEqual(try SectionPreservingEdit.apply("New", to: single)["Recovered manuscript"]?["keep"] as? Int, 7)
        let multiple: [String: [String: Any]] = ["a": ["content": "A\n\nold"], "b": ["content": "B\n\nold"]]
        XCTAssertThrowsError(try SectionPreservingEdit.apply("A\n\nold\n\nB\n\ncopy\n\nB\n\nagain", to: multiple))
    }
}
