import EditorCore

extension BlendMode {
    /// Название в списке режимов панели слоёв.
    public func title(russian: Bool) -> String {
        let names: (String, String)
        switch self {
        case .normal: names = ("Normal", "Обычный")
        case .darken: names = ("Darken", "Затемнение")
        case .multiply: names = ("Multiply", "Умножение")
        case .colorBurn: names = ("Color Burn", "Затемнение основы")
        case .linearBurn: names = ("Linear Burn", "Линейный затемнитель")
        case .darkerColor: names = ("Darker Color", "Темнее")
        case .lighten: names = ("Lighten", "Осветление")
        case .screen: names = ("Screen", "Экран")
        case .colorDodge: names = ("Color Dodge", "Осветление основы")
        case .linearDodge: names = ("Linear Dodge (Add)", "Линейный осветлитель (добавить)")
        case .lighterColor: names = ("Lighter Color", "Светлее")
        case .overlay: names = ("Overlay", "Перекрытие")
        case .softLight: names = ("Soft Light", "Мягкий свет")
        case .hardLight: names = ("Hard Light", "Жёсткий свет")
        case .vividLight: names = ("Vivid Light", "Яркий свет")
        case .linearLight: names = ("Linear Light", "Линейный свет")
        case .pinLight: names = ("Pin Light", "Точечный свет")
        case .hardMix: names = ("Hard Mix", "Жёсткое смешение")
        case .difference: names = ("Difference", "Разница")
        case .exclusion: names = ("Exclusion", "Исключение")
        case .subtract: names = ("Subtract", "Вычитание")
        case .divide: names = ("Divide", "Разделить")
        case .hue: names = ("Hue", "Цветовой тон")
        case .saturation: names = ("Saturation", "Насыщенность")
        case .color: names = ("Color", "Цветность")
        case .luminosity: names = ("Luminosity", "Яркость")
        case .passThrough: names = ("Pass Through", "Пропустить")
        case .behind: names = ("Behind", "Подложка")
        }
        return russian ? names.1 : names.0
    }

    /// Порядок и группы в списке, как в панели образца (между группами — разделитель).
    public static let menuGroups: [[BlendMode]] = [
        [.passThrough, .normal, .behind],
        [.darken, .multiply, .colorBurn, .linearBurn, .darkerColor],
        [.lighten, .screen, .colorDodge, .linearDodge, .lighterColor],
        [.overlay, .softLight, .hardLight, .vividLight, .linearLight, .pinLight, .hardMix],
        [.difference, .exclusion, .subtract, .divide],
        [.hue, .saturation, .color, .luminosity],
    ]
}
