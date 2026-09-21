import SwiftUI
import AppKit

@MainActor
final class Store: ObservableObject {
    @Published var data = Snapshot()
    @Published var syncing = false
    @Published var syncError: String?
    @Published var storageError: String?
    @Published var now = Date()
    private var timer: Timer?
    private var storageAvailable = true
    private var lastSyncAttempt: Date?
    let fileURL: URL

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DayNest", isDirectory: true)
        fileURL = directory.appendingPathComponent("data.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                data = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
                data.followed = Set(data.followed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                data.conferences = data.conferences.map { value in
                    var value = value
                    value.id = value.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    value.category = value.category.trimmingCharacters(in: .whitespacesAndNewlines)
                    value.link = value.link.trimmingCharacters(in: .whitespacesAndNewlines)
                    return value
                }
            }
        } catch {
            storageAvailable = false
            storageError = "读取本地数据失败。为保护原文件，已暂停写入。请备份并检查 \(fileURL.path)：\(error.localizedDescription)"
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                if self.lastSyncAttempt.map({ Date().timeIntervalSince($0) > 21600 }) ?? true {
                    await self.refresh()
                }
            }
        }
    }

    @discardableResult
    func save() -> Bool {
        guard storageAvailable else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: fileURL, options: .atomic)
            storageError = nil
            return true
        } catch {
            storageError = "保存失败：\(error.localizedDescription)。请先导出备份，避免退出后丢失修改。"
            return false
        }
    }
    func put(_ todo: Todo) {
        var todo = todo
        let previous = data.todos.first { $0.id == todo.id }
        if todo.completed {
            if previous?.completed != true { todo.completedAt = now }
        } else { todo.completedAt = nil }
        if let i = data.todos.firstIndex(where: { $0.id == todo.id }) { data.todos[i] = todo }
        else { data.todos.append(todo) }
        save()
    }
    func put(_ meeting: Meeting) {
        if let i = data.meetings.firstIndex(where: { $0.id == meeting.id }) { data.meetings[i] = meeting }
        else { data.meetings.append(meeting) }
        save()
    }
    func put(_ memo: Memo) {
        var memo = memo; memo.updated = Date()
        if let i = data.memos.firstIndex(where: { $0.id == memo.id }) { data.memos[i] = memo }
        else { data.memos.append(memo) }
        save()
    }
    func toggle(_ todo: Todo) { var todo = todo; todo.completed.toggle(); put(todo) }
    func follow(_ conference: Conference) {
        if data.followed.contains(conference.id) { data.followed.remove(conference.id) }
        else { data.followed.insert(conference.id) }
        save()
    }
    func deleteTodo(_ id: UUID) { data.todos.removeAll { $0.id == id }; save() }
    func deleteMeeting(_ id: UUID) { data.meetings.removeAll { $0.id == id }; save() }
    func deleteMemo(_ id: UUID) { data.memos.removeAll { $0.id == id }; save() }

    var customDesktopConferences: Bool { data.desktopPins != nil }
    var desktopConferences: [Conference] {
        (data.desktopPins ?? upcoming).sorted { $0.deadline < $1.deadline }
    }
    var desktopCandidates: [Conference] {
        var items = Dictionary(allFutureConferences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in data.desktopPins ?? [] { items[item.id] = item }
        return items.values.sorted { $0.deadline < $1.deadline }
    }
    func isDesktopPinned(_ conference: Conference) -> Bool {
        data.desktopPins?.contains(where: { $0.id == conference.id }) ?? false
    }
    func setCustomDesktopConferences(_ enabled: Bool) {
        data.desktopPins = enabled ? (data.desktopPins ?? []) : nil
        save()
    }
    func pinToDesktop(_ conference: Conference, pinned: Bool) {
        var items = data.desktopPins ?? []
        items.removeAll { $0.id == conference.id }
        if pinned { items.append(conference) }
        data.desktopPins = items
        save()
    }
    func updateConferenceCache(_ conferences: [Conference]) {
        if let pins = data.desktopPins {
            data.desktopPins = pins.map { pinned in
                if let exact = conferences.first(where: { $0.id == pinned.id }) { return exact }
                // The RSS GUID includes the deadline, so a deadline revision can change it.
                let candidates = conferences.filter { $0.title == pinned.title && $0.category == pinned.category }
                return candidates.count == 1 ? candidates[0] : pinned
            }
        }
        data.conferences = conferences
    }
    var allFutureConferences: [Conference] {
        data.conferences.filter { ($0.isCCFA || $0.isEMNLP) && $0.deadline >= now }.sorted { $0.deadline < $1.deadline }
    }
    var conferenceWindowEnd: Date { Calendar.current.date(byAdding: .month, value: 6, to: now)! }
    var upcoming: [Conference] {
        data.conferences.filter {
            $0.isCCFA && $0.category == "AI" && $0.deadline >= now && $0.deadline <= conferenceWindowEnd
        }.sorted { $0.deadline < $1.deadline }
    }
    var folders: [TodoFolder] { data.folders ?? [] }
    var regularFolders: [TodoFolder] { folders.filter { $0.conferenceKey == nil } }
    func isConferenceTodo(_ item: Todo) -> Bool {
        folders.contains { $0.id == item.folderID && $0.conferenceKey != nil }
    }
    func putFolder(_ folder: TodoFolder) {
        var values = folders
        if let i = values.firstIndex(where: { $0.id == folder.id }) { values[i] = folder }
        else { values.append(folder) }
        data.folders = values; save()
    }
    func deleteRegularFolder(_ id: UUID) {
        guard regularFolders.contains(where: { $0.id == id }) else { return }
        data.folders = folders.filter { $0.id != id }
        for i in data.todos.indices where data.todos[i].folderID == id { data.todos[i].folderID = nil }
        save()
    }
    func conferenceFolder(_ conference: Conference) -> TodoFolder {
        // All submission rounds and abstract/full-paper deadlines of one edition share a folder.
        let key = conference.title.split(separator: " ").prefix(2).joined(separator: " ")
        if let folder = folders.first(where: { $0.conferenceKey == key }) { return folder }
        let folder = TodoFolder(name: key, conferenceKey: key)
        putFolder(folder)
        return folder
    }
    func folderTodos(_ id: UUID?) -> [Todo] {
        data.todos.filter { $0.folderID == id }.sorted {
            if $0.completed != $1.completed { return !$0.completed }
            return $0.due < $1.due
        }
    }
    var overdue: [Todo] { data.todos.filter { !isConferenceTodo($0) && !$0.completed && $0.due < Calendar.current.startOfDay(for: now) } }
    func todos(_ period: Period) -> [Todo] {
        data.todos.filter { !isConferenceTodo($0) && period.contains($0.due, now: now) }.sorted {
            if $0.completed != $1.completed { return !$0.completed }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.due < $1.due
        }
    }
    func desktopTodos(_ period: Period) -> [Todo] {
        data.todos.filter { item in
            !isConferenceTodo(item) && (period.contains(item.due, now: now) ||
            (item.completed && item.completedAt.map { period.contains($0, now: now) } == true))
        }.sorted {
            if $0.completed != $1.completed { return !$0.completed }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.due < $1.due
        }
    }
    func meetings(on date: Date) -> [Meeting] {
        let interval = Calendar.current.dateInterval(of: .day, for: date)!
        return data.meetings.filter { $0.start < interval.end && $0.end > interval.start }.sorted { $0.start < $1.start }
    }
    func refresh() async {
        guard !syncing else { return }
        lastSyncAttempt = Date()
        syncing = true; syncError = nil
        defer { syncing = false }
        do {
            var request = URLRequest(url: URL(string: "https://ccfddl.com/conference/deadlines_en.xml")!)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw FeedError(message: "会议源暂时不可用，请稍后重试。") }
            let conferences = try ConferenceParser().parse(bytes)
            updateConferenceCache(conferences)
            data.lastSync = Date()
            save()
        } catch {
            syncError = "同步失败，保留上次缓存：\(error.localizedDescription)"
        }
    }
    func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "DayNest-备份.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted; try encoder.encode(data).write(to: url, options: .atomic) }
        catch { storageError = "导出失败：\(error.localizedDescription)" }
    }
    func importBackup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
            // Merge by identity; existing local records take precedence.
            let todoIDs = Set(data.todos.map(\.id)), meetingIDs = Set(data.meetings.map(\.id)), memoIDs = Set(data.memos.map(\.id))
            data.todos += imported.todos.filter { !todoIDs.contains($0.id) }
            data.meetings += imported.meetings.filter { !meetingIDs.contains($0.id) && $0.end > $0.start }
            data.memos += imported.memos.filter { !memoIDs.contains($0.id) }
            let folderIDs = Set(folders.map(\.id))
            data.folders = folders + (imported.folders ?? []).filter { !folderIDs.contains($0.id) }
            data.followed.formUnion(imported.followed)
            if let importedPins = imported.desktopPins {
                let existing = Set((data.desktopPins ?? []).map(\.id))
                data.desktopPins = (data.desktopPins ?? []) + importedPins.filter { !existing.contains($0.id) }
            }
            save()
        } catch { storageError = "无法导入该备份：\(error.localizedDescription)" }
    }
}
