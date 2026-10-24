#if canImport(AppKit)
import AppKit
import EditorApp
import EditorCore
import UniformTypeIdentifiers

/// Документ редактора. Свой формат — zip + SQLite + плитки (EditorCore.DocumentFile), расширение .pedoc.
/// Изображения (PNG, JPEG, HEIC, TIFF…) открываются как документ из одного слоя; сохраняются уже в своём формате,
/// в исходный файл — только через «Экспортировать…».
@objc(EditorDocument)
final class EditorDocument: NSDocument {
    static let nativeType = "ru.ect.photoeditor.document"
    static let nativeExtension = "pedoc"

    let session: EditorSession

    override init() {
        var doc = Document(width: 1920, height: 1080, depth: .u8)
        doc.layers = [.bitmap(name: AppInfo.tr("Background", "Фон"), ImageFiles.filled(width: doc.width, height: doc.height, depth: .u8, rgba: [1, 1, 1, 1]))]
        session = EditorSession(document: doc, russian: AppInfo.russian)
        super.init()
        // Отмена — своя (EditorSession.history), не NSUndoManager.
        hasUndoManager = false
    }

    /// Автосохранение как у образца (решение владельца 20.10): правки сами пишутся в файл .pedoc, в заголовке —
    /// «Изменено». Открытая картинка (PNG…) не перезаписывается: её тип не входит в writableTypes, поэтому macOS
    /// держит её как черновик и при сохранении спрашивает, куда положить .pedoc.
    override class var autosavesInPlace: Bool { true }

    override var autosavingFileType: String? { EditorDocument.nativeType }

    /// Как образца: в заголовке имя без расширения («photo_c»). Сверка 7: после автосохранения открытой картинки
    /// тип становится нашим и macOS показывала «photo_c.pedoc» — поэтому расширение убирается всегда.
    override var displayName: String! {
        get { ((super.displayName ?? "") as NSString).deletingPathExtension }
        set { super.displayName = newValue }
    }

    /// Имя открытой картинки не в нашем формате (PNG, JPEG…), без расширения; nil — документ .pedoc или новый.
    private(set) var importedName: String?

    /// Картинка открыта, но ещё не сохранена в .pedoc: всегда «изменена» (у образца под названием сразу «Изменено»).
    var isImportedImage: Bool { importedName != nil && fileURL == nil }

    override var isDocumentEdited: Bool { super.isDocumentEdited || isImportedImage }

    override func makeWindowControllers() {
        // 20.10: с автосохранением macOS сохраняла открытый PNG «на месте» в наш формат — файл photo_c.png
        // переименовывался в photo_c.pedoc. Поэтому, как в Просмотре: открытая картинка становится черновиком без файла
        // (fileURL = nil), автосохранение идёт в системную папку, «Сохранить» спрашивает, куда положить .pedoc,
        // а исходный файл не трогается никогда.
        if let type = fileType, type != EditorDocument.nativeType, let url = fileURL {
            importedName = url.deletingPathExtension().lastPathComponent
            fileURL = nil
            fileType = EditorDocument.nativeType
            displayName = importedName
            updateChangeCount(.changeDone)
        }
        let controller = EditorWindowController()
        addWindowController(controller)
        controller.attach()
    }

    /// Нетронутый пустой документ (его заменяет открытый файл).
    var isBlank: Bool { fileURL == nil && importedName == nil && !isDocumentEdited }

    override func data(ofType typeName: String) throws -> Data {
        Data(try DocumentFile.save(session.document))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let doc: Document
        if typeName == EditorDocument.nativeType {
            doc = try DocumentFile.load([UInt8](data))
        } else {
            doc = try ImageFiles.document(from: data, layerName: AppInfo.tr("Image Layer", "Слой изображения"))
        }
        session.reset(to: doc)
    }

    /// Сохранять можно только в свой формат; для открытого PNG «Сохранить» спросит имя файла.
    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] { [EditorDocument.nativeType] }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        typeName == EditorDocument.nativeType ? EditorDocument.nativeExtension : super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
    }

    /// Отметка «изменён» для заголовка окна и вопроса при закрытии.
    func noteChange(_ change: EditorSession.Change) {
        switch change {
        case .edit: updateChangeCount(.changeDone)
        case .undo: updateChangeCount(.changeUndone)
        case .redo: updateChangeCount(.changeRedone)
        case .selection, .reset: break
        }
    }
}

final class EditorDocumentController: NSDocumentController {
    /// Как Просмотр и TextEdit: нетронутый пустой документ, открытый при запуске, уступает место открытому файлу —
    /// иначе файл встаёт второй вкладкой (сверка 3, 20.10: строка вкладок сдвинула всё окно на 36 точек).
    /// Идёт запуск программы (первые 2 секунды после applicationDidFinishLaunching).
    static var launching = true

    /// Сверка 4: при запуске с файлом пустой документ создаётся, пока файл ещё открывается. Поэтому: добавлен документ
    /// с файлом → закрыть нетронутые пустые; пустой добавлен во время запуска, а файл уже есть → закрыть его.
    /// «Файл → Новый» позже не трогается.
    override func addDocument(_ document: NSDocument) {
        super.addDocument(document)
        func fromFile(_ d: NSDocument) -> Bool { d.fileURL != nil || (d as? EditorDocument)?.importedName != nil }
        guard fromFile(document) || EditorDocumentController.launching else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.documents.contains(where: fromFile) else { return }
            for doc in self.documents where (doc as? EditorDocument)?.isBlank == true { doc.close() }
        }
    }

    /// «Новый из буфера обмена»: документ размером с картинку из буфера.
    static func newFromClipboard() {
        guard let doc = PasteboardImage.read() else { NSSound.beep(); return }
        let controller = NSDocumentController.shared
        do {
            guard let editor = try controller.makeUntitledDocument(ofType: EditorDocument.nativeType) as? EditorDocument else { return }
            var d = Document(width: doc.width, height: doc.height, depth: doc.depth)
            d.layers = doc.layers
            editor.session.reset(to: d)
            controller.addDocument(editor)
            editor.makeWindowControllers()
            editor.showWindows()
        } catch {
            NSApp.presentError(error)
        }
    }
}
#endif
