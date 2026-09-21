import Foundation
import SwiftUI

func XCTAssertTrue(_ value: @autoclosure () -> Bool) { precondition(value()) }
func XCTAssertFalse(_ value: @autoclosure () -> Bool) { precondition(!value()) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(a) == \(b)") }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw FeedError(message: "Unexpected nil") }; return value }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T) { do { _ = try value(); fatalError("Expected error") } catch {} }

@main
struct DayNestTests {
    @MainActor static func main() throws {
        let tests = DayNestTests()
        try tests.testRSSFiltersRankAndConvertsAoE()
        tests.testBrokenFeedDoesNotBecomeEmptySuccess()
        try tests.testWeekStartsMondayAndExcludesEnd()
        try tests.testStorageRoundTripAndCrossMidnightMeeting()
        try tests.testCorruptedStorageIsNotOverwritten()
        tests.testUnsafeConferenceLinksRejected()
        try tests.testFolderIsolationAndPersistence()
        try tests.testCompletedDesktopTodos()
        try tests.testAllFutureConferenceScope()
        try tests.testDesktopConferenceSelection()
        try tests.testSixMonthAIWindow()
        try tests.testLiveFeedFixtureWhenProvided()
        print("PASS: 12 checks — RSS / AoE, corrupt feed, date ranges, persistence / cross-midnight, corrupt storage, safe links, desktop pins, six-month AI window, real feed")
    }
    func testRSSFiltersRankAndConvertsAoE() throws {
        let xml = """
        <rss><channel>
        <item><title>TEST 2027 Abstract Deadline</title><description><![CDATA[Some Conference
        Deadline (UTC-12): 2026-09-20 23:59:59
        CCF A, CORE A*]]></description><pubDate>Sun, 20 Sep 2026 23:59:59 -1200</pubDate><guid>a</guid><category>AI</category><link>https://example.com</link></item>
        <item><title>Not A</title><description>CCF B, CORE A*</description><pubDate>Sun, 20 Sep 2026 23:59:59 -1200</pubDate><guid>b</guid></item>
        </channel></rss>
        """
        let result = try ConferenceParser().parse(Data(xml.utf8))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].category, "AI")
        XCTAssertEqual(result[0].deadline, ISO8601DateFormatter().date(from: "2026-09-21T11:59:59Z"))
        XCTAssertEqual(result[0].originalDeadline, "Deadline (UTC-12): 2026-09-20 23:59:59")
    }
    func testBrokenFeedDoesNotBecomeEmptySuccess() {
        XCTAssertThrowsError(try ConferenceParser().parse(Data("<rss>".utf8)))
        XCTAssertThrowsError(try ConferenceParser().parse(Data("<rss><channel/></rss>".utf8)))
        let xml = "<rss><channel><item><title>X</title><guid>x</guid><description>CCF A</description><pubDate>TBD</pubDate></item></channel></rss>"
        XCTAssertThrowsError(try ConferenceParser().parse(Data(xml.utf8)))
    }
    func testWeekStartsMondayAndExcludesEnd() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = ISO8601DateFormatter()
        let now = try XCTUnwrap(date.date(from: "2026-09-23T12:00:00Z"))
        XCTAssertTrue(Period.week.contains(date.date(from: "2026-09-21T00:00:00Z")!, now: now, calendar: cal))
        XCTAssertFalse(Period.week.contains(date.date(from: "2026-09-28T00:00:00Z")!, now: now, calendar: cal))
        XCTAssertFalse(Period.week.contains(date.date(from: "2026-09-20T12:00:00Z")!, now: now, calendar: cal))
        XCTAssertFalse(Period.month.contains(date.date(from: "2026-10-01T00:00:00Z")!, now: now, calendar: cal))
    }
    @MainActor func testStorageRoundTripAndCrossMidnightMeeting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(directory: directory)
        var todo = Todo(); todo.title = "论文实验"; store.put(todo); store.toggle(todo)
        var memo = Memo(); memo.title = "想法"; memo.body = "保存中文 ✨"; memo.pinned = true; store.put(memo)
        var meeting = Meeting(); meeting.title = "跨天会议"
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        meeting.start = tomorrow.addingTimeInterval(-1800); meeting.end = tomorrow.addingTimeInterval(1800); store.put(meeting)
        let restored = Store(directory: directory)
        XCTAssertTrue(restored.data.todos[0].completed)
        XCTAssertEqual(restored.data.memos[0].body, memo.body)
        XCTAssertEqual(restored.meetings(on: tomorrow).map(\.id), [meeting.id])
        restored.deleteTodo(todo.id)
        XCTAssertTrue(Store(directory: directory).data.todos.isEmpty)
    }
    @MainActor func testCorruptedStorageIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let original = Data("broken data".utf8)
        try original.write(to: file)
        let store = Store(directory: directory)
        var todo = Todo(); todo.title = "保留原文件"; store.put(todo)
        XCTAssertNotNil(store.storageError)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testUnsafeConferenceLinksRejected() {
        XCTAssertNil(safeWebURL("file:///etc/passwd"))
        XCTAssertNil(safeWebURL("javascript:alert(1)"))
        XCTAssertNotNil(safeWebURL("https://ccfddl.com"))
    }
    @MainActor func testFolderIsolationAndPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(directory: directory)
        var normal = TodoFolder(name: "工作"); normal.collapsed = true; store.putFolder(normal)
        var todo = Todo(); todo.title = "普通待办"; todo.folderID = normal.id; store.put(todo)
        let conference = Conference(id: "c1", title: "WWW 2027 Abstract Deadline", deadline: Date(), category: "MX", details: "CCF A", link: "https://example.com")
        let folder = store.conferenceFolder(conference)
        var revision = conference; revision.id = "c2"; revision.title = "WWW 2027 Deadline"
        XCTAssertEqual(store.conferenceFolder(revision).id, folder.id)
        var special = Todo(); special.title = "论文实验"; special.folderID = folder.id; special.due = Date().addingTimeInterval(-86400); store.put(special)
        XCTAssertEqual(store.folderTodos(folder.id).count, 1)
        XCTAssertTrue(store.overdue.isEmpty)
        XCTAssertFalse(store.todos(.month).contains(where: { $0.id == special.id }))
        store.toggle(special)
        XCTAssertFalse(store.desktopTodos(.today).contains(where: { $0.id == special.id }))
        let restored = Store(directory: directory)
        XCTAssertTrue(restored.regularFolders[0].collapsed)
        XCTAssertEqual(restored.conferenceFolder(revision).id, folder.id)
        XCTAssertTrue(restored.folderTodos(folder.id)[0].completed)
        restored.deleteRegularFolder(normal.id)
        XCTAssertEqual(restored.folderTodos(nil).map(\.id), [todo.id])
        XCTAssertEqual(restored.folderTodos(folder.id).count, 1)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Snapshot())) as! [String: Any]
        XCTAssertNil(try JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: json)).folders)
    }
    @MainActor func testCompletedDesktopTodos() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(directory: directory)
        var item = Todo(); item.title = "昨天的任务今天完成"
        item.due = Calendar.current.date(byAdding: .day, value: -1, to: store.now)!
        store.put(item)
        XCTAssertTrue(store.desktopTodos(.today).isEmpty)
        store.toggle(item)
        XCTAssertEqual(store.desktopTodos(.today).map(\.id), [item.id])
        XCTAssertTrue(store.overdue.isEmpty)
        let restored = Store(directory: directory)
        XCTAssertEqual(restored.desktopTodos(.today).map(\.id), [item.id])
        XCTAssertNotNil(restored.data.todos[0].completedAt)
        restored.toggle(restored.data.todos[0])
        XCTAssertNil(restored.data.todos[0].completedAt)
        XCTAssertTrue(restored.desktopTodos(.today).isEmpty)
        XCTAssertEqual(restored.overdue.count, 1)
        var today = Todo(); today.title = "今日完成后保留"
        restored.put(today); restored.toggle(today)
        XCTAssertTrue(restored.desktopTodos(.today)[0].completed)
    }
    @MainActor func testAllFutureConferenceScope() throws {
        let xml = """
        <rss><channel>
        <item><title>EMNLP 2030 Deadline</title><description>CCF B, CORE A</description><pubDate>Sun, 20 Sep 2026 23:59:59 -1200</pubDate><guid>emnlp</guid><category>AI</category></item>
        <item><title>OTHER 2030 Deadline</title><description>CCF B, CORE A</description><pubDate>Sun, 20 Sep 2026 23:59:59 -1200</pubDate><guid>other</guid><category>AI</category></item>
        </channel></rss>
        """
        let parsed = try ConferenceParser().parse(Data(xml.utf8))
        XCTAssertEqual(parsed.map(\.id), ["emnlp"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(directory: directory)
        var emnlp = parsed[0]; emnlp.deadline = store.now.addingTimeInterval(86400)
        let distant = Conference(id: "distant", title: "Systems Conference", deadline: Calendar.current.date(byAdding: .year, value: 1, to: store.now)!, category: "DS", details: "CCF A", link: "https://example.com")
        var past = distant; past.id = "past"; past.deadline = store.now.addingTimeInterval(-1)
        var excluded = distant; excluded.id = "b"; excluded.details = "CCF B"
        store.data.conferences = [distant, past, excluded, emnlp]
        XCTAssertEqual(store.allFutureConferences.map(\.id), ["emnlp", "distant"])
        XCTAssertEqual(store.desktopCandidates.map(\.id), ["emnlp", "distant"])
        XCTAssertTrue(store.upcoming.isEmpty)
    }
    @MainActor func testDesktopConferenceSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(directory: directory)
        let item = Conference(id: "original", title: "ICLR test", deadline: Date().addingTimeInterval(86400), category: "AI", details: "CCF A", link: "https://example.com")
        store.data.conferences = [item]
        XCTAssertEqual(store.desktopConferences, [item])
        store.pinToDesktop(item, pinned: true)
        let restored = Store(directory: directory)
        XCTAssertTrue(restored.customDesktopConferences)
        restored.now = item.deadline.addingTimeInterval(86400)
        XCTAssertTrue(restored.upcoming.isEmpty)
        XCTAssertEqual(restored.desktopConferences, [item])
        restored.updateConferenceCache([])
        XCTAssertEqual(restored.desktopConferences, [item])
        var revision = item; revision.id = "revised"; revision.deadline = item.deadline.addingTimeInterval(604800)
        restored.updateConferenceCache([revision])
        XCTAssertEqual(restored.desktopConferences, [revision])
        restored.pinToDesktop(revision, pinned: false)
        XCTAssertTrue(restored.desktopConferences.isEmpty)
        XCTAssertTrue(Store(directory: directory).customDesktopConferences)
        restored.setCustomDesktopConferences(false)
        XCTAssertEqual(restored.desktopConferences, [revision])
        // A pre-feature JSON backup must still load without migration or data loss.
        let bytes = try JSONEncoder().encode(Snapshot())
        var json = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        json.removeValue(forKey: "desktopPins")
        let old = try JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.desktopPins)
    }
    @MainActor func testSixMonthAIWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(directory: directory)
        // Use a month-end start to ensure six months is calendar arithmetic, not 180 days.
        store.now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!
        let end = Calendar.current.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 12))!
        XCTAssertEqual(store.conferenceWindowEnd, end)
        func conference(_ id: String, _ date: Date, _ category: String = "AI") -> Conference {
            Conference(id: id, title: id, deadline: date, category: category, details: "CCF A", link: "https://example.com")
        }
        store.data.conferences = [
            conference("beyond", end.addingTimeInterval(1)),
            conference("at-end", end),
            conference("past", store.now.addingTimeInterval(-1)),
            conference("non-ai", store.now, "DB"),
            conference("at-start", store.now),
            conference("within", store.now.addingTimeInterval(86400))
        ]
        XCTAssertEqual(store.upcoming.map(\.id), ["at-start", "within", "at-end"])
    }
    func testLiveFeedFixtureWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["CCF_FEED_FIXTURE"] else { print("SKIP: optional real RSS fixture"); return }
        let items = try ConferenceParser().parse(Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertTrue(items.count > 100)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertTrue(items.allSatisfy { $0.link == $0.link.trimmingCharacters(in: .whitespacesAndNewlines) })
        XCTAssertTrue(items.allSatisfy { $0.category == $0.category.trimmingCharacters(in: .whitespacesAndNewlines) })
        print("Parsed \(items.count) real CCF-A / EMNLP deadlines; \(items.filter { $0.deadline > Date() }.count) upcoming")
    }
}
