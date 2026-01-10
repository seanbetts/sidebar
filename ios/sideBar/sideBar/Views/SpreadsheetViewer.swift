import SwiftUI

public struct SpreadsheetViewer: View {
    public let payload: SpreadsheetPayload
    @State private var selectedSheetIndex: Int = 0

    public init(payload: SpreadsheetPayload) {
        self.payload = payload
    }

    public var body: some View {
        VStack(spacing: 12) {
            if payload.sheets.isEmpty {
                PlaceholderView(title: "No spreadsheet data")
            } else {
                header
                sheetView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Sheets")
                .font(.subheadline.weight(.semibold))
            Picker("Sheet", selection: $selectedSheetIndex) {
                ForEach(payload.sheets.indices, id: \.self) { index in
                    Text(payload.sheets[index].name).tag(index)
                }
            }
            .pickerStyle(.menu)
            Spacer()
            Text("\(currentSheet.rows.count) rows")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sheetView: some View {
        let columns = maxColumnCount(for: currentSheet.rows)
        let headerRowIndex = currentSheet.headerRow
        let headerRow = headerRowIndex.flatMap { index in
            currentSheet.rows.indices.contains(index) ? currentSheet.rows[index] : nil
        }

        return ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 6) {
                if let headerRow {
                    rowView(cells: headerRow, columns: columns, isHeader: true)
                }
                ForEach(currentSheet.rows.indices, id: \.self) { rowIndex in
                    if rowIndex == headerRowIndex {
                        EmptyView()
                    } else {
                        rowView(cells: currentSheet.rows[rowIndex], columns: columns, isHeader: false)
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rowView(cells: [String], columns: Int, isHeader: Bool) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<columns, id: \.self) { columnIndex in
                Text(columnIndex < cells.count ? cells[columnIndex] : "")
                    .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(isHeader ? .primary : .secondary)
                    .frame(minWidth: 140, alignment: .leading)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .background(isHeader ? headerBackground : Color.clear)
        .cornerRadius(6)
    }

    private var currentSheet: SpreadsheetSheet {
        guard !payload.sheets.isEmpty else {
            return SpreadsheetSheet(name: "Sheet", rows: [], headerRow: nil)
        }
        let clamped = min(max(selectedSheetIndex, 0), payload.sheets.count - 1)
        return payload.sheets[clamped]
    }

    private func maxColumnCount(for rows: [[String]]) -> Int {
        rows.map { $0.count }.max() ?? 0
    }

    private var headerBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
