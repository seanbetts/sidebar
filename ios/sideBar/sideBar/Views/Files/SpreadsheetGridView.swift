import SwiftUI
import sideBarShared

#if os(iOS)
import UIKit
#endif

#if os(iOS)
// MARK: - SpreadsheetGridView

struct SpreadsheetGridView: UIViewRepresentable {
    let headers: [String]
    let rows: [[String]]
    let numericColumns: [Bool]
    let columnWidth: CGFloat
    let rowHeight: CGFloat
    let onHeaderTap: (Int) -> Void

    func makeUIView(context: Context) -> UICollectionView {
        let layout = SpreadsheetGridLayout(
            columnWidth: columnWidth,
            rowHeight: rowHeight,
            headerHeight: rowHeight,
            minColumnWidth: 120
        )
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = UIColor.systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(SpreadsheetGridCell.self, forCellWithReuseIdentifier: SpreadsheetGridCell.reuseIdentifier)
        return collectionView
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.headers = headers
        context.coordinator.rows = rows
        context.coordinator.numericColumns = numericColumns
        if let layout = uiView.collectionViewLayout as? SpreadsheetGridLayout {
            layout.columnWidth = columnWidth
            layout.rowHeight = rowHeight
            layout.headerHeight = rowHeight
            layout.containerWidth = uiView.bounds.width
        }
        uiView.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(headers: headers, rows: rows, numericColumns: numericColumns, onHeaderTap: onHeaderTap)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var headers: [String]
        var rows: [[String]]
        var numericColumns: [Bool]
        let onHeaderTap: (Int) -> Void

        init(headers: [String], rows: [[String]], numericColumns: [Bool], onHeaderTap: @escaping (Int) -> Void) {
            self.headers = headers
            self.rows = rows
            self.numericColumns = numericColumns
            self.onHeaderTap = onHeaderTap
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            2
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            if section == 0 {
                return headers.count
            }
            return rows.count * max(headers.count, 1)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: SpreadsheetGridCell.reuseIdentifier,
                for: indexPath
            ) as? SpreadsheetGridCell else {
                return UICollectionViewCell()
            }

            if indexPath.section == 0 {
                let text = headers[safe: indexPath.item] ?? ""
                cell.configure(
                    text: text,
                    isHeader: true,
                    alignment: alignment(for: indexPath.item)
                )
            } else {
                let columnCount = max(headers.count, 1)
                let rowIndex = indexPath.item / columnCount
                let columnIndex = indexPath.item % columnCount
                let value = rows[safe: rowIndex]?[safe: columnIndex] ?? ""
                cell.configure(
                    text: value,
                    isHeader: false,
                    alignment: alignment(for: columnIndex)
                )
            }
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            if indexPath.section == 0 {
                onHeaderTap(indexPath.item)
            }
        }

        private func alignment(for columnIndex: Int) -> NSTextAlignment {
            let isNumeric = numericColumns[safe: columnIndex] ?? false
            return isNumeric ? .right : .left
        }
    }
}

final class SpreadsheetGridLayout: UICollectionViewLayout {
    var columnWidth: CGFloat
    var rowHeight: CGFloat
    var headerHeight: CGFloat
    var minColumnWidth: CGFloat
    var containerWidth: CGFloat = 0

    private var columnCount = 0
    private var rowCount = 0
    private var fittedColumnWidth: CGFloat = 0
    private var contentSize: CGSize = .zero

    init(columnWidth: CGFloat, rowHeight: CGFloat, headerHeight: CGFloat, minColumnWidth: CGFloat) {
        self.columnWidth = columnWidth
        self.rowHeight = rowHeight
        self.headerHeight = headerHeight
        self.minColumnWidth = minColumnWidth
        super.init()
    }

    required init?(coder: NSCoder) {
        self.columnWidth = 160
        self.rowHeight = 32
        self.headerHeight = 32
        self.minColumnWidth = 120
        super.init(coder: coder)
    }

    override func prepare() {
        guard let collectionView = collectionView else { return }

        columnCount = collectionView.numberOfItems(inSection: 0)
        rowCount = collectionView.numberOfItems(inSection: 1) / max(columnCount, 1)
        fittedColumnWidth = max(
            minColumnWidth,
            containerWidth > 0 ? containerWidth / max(CGFloat(columnCount), 1) : columnWidth
        )

        let width = CGFloat(columnCount) * fittedColumnWidth
        let height = headerHeight + CGFloat(rowCount) * rowHeight
        contentSize = CGSize(width: width, height: height)
    }

    override var collectionViewContentSize: CGSize {
        contentSize
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView = collectionView else { return nil }
        let offsetY = collectionView.contentOffset.y
        var attributes: [UICollectionViewLayoutAttributes] = []

        for column in visibleColumns(in: rect) {
            let headerAttributes = makeHeaderAttributes(column: column, offsetY: offsetY)
            if headerAttributes.frame.intersects(rect) {
                attributes.append(headerAttributes)
            }
        }

        for row in visibleRows(in: rect) {
            for column in visibleColumns(in: rect) {
                attributes.append(makeBodyAttributes(row: row, column: column))
            }
        }

        return attributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let collectionView = collectionView else { return nil }
        if indexPath.section == 0 {
            guard indexPath.item >= 0, indexPath.item < columnCount else { return nil }
            return makeHeaderAttributes(column: indexPath.item, offsetY: collectionView.contentOffset.y)
        }

        guard indexPath.section == 1, columnCount > 0 else { return nil }
        let row = indexPath.item / columnCount
        let column = indexPath.item % columnCount
        guard row >= 0, row < rowCount, column >= 0, column < columnCount else { return nil }
        return makeBodyAttributes(row: row, column: column)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        true
    }

    private func visibleColumns(in rect: CGRect) -> Range<Int> {
        guard columnCount > 0, fittedColumnWidth > 0 else { return 0..<0 }
        let start = max(0, Int(floor(rect.minX / fittedColumnWidth)))
        let end = min(columnCount - 1, Int(floor(max(rect.minX, rect.maxX - 1) / fittedColumnWidth)))
        guard start <= end else { return 0..<0 }
        return start..<(end + 1)
    }

    private func visibleRows(in rect: CGRect) -> Range<Int> {
        guard rowCount > 0, rowHeight > 0, rect.maxY >= headerHeight else { return 0..<0 }
        let bodyMinY = max(0, rect.minY - headerHeight)
        let bodyMaxY = max(0, rect.maxY - headerHeight - 1)
        let start = max(0, Int(floor(bodyMinY / rowHeight)))
        let end = min(rowCount - 1, Int(floor(bodyMaxY / rowHeight)))
        guard start <= end else { return 0..<0 }
        return start..<(end + 1)
    }

    private func makeHeaderAttributes(column: Int, offsetY: CGFloat) -> UICollectionViewLayoutAttributes {
        let indexPath = IndexPath(item: column, section: 0)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = CGRect(
            x: CGFloat(column) * fittedColumnWidth,
            y: offsetY,
            width: fittedColumnWidth,
            height: headerHeight
        )
        attributes.zIndex = 3
        return attributes
    }

    private func makeBodyAttributes(row: Int, column: Int) -> UICollectionViewLayoutAttributes {
        let indexPath = IndexPath(item: row * columnCount + column, section: 1)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = CGRect(
            x: CGFloat(column) * fittedColumnWidth,
            y: headerHeight + CGFloat(row) * rowHeight,
            width: fittedColumnWidth,
            height: rowHeight
        )
        return attributes
    }
}

final class SpreadsheetGridCell: UICollectionViewCell {
    static let reuseIdentifier = "SpreadsheetGridCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        applyFont(isHeader: false)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = UIColor.separator.cgColor
        contentView.backgroundColor = UIColor.systemBackground
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, isHeader: Bool, alignment: NSTextAlignment) {
        label.text = text
        label.textAlignment = alignment
        applyFont(isHeader: isHeader)
        if isHeader {
            label.textColor = UIColor.label
            contentView.backgroundColor = UIColor.secondarySystemBackground
        } else {
            label.textColor = UIColor.secondaryLabel
            contentView.backgroundColor = UIColor.systemBackground
        }
    }

    private func applyFont(isHeader: Bool) {
        let option = AppTextSizeOption.resolved(
            from: UserDefaults.standard.string(forKey: AppStorageKeys.appTextSize)
                ?? AppTextSizeOption.system.rawValue
        )
        switch option {
        case .system:
            label.adjustsFontForContentSizeCategory = true
            let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
            label.font = isHeader ? baseFont.bold() : baseFont
        case .small, .medium, .large:
            label.adjustsFontForContentSizeCategory = false
            label.font = UIFont.systemFont(
                ofSize: AppFontStyle.subheading.pointSize(for: option),
                weight: isHeader ? .semibold : .regular
            )
        }
    }
}

private extension UIFont {
    func bold() -> UIFont {
        return withTraits(traits: .traitBold)
    }

    func withTraits(traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
#endif
