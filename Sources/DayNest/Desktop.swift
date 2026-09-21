import SwiftUI
import AppKit

struct DesktopView: View {
    @EnvironmentObject var store: Store
    @AppStorage("desktopFloating") private var floating = false
    @State private var period = Period.today
    @State private var quickTitle = ""
    @State private var editingTodo: Todo?
    @AppStorage("unfiledCollapsed") private var unfiledCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "leaf.fill").foregroundStyle(accent)
                Text("DayNest").font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Button { floating.toggle(); AppDelegate.shared.updateDesktopLevel() } label: { Image(systemName: floating ? "pin.fill" : "pin") }.help(floating ? "切换为贴在桌面" : "始终置顶")
                Button { AppDelegate.shared.showMain() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("打开完整应用")
                Button { AppDelegate.shared.hideDesktop() } label: { Image(systemName: "xmark") }.help("隐藏桌面小窗")
            }.buttonStyle(.plain)
            HStack {
                Text(store.now.formatted(.dateTime.month().day().weekday(.wide))).font(.system(size: 12)).foregroundStyle(muted)
                Spacer()
                Text(floating ? "始终置顶" : "贴在桌面").font(.system(size: 9)).foregroundStyle(muted)
            }
            Picker("待办范围", selection: $period) { ForEach(Period.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            HStack {
                TextField("＋ 随手添加待办", text: $quickTitle).textFieldStyle(.plain).onSubmit(addTodo)
                Button(action: addTodo) { Image(systemName: "return") }.buttonStyle(.plain).disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(.system(size: 12)).padding(10).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let error = store.storageError { banner(error, color: .red) }
                    let todos = store.desktopTodos(period)
                    HStack {
                        tinyHeading("\(period.rawValue)日程", icon: "checklist")
                        Spacer()
                        Button("管理文件夹") { AppDelegate.shared.showFolders() }.font(.system(size: 10))
                    }
                    let visible = store.overdue + todos.filter { item in !store.overdue.contains(where: { $0.id == item.id }) }
                    folderGroup(nil, items: visible.filter { $0.folderID == nil })
                    ForEach(store.regularFolders) { folder in
                        folderGroup(folder, items: visible.filter { $0.folderID == folder.id })
                    }
                    Divider()
                    tinyHeading("今日会议", icon: "calendar")
                    let meetings = store.meetings(on: store.now)
                    if meetings.isEmpty { Text("今天没有会议安排").font(.caption).foregroundStyle(muted) }
                    ForEach(meetings) { item in
                        Button { AppDelegate.shared.showMain() } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.start.formatted(date: .omitted, time: .shortened)).monospacedDigit().foregroundStyle(accent)
                                    Text(item.title).lineLimit(1)
                                }
                                if !item.attendees.isEmpty { Text(item.attendees).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1) }
                            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                    Divider()
                    HStack {
                        tinyHeading("CCF · 常驻会议", icon: "pin")
                        Spacer()
                        ConferenceDesktopPicker().font(.system(size: 10))
                    }
                    let conferences = store.desktopConferences
                    if conferences.isEmpty { Text(store.syncing ? "同步中…" : "点击选择常驻会议，添加到这里").font(.caption).foregroundStyle(muted) }
                    if store.syncError != nil { Text("同步失败，当前显示缓存").font(.caption2).foregroundStyle(.orange) }
                    ForEach(conferences) { item in
                        Button { AppDelegate.shared.showFolder(store.conferenceFolder(item)) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Image(systemName: "folder"); Text(item.title).lineLimit(2); Spacer(); Text(deadlineLabel(item.deadline, now: store.now)).foregroundStyle(accent).font(.system(size: 10)) }
                                Text(item.deadline.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(muted)
                            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("打开会议专属待办文件夹")
                    }
                    if let memo = store.data.memos.filter(\.pinned).sorted(by: { $0.updated > $1.updated }).first {
                        Divider()
                        tinyHeading(memo.title, icon: "pin")
                        Text(memo.body).font(.system(size: 12)).foregroundStyle(muted).lineLimit(8).textSelection(.enabled)
                    }
                }.padding(.vertical, 3)
            }
            HStack {
                Circle().fill(accent.opacity(0.6)).frame(width: 5, height: 5)
                Text("本地保存 · 拖动顶部移动位置").font(.system(size: 9)).foregroundStyle(muted)
                Spacer()
            }
        }.padding(20).frame(minWidth: 320, minHeight: 420)
        .background(canvas.opacity(0.97)).foregroundStyle(ink).tint(accent).preferredColorScheme(.light)
        .popover(item: $editingTodo) { item in
            TodoEditor(item: item) { store.put($0) }.environmentObject(store)
        }
    }
    private func folderGroup(_ folder: TodoFolder?, items: [Todo]) -> some View {
        let collapsed = folder?.collapsed ?? unfiledCollapsed
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    if var folder { folder.collapsed.toggle(); store.putFolder(folder) }
                    else { unfiledCollapsed.toggle() }
                } label: {
                    HStack {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        Image(systemName: "folder")
                        Text(folder?.name ?? "未分类").lineLimit(1)
                        Spacer()
                        Text("\(items.filter(\.completed).count)/\(items.count)").foregroundStyle(muted)
                    }.font(.system(size: 11, weight: .medium)).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button {
                    var todo = Todo(); todo.folderID = folder?.id; editingTodo = todo
                } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("在此文件夹新建待办")
                if let folder {
                    Button { AppDelegate.shared.showFolder(folder) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).help("查看文件夹全部待办")
                }
            }
            if !collapsed {
                if items.isEmpty { Text("此范围暂无待办").font(.system(size: 10)).foregroundStyle(muted) }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        compactTodo(item)
                        if !item.completed && item.due < Calendar.current.startOfDay(for: store.now) {
                            Text("逾期 · " + item.due.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 9)).foregroundStyle(.orange).padding(.leading, 28)
                        }
                    }
                }
            }
        }.padding(10).background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
    private func compactTodo(_ item: Todo) -> some View {
        HStack(alignment: .top, spacing: 9) {
            TodoCompletionButton(item: item, size: 16)
            Button { editingTodo = item } label: {
                TodoText(item: item, compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("编辑标题、备注或删除事项")
            if item.completed { Text("已完成").font(.system(size: 9)).foregroundStyle(accent) }
            if item.priority == 2 && !item.completed { Circle().fill(.orange.opacity(0.7)).frame(width: 5, height: 5).padding(.top, 5) }
        }
    }
    private func tinyHeading(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
    }
    private func addTodo() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var todo = Todo(); todo.title = title
        // A quick task belongs to the selected period; today is valid in all three.
        store.put(todo); quickTitle = ""
    }
}

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    let store = Store()
    var mainWindow: NSWindow?
    var desktop: DesktopPanel?
    var statusItem: NSStatusItem?
    var folderWindows: [String: NSWindow] = [:]
    func showFolders() { showFolderWindow(key: "manager", title: "待办文件夹", view: AnyView(FolderManagerView().environmentObject(store))) }
    func showFolder(_ folder: TodoFolder) { showFolderWindow(key: folder.id.uuidString, title: folder.name, view: AnyView(FolderTasksView(folderID: folder.id).environmentObject(store))) }
    private func showFolderWindow(key: String, title: String, view: AnyView) {
        if folderWindows[key] == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = title; window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 500, height: 400)
            window.contentView = NSHostingView(rootView: view)
            window.center(); folderWindows[key] = window
        }
        folderWindows[key]?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        showMain()
        if UserDefaults.standard.bool(forKey: "desktopVisible") { showDesktop() }
        Task { await store.refresh() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func showMain() {
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "DayNest · 日有安排"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 920, height: 650)
            window.contentView = NSHostingView(rootView: RootView().environmentObject(store))
            window.center()
            window.setFrameAutosaveName("DayNestMain")
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showDesktop() {
        if desktop == nil {
            let panel = DesktopPanel(contentRect: NSRect(x: 70, y: 120, width: 365, height: 640), styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "DayNest 桌面"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 320, height: 420)
            panel.contentView = NSHostingView(rootView: DesktopView().environmentObject(store))
            panel.setFrameAutosaveName("DayNestDesktop")
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }), let screen = NSScreen.main {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 30, y: screen.visibleFrame.maxY - panel.frame.height - 30))
            }
            desktop = panel
        }
        updateDesktopLevel()
        desktop?.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: "desktopVisible")
    }
    func updateDesktopLevel() {
        desktop?.level = UserDefaults.standard.bool(forKey: "desktopFloating") ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    func hideDesktop() { desktop?.orderOut(nil); UserDefaults.standard.set(false, forKey: "desktopVisible") }
    private func buildMenu() {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem(); menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 DayNest", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 DayNest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        let editItem = NSMenuItem(); editItem.title = "编辑"; menu.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "DayNest")
        let statusMenu = NSMenu()
        let main = statusMenu.addItem(withTitle: "打开 DayNest", action: #selector(openMain), keyEquivalent: ""); main.target = self
        let widget = statusMenu.addItem(withTitle: "显示 / 隐藏桌面小窗", action: #selector(toggleDesktop), keyEquivalent: ""); widget.target = self
        let sync = statusMenu.addItem(withTitle: "同步 CCF-A 会议", action: #selector(syncFeed), keyEquivalent: ""); sync.target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = statusMenu
    }
    @objc private func openMain() { showMain() }
    @objc private func toggleDesktop() { if desktop?.isVisible == true { hideDesktop() } else { showDesktop() } }
    @objc private func syncFeed() { Task { await store.refresh() } }
}
