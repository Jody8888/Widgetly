import SwiftUI
import EventKit
import WidgetKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @State private var hasCalendarAccess = false
    @State private var isShowingScheduleSettings = false

    var body: some View {
        VStack {
            Button {
                isShowingScheduleSettings = true
            } label: {
                HStack(spacing: 10) {
                    Text("Widgetly")
                        .fontWeight(.heavy)
                        .font(.system(size: 50))
//                    Image(systemName: "slider.horizontal.3")
//                        .font(.system(size: 18, weight: .medium))
//                        .foregroundStyle(.secondary)
//                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("课表设置")
            .accessibilityHint("打开课程配置编辑器")
            .padding(.top, -50)
        }
        .padding()
        .sheet(isPresented: $isShowingScheduleSettings) {
            ScheduleSettingsView()
        }
        .onAppear {
            checkCalendarAccess()
            if !hasCalendarAccess {
                requestCalendarAccess()
            }
        }
    }

    private func checkCalendarAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        #if compiler(>=5.9)
        if #available(iOS 17.0, macOS 14.0, *) {
            hasCalendarAccess = (status == .fullAccess || status == .authorized)
        } else {
            hasCalendarAccess = (status == .authorized)
        }
        #else
        hasCalendarAccess = (status == .authorized)
        #endif
    }

    private func requestCalendarAccess() {
        let store = EKEventStore()
        #if compiler(>=5.9)
        if #available(iOS 17.0, macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { hasCalendarAccess = granted }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async { hasCalendarAccess = granted }
            }
        }
        #else
        store.requestAccess(to: .event) { granted, _ in
            DispatchQueue.main.async { hasCalendarAccess = granted }
        }
        #endif
    }
}

private struct ScheduleSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var jsonText = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isLoading = true

    private let aiPrompt = """
    请根据我提供的课表资料，生成 Widgetly 使用的 ScheduleData.json。这个文件会写入 App 的 Documents/ScheduleData.json。

    资料不完整时先向我提问，不要猜测或编造课程、日期、周次、地点或作息时间。信息明确后，只输出合法 JSON，不加 Markdown 代码围栏或解释。

    JSON 顶层结构：
    {
      "semesterStartDate": "YYYY-MM-DD",
      "totalWeeks": 16,
      "scheduleSelection": {
        "mode": "seasonal",
        "summerScheduleID": "summer",
        "winterScheduleID": "winter",
        "winterStartsOn": "MM-DD",
        "summerStartsOn": "MM-DD",
        "customScheduleID": "custom",
        "fallbackScheduleID": "summer"
      },
      "schedules": [
        { "id": "summer", "name": "夏季作息", "periods": [{ "id": 0, "start": "08:00", "end": "09:50" }] },
        { "id": "winter", "name": "冬季作息", "periods": [{ "id": 0, "start": "08:00", "end": "09:50" }] },
        { "id": "custom", "name": "自定义作息", "periods": [{ "id": 0, "start": "08:00", "end": "09:50" }] }
      ],
      "courses": [
        { "id": "mon-course-period-1", "name": "课程名", "location": "地点", "weekday": 2, "periodID": 0, "validWeeks": [1, 2, 3] }
      ]
    }

    规则：
    - weekday：1=周日、2=周一、3=周二、4=周三、5=周四、6=周五、7=周六。
    - 时段时间格式为 24 小时制 HH:mm。每套作息中的 period id 唯一；同一节次在夏季、冬季和自定义作息中使用相同 id。
    - winterStartsOn 和 summerStartsOn 是每年固定的月日，格式 MM-DD。切换日当天使用新作息，并正确处理跨年区间。若资料未提供这两个日期，先询问我。
    - 课程默认使用 periodID 对应的节次时间。课程有独立时间时，才增加 startTime 和 endTime；两项必须同时填写，格式 HH:mm。否则省略两项。
    - validWeeks 仅填写实际开课周次，范围是 1 到 totalWeeks。单双周课程列出实际开课的周次。
    - 每个课程条目使用唯一且稳定的英文 id。课程在不同星期、节次或周次安排不同时，分别生成条目。
    - 常规季节自动切换时 mode 使用 seasonal。使用自定义作息时 mode 使用 custom，并填写 customScheduleID。
    - 输出前检查 JSON 语法、日期、节次、周次、课程自定义时间成对填写，以及时段是否重叠。
    """

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Button(action: copyPrompt) {
                            Label("复制提示词", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: pasteJSON) {
                            Label("粘贴替换", systemImage: "arrow.down.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let statusMessage {
                        Label(statusMessage, systemImage: statusIsError ? "exclamationmark.circle" : "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("AI 课表生成")
                } footer: {
                   // Text("复制提示词给 AI；粘贴会替换下方编辑内容，保存后同步到 Widget。")
                }

                Section {
                    TextEditor(text: $jsonText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 380)
                        .accessibilityLabel("ScheduleData.json 编辑器")
                        .disabled(isLoading)
                } header: {
                    Text("ScheduleData.json")
                } footer: {
                    Text("文件保存在“我的 iPhone / Widgetly”中。")
                }
            }
            .navigationTitle("课表设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: saveJSON)
                        .disabled(isLoading || jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: loadJSON)
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }

    private func loadJSON() {
        do {
            jsonText = try ScheduleStore.loadDocumentJSON()
            statusMessage = nil
        } catch {
            statusMessage = "读取失败：\(error.localizedDescription)"
            statusIsError = true
        }
        isLoading = false
    }

    private func copyPrompt() {
        #if canImport(UIKit)
        UIPasteboard.general.string = aiPrompt
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(aiPrompt, forType: .string)
        #endif
        statusIsError = false
        statusMessage = "提示词已复制。"
    }

    private func pasteJSON() {
        #if canImport(UIKit)
        let pastedText = UIPasteboard.general.string
        #elseif canImport(AppKit)
        let pastedText = NSPasteboard.general.string(forType: .string)
        #else
        let pastedText: String? = nil
        #endif

        guard let pastedText, !pastedText.isEmpty else {
            statusIsError = true
            statusMessage = "剪贴板中没有可粘贴的文本。"
            return
        }
        jsonText = pastedText
        statusIsError = false
        statusMessage = "内容已替换；检查后点“保存”生效。"
    }

    private func saveJSON() {
        do {
            try ScheduleStore.saveDocumentJSON(jsonText)
            WidgetCenter.shared.reloadAllTimelines()
            statusIsError = false
            statusMessage = "已保存到 Documents/ScheduleData.json，并已请求刷新 Widget。"
        } catch {
            statusIsError = true
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
