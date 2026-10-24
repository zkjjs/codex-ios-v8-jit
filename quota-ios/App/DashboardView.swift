import SwiftUI

struct DashboardView: View {
    @StateObject private var model = QuotaModel()
    @State private var settings = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            background
            ScrollView {
                GlassGroup {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if let snapshot = model.snapshot {
                            status(snapshot)
                            ForEach(snapshot.windows) { window in QuotaCard(window: window) }
                            if snapshot.windows.isEmpty {
                                notice("暂无额度信息", detail: "账号没有返回可显示的额度窗口。", icon: "chart.bar.xaxis")
                            }
                        } else {
                            notice(model.connection == nil ? "让额度，一目了然" : "正在读取额度",
                                   detail: model.connection == nil ? "配对你的服务器，查看 Codex 剩余额度和下一次重置时间。" : "正在连接服务器上已登录的 Codex 账号。",
                                   icon: "circle.hexagongrid")
                            if model.connection == nil {
                                Button { settings = true } label: {
                                    Label("配对服务器", systemImage: "link")
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                }.modifier(GlassAction())
                            }
                        }
                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.subheadline).foregroundStyle(.orange)
                                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .modifier(GlassPanel())
                        }
                        footer
                    }.padding(24).frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                }
            }.refreshable { await model.refresh() }
        }
        .sheet(isPresented: $settings) { ConnectionView(model: model) }
        .task {
            await model.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { break }
                if scenePhase == .active { await model.refresh() }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    private var background: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            Circle().fill(Color.blue.opacity(colorScheme == .dark ? 0.24 : 0.15))
                .frame(width: 340, height: 340).blur(radius: 65).offset(x: 140, y: -280)
            Circle().fill(Color.cyan.opacity(0.12))
                .frame(width: 260, height: 260).blur(radius: 60).offset(x: -140, y: 30)
        }.ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("CODEX QUOTA").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(3).foregroundStyle(.secondary)
                Text("额度").font(.system(size: 38, weight: .bold, design: .rounded))
            }
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Group {
                    if model.loading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise").font(.title3) }
                }.frame(width: 24, height: 24).padding(9)
            }.disabled(model.loading || model.connection == nil)
                .modifier(GlassAction()).accessibilityLabel("刷新额度")
            Button { settings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).padding(9)
            }.modifier(GlassAction()).accessibilityLabel("服务器设置")
        }.padding(.top, 16)
    }

    private func status(_ snapshot: QuotaSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 8) {
                Circle().fill(snapshot.isStale(at: context.date) || model.error != nil ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(snapshot.isStale(at: context.date) || model.error != nil ? "历史数据 · 等待更新" : "已连接服务器")
                Spacer()
                if let plan = snapshot.plan { Text(plan.uppercased()).fontWeight(.semibold) }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private func notice(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(.blue)
            Text(title).font(.title2.bold())
            Text(detail).font(.subheadline).foregroundStyle(.secondary).lineSpacing(5)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(28).modifier(GlassPanel())
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = model.snapshot {
                HStack(spacing: 4) {
                    Text("上次更新")
                    Text(snapshot.updatedDate, style: .date)
                    Text(snapshot.updatedDate, style: .time)
                }
            }
            Text("额度来自服务器上的 Codex 账号。小组件按系统调度刷新。")
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
    }
}

private struct QuotaCard: View {
    let window: QuotaWindow
    private var tint: Color { window.remainingPercent <= 15 ? .orange : .blue }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label(window.title, systemImage: window.id == "primary" ? "bolt" : "calendar")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("剩余").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.remainingText).font(.system(size: 72, weight: .light, design: .rounded))
                Text("%").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "circle.dotted").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(tint.opacity(0.6))
            }.monospacedDigit()
            GeometryReader { geometry in
                Capsule().fill(tint.opacity(0.12)).overlay(alignment: .leading) {
                    Capsule().fill(tint.gradient).frame(width: max(0, geometry.size.width * window.progress))
                }
            }.frame(height: 7).accessibilityLabel("剩余百分之\(window.remainingText)")
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("距离重置").foregroundStyle(.secondary)
                        Spacer()
                        if let reset = window.resetDate, reset > context.date {
                            Text(timerInterval: context.date...reset, countsDown: true)
                                .monospacedDigit().fixedSize()
                        } else {
                            Text(window.resetDate == nil ? "未提供时间" : "等待额度更新")
                        }
                    }.font(.subheadline)
                    if let reset = window.resetDate {
                        HStack(spacing: 4) {
                            Text(reset, style: .date)
                            Text(reset, style: .time)
                            Text("重置")
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(26).modifier(GlassPanel())
    }
}
