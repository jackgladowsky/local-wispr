import AppKit
import Foundation

struct PasteboardSnapshot: Equatable {
    struct Item: Equatable {
        let representations: [Representation]
    }

    struct Representation: Equatable {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    let items: [Item]

    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            let representations = item.types.compactMap { type -> Representation? in
                guard let data = item.data(forType: type) else { return nil }
                return Representation(type: type, data: data)
            }

            return Item(representations: representations)
        }

        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()

        let restoredItems = items.map { snapshotItem in
            let item = NSPasteboardItem()
            for representation in snapshotItem.representations {
                item.setData(representation.data, forType: representation.type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}
