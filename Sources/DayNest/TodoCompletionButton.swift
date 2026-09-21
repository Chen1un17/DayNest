import SwiftUI

/// Completion feedback is shared by the main window and the desktop panel.
struct TodoCompletionButton: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: Todo
    let size: CGFloat
    @State private var burst = 0
    @State private var phase: CGFloat = 0
    @State private var celebrating = false

    var body: some View {
        Button { store.toggle(item) } label: {
            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size))
                .foregroundStyle(item.completed ? accent : muted.opacity(0.65))
                .scaleEffect(celebrating && !reduceMotion ? 1 + 0.25 * (1 - phase) : 1)
                .overlay {
                    if celebrating && !reduceMotion {
                        ZStack {
                            ForEach(0..<7) { index in
                                let angle = Double(index) * .pi * 2 / 7
                                Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                                    .font(.system(size: index.isMultiple(of: 2) ? 7 : 4))
                                    .foregroundStyle(index.isMultiple(of: 2) ? Color.orange : accent)
                                    .offset(x: cos(angle) * (8 + 20 * phase), y: sin(angle) * (8 + 20 * phase))
                                    .opacity(Double(1 - phase))
                            }
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .frame(width: size + 6, height: size + 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.completed ? "标记未完成：\(item.title)" : "完成待办：\(item.title)")
        .help(item.completed ? "标记未完成" : "完成待办")
        .onChange(of: item.completed) { _, completed in
            if completed { burst += 1 }
            else { celebrating = false }
        }
        .task(id: burst) {
            guard burst > 0, item.completed, !reduceMotion else { return }
            phase = 0
            celebrating = true
            do {
                try await Task.sleep(for: .milliseconds(35))
                guard item.completed else { celebrating = false; return }
                withAnimation(.easeOut(duration: 0.6)) { phase = 1 }
                try await Task.sleep(for: .milliseconds(650))
                celebrating = false
            } catch { celebrating = false }
        }
    }
}
