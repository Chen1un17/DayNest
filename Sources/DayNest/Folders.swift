import SwiftUI

struct FolderManagerView: View {
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var editing: TodoFolder?
    @State private var deleting: TodoFolder?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("待办文件夹").font(.title2.bold())
            Text("普通文件夹显示在桌面；会议文件夹独立保存，可从常驻会议进入。").font(.caption).foregroundStyle(muted)
            HStack {
                TextField("新文件夹名称", text: $name).textFieldStyle(.roundedBorder).onSubmit(create)
                Button("新建", action: create).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.folders) { folder in
                        HStack {
                            Button { AppDelegate.shared.showFolder(folder) } label: {
                                Label(folder.name, systemImage: folder.conferenceKey == nil ? "folder" : "graduationcap")
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Text("\(store.folderTodos(folder.id).count) 项").font(.caption).foregroundStyle(muted)
                            if folder.conferenceKey == nil {
                                Button("重命名") { editing = folder }
                                Button("删除", role: .destructive) { deleting = folder }
                            } else { Text("会议专属").font(.caption).foregroundStyle(accent) }
                        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if store.folders.isEmpty { empty("创建第一个文件夹", "例如：工作、学习、生活。已有待办可在编辑时选择文件夹。", icon: "folder.badge.plus") }
                }
            }
        }.padding(24).frame(minWidth: 500, minHeight: 400).background(canvas).tint(accent).preferredColorScheme(.light)
        .sheet(item: $editing) { folder in FolderNameEditor(folder: folder).environmentObject(store) }
        .alert("删除文件夹？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除文件夹", role: .destructive) { if let deleting { store.deleteRegularFolder(deleting.id) }; deleting = nil }
        } message: { Text("其中的待办会移到「未分类」，不会删除待办内容。") }
    }
    private func create() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        store.putFolder(TodoFolder(name: value)); name = ""
    }
}

struct FolderNameEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var folder: TodoFolder
    var body: some View {
        VStack(spacing: 18) {
            Text("重命名文件夹").font(.headline)
            TextField("名称", text: $folder.name).textFieldStyle(.roundedBorder)
            editorButtons(valid: !folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                folder.name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
                store.putFolder(folder); dismiss()
            } cancel: { dismiss() }
        }.padding(24).frame(width: 350)
    }
}

struct FolderTasksView: View {
    @EnvironmentObject var store: Store
    let folderID: UUID
    @State private var editor: Todo?
    @State private var query = ""
    private var folder: TodoFolder? { store.folders.first { $0.id == folderID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label(folder?.name ?? "文件夹已删除", systemImage: folder?.conferenceKey == nil ? "folder" : "graduationcap").font(.title2.bold())
                    Text(folder?.conferenceKey == nil ? "此文件夹的全部待办 · 不限日期" : "会议专属待办 · 不显示在桌面普通待办中").font(.caption).foregroundStyle(muted)
                }
                Spacer()
                Button {
                    var todo = Todo(); todo.folderID = folderID; editor = todo
                } label: { Label("新增待办", systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(folder == nil)
            }
            TextField("搜索标题或备注…", text: $query).textFieldStyle(.roundedBorder)
            if let error = store.storageError { banner(error, color: .red) }
            let items = store.folderTodos(folderID).filter { query.isEmpty || ($0.title + $0.notes).localizedCaseInsensitiveContains(query) }
            Text("已完成 \(items.filter(\.completed).count) / \(items.count)").font(.caption).foregroundStyle(muted)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            TodoCompletionButton(item: item, size: 20)
                            Button { editor = item } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    TodoText(item: item, compact: false)
                                    Text(item.due.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(muted)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("编辑标题、备注或删除事项")
                            if item.completed { Text("已完成").font(.caption).foregroundStyle(accent) }
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if items.isEmpty { empty("暂无待办", "点击新增待办，开始整理这个文件夹。", icon: "checklist") }
                }
            }
        }.padding(24).frame(minWidth: 500, minHeight: 400).background(canvas).foregroundStyle(ink).tint(accent).preferredColorScheme(.light)
        .sheet(item: $editor) { item in TodoEditor(item: item) { store.put($0) }.environmentObject(store) }
    }
}
