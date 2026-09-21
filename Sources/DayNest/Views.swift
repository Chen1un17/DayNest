import SwiftUI
import AppKit

let ink = Color(red: 0.16, green: 0.23, blue: 0.22)
let accent = Color(red: 0.20, green: 0.43, blue: 0.35)
let canvas = Color(red: 0.96, green: 0.96, blue: 0.93)
let muted = Color(red: 0.48, green: 0.52, blue: 0.48)

enum Page: String, CaseIterable, Identifiable {
    case overview = "我的一天", todos = "待办计划", conferences = "学术 DDL", meetings = "会议日程", memos = "备忘录"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "sun.max"
        case .todos: return "checkmark.circle"
        case .conferences: return "graduationcap"
        case .meetings: return "calendar"
        case .memos: return "note.text"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "给重要的事，留一点专注的时间。"
        case .todos: return "从今天出发，让每一个计划落地。"
        case .conferences: return "所有未来的 CCF-A 会议与 EMNLP，自由选择常驻桌面。"
        case .meetings: return "安排时间，也记录每一次交流。"
        case .memos: return "让灵感有处安放。"
        }
    }
}

enum Editor: Identifiable {
    case todo(Todo), meeting(Meeting), memo(Memo)
    var id: UUID {
        switch self { case .todo(let x): return x.id; case .meeting(let x): return x.id; case .memo(let x): return x.id }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var page = Page.overview
    @State private var period = Period.today
    @State private var search = ""
    @State private var onlyFollowed = false
    @State private var selectedDay = Date()
    @State private var editor: Editor?
    @State private var deletion: Editor?
    @State private var hideCompleted = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                header
                if let error = store.storageError { banner(error, color: .red) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch page {
                        case .overview: overview
                        case .todos: todoPage
                        case .conferences: conferencePage
                        case .meetings: meetingPage
                        case .memos: memoPage
                        }
                    }.padding(30)
                }
            }.background(canvas)
        }
        .foregroundStyle(ink).tint(accent).preferredColorScheme(.light)
        .frame(minWidth: 920, minHeight: 650)
        .sheet(item: $editor) { item in
            switch item {
            case .todo(let todo): TodoEditor(item: todo) { store.put($0) }
            case .meeting(let meeting): MeetingEditor(item: meeting) { store.put($0) }
            case .memo(let memo): MemoEditor(item: memo) { store.put($0) }
            }
        }
        .alert("删除这条记录？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("取消", role: .cancel) { deletion = nil }
            Button("删除", role: .destructive) {
                if let deletion {
                    switch deletion {
                    case .todo(let x): store.deleteTodo(x.id)
                    case .meeting(let x): store.deleteMeeting(x.id)
                    case .memo(let x): store.deleteMemo(x.id)
                    }
                }
                deletion = nil
            }
        } message: { Text("此操作会删除本地记录。") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill").font(.title).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DayNest").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("日有安排 · 心有余白").font(.system(size: 10)).foregroundStyle(muted)
                }
            }.padding(.top, 20)
            VStack(spacing: 7) {
                ForEach(Page.allCases) { item in
                    Button { page = item; search = "" } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).frame(width: 20)
                            Text(item.rawValue).fontWeight(page == item ? .semibold : .regular)
                            Spacer()
                            if page == item { Circle().fill(accent).frame(width: 5, height: 5) }
                        }.padding(.horizontal, 14).padding(.vertical, 13)
                            .background(page == item ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(page == item ? accent : muted)
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("你的桌面，轻一点").font(.system(size: 13, weight: .medium))
                Text("把今天的待办、会议和\n截稿提醒放在手边。").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4)
                Button { AppDelegate.shared.showDesktop() } label: {
                    Label("打开桌面小窗", systemImage: "rectangle.on.rectangle").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(14).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            Menu {
                Button("导出本地备份…") { store.exportBackup() }
                Button("合并导入备份…") { store.importBackup() }
                Button("打开数据文件夹") { NSWorkspace.shared.selectFile(store.fileURL.path, inFileViewerRootedAtPath: "") }
            } label: { Label("本地存储与备份", systemImage: "externaldrive").font(.system(size: 11)).foregroundStyle(muted) }
            .menuStyle(.borderlessButton)
        }.padding(20).frame(width: 200).background(Color(red: 0.91, green: 0.93, blue: 0.88))
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.now.formatted(.dateTime.year().month(.wide).day().weekday(.wide))).font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                Text(page.rawValue).font(.system(size: 29, weight: .semibold))
                Text(page.subtitle).font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer()
            if page != .overview {
                TextField("搜索\(page.rawValue)…", text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            if page == .conferences {
                Button { Task { await store.refresh() } } label: { Label(store.syncing ? "同步中…" : "同步会议", systemImage: "arrow.clockwise") }.disabled(store.syncing)
            } else {
                Button {
                    switch page {
                    case .meetings:
                        var item = Meeting(); item.start = selectedDay; item.end = selectedDay.addingTimeInterval(3600); editor = .meeting(item)
                    case .memos: editor = .memo(Memo())
                    default: editor = .todo(Todo())
                    }
                } label: { Label(page == .meetings ? "新建会议" : page == .memos ? "新建备忘" : "新建待办", systemImage: "plus") }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(30).background(.white.opacity(0.50))
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                metric("今日待办", value: "\(store.todos(.today).filter { !$0.completed }.count)", unit: "件待完成", icon: "checkmark.circle")
                metric("今日会议", value: "\(store.meetings(on: store.now).count)", unit: "场交流", icon: "calendar")
                metric("AI 会议截稿", value: "\(store.upcoming.count)", unit: "项 · 未来六个月", icon: "flag")
            }
            if !store.overdue.isEmpty {
                section("还需要一点时间", detail: "\(store.overdue.count) 项已逾期", icon: "clock.badge.exclamationmark") {
                    ForEach(store.overdue) { todo in todoRow(todo) }
                }
            }
            section("今天，专注这几件事", detail: "TODAY’S FOCUS", icon: "sun.max") {
                if store.todos(.today).isEmpty { empty("今天还是一张白纸", "添加第一件待办，开始有条理的一天。", icon: "checkmark.circle") }
                ForEach(store.todos(.today)) { todo in todoRow(todo) }
            }
            section("今日会议", detail: "\(store.meetings(on: store.now).count) 场", icon: "calendar") {
                if store.meetings(on: store.now).isEmpty { empty("今天没有会议", "留一段完整的时间给自己。", icon: "cup.and.saucer") }
                ForEach(store.meetings(on: store.now)) { item in meetingRow(item) }
            }
            section("CCF · 桌面常驻", detail: store.customDesktopConferences ? "自选会议" : "AI · 未来六个月", icon: "graduationcap") {
                ConferenceDesktopPicker().padding(12)
                if store.desktopConferences.isEmpty { empty("尚未选择常驻会议", store.syncError ?? "点击选择会议，勾选想在桌面保留的截止日期。", icon: "antenna.radiowaves.left.and.right") }
                ForEach(store.desktopConferences) { item in conferenceRow(item) }
            }
            if let memo = store.data.memos.filter(\.pinned).sorted(by: { $0.updated > $1.updated }).first {
                section("置顶备忘", detail: "随手记，随时看", icon: "pin") {
                    Button { editor = .memo(memo) } label: {
                        VStack(alignment: .leading, spacing: 8) { Text(memo.title).font(.headline); Text(memo.body).lineLimit(5).foregroundStyle(muted) }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private var todoPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Picker("计划范围", selection: $period) { ForEach(Period.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width: 270)
                Spacer()
                Toggle("隐藏已完成", isOn: $hideCompleted).toggleStyle(.checkbox)
            }
            Button { AppDelegate.shared.showFolders() } label: { Label("管理待办文件夹", systemImage: "folder") }
            Text("按截止日期归入今日、本周（周一开始）和本月；逾期事项单独显示。").font(.caption).foregroundStyle(muted)
            if !store.overdue.filter({ matches($0.title + $0.notes) }).isEmpty {
                section("逾期待办", detail: "及时调整计划", icon: "clock") {
                    ForEach(store.overdue.filter { matches($0.title + $0.notes) }) { todoRow($0) }
                }
            }
            let items = store.todos(period).filter { matches($0.title + $0.notes) && (!hideCompleted || !$0.completed) }
            section("\(period.rawValue)计划", detail: "\(items.filter(\.completed).count) / \(items.count) 已完成", icon: "checklist") {
                if items.isEmpty { empty("这里暂时没有待办", "新建任务并设置截止日期，或调整筛选条件。", icon: "checklist") }
                ForEach(items) { todoRow($0) }
            }
        }
    }
    private var conferencePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("CCF A + EMNLP").font(.system(size: 11, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 6).background(accent.opacity(0.1), in: Capsule())
                Text("全部领域 · 不限未来时长").font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                Spacer()
                Toggle("只看关注", isOn: $onlyFollowed).toggleStyle(.checkbox)
            }
            HStack {
                Text(store.data.lastSync.map { "上次同步：" + $0.formatted(date: .abbreviated, time: .shortened) } ?? "尚未同步")
                Spacer()
                Link("来源 ccfddl.com ↗", destination: URL(string: "https://ccfddl.com")!)
            }.font(.caption).foregroundStyle(muted)
            Text("范围：所有已公布且尚未截止的 CCF-A 会议，以及 EMNLP；不限领域和六个月。").font(.caption).foregroundStyle(accent)
            Text("日期已换算为 \(TimeZone.current.identifier)；摘要与全文截止分别列出。投稿前请核对会议官网。").font(.caption).foregroundStyle(muted)
            ConferenceDesktopPicker()
            if let error = store.syncError { banner(error, color: .orange) }
            let items = store.allFutureConferences.filter {
                (!onlyFollowed || store.data.followed.contains($0.id)) && matches($0.title + $0.details)
            }
            section("会议时间线", detail: "\(items.count) 项截止日期", icon: "flag") {
                if items.isEmpty { empty(store.syncing ? "正在同步会议…" : "暂无匹配的会议", "仅展示来源已公布、尚未截止的会议。可清空搜索、取消关注筛选或同步数据。", icon: "graduationcap") }
                LazyVStack(spacing: 0) { ForEach(items) { conferenceRow($0) } }
            }
        }
    }
    private var meetingPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                DatePicker("查看日期", selection: $selectedDay, displayedComponents: .date).labelsHidden()
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                Button("今天") { selectedDay = store.now }
                Spacer()
                Text("\(store.meetings(on: selectedDay).count) 场会议").foregroundStyle(muted)
            }
            let items = store.meetings(on: selectedDay).filter { matches($0.title + $0.attendees + $0.notes + $0.location) }
            section("\(selectedDay.formatted(.dateTime.month().day().weekday(.wide)))", detail: "DAILY SCHEDULE", icon: "calendar") {
                if items.isEmpty { empty("这一天暂无匹配会议", "记录主题、参与人、时间、地点和会议笔记。", icon: "calendar.badge.plus") }
                ForEach(items) { meetingRow($0) }
            }
        }
    }
    private var memoPage: some View {
        let items = store.data.memos.filter { matches($0.title + $0.body) }.sorted {
            $0.pinned != $1.pinned ? $0.pinned : $0.updated > $1.updated
        }
        return VStack(alignment: .leading, spacing: 18) {
            Text("\(items.count) 篇备忘 · 置顶内容也会显示在桌面小窗").font(.caption).foregroundStyle(muted)
            if items.isEmpty { empty("收集一个想法", "灵感、阅读笔记，或明天想做的事。", icon: "note.text") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: item.pinned ? "pin.fill" : "note.text").foregroundStyle(accent)
                            Spacer()
                            Menu {
                                Button(item.pinned ? "取消置顶" : "置顶") { var item = item; item.pinned.toggle(); store.put(item) }
                                Button("删除", role: .destructive) { deletion = .memo(item) }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                        }
                        Button { editor = .memo(item) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(item.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                                Text(item.body.isEmpty ? "暂无内容" : item.body).font(.system(size: 13)).foregroundStyle(muted).lineLimit(6).frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                                Text(item.updated.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(muted)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.padding(20).background(Color(red: 0.99, green: 0.98, blue: 0.88), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
    private func todoRow(_ item: Todo) -> some View {
        HStack(spacing: 13) {
            TodoCompletionButton(item: item, size: 21)
            Button { editor = .todo(item) } label: {
                TodoText(item: item, compact: false)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if item.priority == 2 { Text("重要").font(.caption2).foregroundStyle(.orange).padding(5).background(.orange.opacity(0.08), in: Capsule()) }
            Text(item.due.formatted(.dateTime.month().day())).font(.caption).foregroundStyle(!item.completed && item.due < Calendar.current.startOfDay(for: store.now) ? .orange : muted)
            Menu { Button("编辑") { editor = .todo(item) }; Button("删除", role: .destructive) { deletion = .todo(item) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
        }.padding(17)
        .background(.white.opacity(0.4))
        .overlay(alignment: .bottom) { Divider().opacity(0.35).padding(.horizontal, 17) }
    }
    private func meetingRow(_ item: Meeting) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.start.formatted(date: .omitted, time: .shortened)).font(.system(size: 17, weight: .medium, design: .rounded))
                Text(item.end.formatted(date: Calendar.current.isDate(item.start, inSameDayAs: item.end) ? .omitted : .abbreviated, time: .shortened)).font(.caption).foregroundStyle(muted)
            }.frame(width: 85, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.45)).frame(width: 3, height: 51)
            Button { editor = .meeting(item) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title).font(.system(size: 15, weight: .semibold))
                    Text([item.attendees, item.location].filter { !$0.isEmpty }.joined(separator: "  ·  ")).font(.caption).foregroundStyle(muted)
                    if !item.notes.isEmpty { Text(item.notes).font(.caption).foregroundStyle(muted).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if item.start <= store.now && item.end > store.now { Text("进行中").font(.caption).foregroundStyle(accent) }
            Menu { Button("编辑") { editor = .meeting(item) }; Button("删除", role: .destructive) { deletion = .meeting(item) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
        }.padding(20).overlay(alignment: .bottom) { Divider().opacity(0.35).padding(.horizontal, 17) }
    }
    private func conferenceRow(_ item: Conference) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 3) {
                Text(item.deadline.formatted(.dateTime.month(.abbreviated))).font(.caption2)
                Text(item.deadline.formatted(.dateTime.day())).font(.system(size: 25, weight: .medium, design: .rounded))
            }.foregroundStyle(accent).frame(width: 55, height: 59).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(item.title).font(.system(size: 14, weight: .semibold)); Text("\(item.isCCFA ? "CCF A" : "EMNLP") · \(item.category)").font(.caption2).foregroundStyle(muted) }
                Text(item.deadline.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(muted)
                Text(item.originalDeadline).font(.system(size: 10)).foregroundStyle(muted)
                DisclosureGroup("会议详情") { Text(item.details).font(.caption).foregroundStyle(muted).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6) }.font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 9) {
                Text(deadlineLabel(item.deadline, now: store.now)).font(.caption).foregroundStyle(item.deadline.timeIntervalSince(store.now) < 7 * 86400 ? .orange : accent)
                Button("会议待办") { AppDelegate.shared.showFolder(store.conferenceFolder(item)) }.font(.caption)
                Toggle("常驻桌面", isOn: Binding(
                    get: { store.isDesktopPinned(item) },
                    set: { store.pinToDesktop(item, pinned: $0) }
                )).toggleStyle(.checkbox).font(.caption)
                HStack {
                    if let url = safeWebURL(item.link) { Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help("会议官网") }
                    Button { store.follow(item) } label: { Image(systemName: store.data.followed.contains(item.id) ? "star.fill" : "star") }.buttonStyle(.plain).help("关注此截止日期")
                }
            }
        }.padding(18).overlay(alignment: .bottom) { Divider().opacity(0.35).padding(.horizontal, 17) }
    }
    private func section<Content: View>(_ title: String, detail: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold)); Spacer(); Text(detail).font(.system(size: 10)).foregroundStyle(muted) }.padding(18)
            Divider().opacity(0.4)
            content()
        }.background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(ink.opacity(0.055)) }
    }
    private func metric(_ title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text(title).font(.system(size: 12)); Spacer(); Image(systemName: icon).foregroundStyle(accent) }
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text(value).font(.system(size: 34, weight: .medium, design: .rounded)); Text(unit).font(.system(size: 10)).foregroundStyle(muted) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
    }
    private func matches(_ string: String) -> Bool { search.isEmpty || string.localizedCaseInsensitiveContains(search) }
    private func shiftDay(_ value: Int) { selectedDay = Calendar.current.date(byAdding: .day, value: value, to: selectedDay)! }
}

func deadlineLabel(_ date: Date, now: Date) -> String {
    let seconds = date.timeIntervalSince(now)
    if seconds < 0 { return "已截止" }
    if seconds < 3600 { return "剩余 \(max(1, Int(ceil(seconds / 60)))) 分钟" }
    if seconds < 86400 { return "剩余 \(Int(ceil(seconds / 3600))) 小时" }
    return "剩余 \(Int(ceil(seconds / 86400))) 天"
}

func empty(_ title: String, _ subtitle: String, icon: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: icon).font(.system(size: 26, weight: .light)).foregroundStyle(accent.opacity(0.55))
        Text(title).font(.system(size: 14, weight: .medium))
        Text(subtitle).font(.caption).foregroundStyle(muted).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(30)
}
func banner(_ text: String, color: Color) -> some View {
    Label(text, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(color).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
}

struct TodoEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @State private var confirmingDeletion = false
    @State var item: Todo
    var save: (Todo) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.data.todos.contains(where: { $0.id == item.id }) ? "编辑事项" : "安排一件事").font(.title2.bold())
            Form {
                TextField("待办标题", text: $item.title)
                Picker("文件夹", selection: $item.folderID) {
                    Text("未分类").tag(nil as UUID?)
                    ForEach(store.folders) { folder in
                        Text((folder.conferenceKey == nil ? "" : "会议 · ") + folder.name).tag(Optional(folder.id))
                    }
                }
                DatePicker("截止日期", selection: $item.due, displayedComponents: .date)
                Picker("优先级", selection: $item.priority) { Text("低").tag(0); Text("普通").tag(1); Text("重要").tag(2) }
                TextField("备注", text: $item.notes, axis: .vertical).lineLimit(3...6)
                Toggle("已完成", isOn: $item.completed)
            }.formStyle(.grouped)
            HStack {
                if store.data.todos.contains(where: { $0.id == item.id }) {
                    Button("删除事项", role: .destructive) { confirmingDeletion = true }.foregroundStyle(.red)
                }
                editorButtons(valid: !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { save(item); dismiss() } cancel: { dismiss() }
            }
        }.padding(24).frame(width: 470).tint(accent)
        .alert("删除这条事项？", isPresented: $confirmingDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { store.deleteTodo(item.id); dismiss() }
        } message: { Text("标题和备注都会被删除，此操作无法撤销。") }
    }
}
struct MeetingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @State var item: Meeting
    var save: (Meeting) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("记录一次交流").font(.title2.bold())
            Form {
                TextField("会议主题", text: $item.title)
                DatePicker("开始时间", selection: $item.start)
                DatePicker("结束时间", selection: $item.end)
                TextField("和谁开会", text: $item.attendees, prompt: Text("姓名、团队，逗号分隔"))
                TextField("地点 / 链接", text: $item.location)
                TextField("议程 / 会议记录", text: $item.notes, axis: .vertical).lineLimit(5...9)
            }.formStyle(.grouped)
            if item.end <= item.start { Text("结束时间需要晚于开始时间。").font(.caption).foregroundStyle(.red) }
            else if store.data.meetings.contains(where: { $0.id != item.id && $0.start < item.end && $0.end > item.start }) { Text("这段时间已有其他会议，请留意时间冲突。").font(.caption).foregroundStyle(.orange) }
            editorButtons(valid: !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.end > item.start) { save(item); dismiss() } cancel: { dismiss() }
        }.padding(24).frame(width: 520).tint(accent)
    }
}
struct MemoEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: Memo
    var save: (Memo) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("留住一个想法").font(.title2.bold()); Spacer(); Toggle("置顶", isOn: $item.pinned).toggleStyle(.checkbox) }
            TextField("备忘标题", text: $item.title).font(.title3).textFieldStyle(.roundedBorder)
            TextEditor(text: $item.body).font(.system(size: 14)).scrollContentBackground(.hidden).padding(12).background(canvas, in: RoundedRectangle(cornerRadius: 12)).frame(height: 280)
            editorButtons(valid: !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { save(item); dismiss() } cancel: { dismiss() }
        }.padding(24).frame(width: 530).tint(accent)
    }
}
func editorButtons(valid: Bool, save: @escaping () -> Void, cancel: @escaping () -> Void) -> some View {
    HStack { Spacer(); Button("取消", action: cancel).keyboardShortcut(.cancelAction); Button("保存", action: save).buttonStyle(.borderedProminent).disabled(!valid).keyboardShortcut(.defaultAction) }
}

struct ConferenceDesktopPicker: View {
    @EnvironmentObject var store: Store
    @State private var showing = false
    @State private var query = ""
    var body: some View {
        Button { showing.toggle() } label: {
            Label("选择常驻会议", systemImage: "pin")
        }
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 14) {
                Text("桌面 CCF 展示").font(.headline)
                Toggle("自定义常驻会议", isOn: Binding(
                    get: { store.customDesktopConferences },
                    set: { store.setCustomDesktopConferences($0) }
                )).toggleStyle(.switch)
                Text(store.customDesktopConferences ? "勾选后固定显示，截止后仍保留，直到手动取消。" : "当前自动展示未来六个月的 CCF-A AI 会议。勾选任意会议即可切换为自选。")
                    .font(.caption).foregroundStyle(muted)
                TextField("搜索会议或领域…", text: $query).textFieldStyle(.roundedBorder)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(store.desktopCandidates.filter { query.isEmpty || ($0.title + $0.category).localizedCaseInsensitiveContains(query) }) { item in
                            Toggle(isOn: Binding(
                                get: { store.isDesktopPinned(item) },
                                set: { store.pinToDesktop(item, pinned: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.system(size: 12, weight: .medium))
                                    Text(item.deadline.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(muted)
                                }
                            }.toggleStyle(.checkbox)
                        }
                        if store.desktopCandidates.isEmpty { Text("暂无可选会议，请先同步会议数据。").font(.caption).foregroundStyle(muted) }
                    }.padding(4)
                }.frame(maxHeight: 300)
                HStack {
                    Text("已选择 \(store.data.desktopPins?.count ?? 0) 项").font(.caption).foregroundStyle(muted)
                    Spacer()
                    Button("完成") { showing = false }.buttonStyle(.borderedProminent)
                }
            }.padding(20).frame(width: 370).tint(accent).preferredColorScheme(.light)
        }
    }
}

/// Keep notes next to the title in both completed and incomplete rows.
struct TodoText: View {
    let item: Todo
    let compact: Bool
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 6 : 10) {
            Text(item.title)
                .font(.system(size: compact ? 12 : 14, weight: .medium))
                .strikethrough(item.completed)
                .foregroundStyle(item.completed ? muted : ink)
                .lineLimit(compact ? 3 : 2)
            if !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.notes)
                    .font(.system(size: compact ? 10 : 12))
                    .foregroundStyle(muted.opacity(0.8))
                    .lineLimit(compact ? 2 : 3)
                    .help(item.notes)
            }
        }
    }
}
