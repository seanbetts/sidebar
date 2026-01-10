import SwiftUI

public struct SpreadsheetViewer: View {
    public let payload: SpreadsheetPayload
    @State private var selectedSheetIndex: Int = 0
    @State private var filterText: String = ""
    @State private var sortColumn: Int? = nil
    @State private var sortDirection: SortDirection = .ascending
    @State private var baseRowsPerView: Int = 1
    @State private var loadMorePages: Int = 0
    @State private var tableHeight: CGFloat = 0
    private let minimumRowHeight: CGFloat = 32

    public init(payload: SpreadsheetPayload) {
        self.payload = payload
    }

    public var body: some View {
        VStack(spacing: 12) {
            if payload.sheets.isEmpty {
                PlaceholderView(title: "No spreadsheet data")
            } else {
                header
                controls
                sheetView
                pagination
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .onChange(of: payload.sheets.count) { _, _ in
            ensureValidSheetIndex()
        }
        .onChange(of: selectedSheetIndex) { _, _ in
            resetPaging()
        }
        .onChange(of: filterText) { _, _ in
            resetPaging()
            updateRowsPerPage()
        }
        .onChange(of: sortColumn) { _, _ in
            resetPaging()
            updateRowsPerPage()
        }
        .onChange(of: sortDirection) { _, _ in
            resetPaging()
            updateRowsPerPage()
        }
        .onChange(of: tableHeight) { _, _ in
            updateRowsPerPage()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Sheets")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(currentSheet.rows.count) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if payload.sheets.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(payload.sheets.indices, id: \.self) { index in
                            Button {
                                selectedSheetIndex = index
                            } label: {
                                Text(payload.sheets[index].name.isEmpty ? "Sheet \(index + 1)" : payload.sheets[index].name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(index == selectedSheetIndex ? .primary : .secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(index == selectedSheetIndex ? tabSelectedBackground : tabBackground)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            TextField("Filter rows", text: $filterText)
                .textFieldStyle(.plain)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(controlBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(controlBorder, lineWidth: 1)
        )
    }

    private var sheetView: some View {
        GeometryReader { proxy in
            #if os(iOS)
            SpreadsheetGridView(
                headers: columnLabels,
                rows: visibleRows,
                numericColumns: numericColumns,
                columnWidth: 160,
                rowHeight: minimumRowHeight,
                onHeaderTap: toggleSort
            )
            .onAppear {
                updateTableHeight(proxy.size.height)
            }
            .onChange(of: proxy.size) { _, newSize in
                updateTableHeight(newSize.height)
            }
            #else
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section(header: headerRowView) {
                        if visibleRows.isEmpty {
                            Text("No data")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(visibleRows.indices, id: \.self) { index in
                                dataRowView(row: visibleRows[index])
                            }
                        }
                    }
                }
            }
            .onAppear {
                updateTableHeight(proxy.size.height)
            }
            .onChange(of: proxy.size) { _, newSize in
                updateTableHeight(newSize.height)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dataRowView(row: [String]) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<columnCount, id: \.self) { columnIndex in
                Text(columnIndex < row.count ? row[columnIndex] : "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 140, alignment: alignmentForColumn(columnIndex))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(rowBackground)
    }

    private var currentSheet: SpreadsheetSheet {
        guard !payload.sheets.isEmpty else {
            return SpreadsheetSheet(name: "Sheet", rows: [], headerRow: nil)
        }
        let clamped = min(max(selectedSheetIndex, 0), payload.sheets.count - 1)
        return payload.sheets[clamped]
    }

    private var headerRowIndex: Int? {
        currentSheet.headerRow
    }

    private var headerRow: [String] {
        guard let index = headerRowIndex, currentSheet.rows.indices.contains(index) else {
            return []
        }
        return currentSheet.rows[index]
    }

    private var hasHeaderLabels: Bool {
        headerRow.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var columnCount: Int {
        currentSheet.rows.reduce(headerRow.count) { max($0, $1.count) }
    }

    private var columnLabels: [String] {
        guard hasHeaderLabels else {
            return Array(repeating: "", count: columnCount)
        }
        return headerRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var dataRows: [[String]] {
        guard let headerRowIndex else { return currentSheet.rows }
        return currentSheet.rows.enumerated().compactMap { index, row in
            index == headerRowIndex ? nil : row
        }
    }

    private var filteredRows: [[String]] {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return dataRows }
        let needle = trimmed.lowercased()
        return dataRows.filter { row in
            row.joined(separator: " ").lowercased().contains(needle)
        }
    }

    private var sortedRows: [[String]] {
        guard let sortColumn else { return filteredRows }
        return filteredRows.sorted { lhs, rhs in
            let left = sortColumn < lhs.count ? lhs[sortColumn] : ""
            let right = sortColumn < rhs.count ? rhs[sortColumn] : ""
            let comparison = left.compare(right, options: .numeric)
            if sortDirection == .ascending {
                return comparison == .orderedAscending
            }
            return comparison == .orderedDescending
        }
    }

    private var visibleRows: [[String]] {
        let total = sortedRows.count
        let pages = max(1, loadMorePages + 1)
        let rowsToShow = min(total, baseRowsPerView * pages)
        return Array(sortedRows.prefix(rowsToShow))
    }

    private var numericColumns: [Bool] {
        (0..<columnCount).map { columnIndex in
            for row in dataRows {
                guard columnIndex < row.count else { continue }
                let value = row[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty { continue }
                return Double(value) != nil
            }
            return false
        }
    }

    private var headerRowView: some View {
        HStack(spacing: 12) {
            ForEach(0..<columnCount, id: \.self) { columnIndex in
                Button {
                    toggleSort(columnIndex)
                } label: {
                    HStack(spacing: 6) {
                        Text(columnLabels[safe: columnIndex] ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if sortColumn == columnIndex {
                            Image(systemName: sortDirection == .ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 140, alignment: alignmentForColumn(columnIndex))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(columnLabels[safe: columnIndex]?.isEmpty == false
                    ? columnLabels[safe: columnIndex] ?? ""
                    : "Column \(columnIndex + 1)")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(headerBackground)
    }

    private var pagination: some View {
        let total = sortedRows.count
        let shown = visibleRows.count
        return HStack {
            if shown < total {
                Button("Load more") {
                    loadMorePages += 1
                }
                .buttonStyle(.bordered)
            } else {
                Text(total == 0 ? "No rows" : "All rows loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func updateTableHeight(_ height: CGFloat) {
        if abs(tableHeight - height) > 1 {
            tableHeight = height
        }
    }

    private func updateRowsPerPage() {
        guard tableHeight > 0 else {
            return
        }
        let headerHeight = minimumRowHeight
        let usable = max(0, tableHeight - headerHeight)
        let rows = max(1, Int(usable / minimumRowHeight))
        if rows != baseRowsPerView {
            baseRowsPerView = rows
            loadMorePages = 0
        }
    }

    private func resetPaging() {
        loadMorePages = 0
    }

    private func ensureValidSheetIndex() {
        if selectedSheetIndex >= payload.sheets.count {
            selectedSheetIndex = 0
        }
    }

    private func toggleSort(_ columnIndex: Int) {
        if sortColumn == columnIndex {
            sortDirection = sortDirection == .ascending ? .descending : .ascending
        } else {
            sortColumn = columnIndex
            sortDirection = .ascending
        }
    }

    private func alignmentForColumn(_ columnIndex: Int) -> Alignment {
        guard let firstRow = dataRows.first else { return .leading }
        guard columnIndex < firstRow.count else { return .leading }
        let value = firstRow[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(value) != nil ? .trailing : .leading
    }

    private enum SortDirection {
        case ascending
        case descending
    }

    private var headerBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var rowBackground: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    private var tabBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var tabSelectedBackground: Color {
        #if os(macOS)
        return Color(nsColor: .selectedContentBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var controlBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var controlBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
