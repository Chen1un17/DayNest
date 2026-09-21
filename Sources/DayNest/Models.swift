import Foundation

struct Todo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var due = Date()
    var priority = 1
    var notes = ""
    var completed = false
    var completedAt: Date?
    var folderID: UUID?
}

struct TodoFolder: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var conferenceKey: String?
    var collapsed = false
}

struct Meeting: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var start = Date()
    var end = Date().addingTimeInterval(3600)
    var attendees = ""
    var location = ""
    var notes = ""
}

struct Memo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var body = ""
    var pinned = false
    var updated = Date()
}

struct Conference: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var deadline: Date
    var category: String
    var details: String
    var link: String
    var isCCFA: Bool { details.range(of: #"(?m)^CCF A(?:,|\s*$)"#, options: .regularExpression) != nil }
    var isEMNLP: Bool { title.range(of: #"^EMNLP(?:\s|$)"#, options: .regularExpression) != nil }
    var originalDeadline: String {
        details.components(separatedBy: "\n").first(where: { $0.hasPrefix("Deadline") }) ?? ""
    }
}

struct Snapshot: Codable {
    var todos: [Todo] = []
    var meetings: [Meeting] = []
    var memos: [Memo] = []
    var conferences: [Conference] = []
    var followed: Set<String> = []
    // nil keeps automatic selection; an empty array is an explicit empty desktop.
    var desktopPins: [Conference]?
    var folders: [TodoFolder]?
    var lastSync: Date?
}

enum Period: String, CaseIterable, Identifiable {
    case today = "今日", week = "本周", month = "本月"
    var id: String { rawValue }
    func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal.dateInterval(of: self == .today ? .day : self == .week ? .weekOfYear : .month, for: now)!
    }
    func contains(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let range = interval(now: now, calendar: calendar)
        return date >= range.start && date < range.end
    }
}

struct FeedError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

final class ConferenceParser: NSObject, XMLParserDelegate {
    private var items: [Conference] = []
    private var current: [String: String] = [:]
    private var element = ""
    private var insideItem = false
    private var invalidEntries = 0
    private let formatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return value
    }()

    func parse(_ data: Data) throws -> [Conference] {
        items = []; current = [:]; invalidEntries = 0; insideItem = false
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse() else {
            throw FeedError(message: "会议源解析失败：\(parser.parserError?.localizedDescription ?? "RSS 格式错误")")
        }
        guard invalidEntries == 0 else {
            throw FeedError(message: "会议源有 \(invalidEntries) 条会议日期无法解析，已保留上次数据。")
        }
        guard !items.isEmpty else { throw FeedError(message: "会议源没有有效的 CCF-A 或 EMNLP 日期，已保留上次数据。") }
        return Array(Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
            .sorted { $0.deadline < $1.deadline }
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        element = elementName
        if elementName == "item" { insideItem = true; current = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem { current[element, default: ""] += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8), insideItem { current[element, default: ""] += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "item" else { return }
        insideItem = false
        current = current.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let details = current["description", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        let isA = details.range(of: #"(?m)^CCF A(?:,|\s*$)"#, options: .regularExpression) != nil
        let isEMNLP = current["title", default: ""].range(of: #"^EMNLP(?:\s|$)"#, options: .regularExpression) != nil
        guard isA || isEMNLP else { return }
        guard let date = formatter.date(from: current["pubDate", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)),
              let title = current["title"], let id = current["guid"], !title.isEmpty, !id.isEmpty else {
            invalidEntries += 1; return
        }
        items.append(Conference(id: id, title: title, deadline: date, category: current["category", default: ""], details: details, link: current["link", default: ""]))
    }
}

func safeWebURL(_ string: String) -> URL? {
    guard let url = URL(string: string), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
    return url
}
