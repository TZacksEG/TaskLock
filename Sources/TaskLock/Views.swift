import SwiftUI
import TaskLockCore

private let canvas = Color(red: 0.035, green: 0.052, blue: 0.067)
private let panel = Color(red: 0.075, green: 0.097, blue: 0.112)
private let mint = Color(red: 0.58, green: 0.91, blue: 0.77)

struct LockView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                canvas.ignoresSafeArea()
                RadialGradient(colors: [mint.opacity(0.07), .clear], center: .center, startRadius: 10, endRadius: 580).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(mint)
                        Text("TASKLOCK").font(.system(size: 13, weight: .semibold, design: .rounded)).tracking(3)
                    }.environment(\.layoutDirection, .leftToRight)
                    Spacer(minLength: 24)
                    VStack(spacing: 18) {
                        Text(store.previewRemaining > 0 ? "معاينة · \(store.previewRemaining) ثانية" : Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(mint)
                        Text("وقتك لنفسك أولًا").font(.system(size: 42, weight: .bold))
                        Text("خلّص روتينك، وبعدها الماك جاهز لك.")
                            .font(.system(size: 18)).foregroundStyle(.white.opacity(0.57))
                        HStack(spacing: 12) {
                            ProgressView(value: Double(store.completedCount), total: Double(max(store.tasks.count, 1))).tint(mint)
                            Text("\(store.completedCount) / \(store.tasks.count)").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(mint)
                        }.padding(.top, 10)
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(store.tasks) { task in
                                    let done = store.completed.contains(task.id)
                                    Button { store.complete(task.id) } label: {
                                        HStack(spacing: 16) {
                                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 26, weight: .light)).foregroundStyle(done ? mint : .white.opacity(0.3))
                                            Text(task.title).font(.system(size: 19, weight: .medium)).strikethrough(done).foregroundStyle(done ? .white.opacity(0.4) : .white)
                                                .multilineTextAlignment(.leading)
                                            Spacer(minLength: 0)
                                        }.padding(.horizontal, 22).padding(.vertical, 19)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(done ? mint.opacity(0.045) : panel, in: RoundedRectangle(cornerRadius: 16))
                                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(done ? mint.opacity(0.18) : .white.opacity(0.07)))
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(done)
                                        .accessibilityLabel(task.title).accessibilityValue(done ? "مكتملة" : "غير مكتملة")
                                }
                            }
                        }.frame(maxHeight: min(360, max(130, geometry.size.height - 360)))
                            .background(InputRegionReporter { id, rect in store.updateInputRegion?(id, rect) })
                        if let error = store.errorMessage {
                            Text(error).font(.system(size: 12)).foregroundStyle(.orange).multilineTextAlignment(.center)
                        }
                    }.frame(maxWidth: min(570, geometry.size.width - 64))
                    Spacer(minLength: 24)
                    Text(store.previewRemaining > 0 ? "المعاينة تنتهي تلقائيًا · المهام هنا للتجربة فقط" : "التقدم محفوظ · الشاشة تفتح بعد إكمال كل المهام")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.32))
                }.padding(.vertical, 38).frame(maxWidth: .infinity)
            }.foregroundStyle(.white).preferredColorScheme(.dark)
        }
    }
}

private struct InputRegionReporter: NSViewRepresentable {
    var report: (Int, CGRect) -> Void
    func makeNSView(context: Context) -> RegionView { let view = RegionView(); view.report = report; return view }
    func updateNSView(_ nsView: RegionView, context: Context) { nsView.report = report; nsView.needsLayout = true }
    final class RegionView: NSView {
        var report: ((Int, CGRect) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() { super.layout(); publish() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); DispatchQueue.main.async { [weak self] in self?.publish() } }
        private func publish() {
            guard let window else { return }
            report?(window.windowNumber, window.convertToScreen(convert(bounds, to: nil)))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var draftTasks: [DailyTask] = []
    @State private var newTitle = ""
    @State private var resetHour = 0
    @State private var resetMinute = 0
    @State private var loaded = false

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ابدأ يومك بطريقتك").font(.system(size: 30, weight: .bold))
                            Text("مهام بسيطة بعيد عن الشاشة، قبل ما تبدأ استخدام الماك.")
                                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: "checkmark.shield.fill").font(.system(size: 38)).foregroundStyle(mint)
                    }

                    HStack(spacing: 10) {
                        Circle().fill(store.state.isEnabled ? mint : .white.opacity(0.3)).frame(width: 7, height: 7)
                        Text(statusText).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("TASKLOCK").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(.white.opacity(0.35))
                    }.padding(14).background(panel, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("مهامك اليومية").font(.system(size: 17, weight: .semibold))
                        if draftTasks.isEmpty {
                            Text("أضف أول مهمة، مثل: التمرين أو القراءة أو ترتيب المكان.")
                                .foregroundStyle(.white.opacity(0.4)).font(.system(size: 13)).padding(.vertical, 6)
                        }
                        ForEach($draftTasks) { $task in
                            HStack(spacing: 10) {
                                Image(systemName: "circle").foregroundStyle(mint.opacity(0.5))
                                TextField("اسم المهمة", text: $task.title).textFieldStyle(.plain)
                                Button { draftTasks.removeAll { $0.id == task.id } } label: {
                                    Image(systemName: "trash").foregroundStyle(.white.opacity(0.4))
                                }.buttonStyle(.plain).accessibilityLabel("حذف \(task.title)")
                            }.padding(13).background(panel, in: RoundedRectangle(cornerRadius: 10))
                        }
                        HStack(spacing: 10) {
                            TextField("اكتب مهمة جديدة…", text: $newTitle).textFieldStyle(.plain).onSubmit(addTask)
                            Button(action: addTask) { Image(systemName: "plus").fontWeight(.semibold) }
                                .buttonStyle(.plain).foregroundStyle(mint).disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityLabel("إضافة مهمة")
                        }.padding(13).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("بداية يوم جديد").font(.system(size: 15, weight: .semibold))
                            Text("ترجع المهام غير مكتملة في المعاد ده كل يوم.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        HStack(spacing: 3) {
                            Picker("الساعة", selection: $resetHour) { ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) } }.labelsHidden().frame(width: 65)
                            Text(":")
                            Picker("الدقيقة", selection: $resetMinute) { ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) } }.labelsHidden().frame(width: 65)
                        }.environment(\.layoutDirection, .leftToRight)
                    }

                    Divider().overlay(.white.opacity(0.08))
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: store.accessibilityGranted ? "checkmark.circle.fill" : "hand.raised.fill").foregroundStyle(store.accessibilityGranted ? mint : .orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.accessibilityGranted ? "إذن حجب الإدخال جاهز" : "إذن حجب الإدخال مطلوب").font(.system(size: 14, weight: .medium))
                                Text("Accessibility ← فعّل TaskLock").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            if !store.accessibilityGranted { Button("فتح الإعدادات") { store.requestAccessibility() }.controlSize(.small) }
                        }
                        HStack {
                            Image(systemName: "power").foregroundStyle(mint)
                            Text("تشغيل تلقائي مع دخول الماك").font(.system(size: 14))
                            Spacer()
                            Toggle("تشغيل تلقائي", isOn: Binding(get: { store.loginEnabled }, set: { store.setLoginEnabled($0) })).labelsHidden().toggleStyle(.switch).tint(mint).disabled(store.testMode)
                        }
                        if store.loginNeedsApproval { Text("وافق على TaskLock في إعدادات Login Items.").font(.system(size: 12)).foregroundStyle(.orange) }
                    }

                    if let error = store.errorMessage { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                    if !store.storageHealthy { Button("إعادة محاولة قراءة وحفظ المهام") { store.retryStorage() } }

                    HStack(spacing: 12) {
                        Button {
                            if !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addTask() }
                            store.saveRoutine(tasks: draftTasks, hour: resetHour, minute: resetMinute)
                        } label: {
                            Text("حفظ وتفعيل الروتين").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 22).padding(.vertical, 12)
                                .background(mint, in: Capsule()).foregroundStyle(canvas)
                        }.buttonStyle(.plain).disabled(!store.storageHealthy || !store.accessibilityGranted || (draftTasks.isEmpty && newTitle.isEmpty))
                            .opacity(store.accessibilityGranted ? 1 : 0.45)
                        Button("معاينة ١٥ ثانية") { store.preview?() }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        if store.state.isEnabled { Button("إيقاف الروتين") { store.disableRoutine() }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.4)).font(.system(size: 12)) }
                    }
                    Text("بعد التفعيل، استخدام الماك يتوقف لحد إكمال المهام. كل بياناتك بتفضل على جهازك.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
                }.padding(32)
            }
        }.foregroundStyle(.white).preferredColorScheme(.dark)
            .onAppear { if !loaded { reloadDraft() } }
            .onChange(of: store.configurationRevision) { _, _ in reloadDraft() }
    }

    private var statusText: String {
        if !store.storageHealthy { return "تعذّر تحميل المهام المحفوظة" }
        if !store.state.isEnabled { return "جاهز لإعداد روتينك" }
        if store.state.isComplete { return "روتين النهارده خلص · الماك متاح لباقي اليوم" }
        return store.accessibilityGranted ? "الروتين مفعّل" : "الروتين محفوظ · في انتظار الإذن"
    }
    private func addTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draftTasks.append(DailyTask(title: trimmed))
        newTitle = ""
    }
    private func reloadDraft() {
        draftTasks = store.state.tasks
        resetHour = store.state.resetHour
        resetMinute = store.state.resetMinute
        loaded = true
    }
}
