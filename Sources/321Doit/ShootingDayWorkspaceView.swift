import SwiftUI

private enum ShootingDayViewMode: String, CaseIterable, Identifiable {
    case calendar
    case list

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .calendar: return L10n.t("日历", "Calendar", language: language)
        case .list: return L10n.t("列表", "List", language: language)
        }
    }
}

private struct ShootingCalendarCell: Identifiable {
    var id: Date { date }
    let date: Date
    let isCurrentMonth: Bool
    let day: ShootingDay?
}

private enum InlineSuggestionMode {
    case replace
    case appendCommaSeparated
}

private enum ShootingDateFormatters {
    static let zhMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        return formatter
    }()

    static let enMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    static let zhLongDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .full
        return formatter
    }()

    static let enLongDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .full
        return formatter
    }()
}

struct ShootingDayWorkspaceView: View {
    @ObservedObject var store: ScriptLogStore
    @Binding var selection: Workspace
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @State private var viewMode: ShootingDayViewMode = .calendar
    @State private var visibleMonth: Date = Date()
    @State private var exportFormat: CallSheetExportFormat = .html
    @State private var selectedCalendarDates: Set<Date> = []
    @State private var dragStartPoint: CGPoint?
    @State private var dragCurrentPoint: CGPoint?

    private let calendar = Calendar(identifier: .gregorian)
    private let calendarCellHeight: CGFloat = 56
    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var selectedDay: ShootingDay? {
        if selectedCalendarDates.count == 1, let date = selectedCalendarDates.first {
            return shootingDay(on: date)
        }
        if selectedCalendarDates.count > 1 {
            let days = selectedBatchDays
            return days.count == selectedCalendarDates.count ? days.first : nil
        }
        return store.currentShootingDay ?? store.project.shootingDays.first
    }

    private var selectedSingleUnscheduledDate: Date? {
        guard selectedCalendarDates.count == 1, let date = selectedCalendarDates.first else { return nil }
        return shootingDay(on: date) == nil ? date : nil
    }

    private var selectedBatchDays: [ShootingDay] {
        guard selectedCalendarDates.count > 1 else { return [] }
        return store.project.shootingDays
            .filter { selectedCalendarDates.contains(calendar.startOfDay(for: $0.date)) }
            .sorted { $0.date < $1.date }
    }

    private var isBatchEditing: Bool {
        selectedBatchDays.count > 1 && selectedBatchDays.count == selectedCalendarDates.count
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 370)
                .background(colors.panelBg)
            Divider()

            Group {
                if let day = selectedDay {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            dayHeader(day)
                            overviewCard(day)
                            timelineCard(day)
                            scenesCard(day)
                            castCard(day)
                            departmentsCard(day)
                            locationCard(day)
                            cameraPlanCard(day)
                        }
                        .padding(20)
                        .frame(maxWidth: 920, alignment: .topLeading)
                    }
                } else if let date = selectedSingleUnscheduledDate {
                    unscheduledDateState(date)
                } else if !selectedCalendarDates.isEmpty {
                    unscheduledSelectionState
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(colors.surfaceBg)

            Divider()
            inspector
                .frame(width: 300)
                .background(colors.panelBg)
        }
        .onAppear {
            if let day = selectedDay {
                visibleMonth = day.date
                selectedCalendarDates = [calendar.startOfDay(for: day.date)]
                store.autofillSunTimesForAllDaysFromMacLocation()
            }
        }
        .onChange(of: store.selectedShootingDayID) { dayID in
            guard let dayID else { return }
            store.autofillSunTimesFromMacLocation(dayID: dayID)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("拍摄日历", "Shooting Calendar"))
                        .font(.system(size: 20, weight: .semibold))
                    Text("\(store.project.shootingDays.count) \(t("天", "days")) · \(store.takeCount) \(t("条场记", "script takes"))")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Button {
                    let id = store.createShootingPlanDay(on: Date())
                    if let day = store.project.shootingDays.first(where: { $0.id == id }) {
                        visibleMonth = day.date
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityIdentifier("productionPlanning.addShootingDay")
                .help(t("新建拍摄日", "New shooting day"))
            }

            HStack(spacing: 8) {
                Button(t("今天", "Today")) {
                    visibleMonth = Date()
                    selectCalendarDate(on: Date())
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .focusable(false)

                Spacer()

                Button {
                    visibleMonth = calendar.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .focusable(false)

                Text(monthTitle(visibleMonth))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 88)

                Button {
                    visibleMonth = calendar.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }

            Picker("", selection: $viewMode) {
                ForEach(ShootingDayViewMode.allCases) { mode in
                    Text(mode.label(language: lang)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                if viewMode == .calendar {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 14) {
                            calendarGrid
                            calendarSelectionPanel
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    dayList
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(18)
    }

    private var calendarGrid: some View {
        let cells = monthCells()
        return VStack(spacing: 8) {
            HStack {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(colors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(cells) { cell in
                            calendarCell(cell)
                        }
                    }
                    selectionRubberBand
                        .allowsHitTesting(false)
                }
                .highPriorityGesture(calendarSelectionDrag(cells: cells, width: proxy.size.width))
            }
            .frame(height: calendarGridHeight(for: cells.count))
        }
    }

    @ViewBuilder
    private var selectionRubberBand: some View {
        if let start = dragStartPoint, let current = dragCurrentPoint {
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colors.toolAccent(.shootingDay).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(colors.toolAccent(.shootingDay).opacity(0.72), lineWidth: 1.2)
                )
                .frame(width: max(rect.width, 2), height: max(rect.height, 2))
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder
    private var calendarSelectionPanel: some View {
        if !selectedCalendarDates.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(t("已选 \(selectedCalendarDates.count) 天", "\(selectedCalendarDates.count) day(s) selected"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                    Spacer()
                    Button(t("清除选择", "Clear")) {
                        selectedCalendarDates.removeAll()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .focusable(false)
                }

                HStack(spacing: 8) {
                    Menu {
                        ForEach(ShootingDayType.allCases) { type in
                            Button(type.label(language: lang)) {
                                applyCalendarSelection(type: type)
                            }
                        }
                    } label: {
                        Label(t("批量设类型", "Set Type"), systemImage: "tag")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Menu {
                        ForEach(ShootingDayCallSheetStatus.allCases) { status in
                            Button(status.label(language: lang)) {
                                store.setShootingPlanDaysStatus(on: Array(selectedCalendarDates), status: status)
                            }
                        }
                    } label: {
                        Label(t("批量设状态", "Set Status"), systemImage: "checklist")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        store.clearShootingPlanDaySchedules(on: Array(selectedCalendarDates))
                    } label: {
                        Label(t("清空通告", "Clear Schedules"), systemImage: "eraser")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)

                    Button(role: .destructive) {
                        store.deleteShootingPlanDays(on: Array(selectedCalendarDates))
                        selectedCalendarDates.removeAll()
                    } label: {
                        Label(t("删除拍摄日", "Delete Days"), systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(colors.inputBg.opacity(0.62), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(colors.hairline.opacity(0.65), lineWidth: 0.6)
            )
        }
    }

    private func calendarCell(_ cell: ShootingCalendarCell) -> some View {
        let normalizedDate = calendar.startOfDay(for: cell.date)
        let isSelected = selectedCalendarDates.contains(normalizedDate)
            || (selectedCalendarDates.isEmpty && cell.day?.id == store.selectedShootingDayID)
        return Button {
            selectCalendarDate(on: normalizedDate)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(dayNumberText(cell.date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(cell.isCurrentMonth ? colors.textPrimary : colors.textTertiary)
                if let day = cell.day {
                    Text(store.shootingDayCode(for: day.id))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(statusColor(day.callSheet.status))
                    Text(day.callSheet.type.label(language: lang))
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                } else {
                    Text(t("未设拍摄日", "Not scheduled"))
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textTertiary)
                        .lineLimit(1)
                    Text(t("未设置", "Unset"))
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(7)
            .frame(height: calendarCellHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(isSelected ? colors.toolAccent(.shootingDay).opacity(0.16) : colors.inputBg.opacity(cell.day == nil ? 0.25 : 0.58))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? colors.toolAccent(.shootingDay).opacity(0.62) : colors.hairline.opacity(0.55), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contextMenu {
            calendarCellMenu(cell)
        }
    }

    private func calendarGridHeight(for cellCount: Int) -> CGFloat {
        let rows = max(1, CGFloat((cellCount + 6) / 7))
        return rows * calendarCellHeight + max(0, rows - 1) * 6
    }

    private func calendarSelectionDrag(cells: [ShootingCalendarCell], width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if dragStartPoint == nil {
                    dragStartPoint = value.startLocation
                }
                dragCurrentPoint = value.location
                updateCalendarSelection(cells: cells, width: width)
            }
            .onEnded { value in
                if selectedCalendarDates.count == 1, let date = selectedCalendarDates.first {
                    selectCalendarDate(on: date)
                } else if selectedCalendarDates.count > 1 {
                    if let firstExistingDay = store.project.shootingDays
                        .filter({ selectedCalendarDates.contains(calendar.startOfDay(for: $0.date)) })
                        .sorted(by: { $0.date < $1.date })
                        .first {
                        store.selectShootingDay(firstExistingDay.id)
                        visibleMonth = firstExistingDay.date
                    } else if let first = selectedCalendarDates.sorted().first {
                        visibleMonth = first
                    }
                }
                dragStartPoint = nil
                dragCurrentPoint = nil
            }
    }

    private func calendarDate(at point: CGPoint, cells: [ShootingCalendarCell], width: CGFloat) -> Date? {
        guard width > 0, point.x >= 0, point.y >= 0 else { return nil }
        let spacing: CGFloat = 6
        let cellHeight = calendarCellHeight
        let cellWidth = (width - spacing * 6) / 7
        let col = Int(point.x / (cellWidth + spacing))
        let row = Int(point.y / (cellHeight + spacing))
        guard col >= 0, col < 7, row >= 0 else { return nil }
        let colRemainder = point.x.truncatingRemainder(dividingBy: cellWidth + spacing)
        let rowRemainder = point.y.truncatingRemainder(dividingBy: cellHeight + spacing)
        guard colRemainder <= cellWidth, rowRemainder <= cellHeight else { return nil }
        let index = row * 7 + col
        guard cells.indices.contains(index) else { return nil }
        return calendar.startOfDay(for: cells[index].date)
    }

    private func updateCalendarSelection(cells: [ShootingCalendarCell], width: CGFloat) {
        guard let start = dragStartPoint, let current = dragCurrentPoint else { return }
        let selectionRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: max(2, abs(current.x - start.x)),
            height: max(2, abs(current.y - start.y))
        )
        let dates = cells.indices.reduce(into: Set<Date>()) { selected, index in
            guard let frame = calendarCellFrame(at: index, width: width),
                  frame.intersects(selectionRect) else { return }
            selected.insert(calendar.startOfDay(for: cells[index].date))
        }
        selectedCalendarDates = dates
    }

    private func calendarCellFrame(at index: Int, width: CGFloat) -> CGRect? {
        guard width > 0 else { return nil }
        let spacing: CGFloat = 6
        let cellHeight = calendarCellHeight
        let cellWidth = (width - spacing * 6) / 7
        guard cellWidth > 0 else { return nil }
        let col = index % 7
        let row = index / 7
        return CGRect(
            x: CGFloat(col) * (cellWidth + spacing),
            y: CGFloat(row) * (cellHeight + spacing),
            width: cellWidth,
            height: cellHeight
        )
    }

    private func selectCalendarDate(on date: Date) {
        let normalized = calendar.startOfDay(for: date)
        if let day = shootingDay(on: normalized) {
            store.selectShootingDay(day.id)
        } else {
            store.selectedShootingDayID = nil
        }
        visibleMonth = normalized
        selectedCalendarDates = [normalized]
    }

    private func createShootingPlanDay(on date: Date, type: ShootingDayType) {
        let normalized = calendar.startOfDay(for: date)
        let id = store.createOrUpdateShootingPlanDay(on: normalized, type: type)
        store.selectShootingDay(id)
        visibleMonth = normalized
        selectedCalendarDates = [normalized]
    }

    private func applyCalendarSelection(type: ShootingDayType) {
        let dates = Array(selectedCalendarDates).sorted()
        store.setShootingPlanDays(on: dates, type: type)
        if let first = dates.first {
            selectDay(on: first)
            visibleMonth = first
        }
    }

    @ViewBuilder
    private func calendarCellMenu(_ cell: ShootingCalendarCell) -> some View {
        Button(t("选择这一天", "Select This Day")) {
            selectCalendarDate(on: cell.date)
        }

        Button(t("设为工作日起始", "Set As Workday Start")) {
            store.setShootingPlanStartDate(cell.date)
            visibleMonth = cell.date
        }

        Divider()

        Button(t("设为拍摄日", "Set As Shooting Day")) {
            createShootingPlanDay(on: cell.date, type: .shooting)
        }

        Button(t("设为休息日", "Set As Rest Day")) {
            createShootingPlanDay(on: cell.date, type: .rest)
        }

        Button(t("设为转场日", "Set As Travel Day")) {
            createShootingPlanDay(on: cell.date, type: .travel)
        }

        if let day = cell.day {
            Divider()
            Button(t("清空当天通告内容", "Clear This Day's Schedule"), role: .destructive) {
                store.clearShootingPlanDaySchedule(day.id)
            }
            Button(t("删除当前拍摄日", "Delete Shooting Day"), role: .destructive) {
                store.deleteShootingPlanDay(day.id)
            }
        }
    }

    private var dayList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(store.project.shootingDays.sorted(by: { $0.date < $1.date })) { day in
                    dayListRow(day)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func dayListRow(_ day: ShootingDay) -> some View {
        let isSelected = day.id == store.selectedShootingDayID
        return Button {
            store.selectShootingDay(day.id)
            visibleMonth = day.date
            selectedCalendarDates = [calendar.startOfDay(for: day.date)]
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.shootingDayCode(for: day.id))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(day.callSheet.title.isEmpty ? day.label : day.callSheet.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(shortDate(day.date))
                        .font(.system(size: 11, design: .monospaced))
                    Text("\(day.callSheet.scenePlans.count) \(t("场", "scenes"))")
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? colors.toolAccent(.shootingDay).opacity(0.16) : colors.inputBg.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? colors.toolAccent(.shootingDay).opacity(0.55) : colors.hairline.opacity(0.55), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func dayHeader(_ day: ShootingDay) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(dayCodeTitle(for: day))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    statusPill(day.callSheet.status)
                }
                Text("\(dayDateTitle(for: day)) · \(day.callSheet.type.label(language: lang))")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
                Text(day.callSheet.title.isEmpty ? t("单日工作台", "Day Workspace") : day.callSheet.title)
                    .font(.system(size: 18, weight: .semibold))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Picker("", selection: sheetBinding(day.id, \.status, default: .draft)) {
                    ForEach(ShootingDayCallSheetStatus.allCases) { status in
                        Text(status.label(language: lang)).tag(status)
                    }
                }
                .frame(width: 128)
                .labelsHidden()
                .controlSize(.small)

                Button {
                    store.duplicateShootingPlanDay(day.id)
                } label: {
                    Label(t("复制上一日", "Duplicate Day"), systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .focusable(false)
            }
        }
        .padding(18)
        .liquidGlassSurface(colors: colors, cornerRadius: 18)
    }

    private func overviewCard(_ day: ShootingDay) -> some View {
        workspaceCard(title: t("今日总览", "Day Overview"), icon: "rectangle.grid.2x2") {
            HStack(alignment: .bottom, spacing: 12) {
                if isBatchEditing {
                    labeledStaticValue(t("自然日期", "Date"), value: dayDateTitle(for: day))
                        .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                } else {
                    labeledDatePicker(t("自然日期", "Date"), selection: dayDateBinding(day.id))
                        .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                }
                labeledPicker(t("当日类型", "Day Type"), selection: sheetBinding(day.id, \.type, default: .shooting)) {
                    ForEach(ShootingDayType.allCases) { type in
                        Text(type.label(language: lang)).tag(type)
                    }
                }
                .frame(width: 190, alignment: .leading)
                Spacer(minLength: 0)
            }
            formGrid {
                labeledTimeField(t("全组到场", "Crew Call"), text: syncedSheetTimeBinding(day.id, \.callTime, category: .crewCall))
                labeledTimeField(t("预计开机", "Estimated Start"), text: syncedSheetTimeBinding(day.id, \.estimatedStartTime, category: .shooting))
                labeledTimeField(t("预计收工", "Estimated Wrap"), text: syncedSheetTimeBinding(day.id, \.estimatedWrapTime, category: .wrap))
                labeledField(t("地点", "Location"), text: mainLocationBinding(day.id), suggestions: store.project.locationMemory, clearSuggestions: store.clearLocationMemory)
                labeledField(t("天气备注", "Weather Note"), text: sheetBinding(day.id, \.weatherNote, default: ""))
                labeledTimeField(t("日出", "Sunrise"), text: sheetBinding(day.id, \.sunriseTime, default: ""))
                labeledTimeField(t("日落", "Sunset"), text: sheetBinding(day.id, \.sunsetTime, default: ""))
            }
            labeledField(t("总备注", "General Note"), text: sheetBinding(day.id, \.generalNote, default: ""))
        }
    }

    private func timelineCard(_ day: ShootingDay) -> some View {
        workspaceCard(title: t("时间安排", "Schedule"), icon: "clock") {
            VStack(spacing: 8) {
                ForEach(day.callSheet.timeline) { item in
                    HStack(spacing: 8) {
                        TimeInputField(text: timelineBinding(day.id, item.id, \.time), placeholder: "06:30")
                            .frame(width: 96)
                        timelineTitleField(day.id, item.id)
                            .frame(minWidth: 190)
                        TextField(t("备注", "Note"), text: timelineBinding(day.id, item.id, \.note))
                        Toggle("", isOn: timelineBoolBinding(day.id, item.id, \.isKeyMilestone))
                            .toggleStyle(.checkbox)
                            .help(t("关键节点", "Key milestone"))
                        removeButton {
                            updateWorktableDay(day.id) { day in
                                day.callSheet.timeline.removeAll { $0.id == item.id }
                            }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                }
                addRowButton(t("新增时间项", "Add schedule item")) {
                    updateWorktableDay(day.id) { day in
                        day.callSheet.timeline.append(DayTimelineItem(time: "", title: t("新时间项", "New item"), category: .custom))
                    }
                }
            }
        }
    }

    private func scenesCard(_ day: ShootingDay) -> some View {
        workspaceCard(title: t("今日场次", "Scenes Today"), icon: "list.bullet.rectangle") {
            VStack(spacing: 10) {
                HStack {
                    Button(t("从场记导入场次", "Import From Script Log")) {
                        store.importScriptLogScenesToCallSheet(dayID: day.id)
                        propagateBatchSelection(from: day.id)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    Button(t("推送到场记", "Push To Script Log")) {
                        store.pushCallSheetScenesToScriptLog(dayID: day.id)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    Spacer()
                }
                ForEach(day.callSheet.scenePlans) { scene in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            labeledInlineField(t("场次", "Scene"), text: sceneNumberBinding(day.id, scene.id), width: 84)
                            labeledInlineField(
                                t("地点", "Location"),
                                text: sceneBinding(day.id, scene.id, \.location),
                                suggestions: locationSuggestions(for: day),
                                width: nil
                            )
                            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                            labeledInlineField(t("内外景", "I/E"), text: sceneBinding(day.id, scene.id, \.interiorExterior), width: 84)
                            removeButton {
                                updateWorktableDay(day.id) { day in
                                    day.callSheet.scenePlans.removeAll { $0.id == scene.id }
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            labeledInlineField(t("内容摘要", "Summary"), text: sceneBinding(day.id, scene.id, \.summary))
                            labeledInlineField(
                                t("演员", "Cast"),
                                text: sceneArrayBinding(day.id, scene.id, \.cast),
                                suggestions: principalCastNames,
                                suggestionMode: .appendCommaSeparated
                            )
                            labeledInlineField(t("机位", "Units"), text: sceneArrayBinding(day.id, scene.id, \.cameraUnits))
                        }
                    }
                    .padding(10)
                    .background(colors.inputBg.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                addRowButton(t("新增场次", "Add scene")) {
                    updateWorktableDay(day.id) { day in
                        day.callSheet.scenePlans.append(DayScenePlan(sceneNumber: "\(day.callSheet.scenePlans.count + 1)", cameraUnits: ["A机"]))
                    }
                }
            }
        }
    }

    private func castCard(_ day: ShootingDay) -> some View {
        workspaceCard(title: t("演员通告", "Cast Calls"), icon: "person.2") {
            VStack(spacing: 8) {
                HStack {
                    Button {
                        store.importPrincipalCastToCallSheet(dayID: day.id)
                        propagateBatchSelection(from: day.id)
                    } label: {
                        Label(t("导入主要角色", "Import Principal Cast"), systemImage: "person.crop.rectangle.stack")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    Spacer()
                }
                ForEach(day.callSheet.castCalls) { item in
                    HStack(spacing: 8) {
                        labeledInlineField(
                            t("演员", "Performer"),
                            text: castPerformerBinding(day.id, item.id),
                            suggestions: principalCastNames
                        )
                        labeledInlineField(
                            t("角色", "Character"),
                            text: castCharacterBinding(day.id, item.id),
                            suggestions: principalCharacterNames
                        )
                        labeledInlineTimeField(t("到场", "Call"), text: castBinding(day.id, item.id, \.callTime), width: 96)
                        labeledInlineTimeField(t("化妆", "Makeup"), text: castBinding(day.id, item.id, \.makeupTime), width: 96)
                        labeledInlineField(t("备注", "Note"), text: castBinding(day.id, item.id, \.note))
                        Toggle("", isOn: castBoolBinding(day.id, item.id, \.showInExport))
                            .toggleStyle(.checkbox)
                            .help(t("显示在导出", "Show in export"))
                        removeButton {
                            updateWorktableDay(day.id) { day in
                                day.callSheet.castCalls.removeAll { $0.id == item.id }
                            }
                        }
                    }
                }
                addRowButton(t("新增演员通告", "Add cast call")) {
                    updateWorktableDay(day.id) { day in
                        day.callSheet.castCalls.append(CastCall())
                    }
                }
            }
        }
    }

    private func departmentsCard(_ day: ShootingDay) -> some View {
        workspaceCard(title: t("部门通告", "Department Calls"), icon: "person.3.sequence") {
            VStack(spacing: 8) {
                ForEach(day.callSheet.departmentCalls) { item in
                    HStack(spacing: 8) {
                        labeledInlineField(
                            t("部门", "Department"),
                            text: departmentNameBinding(day.id, item.id),
                            suggestions: departmentNames,
                            width: 130
                        )
                        labeledInlineTimeField(t("到场", "Call"), text: departmentBinding(day.id, item.id, \.callTime), width: 96)
                        labeledInlineField(t("负责人", "Lead"), text: departmentBinding(day.id, item.id, \.leadName), width: 120)
                        labeledInlineField(t("电话", "Phone"), text: departmentBinding(day.id, item.id, \.phone), width: 120)
                        labeledInlineField(t("备注", "Note"), text: departmentBinding(day.id, item.id, \.note))
                        Toggle("", isOn: departmentBoolBinding(day.id, item.id, \.showInExport))
                            .toggleStyle(.checkbox)
                            .help(t("显示在导出", "Show in export"))
                        removeButton {
                            updateWorktableDay(day.id) { day in
                                day.callSheet.departmentCalls.removeAll { $0.id == item.id }
                            }
                        }
                    }
                }
                addRowButton(t("新增部门通告", "Add department call")) {
                    updateWorktableDay(day.id) { day in
                        day.callSheet.departmentCalls.append(DepartmentCall())
                    }
                }
            }
        }
    }

    private func locationCard(_ day: ShootingDay) -> some View {
        workspaceCard(title: t("地点 / 交通 / 安全", "Location / Traffic / Safety"), icon: "location") {
            formGrid {
                labeledField(t("集合地点", "Meeting Point"), text: locationBinding(day.id, \.meetingPoint), suggestions: store.project.locationMemory, clearSuggestions: store.clearLocationMemory)
                labeledField(t("拍摄地点", "Shooting Location"), text: locationBinding(day.id, \.shootingLocation), suggestions: store.project.locationMemory, clearSuggestions: store.clearLocationMemory)
                labeledField(t("停车位置", "Parking"), text: locationBinding(day.id, \.parkingLocation), suggestions: store.project.locationMemory, clearSuggestions: store.clearLocationMemory)
                labeledField(t("转场路线", "Company Move"), text: locationBinding(day.id, \.companyMoveNote), suggestions: store.project.locationMemory, clearSuggestions: store.clearLocationMemory)
                labeledField(t("最近医院", "Nearest Hospital"), text: locationBinding(day.id, \.nearestHospital), suggestions: store.project.locationMemory, clearSuggestions: store.clearLocationMemory)
                labeledField(t("紧急联系人", "Emergency Contact"), text: locationBinding(day.id, \.emergencyContactName))
                labeledField(t("联系电话", "Emergency Phone"), text: locationBinding(day.id, \.emergencyContactPhone))
                labeledField(t("安全注意事项", "Safety Notes"), text: safetyNotesBinding(day.id))
            }
        }
    }

    private func cameraPlanCard(_ day: ShootingDay) -> some View {
        workspaceCard(title: t("摄影机 / 卡号计划", "Camera / Card Plan"), icon: "camera") {
            VStack(spacing: 10) {
                ForEach(day.callSheet.cameraPlans) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            labeledInlineField(t("机位", "Unit"), text: cameraBinding(day.id, plan.id, \.unitName), width: 80)
                            labeledInlineField(t("摄影机", "Camera"), text: cameraBinding(day.id, plan.id, \.cameraName))
                            labeledInlineField(t("镜头", "Lens"), text: cameraBinding(day.id, plan.id, \.lensNote))
                            labeledInlineField(t("卡号", "Cards"), text: cameraCardsBinding(day.id, plan.id))
                            removeButton {
                                updateWorktableDay(day.id) { day in
                                    day.callSheet.cameraPlans.removeAll { $0.id == plan.id }
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            labeledInlineField(t("记录格式", "Format"), text: cameraBinding(day.id, plan.id, \.recordingFormat))
                            labeledInlineField(t("帧率", "FPS"), text: cameraBinding(day.id, plan.id, \.frameRate), width: 80)
                            labeledInlineField(t("分辨率", "Resolution"), text: cameraBinding(day.id, plan.id, \.resolution), width: 100)
                            labeledInlineField(t("色彩模式", "Color"), text: cameraBinding(day.id, plan.id, \.colorProfile))
                        }
                    }
                    .padding(10)
                    .background(colors.inputBg.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                addRowButton(t("新增机位计划", "Add camera plan")) {
                    updateWorktableDay(day.id) { day in
                        let letter = Character(UnicodeScalar(65 + min(day.callSheet.cameraPlans.count, 25))!)
                        day.callSheet.cameraPlans.append(CameraCardPlan(unitName: "\(letter)机", expectedCardIDs: ["\(letter)01"]))
                    }
                }
            }
        }
    }

    private func ditPlanCard(_ day: ShootingDay) -> some View {
        workspaceCard(title: t("DIT / 代理 / 后期交接", "DIT / Proxy / Handoff"), icon: "externaldrive.badge.checkmark") {
            formGrid {
                labeledField(t("DIT 负责人", "DIT Lead"), text: ditBinding(day.id, \.ditName))
                labeledField(t("校验算法", "Checksum"), text: ditBinding(day.id, \.checksumAlgorithm))
                labeledField(t("主目标盘", "Primary Destination"), text: ditBinding(day.id, \.primaryDestinationName))
                labeledField(t("备份盘", "Backup Destination"), text: ditBinding(day.id, \.backupDestinationName))
                labeledField(t("代理格式", "Proxy Format"), text: ditBinding(day.id, \.proxyFormat))
                labeledField(t("备注", "Note"), text: ditBinding(day.id, \.note))
            }
            HStack(spacing: 18) {
                Toggle(t("生成 MHL", "Generate MHL"), isOn: ditBoolBinding(day.id, \.shouldGenerateMHL))
                Toggle(t("生成 PDF 报告", "Generate PDF Report"), isOn: ditBoolBinding(day.id, \.shouldGeneratePDFReport))
                Toggle(t("代理带 LUT", "Proxy With LUT"), isOn: ditBoolBinding(day.id, \.proxyWithLUT))
                Toggle(t("收工交接包", "Wrap Handoff Package"), isOn: ditBoolBinding(day.id, \.shouldGenerateHandoffPackage))
            }
            .toggleStyle(.checkbox)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("检查与导出", "Check & Export"))
                .font(.system(size: 17, weight: .semibold))

            if let day = selectedDay {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("发布前检查", "Preflight"))
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(store.callSheetChecks(dayID: day.id)) { result in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(for: result.level))
                                .foregroundStyle(color(for: result.level))
                                .frame(width: 16)
                            Text(result.message)
                                .font(.system(size: 11))
                                .foregroundStyle(colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .liquidGlassSurface(colors: colors, cornerRadius: 14)

                VStack(alignment: .leading, spacing: 10) {
                    Text(t("导出通告单", "Export Call Sheet"))
                        .font(.system(size: 12, weight: .semibold))
                    Picker("", selection: $exportFormat) {
                        ForEach(CallSheetExportFormat.allCases) { format in
                            Text(format.label(language: lang)).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    Button {
                        store.exportCallSheet(dayID: day.id, format: exportFormat)
                    } label: {
                        Label(t("导出", "Export"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(.white)
                            .background(colors.toolAccent(.shootingDay), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .controlSize(.small)
                    .buttonStyle(.plain)
                    .focusable(false)

                    Text(t("PDF 正式版与图片分享版正在适配。", "Formal PDF and image sharing versions are being adapted."))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textTertiary)
                }
                .padding(12)
                .liquidGlassSurface(colors: colors, cornerRadius: 14)

                VStack(alignment: .leading, spacing: 8) {
                    Text(t("快捷操作", "Quick Actions"))
                        .font(.system(size: 12, weight: .semibold))
                    Button(t("进入今日场记", "Open Today's Script Log")) {
                        selection = .scriptLog
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    Button(t("复制上一日", "Duplicate Day")) {
                        store.duplicateShootingPlanDay(day.id)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    Button(t("删除当前拍摄日", "Delete Current Day"), role: .destructive) {
                        store.deleteShootingPlanDay(day.id)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }
                .padding(12)
                .liquidGlassSurface(colors: colors, cornerRadius: 14)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(colors.toolAccent(.shootingDay))
            Text(t("还没有拍摄日", "No shooting days yet"))
                .font(.system(size: 18, weight: .semibold))
            Button(t("新建拍摄日", "Create Shooting Day")) {
                _ = store.createShootingPlanDay()
            }
            .buttonStyle(.borderedProminent)
            .focusable(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unscheduledDateState(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 30))
                    .foregroundStyle(colors.toolAccent(.shootingDay))
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text(longDate(date))
                        .font(.system(size: 22, weight: .semibold))
                    Text(t("这一天还没有加入拍摄计划。请选择类型后再生成对应工作台。", "This date is not in the shooting plan yet. Choose a type to create its workspace."))
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    createShootingPlanDay(on: date, type: .shooting)
                } label: {
                    Label(t("设为拍摄日", "Set Shooting Day"), systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
                .focusable(false)

                Button {
                    createShootingPlanDay(on: date, type: .rest)
                } label: {
                    Label(t("设为休息日", "Set Rest Day"), systemImage: "bed.double")
                }
                .buttonStyle(.bordered)
                .focusable(false)

                Button {
                    createShootingPlanDay(on: date, type: .travel)
                } label: {
                    Label(t("设为转场日", "Set Travel Day"), systemImage: "car")
                }
                .buttonStyle(.bordered)
                .focusable(false)
            }
        }
        .padding(24)
        .frame(maxWidth: 720, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var unscheduledSelectionState: some View {
        let missingCount = selectedCalendarDates.filter { shootingDay(on: $0) == nil }.count
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 30))
                    .foregroundStyle(colors.toolAccent(.shootingDay))
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("已选择 \(selectedCalendarDates.count) 天", "\(selectedCalendarDates.count) day(s) selected"))
                        .font(.system(size: 22, weight: .semibold))
                    Text(t(
                        "其中 \(missingCount) 天还没有加入拍摄计划。请选择类型后再生成这些日期的工作台。",
                        "\(missingCount) selected day(s) are not in the shooting plan yet. Choose a type to create workspaces for them."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(colors.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    applyCalendarSelection(type: .shooting)
                } label: {
                    Label(t("批量设为拍摄日", "Set Shooting Days"), systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
                .focusable(false)

                Button {
                    applyCalendarSelection(type: .rest)
                } label: {
                    Label(t("批量设为休息日", "Set Rest Days"), systemImage: "bed.double")
                }
                .buttonStyle(.bordered)
                .focusable(false)

                Button {
                    applyCalendarSelection(type: .travel)
                } label: {
                    Label(t("批量设为转场日", "Set Travel Days"), systemImage: "car")
                }
                .buttonStyle(.bordered)
                .focusable(false)
            }
        }
        .padding(24)
        .frame(maxWidth: 760, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func workspaceCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(colors.toolAccent(.shootingDay))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            content()
        }
        .padding(16)
        .liquidGlassSurface(colors: colors, cornerRadius: 16)
    }

    private func formGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 10) {
            content()
        }
    }

    private func labeledField(
        _ title: String,
        text: Binding<String>,
        suggestions: [String] = [],
        clearSuggestions: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            HStack(spacing: 4) {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                if !suggestions.isEmpty || clearSuggestions != nil {
                    Menu {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                text.wrappedValue = suggestion
                            }
                        }
                        if !suggestions.isEmpty, clearSuggestions != nil {
                            Divider()
                        }
                        if let clearSuggestions {
                            Button(t("清空所有记录", "Clear All Records"), role: .destructive) {
                                clearSuggestions()
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(colors.toolAccent(.shootingDay))
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(t("选择历史记录", "Pick from history"))
                }
            }
        }
    }

    private func labeledTimeField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TimeInputField(text: text)
        }
    }

    private func labeledStaticValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
                .background(colors.inputBg.opacity(0.72), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(colors.hairline.opacity(0.5), lineWidth: 0.6)
                )
        }
    }

    private func labeledInlineField(
        _ title: String,
        text: Binding<String>,
        suggestions: [String] = [],
        suggestionMode: InlineSuggestionMode = .replace,
        width: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            HStack(spacing: 4) {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                if !suggestions.isEmpty {
                    Menu {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                applySuggestion(suggestion, to: text, mode: suggestionMode)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(colors.toolAccent(.shootingDay))
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(t("选择候选项", "Pick a suggestion"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width)
    }

    private func labeledInlineTimeField(_ title: String, text: Binding<String>, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TimeInputField(text: text)
        }
        .frame(width: width)
    }

    private func labeledDatePicker(_ title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            DatePicker("", selection: selection, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.stepperField)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(colors.inputBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(colors.hairline, lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func labeledPicker<SelectionValue: Hashable, Content: View>(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Picker("", selection: selection) {
                content()
            }
            .labelsHidden()
        }
    }

    private func dateQuickMenu(_ dayID: UUID) -> some View {
        Menu {
            Button(t("今天", "Today")) {
                setDayDate(dayID, Date())
            }
            Button(t("明天", "Tomorrow")) {
                setDayDate(dayID, calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
            }
            Button(t("后天", "Day After Tomorrow")) {
                setDayDate(dayID, calendar.date(byAdding: .day, value: 2, to: Date()) ?? Date())
            }
            Divider()
            Button(t("排到当前最后一天之后", "After Last Scheduled Day")) {
                let lastDate = store.project.shootingDays.map(\.date).max() ?? Date()
                setDayDate(dayID, calendar.date(byAdding: .day, value: 1, to: lastDate) ?? lastDate)
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.toolAccent(.shootingDay))
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(t("快速选择日期", "Quick Date Picker"))
    }

    private func setDayDate(_ dayID: UUID, _ date: Date) {
        visibleMonth = date
        store.updateShootingDay(dayID) { day in
            day.date = date
        }
        store.autofillSunTimesFromMacLocation(dayID: dayID, force: true)
    }

    private var principalCastNames: [String] {
        uniqueNonEmpty(store.project.principalCast.map(\.performerName))
    }

    private var principalCharacterNames: [String] {
        uniqueNonEmpty(store.project.principalCast.map(\.characterName))
    }

    private var departmentNames: [String] {
        uniqueNonEmpty(ScriptLogStore.defaultDepartmentNames(language: lang) + store.project.departmentContacts.map(\.departmentName))
    }

    private func timelineTitleField(_ dayID: UUID, _ itemID: UUID) -> some View {
        HStack(spacing: 4) {
            TextField(t("内容", "Title"), text: timelineTitleBinding(dayID, itemID))
            Menu {
                ForEach(TimelineCategory.allCases.filter { $0 != .custom }) { category in
                    Button(category.label(language: lang)) {
                        setTimelineTitle(dayID, itemID, category: category)
                    }
                }
                Divider()
                Button(TimelineCategory.custom.label(language: lang)) {
                    setTimelineTitle(dayID, itemID, category: .custom)
                }
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.toolAccent(.shootingDay))
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(t("快捷选择时间项", "Pick a schedule item"))
        }
    }

    private func locationSuggestions(for day: ShootingDay) -> [String] {
        uniqueNonEmpty([
            day.callSheet.mainLocation,
            day.callSheet.locationInfo.shootingLocation,
            day.callSheet.locationInfo.meetingPoint
        ] + day.callSheet.scenePlans.map(\.location))
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }

    private func applySuggestion(_ suggestion: String, to binding: Binding<String>, mode: InlineSuggestionMode) {
        switch mode {
        case .replace:
            binding.wrappedValue = suggestion
        case .appendCommaSeparated:
            let existing = binding.wrappedValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if existing.contains(suggestion) {
                binding.wrappedValue = existing.joined(separator: ", ")
            } else {
                binding.wrappedValue = (existing + [suggestion]).joined(separator: ", ")
            }
        }
    }

    private func addRowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .focusable(false)
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .focusable(false)
    }

    private func statusPill(_ status: ShootingDayCallSheetStatus) -> some View {
        Text(status.label(language: lang))
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.14), in: Capsule())
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: ShootingDayCallSheetStatus) -> Color {
        switch status {
        case .empty: return colors.textTertiary
        case .draft: return colors.toolAccent(.shootingDay)
        case .published: return colors.stateSuccess
        case .revised: return colors.stateWarning
        case .completed: return Color.purple
        case .risky: return colors.stateFail
        }
    }

    private func icon(for level: CheckLevel) -> String {
        switch level {
        case .info: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "xmark.octagon"
        }
    }

    private func color(for level: CheckLevel) -> Color {
        switch level {
        case .info: return colors.stateSuccess
        case .warning: return colors.stateWarning
        case .critical: return colors.stateFail
        }
    }

    private func selectDay(on date: Date) {
        let start = calendar.startOfDay(for: date)
        if let day = shootingDay(on: start) {
            store.selectShootingDay(day.id)
        }
    }

    private func shootingDay(on date: Date) -> ShootingDay? {
        let start = calendar.startOfDay(for: date)
        return store.project.shootingDays.first { calendar.isDate($0.date, inSameDayAs: start) }
    }

    private func monthCells() -> [ShootingCalendarCell] {
        let components = calendar.dateComponents([.year, .month], from: visibleMonth)
        guard let monthStart = calendar.date(from: components),
              let daysRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) ?? monthStart
        let currentMonth = calendar.component(.month, from: monthStart)
        var daysByDate: [Date: ShootingDay] = [:]
        for day in store.project.shootingDays.sorted(by: { $0.date < $1.date }) {
            daysByDate[calendar.startOfDay(for: day.date)] = day
        }
        let cellCount = max(35, ((leading + daysRange.count + 6) / 7) * 7)
        return (0..<cellCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let day = daysByDate[calendar.startOfDay(for: date)]
            return ShootingCalendarCell(date: date, isCurrentMonth: calendar.component(.month, from: date) == currentMonth, day: day)
        }
    }

    private var weekdaySymbols: [String] {
        lang == .zh ? ["一", "二", "三", "四", "五", "六", "日"] : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }

    private func dayNumberText(_ date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }

    private func monthTitle(_ date: Date) -> String {
        (lang == .zh ? ShootingDateFormatters.zhMonth : ShootingDateFormatters.enMonth).string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        ShootingDateFormatters.shortDate.string(from: date)
    }

    private func longDate(_ date: Date) -> String {
        (lang == .zh ? ShootingDateFormatters.zhLongDate : ShootingDateFormatters.enLongDate).string(from: date)
    }

    private func dayCodeTitle(for day: ShootingDay) -> String {
        let days = selectedBatchDays
        guard days.count > 1, let first = days.first, let last = days.last else {
            return store.shootingDayCode(for: day.id)
        }
        return "\(store.shootingDayCode(for: first.id))-\(store.shootingDayCode(for: last.id))"
    }

    private func dayDateTitle(for day: ShootingDay) -> String {
        let days = selectedBatchDays
        guard days.count > 1, let first = days.first, let last = days.last else {
            return longDate(day.date)
        }
        return "\(shortDate(first.date)) - \(shortDate(last.date))"
    }

    private func updateWorktableDay(_ dayID: UUID, update: (inout ShootingDay) -> Void) {
        store.updateShootingDay(dayID, update: update)
        propagateBatchSelection(from: dayID)
    }

    private func propagateBatchSelection(from dayID: UUID) {
        guard selectedCalendarDates.count > 1 else { return }
        store.propagateCallSheet(from: dayID, to: Array(selectedCalendarDates))
    }

    private func t(_ zh: String, _ en: String) -> String {
        L10n.t(zh, en, language: lang)
    }

    private func dayDateBinding(_ dayID: UUID) -> Binding<Date> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.date ?? Date() },
            set: { value in
                visibleMonth = value
                store.updateShootingDay(dayID) { day in
                    day.date = value
                    day.callSheet.sunriseTime = ""
                    day.callSheet.sunsetTime = ""
                }
                store.autofillSunTimesFromMacLocation(dayID: dayID, force: true)
            }
        )
    }

    private func sheetBinding<Value: Equatable>(_ dayID: UUID, _ keyPath: WritableKeyPath<ShootingDayCallSheet, Value>, default defaultValue: Value) -> Binding<Value> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet[keyPath: keyPath] ?? defaultValue },
            set: { value in
                updateWorktableDay(dayID) { $0.callSheet[keyPath: keyPath] = value }
            }
        )
    }

    private func mainLocationBinding(_ dayID: UUID) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.mainLocation ?? "" },
            set: { value in
                store.updateMainLocation(dayID: dayID, value: value)
                propagateBatchSelection(from: dayID)
            }
        )
    }

    private func syncedSheetTimeBinding(
        _ dayID: UUID,
        _ keyPath: WritableKeyPath<ShootingDayCallSheet, String>,
        category: TimelineCategory
    ) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet[keyPath: keyPath] ?? "" },
            set: { value in
                updateWorktableDay(dayID) { day in
                    day.callSheet[keyPath: keyPath] = value
                    if let index = day.callSheet.timeline.firstIndex(where: { $0.category == category }) {
                        day.callSheet.timeline[index].time = value
                    }
                }
            }
        )
    }

    private func timelineBinding(_ dayID: UUID, _ itemID: UUID, _ keyPath: WritableKeyPath<DayTimelineItem, String>) -> Binding<String> {
        Binding(
            get: {
                store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.timeline.first(where: { $0.id == itemID })?[keyPath: keyPath] ?? ""
            },
            set: { value in
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.timeline.firstIndex(where: { $0.id == itemID }) else { return }
                    day.callSheet.timeline[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private func timelineTitleBinding(_ dayID: UUID, _ itemID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.timeline.first(where: { $0.id == itemID })?.title ?? ""
            },
            set: { value in
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.timeline.firstIndex(where: { $0.id == itemID }) else { return }
                    day.callSheet.timeline[index].title = value
                    let matched = TimelineCategory.allCases.first {
                        $0 != .custom && $0.label(language: lang) == value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    day.callSheet.timeline[index].category = matched ?? .custom
                }
            }
        )
    }

    private func setTimelineTitle(_ dayID: UUID, _ itemID: UUID, category: TimelineCategory) {
        updateWorktableDay(dayID) { day in
            guard let index = day.callSheet.timeline.firstIndex(where: { $0.id == itemID }) else { return }
            day.callSheet.timeline[index].category = category
            if category != .custom {
                day.callSheet.timeline[index].title = category.label(language: lang)
            }
        }
    }

    private func timelineCategoryBinding(_ dayID: UUID, _ itemID: UUID) -> Binding<TimelineCategory> {
        Binding(
            get: {
                store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.timeline.first(where: { $0.id == itemID })?.category ?? .custom
            },
            set: { value in
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.timeline.firstIndex(where: { $0.id == itemID }) else { return }
                    day.callSheet.timeline[index].category = value
                }
            }
        )
    }

    private func timelineBoolBinding(_ dayID: UUID, _ itemID: UUID, _ keyPath: WritableKeyPath<DayTimelineItem, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.timeline.first(where: { $0.id == itemID })?[keyPath: keyPath] ?? false },
            set: { value in
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.timeline.firstIndex(where: { $0.id == itemID }) else { return }
                    day.callSheet.timeline[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private func sceneBinding(_ dayID: UUID, _ sceneID: UUID, _ keyPath: WritableKeyPath<DayScenePlan, String>) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.scenePlans.first(where: { $0.id == sceneID })?[keyPath: keyPath] ?? "" },
            set: { value in
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.scenePlans.firstIndex(where: { $0.id == sceneID }) else { return }
                    day.callSheet.scenePlans[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private func sceneNumberBinding(_ dayID: UUID, _ sceneID: UUID) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.scenePlans.first(where: { $0.id == sceneID })?.sceneNumber ?? "" },
            set: { value in
                store.updateScenePlanSceneNumber(dayID: dayID, planID: sceneID, value: value)
                propagateBatchSelection(from: dayID)
            }
        )
    }

    private func sceneBoolBinding(_ dayID: UUID, _ sceneID: UUID, _ keyPath: WritableKeyPath<DayScenePlan, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.scenePlans.first(where: { $0.id == sceneID })?[keyPath: keyPath] ?? false },
            set: { value in
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.scenePlans.firstIndex(where: { $0.id == sceneID }) else { return }
                    day.callSheet.scenePlans[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private func sceneArrayBinding(_ dayID: UUID, _ sceneID: UUID, _ keyPath: WritableKeyPath<DayScenePlan, [String]>) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.scenePlans.first(where: { $0.id == sceneID })?[keyPath: keyPath].joined(separator: ", ") ?? "" },
            set: { value in
                let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.scenePlans.firstIndex(where: { $0.id == sceneID }) else { return }
                    day.callSheet.scenePlans[index][keyPath: keyPath] = parts
                }
            }
        )
    }

    private func castPerformerBinding(_ dayID: UUID, _ itemID: UUID) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.castCalls.first(where: { $0.id == itemID })?.performerName ?? "" },
            set: { value in
                let match = store.project.principalCast.first {
                    $0.performerName.trimmingCharacters(in: .whitespacesAndNewlines) == value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.castCalls.firstIndex(where: { $0.id == itemID }) else { return }
                    day.callSheet.castCalls[index].performerName = value
                    if let match {
                        day.callSheet.castCalls[index].characterName = match.characterName
                        if day.callSheet.castCalls[index].phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            day.callSheet.castCalls[index].phone = match.phone
                        }
                        if day.callSheet.castCalls[index].note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            day.callSheet.castCalls[index].note = match.note
                        }
                    }
                }
            }
        )
    }

    private func castCharacterBinding(_ dayID: UUID, _ itemID: UUID) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.castCalls.first(where: { $0.id == itemID })?.characterName ?? "" },
            set: { value in
                let match = store.project.principalCast.first {
                    $0.characterName.trimmingCharacters(in: .whitespacesAndNewlines) == value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.castCalls.firstIndex(where: { $0.id == itemID }) else { return }
                    day.callSheet.castCalls[index].characterName = value
                    if let match {
                        day.callSheet.castCalls[index].performerName = match.performerName
                        if day.callSheet.castCalls[index].phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            day.callSheet.castCalls[index].phone = match.phone
                        }
                        if day.callSheet.castCalls[index].note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            day.callSheet.castCalls[index].note = match.note
                        }
                    }
                }
            }
        )
    }

    private func castBinding(_ dayID: UUID, _ itemID: UUID, _ keyPath: WritableKeyPath<CastCall, String>) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.castCalls.first(where: { $0.id == itemID })?[keyPath: keyPath] ?? "" },
            set: { value in updateWorktableDay(dayID) { day in if let index = day.callSheet.castCalls.firstIndex(where: { $0.id == itemID }) { day.callSheet.castCalls[index][keyPath: keyPath] = value } } }
        )
    }

    private func castBoolBinding(_ dayID: UUID, _ itemID: UUID, _ keyPath: WritableKeyPath<CastCall, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.castCalls.first(where: { $0.id == itemID })?[keyPath: keyPath] ?? false },
            set: { value in updateWorktableDay(dayID) { day in if let index = day.callSheet.castCalls.firstIndex(where: { $0.id == itemID }) { day.callSheet.castCalls[index][keyPath: keyPath] = value } } }
        )
    }

    private func departmentBinding(_ dayID: UUID, _ itemID: UUID, _ keyPath: WritableKeyPath<DepartmentCall, String>) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.departmentCalls.first(where: { $0.id == itemID })?[keyPath: keyPath] ?? "" },
            set: { value in updateWorktableDay(dayID) { day in if let index = day.callSheet.departmentCalls.firstIndex(where: { $0.id == itemID }) { day.callSheet.departmentCalls[index][keyPath: keyPath] = value } } }
        )
    }

    private func departmentNameBinding(_ dayID: UUID, _ itemID: UUID) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.departmentCalls.first(where: { $0.id == itemID })?.departmentName ?? "" },
            set: { value in
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let contact = store.project.departmentContacts.first {
                    $0.departmentName.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
                }
                updateWorktableDay(dayID) { day in
                    guard let index = day.callSheet.departmentCalls.firstIndex(where: { $0.id == itemID }) else { return }
                    day.callSheet.departmentCalls[index].departmentName = value
                    if let contact {
                        if day.callSheet.departmentCalls[index].leadName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            day.callSheet.departmentCalls[index].leadName = contact.leadName
                        }
                        if day.callSheet.departmentCalls[index].phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            day.callSheet.departmentCalls[index].phone = contact.phone
                        }
                        if day.callSheet.departmentCalls[index].note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            day.callSheet.departmentCalls[index].note = contact.note
                        }
                    }
                }
            }
        )
    }

    private func departmentBoolBinding(_ dayID: UUID, _ itemID: UUID, _ keyPath: WritableKeyPath<DepartmentCall, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.departmentCalls.first(where: { $0.id == itemID })?[keyPath: keyPath] ?? false },
            set: { value in updateWorktableDay(dayID) { day in if let index = day.callSheet.departmentCalls.firstIndex(where: { $0.id == itemID }) { day.callSheet.departmentCalls[index][keyPath: keyPath] = value } } }
        )
    }

    private func locationBinding(_ dayID: UUID, _ keyPath: WritableKeyPath<LocationInfo, String>) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.locationInfo[keyPath: keyPath] ?? "" },
            set: { value in
                store.updateLocationInfo(dayID: dayID, keyPath: keyPath, value: value)
                propagateBatchSelection(from: dayID)
            }
        )
    }

    private func safetyNotesBinding(_ dayID: UUID) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.locationInfo.safetyNotes.joined(separator: "；") ?? "" },
            set: { value in
                let notes = value.split(separator: "；").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                updateWorktableDay(dayID) { $0.callSheet.locationInfo.safetyNotes = notes }
            }
        )
    }

    private func cameraBinding(_ dayID: UUID, _ itemID: UUID, _ keyPath: WritableKeyPath<CameraCardPlan, String>) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.cameraPlans.first(where: { $0.id == itemID })?[keyPath: keyPath] ?? "" },
            set: { value in updateWorktableDay(dayID) { day in if let index = day.callSheet.cameraPlans.firstIndex(where: { $0.id == itemID }) { day.callSheet.cameraPlans[index][keyPath: keyPath] = value } } }
        )
    }

    private func cameraCardsBinding(_ dayID: UUID, _ itemID: UUID) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.cameraPlans.first(where: { $0.id == itemID })?.expectedCardIDs.joined(separator: ", ") ?? "" },
            set: { value in
                let cards = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                updateWorktableDay(dayID) { day in if let index = day.callSheet.cameraPlans.firstIndex(where: { $0.id == itemID }) { day.callSheet.cameraPlans[index].expectedCardIDs = cards } }
            }
        )
    }

    private func ditBinding(_ dayID: UUID, _ keyPath: WritableKeyPath<DITPlan, String>) -> Binding<String> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.ditPlan[keyPath: keyPath] ?? "" },
            set: { value in updateWorktableDay(dayID) { $0.callSheet.ditPlan[keyPath: keyPath] = value } }
        )
    }

    private func ditBoolBinding(_ dayID: UUID, _ keyPath: WritableKeyPath<DITPlan, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.project.shootingDays.first(where: { $0.id == dayID })?.callSheet.ditPlan[keyPath: keyPath] ?? false },
            set: { value in updateWorktableDay(dayID) { $0.callSheet.ditPlan[keyPath: keyPath] = value } }
        )
    }
}
