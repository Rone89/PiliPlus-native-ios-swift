import SwiftUI

struct AccountManagementView: View {
    @EnvironmentObject private var authStore: AuthStore

    @State private var showLoginSheet = false

    var body: some View {
        List {
            Section("当前账号") {
                if let session = authStore.session, let currentMID = session.mid {
                    AccountRow(
                        title: authStore.displayName(for: session),
                        subtitle: "UID \(currentMID)",
                        isCurrent: true
                    )
                } else {
                    Text("当前未登录")
                        .foregroundStyle(.secondary)
                }
            }

            Section("已保存账号") {
                if authStore.savedSessions.isEmpty {
                    Text("还没有保存任何账号")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(authStore.savedSessions) { session in
                        let mid = session.mid
                        AccountRow(
                            title: authStore.displayName(for: session),
                            subtitle: mid.map { "UID \($0)" } ?? "未知 UID",
                            isCurrent: authStore.currentSessionMID == mid
                        )
                        .swipeActions(edge: .trailing) {
                            if let mid {
                                Button(role: .destructive) {
                                    Task {
                                        await authStore.removeAccount(mid: mid)
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if let mid, authStore.currentSessionMID != mid {
                                Button {
                                    Task {
                                        await authStore.switchTo(mid: mid)
                                    }
                                } label: {
                                    Label("切换", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .tint(AppTheme.accent)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("账号管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLoginSheet = true
                } label: {
                    Label("新增账号", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
                .environmentObject(authStore)
        }
    }
}

private struct AccountRow: View {
    let title: String
    let subtitle: String
    let isCurrent: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    if isCurrent {
                        Text("当前")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
