import CoreGraphics
import Foundation

/// One server on the map, running or stopped. A stopped one keeps its old size and draws dashed.
public struct MapItem: Equatable {
    public let id: String
    public let project: String
    public let port: Int
    public let memory: UInt64
    public let idle: Bool
    public let stopped: Bool

    public init(id: String, project: String, port: Int, memory: UInt64, idle: Bool, stopped: Bool) {
        self.id = id
        self.project = project
        self.port = port
        self.memory = memory
        self.idle = idle
        self.stopped = stopped
    }
}

public struct MapTile: Equatable {
    public enum Kind: Equatable {
        case server(MapItem, showsProject: Bool)
        case more([MapItem])
        case free
    }
    public let kind: Kind
    public let frame: CGRect
    public let color: Int
}

let tileGap: CGFloat = 4
let tileInset: CGFloat = 2
let minColumnWidth: CGFloat = 72
let minFreeWidth: CGFloat = 56
let minTileHeight: CGFloat = 40

/// One column per project, biggest first, with its servers stacked inside. What can't fit legibly
/// folds into a "+N more" tile. `capacity` is what the full width stands for.
public func layoutTreemap(items: [MapItem], capacity: UInt64, size: CGSize) -> [MapTile] {
    let projects = Dictionary(grouping: items, by: \.project)
        .map { (name: $0.key, items: $0.value.sorted { $0.memory > $1.memory }) }
        .sorted { total($0.items) != total($1.items) ? total($0.items) > total($1.items) : $0.name < $1.name }

    let width = size.width - 2 * tileInset
    let height = size.height - 2 * tileInset
    let fit = max(1, Int((width + tileGap) / (minColumnWidth + tileGap)))
    var columns = projects.map(\.items)
    if columns.count > fit {
        columns = Array(columns.prefix(fit - 1)) + [Array(columns.dropFirst(fit - 1).joined())]
    }

    let gaps = CGFloat(max(columns.count - 1, 0)) * tileGap
    let scale = width / CGFloat(max(capacity, total(items), 1))
    var widths = columns.map { max(minColumnWidth, CGFloat(total($0)) * scale) }
    var freeWidth = width - gaps - widths.reduce(0, +) - tileGap
    if columns.isEmpty { freeWidth = width }
    if freeWidth < minFreeWidth {
        freeWidth = 0
        let spare = max(width - gaps - CGFloat(columns.count) * minColumnWidth, 0)
        let sum = CGFloat(max(total(items), 1))
        widths = columns.map { minColumnWidth + spare * CGFloat(total($0)) / sum }
    }

    var tiles: [MapTile] = []
    var x = tileInset
    for (index, column) in columns.enumerated() {
        let foldedProjects = Set(column.map(\.project)).count > 1
        let frames = stack(column, height: height, folded: foldedProjects)
        var y = tileInset
        for (kind, tileHeight) in frames {
            let frame = CGRect(x: x, y: y, width: widths[index], height: tileHeight)
            tiles.append(MapTile(kind: kind, frame: frame, color: index))
            y += tileHeight + tileGap
        }
        x += widths[index] + tileGap
    }
    if freeWidth > 0 {
        tiles.append(MapTile(kind: .free, frame: CGRect(x: x, y: tileInset, width: freeWidth, height: height), color: 0))
    }
    return tiles
}

private func stack(_ items: [MapItem], height: CGFloat, folded: Bool) -> [(MapTile.Kind, CGFloat)] {
    if folded { return [(.more(items), height)] }
    if items.count == 1 { return [(.server(items[0], showsProject: true), height)] }
    let fit = max(1, Int((height + tileGap) / (minTileHeight + tileGap)))
    let maxTiles = min(fit, 3)
    let shown = items.count > maxTiles ? Array(items.prefix(maxTiles - 1)) : items
    let rest = items.count > maxTiles ? Array(items.dropFirst(maxTiles - 1)) : []
    let count = shown.count + (rest.isEmpty ? 0 : 1)
    let gaps = CGFloat(count - 1) * tileGap
    let spare = max(height - gaps - CGFloat(count) * minTileHeight, 0)
    let sum = CGFloat(max(total(shown), 1))
    var result: [(MapTile.Kind, CGFloat)] = shown.map {
        (.server($0, showsProject: false), minTileHeight + spare * CGFloat($0.memory) / sum)
    }
    if !rest.isEmpty { result.append((.more(rest), minTileHeight)) }
    return result
}

private func total(_ items: [MapItem]) -> UInt64 {
    items.reduce(0) { $0 + $1.memory }
}

/// Words for how full the budget is, using the meter's two marks.
public enum BudgetStatus: Equatable {
    case roomToSpare, gettingFull, almostFull, overBudget

    public init(used: UInt64, budget: UInt64) {
        let share = Double(used) / Double(max(budget, 1))
        self = share > 1 ? .overBudget : share >= 0.95 ? .almostFull : share >= 0.8 ? .gettingFull : .roomToSpare
    }

    public var title: String {
        switch self {
        case .roomToSpare: return "Room to spare"
        case .gettingFull: return "Getting full"
        case .almostFull: return "Almost full"
        case .overBudget: return "Over budget"
        }
    }
}
