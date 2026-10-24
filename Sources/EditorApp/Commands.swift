import EditorCore
import Foundation

/// Команды меню, которые выполняет сам документ (без окна и диалогов).
/// Окно добавляет свои: открыть, сохранить, экспорт, буфер обмена, масштаб, инструменты.
extension EditorSession {
    public static let documentCommands: Set<String> = [
        "edit.undo", "edit.redo", "edit.duplicate", "edit.delete",
        "insert.emptyLayer",
        "image.rotate180", "image.rotateRight", "image.rotateLeft", "image.flipH", "image.flipV",
        "arrange.forward", "arrange.front", "arrange.backward", "arrange.back",
        "arrange.rotate180", "arrange.rotateRight", "arrange.rotateLeft", "arrange.flipH", "arrange.flipV",
        "arrange.toggleVisibility", "arrange.hide", "arrange.show", "arrange.lock", "arrange.unlock",
        "arrange.group", "arrange.ungroup", "arrange.merge", "arrange.mergeAll",
        "align.top", "align.vcenter", "align.bottom", "align.left", "align.hcenter", "align.right",
        "format.preserveTransparency",
        "mask.revealAll", "mask.hideAll", "mask.remove", "mask.enable", "mask.disable", "mask.clipping",
    ]

    /// Название пункта меню, если оно зависит от состояния (например, «Отменить Перемещение»).
    public func dynamicTitle(_ id: String) -> String? {
        switch id {
        case "edit.undo": return history.undoName.map { tr("Undo \($0)", "Отменить «\($0)»") }
        case "edit.redo": return history.redoName.map { tr("Redo \($0)", "Повторить «\($0)»") }
        case "mask.clipping":
            return primaryLayer?.isClippingMask == true ? tr("Release Clipping Mask", "Отменить обтравочную маску") : nil
        default: return nil
        }
    }

    /// Отметка «галочкой» у пунктов-переключателей.
    public func isChecked(_ id: String) -> Bool {
        switch id {
        case "format.preserveTransparency": return primaryLayer?.preserveTransparency == true
        default: return false
        }
    }

    public func canPerform(_ id: String) -> Bool {
        let layer = primaryLayer
        let siblings = primary.flatMap { document.path(of: $0) }.map { (document.siblings(of: $0), $0.last!) }
        switch id {
        case "edit.undo": return history.canUndo
        case "edit.redo": return history.canRedo
        case "insert.emptyLayer", "image.rotate180", "image.rotateRight", "image.rotateLeft", "image.flipH", "image.flipV":
            return true
        case "edit.duplicate", "edit.delete", "arrange.toggleVisibility", "arrange.group":
            return !selection.isEmpty
        case "arrange.forward", "arrange.front":
            return siblings.map { $0.1 < $0.0.count - 1 } ?? false
        case "arrange.backward", "arrange.back":
            return siblings.map { $0.1 > 0 } ?? false
        case "arrange.hide": return selection.contains { document.layer($0)?.isVisible == true }
        case "arrange.show": return selection.contains { document.layer($0)?.isVisible == false }
        case "arrange.lock": return selection.contains { document.layer($0)?.isLocked == false }
        case "arrange.unlock": return selection.contains { document.layer($0)?.isLocked == true }
        case "arrange.ungroup": return layer?.isGroup == true
        case "arrange.merge": return mergeCandidates() != nil
        case "arrange.mergeAll": return !document.layers.isEmpty
        case "arrange.rotate180", "arrange.rotateRight", "arrange.rotateLeft", "arrange.flipH", "arrange.flipV":
            return layer?.bounds != nil && layer?.isLocked == false
        case "align.top", "align.vcenter", "align.bottom", "align.left", "align.hcenter", "align.right":
            return selection.count >= 1 && layer?.bounds != nil
        case "format.preserveTransparency", "mask.revealAll", "mask.hideAll", "mask.clipping":
            return layer != nil
        case "mask.remove", "mask.invert": return layer?.masks.isEmpty == false
        case "mask.enable": return layer?.masks.contains { !$0.isEnabled } == true
        case "mask.disable": return layer?.masks.contains { $0.isEnabled } == true
        default: return false
        }
    }

    /// Выполнить команду меню. `title` — название пункта (оно же — название шага истории).
    public func run(_ id: String, title: String) throws {
        guard canPerform(id) else { return }
        switch id {
        case "edit.undo": undo()
        case "edit.redo": redo()
        case "insert.emptyLayer": insertEmptyLayer(name: title)
        case "edit.duplicate": duplicate(title)
        case "edit.delete": deleteSelected(title)
        case "image.rotate180": perform(title) { $0.transformImage(.rotate180) }
        case "image.rotateRight": perform(title) { $0.transformImage(.rotateRight) }
        case "image.rotateLeft": perform(title) { $0.transformImage(.rotateLeft) }
        case "image.flipH": perform(title) { $0.transformImage(.flipHorizontal) }
        case "image.flipV": perform(title) { $0.transformImage(.flipVertical) }
        case "arrange.forward": restack(title) { i, n in min(i + 1, n - 1) }
        case "arrange.front": restack(title) { _, n in n - 1 }
        case "arrange.backward": restack(title) { i, _ in max(i - 1, 0) }
        case "arrange.back": restack(title) { _, _ in 0 }
        case "arrange.rotate180": transformSelected(title, .rotate180)
        case "arrange.rotateRight": transformSelected(title, .rotateRight)
        case "arrange.rotateLeft": transformSelected(title, .rotateLeft)
        case "arrange.flipH": transformSelected(title, .flipHorizontal)
        case "arrange.flipV": transformSelected(title, .flipVertical)
        case "arrange.toggleVisibility":
            let show = selection.contains { document.layer($0)?.isVisible == false }
            try updateSelected(title) { $0.isVisible = show }
        case "arrange.hide": try updateSelected(title) { $0.isVisible = false }
        case "arrange.show": try updateSelected(title) { $0.isVisible = true }
        case "arrange.lock": try updateSelected(title) { $0.isLocked = true }
        case "arrange.unlock": try updateSelected(title) { $0.isLocked = false }
        case "arrange.group": group(title)
        case "arrange.ungroup": ungroup(title)
        case "arrange.merge": try merge(title)
        case "arrange.mergeAll": try mergeAll(title)
        case "align.top", "align.vcenter", "align.bottom", "align.left", "align.hcenter", "align.right": try align(id, title)
        case "format.preserveTransparency":
            let on = !(primaryLayer?.preserveTransparency ?? false)
            try updatePrimary(title) { $0.preserveTransparency = on }
        case "mask.revealAll": try updatePrimary(title) { $0.masks.append(.revealAll()) }
        case "mask.hideAll": try updatePrimary(title) { $0.masks.append(.hideAll()) }
        case "mask.remove": try updatePrimary(title) { _ = $0.masks.popLast() }
        case "mask.enable": try updatePrimary(title) { for i in $0.masks.indices { $0.masks[i].isEnabled = true } }
        case "mask.disable": try updatePrimary(title) { for i in $0.masks.indices { $0.masks[i].isEnabled = false } }
        case "mask.invert": try updatePrimary(title) { $0.masks[$0.masks.count - 1].isInverted.toggle() }
        case "mask.clipping":
            let on = !(primaryLayer?.isClippingMask ?? false)
            try updatePrimary(dynamicTitle(id) ?? title) { $0.isClippingMask = on }
        default: break
        }
    }

    // MARK: реализация

    func updateSelected(_ title: String, _ change: @escaping (inout Layer) -> Void) throws {
        let ids = selection
        try perform(title) { doc in for id in ids { try doc.updateLayer(id, change) } }
    }

    func updatePrimary(_ title: String, _ change: @escaping (inout Layer) -> Void) throws {
        guard let id = primary else { return }
        try perform(title) { try $0.updateLayer(id, change) }
    }

    /// Пустой слой над основным выбранным (в той же группе), размером с документ.
    public func insertEmptyLayer(name: String) {
        let doc = document
        let layer = Layer.bitmap(name: name, Bitmap(width: doc.width, height: doc.height, channels: 4, depth: doc.depth))
        insert([layer], title: name)
    }

    /// Вставить готовые слои над основным выбранным (вставка из буфера, импорт).
    public func insert(_ newLayers: [Layer], title: String) {
        guard !newLayers.isEmpty else { return }
        var path: LayerPath = [document.layers.count]
        if let p = primary.flatMap({ document.path(of: $0) }) { path = Array(p.dropLast()) + [p.last! + 1] }
        perform(title, select: [newLayers.last!.id]) { doc in
            for (k, l) in newLayers.enumerated() { doc.insertLayer(l, at: Array(path.dropLast()) + [path.last! + k]) }
        }
    }

    func duplicate(_ title: String) {
        let copyWord = tr("copy", "копия")
        var newSelection: [LayerID] = []
        // Внутри perform нельзя читать self.document — история в этот момент изменяется.
        let ids = topmostSelected()
        perform(title) { doc in
            for id in ids {
                guard let p = doc.path(of: id) else { continue }
                var copy = doc.layer(at: p).withFreshIDs()
                copy.name += " " + copyWord
                doc.insertLayer(copy, at: Array(p.dropLast()) + [p.last! + 1])
                newSelection.append(copy.id)
            }
        }
        select(newSelection)
    }

    func deleteSelected(_ title: String) {
        let ids = topmostSelected()
        // Новый выбор — слой, который окажется на месте основного (или ниже него).
        var next: LayerID?
        if let p = primary.flatMap({ document.path(of: $0) }) {
            let list = document.siblings(of: p).filter { !ids.contains($0.id) }
            let below = document.siblings(of: p)[..<p.last!].last { !ids.contains($0.id) }
            next = below?.id ?? list.first?.id
        }
        perform(title, select: next.map { [$0] } ?? []) { doc in
            for id in ids { if let p = doc.path(of: id) { doc.removeLayer(at: p) } }
        }
    }

    /// Перестановка основного слоя внутри своего списка: новая позиция по (текущей, числу слоёв).
    func restack(_ title: String, _ to: @escaping (Int, Int) -> Int) {
        guard let id = primary, let p = document.path(of: id) else { return }
        perform(title) { doc in
            let parent = Array(p.dropLast())
            doc.editList(parent) { list in
                let l = list.remove(at: p.last!)
                list.insert(l, at: to(p.last!, list.count + 1))
            }
        }
    }

    /// Поворот или отражение выбранного слоя вокруг центра его границ.
    func transformSelected(_ title: String, _ op: RightAngle) {
        guard let id = primary, let box = document.layer(id)?.bounds else { return }
        let w = op.swapsAxes ? box.height : box.width, h = op.swapsAxes ? box.width : box.height
        let origin = PixelPoint(x: box.x + (box.width - w) / 2, y: box.y + (box.height - h) / 2)
        perform(title) { doc in
            guard let p = doc.path(of: id) else { return }
            let l = doc.layer(at: p).transformed(op, box: box, newOrigin: origin)
            doc.removeLayer(at: p)
            doc.insertLayer(l, at: p)
        }
    }

    /// Сгруппировать выбранные слои того же списка, что и основной; группа встаёт на место верхнего из них.
    func group(_ title: String) {
        guard let id = primary, let p = document.path(of: id) else { return }
        let parent = Array(p.dropLast())
        let list = document.siblings(of: p)
        let indices = list.indices.filter { selection.contains(list[$0].id) }
        let groupLayer = Layer.group(name: tr("Group", "Группа"), indices.map { list[$0] })
        perform(title, select: [groupLayer.id]) { doc in
            doc.editList(parent) { l in
                let top = indices.last! - (indices.count - 1)
                for i in indices.reversed() { l.remove(at: i) }
                l.insert(groupLayer, at: top)
            }
        }
    }

    func ungroup(_ title: String) {
        guard let id = primary, let p = document.path(of: id) else { return }
        let g = document.layer(at: p)
        perform(title, select: g.children.map(\.id)) { doc in
            doc.editList(Array(p.dropLast())) { l in
                l.remove(at: p.last!)
                l.insert(contentsOf: g.children, at: p.last!)
            }
        }
    }

    /// Что объединяет «Объединить»: выбранные слои одного списка (≥ 2) или основной слой с нижним соседом.
    func mergeCandidates() -> (parent: LayerPath, indices: [Int])? {
        guard let id = primary, let p = document.path(of: id) else { return nil }
        let list = document.siblings(of: p)
        let chosen = list.indices.filter { selection.contains(list[$0].id) }
        if chosen.count >= 2 { return (Array(p.dropLast()), chosen) }
        guard p.last! > 0 else { return nil }
        return (Array(p.dropLast()), [p.last! - 1, p.last!])
    }

    func merge(_ title: String) throws {
        guard let candidates = mergeCandidates() else { return }
        let (parent, indices) = candidates
        let list = parent.isEmpty ? document.layers : document.layer(at: parent).children
        let parts = indices.map { list[$0] }
        let merged = try flatten(parts, name: parts.last!.name)
        perform(title, select: [merged.id]) { doc in
            doc.editList(parent) { l in
                let at = indices.last! - (indices.count - 1)
                for i in indices.reversed() { l.remove(at: i) }
                l.insert(merged, at: at)
            }
        }
    }

    func mergeAll(_ title: String) throws {
        let merged = try flatten(document.layers, name: document.layers.last?.name ?? tr("Layer", "Слой"))
        perform(title, select: [merged.id]) { $0.layers = [merged] }
    }

    /// Свести слои в один растр по границам их содержимого (внутри холста).
    func flatten(_ parts: [Layer], name: String) throws -> Layer {
        var scratch = Document(width: document.width, height: document.height, depth: document.depth)
        scratch.colorProfile = document.colorProfile
        scratch.layers = parts
        let area = (parts.compactMap(\.bounds).reduce(PixelRect(x: 0, y: 0, width: 0, height: 0)) { $0.union($1) }).intersection(document.bounds)
        guard !area.isEmpty else {
            return .bitmap(name: name, Bitmap(width: 0, height: 0, channels: 4, depth: document.depth))
        }
        let result = try CPURenderer.render(scratch, region: RenderRegion(x: area.x, y: area.y, width: area.width, height: area.height))
        return .bitmap(name: name, Bitmap(image: result.image, depth: document.depth), at: PixelPoint(x: area.x, y: area.y))
    }

    /// Выравнивание: по границам выбранных слоёв, а если выбран один — по холсту.
    func align(_ id: String, _ title: String) throws {
        let ids = topmostSelected()
        let rects = ids.compactMap { document.layer($0)?.bounds }
        guard !rects.isEmpty else { return }
        let target = rects.count == 1 ? document.bounds : rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        try perform(title) { doc in
            for lid in ids {
                guard let r = doc.layer(lid)?.bounds else { continue }
                var dx = 0, dy = 0
                switch id {
                case "align.top": dy = target.y - r.y
                case "align.bottom": dy = target.maxY - r.maxY
                case "align.vcenter": dy = (target.y + target.maxY) / 2 - (r.y + r.maxY) / 2
                case "align.left": dx = target.x - r.x
                case "align.right": dx = target.maxX - r.maxX
                default: dx = (target.x + target.maxX) / 2 - (r.x + r.maxX) / 2
                }
                try doc.updateLayer(lid) { $0.offset(dx: dx, dy: dy) }
            }
        }
    }
}
