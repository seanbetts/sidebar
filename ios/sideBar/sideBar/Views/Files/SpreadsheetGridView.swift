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

    private var cachedAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
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
        cachedAttributes.removeAll()

        let columnCount = collectionView.numberOfItems(inSection: 0)
        let rowCount = collectionView.numberOfItems(inSection: 1) / max(columnCount, 1)
        let fittedWidth = max(
            minColumnWidth,
            containerWidth > 0 ? containerWidth / max(CGFloat(columnCount), 1) : columnWidth
        )

        for column in 0..<columnCount {
            let indexPath = IndexPath(item: column, section: 0)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = CGRect(
                x: CGFloat(column) * fittedWidth,
                y: 0,
                width: fittedWidth,
                height: headerHeight
            )
            attributes.zIndex = 2
            cachedAttributes[indexPath] = attributes
        }

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let indexPath = IndexPath(item: row * columnCount + column, section: 1)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                attributes.frame = CGRect(
                    x: CGFloat(column) * fittedWidth,
                    y: headerHeight + CGFloat(row) * rowHeight,
                    width: fittedWidth,
                    height: rowHeight
                )
                cachedAttributes[indexPath] = attributes
            }
        }

        let width = CGFloat(columnCount) * fittedWidth
        let height = headerHeight + CGFloat(rowCount) * rowHeight
        contentSize = CGSize(width: width, height: height)
    }

    override var collectionViewContentSize: CGSize {
        contentSize
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView = collectionView else { return nil }
        let offsetY = collectionView.contentOffset.y
        return cachedAttributes.values.compactMap { attributes in
            if attributes.frame.intersects(rect) {
                if attributes.indexPath.section == 0 {
                    guard let adjusted = attributes.copy() as? UICollectionViewLayoutAttributes else {
                        return attributes
                    }
                    adjusted.frame.origin.y = offsetY
                    adjusted.zIndex = 3
                    return adjusted
                }
                return attributes
            }
            return nil
        }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        true
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
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
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
        if isHeader {
            label.font = UIFont.preferredFont(forTextStyle: .subheadline).bold()
            label.textColor = UIColor.label
            contentView.backgroundColor = UIColor.secondarySystemBackground
        } else {
            label.font = UIFont.preferredFont(forTextStyle: .subheadline)
            label.textColor = UIColor.secondaryLabel
            contentView.backgroundColor = UIColor.systemBackground
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
