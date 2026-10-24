import SwiftUI
import QuotaCore

struct DashboardView: View {
    let store: QuotaStore
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    GlassEffectContainer(spacing: 24) {
                    VStack(alignment: .leading, spacing: 24) {
                        heading
                        if store.isSignedIn || displayedSnapshot != nil {
                            if let snapshot = displayedSnapshot { quotaContent(snapshot) }
                            else { initialLoad }
                        } else { loginContent }
                        if let message = store.message {
                            status(message, symbol: "exclamationmark.circle", color: .orange)
                        }
                        if let warning = store.sharingWarning {
                            status(warning, symbol: "square.grid.2x2", color: .secondary)
                        }
                        footnote
                    }
                    .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 36)
                    }
                }
                .refreshable { await store.refresh() }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Codex 额度").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        Button { Task { await store.refresh() } } label: {
                            if store.isRefreshing { ProgressView() }
                            else { Image(systemName: "arrow.clockwise") }
                        }
                        .disabled(!store.isSignedIn || store.isRefreshing || (store.retryAt.map { $0 > context.date } ?? false))
                        .accessibilityLabel("刷新额度")
                    }
                }
            }
        }
    }
    private var displayedSnapshot: QuotaSnapshot? {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            let json = #"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":28,"limit_window_seconds":18000,"reset_at":RESET1},"secondary_window":{"used_percent":44,"limit_window_seconds":604800,"reset_at":RESET2}}}"#
                .replacingOccurrences(of: "RESET1", with: String(Int(Date().addingTimeInterval(9240).timeIntervalSince1970)))
                .replacingOccurrences(of: "RESET2", with: String(Int(Date().addingTimeInterval(280800).timeIntervalSince1970)))
            return (try? JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8)))?.snapshot(at: Date())
        }
        #endif
        return store.snapshot
    }
    private var background: some View {
        ZStack(alignment: .topTrailing) {
            Color(uiColor: .systemGroupedBackground)
            Circle().fill(Color.quotaMint.opacity(0.17)).frame(width: 340, height: 340)
                .blur(radius: 85).offset(x: 110, y: -140)
            Circle().fill(Color.quotaBlue.opacity(0.09)).frame(width: 260, height: 260)
                .blur(radius: 75).offset(x: -180, y: 350)
        }.ignoresSafeArea()
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(Color.quotaMint).frame(width: 6, height: 6)
                Text("YOUR CODING CAPACITY").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
            }.foregroundStyle(.secondary)
            Text("每一份额度，\n心中有数。")
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1)
            if store.isSignedIn {
                Label((store.snapshot?.plan ?? "ChatGPT").uppercased(), systemImage: "person.crop.circle")
                    .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
    private var loginContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "terminal").font(.system(size: 38, weight: .light)).foregroundStyle(Color.quotaMint)
                .padding(.top, 8)
            Text("连接你的 Codex").font(.title2.bold())
            Text("使用 ChatGPT 账号授权，即可查看剩余额度、重置时间和桌面小组件。")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let code = store.deviceCode {
                VStack(alignment: .leading, spacing: 14) {
                    Text("你的登录授权码").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(code.userCode).font(.system(.title, design: .monospaced, weight: .bold)).textSelection(.enabled)
                        Spacer()
                        ShareLink(item: code.userCode) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("分享或复制登录码")
                    }
                    Button { openURL(code.verificationURL) } label: {
                        Label("前往 OpenAI 授权", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent).controlSize(.large)
                    Text("在官方网页输入上方代码，完成后返回这里。代码 15 分钟有效。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("取消登录", role: .cancel) { store.cancelLogin() }.font(.subheadline)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    let coolingDown = store.retryAt.map { $0 > context.date } ?? false
                    Button { store.startLogin() } label: {
                        HStack {
                            if store.isLoggingIn { ProgressView() }
                            Text(store.isLoggingIn ? "正在生成授权码…" : coolingDown ? "稍后可重新登录" : "使用 ChatGPT 登录")
                            Image(systemName: "arrow.right")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent).controlSize(.large)
                        .disabled(store.isLoggingIn || coolingDown)
                }
            }
            Label("密码仅在 OpenAI 官方网页输入", systemImage: "lock.shield")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(.primary.opacity(0.06)))
    }
    private var initialLoad: some View {
        VStack(spacing: 16) {
            if store.isRefreshing { ProgressView("正在读取账号额度…") }
            else {
                Image(systemName: "arrow.triangle.2.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                Text("尚未取得额度数据").font(.headline)
                Button("重新读取") { Task { await store.refresh() } }.buttonStyle(.glass)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 42).modifier(GlassSurface())
    }
    private func quotaContent(_ snapshot: QuotaSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 18) {
                if snapshot.windows.isEmpty {
                    status("账号已连接，但服务暂未返回额度窗口。", symbol: "questionmark.circle", color: .secondary)
                }
                ForEach(snapshot.windows) { window in
                    quotaCard(window, now: context.date)
                }
                if let next = snapshot.nextReset(after: context.date) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.quotaMint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("下一次重置").font(.caption).foregroundStyle(.secondary)
                            Text(next, format: .dateTime.month().day().hour().minute()).font(.headline)
                        }
                        Spacer()
                        Text(timerInterval: context.date...next, countsDown: true)
                            .monospacedDigit().font(.callout.weight(.medium)).frame(maxWidth: 110)
                    }.padding(20).modifier(GlassSurface())
                }
                HStack(spacing: 6) {
                    Circle().fill(snapshot.isStale(at: context.date) ? Color.orange : Color.quotaMint).frame(width: 5, height: 5)
                    Text(snapshot.isStale(at: context.date) ? "数据待更新" : "最近同步")
                    Text(snapshot.fetchedAt, format: .dateTime.hour().minute())
                    Spacer()
                }.font(.caption2).foregroundStyle(.secondary)
                #if targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
                    Text("设计预览 · 示例数据").font(.caption).foregroundStyle(.orange)
                }
                #endif
            }
        }
    }
    private func quotaCard(_ window: QuotaWindow, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(window.title).font(.headline)
                Spacer()
                Image(systemName: window.id == "primary" ? "bolt" : "calendar").foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                QuotaRing(percent: window.remainingPercent, tint: window.id == "primary" ? .quotaMint : .quotaBlue)
                    .frame(width: 156, height: 156)
                VStack(alignment: .leading, spacing: 9) {
                    Text("下次重置").font(.caption).foregroundStyle(.secondary)
                    ResetLabel(window: window, now: now)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if window.needsResetRefresh(at: now) {
                Text("等待重新查询，当前百分比为上次记录。")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(24).frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(.primary.opacity(0.06)))
    }
    private func status(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.07), in: .rect(cornerRadius: 18))
    }
    private var footnote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CODEX QUOTA").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
            Text("非 OpenAI 官方应用 · 额度以账号服务返回为准")
                .font(.caption2)
        }.foregroundStyle(.tertiary).padding(.top, 6)
    }
}
