import SwiftUI

struct TemplateCatalogView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var audience: TemplateAudience = .student
    @State private var selectedID = BuiltInTemplate.all.first?.id ?? ""
    @State private var variables = TemplateVariables.defaults(for: .student)
    @State private var selectedTaskIDs: Set<String> = []
    @State private var target: BuiltInTemplateTarget = .create
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var templates: [BuiltInTemplate] { BuiltInTemplate.all.filter { $0.audience == audience } }
    private var template: BuiltInTemplate { templates.first(where: { $0.id == selectedID }) ?? templates[0] }
    private var resolved: [TaskItem] { (try? store.builtInTasks(template: template, variables: variables, selectedIDs: selectedTaskIDs)) ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    audiencePicker
                    templatePicker
                    variableSection
                    previewSection
                }
                .padding(14)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 390, height: 520)
        .onAppear { resetSelection() }
        .onChange(of: audience) { _ in
            selectedID = templates.first?.id ?? ""
            variables = TemplateVariables.defaults(for: audience)
            resetSelection()
        }
        .onChange(of: selectedID) { _ in resetSelection() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Accent.gradient)
            Text("内置日程模板")
                .font(.system(size: 14, weight: .bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var audiencePicker: some View {
        Picker("", selection: $audience) {
            ForEach(TemplateAudience.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("选择模板")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            ForEach(templates) { item in
                Button {
                    selectedID = item.id
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: item.colorHex))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(size: 12.5, weight: .semibold))
                            Text(item.summary).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(item.tasks.count) 项")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        if item.id == selectedID {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: item.colorHex))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(item.id == selectedID ? Color(hex: item.colorHex).opacity(0.12) : Color.primary.opacity(0.045)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(item.id == selectedID ? Color(hex: item.colorHex).opacity(0.4) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .hoverPointing()
            }
        }
    }

    private var variableSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("按你的作息调整")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Label(audience == .student ? "上课开始" : "上班/班次开始", systemImage: "clock")
                    .font(.system(size: 11))
                Spacer()
                timeMenus($variables.startMinutes)
            }
            HStack(spacing: 8) {
                Label("通勤时长", systemImage: "figure.walk")
                    .font(.system(size: 11))
                Spacer()
                Picker("", selection: $variables.commuteMinutes) {
                    ForEach([0, 15, 20, 30, 40, 45, 60, 75, 90], id: \.self) { value in
                        Text(value == 0 ? "无需通勤" : "\(value) 分钟").tag(value)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 92)
            }
            HStack(spacing: 8) {
                Label("准备睡眠", systemImage: "moon.stars")
                    .font(.system(size: 11))
                Spacer()
                timeMenus($variables.sleepMinutes)
            }
            Text("模板会先生成可编辑预览；超出当天范围的任务会被明确拒绝，不会写入计划表。")
                .font(.system(size: 9.5)).foregroundColor(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
    }

    private func timeMenus(_ value: Binding<Int>) -> some View {
        HStack(spacing: 3) {
            Menu {
                ForEach(0..<24, id: \.self) { hour in
                    Button(String(format: "%02d 时", hour)) { value.wrappedValue = hour * 60 + value.wrappedValue % 60 }
                }
            } label: {
                Text(String(format: "%02d 时", value.wrappedValue / 60))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            }
            Menu {
                ForEach(stride(from: 0, to: 60, by: 5).map { $0 }, id: \.self) { minute in
                    Button(String(format: "%02d 分", minute)) { value.wrappedValue = value.wrappedValue / 60 * 60 + minute }
                }
            } label: {
                Text(String(format: "%02d 分", value.wrappedValue % 60))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            }
        }
        .fixedSize()
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("任务预览")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(selectedTaskIDs.count == template.tasks.count ? "全不选" : "全选") {
                    selectedTaskIDs = selectedTaskIDs.count == template.tasks.count ? [] : Set(template.tasks.map(\.id))
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
            }
            ForEach(template.tasks) { task in
                let item = try? task.resolve(with: variables)
                Button {
                    if selectedTaskIDs.contains(task.id) { selectedTaskIDs.remove(task.id) } else { selectedTaskIDs.insert(task.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selectedTaskIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundColor(selectedTaskIDs.contains(task.id) ? Color(hex: template.colorHex) : .secondary.opacity(0.55))
                        Text(task.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        Spacer()
                        if let item, let time = item.remindAt {
                            Text(item.durationMinutes.map { "\(store.timeString(time))-\(store.timeString(time + $0))" } ?? store.timeString(time))
                                .font(.system(size: 9.5, design: .monospaced)).foregroundColor(.secondary)
                        } else {
                            Text("超出当天").font(.system(size: 9.5, weight: .semibold)).foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.035)))
                }
                .buttonStyle(.plain)
                .hoverPointing()
            }
            if resolved.isEmpty && !selectedTaskIDs.isEmpty {
                Text("当前变量会让所选任务跨过 0 点，请调整开始或睡眠时间。")
                    .font(.system(size: 10)).foregroundColor(.orange)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 7) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let successMessage {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10.5)).foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Picker("", selection: $target) {
                    ForEach(BuiltInTemplateTarget.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 178)
                Spacer()
                Button(action: apply) {
                    Label(target.rawValue, systemImage: target == .create ? "plus.rectangle.on.rectangle" : "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.link)
                .disabled(selectedTaskIDs.isEmpty)
            }
            Text("已选 \(selectedTaskIDs.count) / \(template.tasks.count) 项 · 不会覆盖已有任务")
                .font(.system(size: 9.5)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private func resetSelection() {
        selectedTaskIDs = Set(template.tasks.map(\.id))
        errorMessage = nil
        successMessage = nil
    }

    private func apply() {
        do {
            let count = try store.applyBuiltInTemplate(template, variables: variables, selectedIDs: selectedTaskIDs, target: target)
            errorMessage = nil
            successMessage = target == .create ? "已创建「\(template.suggestedSheetName)」并加入 \(count) 项任务" : "已追加 \(count) 项任务到「\(store.activeSheetName)」"
            withDDAnimation { }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
