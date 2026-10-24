@testable import EditorCore
import Foundation
import XCTest

final class ZipTests: XCTestCase {
    func testWriteReadStored() throws {
        var w = ZipWriter()
        try w.add("document.sqlite", [1, 2, 3])
        try w.add("tiles/a/0_0", Array(repeating: 7, count: 1000))
        let r = try ZipReader(try w.finish())
        XCTAssertEqual(r.entries.map(\.name), ["document.sqlite", "tiles/a/0_0"])
        XCTAssertEqual(try r.read("document.sqlite"), [1, 2, 3])
        XCTAssertEqual(try r.read("tiles/a/0_0"), Array(repeating: 7, count: 1000))
        XCTAssertThrowsError(try r.read("нет"))
    }

    func testReadsDeflatedZipFromPython() throws {
        // zipfile.ZIP_DEFLATED из Python: 'привет '×50 и bytes(range(256))×3.
        let b64 = "UEsDBBQAAAAIAGM6UV2U2dxZFwAAAIoCAAAFAAAAYS50eHS7sP9iw4UdFzZd2HqxSeHCKGeUM1AcAFBLAwQUAAAACABjOlFdKt/AsBYBAAAAAwAACQAAAGRpci9iLmJpbmNgZGJmYWVj5+Dk4ubh5eMXEBQSFhEVE5eQlJKWkZWTV1BUUlZRVVPX0NTS1tHV0zcwNDI2MTUzt7C0sraxtbN3cHRydnF1c/fw9PL28fXzDwgMCg4JDQuPiIyKjomNi09ITEpOSU1Lz8jMys7JzcsvKCwqLiktK6+orKquqa2rb2hsam5pbWvv6Ozq7unt658wcdLkKVOnTZ8xc9bsOXPnzV+wcNHiJUuXLV+xctXqNWvXrd+wcdPmLVu3bd+xc9fuPXv37T9w8NDhI0ePHT9x8tTpM2fPnb9w8dLlK1evXb9x89btO3fv3X/w8NHjJ0+fPX/x8tXrN2/fvf/w8dPnL1+/ff/x89fvP3///WcY9f+I9j8AUEsBAhQDFAAAAAgAYzpRXZTZ3FkXAAAAigIAAAUAAAAAAAAAAAAAAIABAAAAAGEudHh0UEsBAhQDFAAAAAgAYzpRXSrfwLAWAQAAAAMAAAkAAAAAAAAAAAAAAIABOgAAAGRpci9iLmJpblBLBQYAAAAAAgACAGoAAAB3AQAAAAA="
        let r = try ZipReader([UInt8](Data(base64Encoded: b64)!))
        XCTAssertEqual(String(decoding: try r.read("a.txt"), as: UTF8.self), String(repeating: "привет ", count: 50))
        XCTAssertEqual(try r.read("dir/b.bin"), Array((0..<768).map { UInt8($0 % 256) }))
    }
}

final class DocumentFileTests: XCTestCase {
    func gradient(_ w: Int, _ h: Int, depth: BitDepth) -> Bitmap {
        var img = FloatImage(width: w, height: h, channels: 4)
        for y in 0..<h {
            for x in 0..<w {
                img[x, y, 0] = Float(x) / Float(w)
                img[x, y, 1] = Float(y) / Float(h)
                img[x, y, 2] = Float((x * 31 + y * 17) % 97) / 96
                img[x, y, 3] = x % 7 == 0 ? 0 : 1
            }
        }
        return Bitmap(image: img, depth: depth)
    }

    func sampleDocument(depth: BitDepth) -> Document {
        var doc = Document(width: 300, height: 270, depth: depth)
        let bg = Layer.bitmap(name: "Фон", gradient(300, 270, depth: depth))
        var top = Layer.bitmap(name: "Сверху", gradient(40, 30, depth: depth), at: PixelPoint(x: 250, y: 100))
        top.opacity = 0.37
        top.blendMode = .vividLight
        var maskImage = FloatImage(width: 20, height: 10, channels: 1)
        for i in maskImage.data.indices { maskImage.data[i] = Float(i % 20) / 19 }
        var mask = LayerMask(bitmap: Bitmap(image: maskImage, depth: depth), offset: PixelPoint(x: 255, y: 105), backgroundValue: 0)
        mask.density = 0.8
        mask.isInverted = true
        top.masks = [mask, .revealAll()]
        var clipped = Layer.bitmap(name: "Обтравка", gradient(10, 10, depth: depth), at: PixelPoint(x: 260, y: 110))
        clipped.isClippingMask = true
        var hidden = Layer.bitmap(name: "Скрытый", gradient(5, 5, depth: depth))
        hidden.isVisible = false
        hidden.isLocked = true
        let group = Layer.group(name: "Группа", [hidden, Layer(name: "Текст", content: .unsupported(kind: "text"))], blendMode: .normal)
        doc.layers = [bg, top, clipped, group]
        return doc
    }

    func assertSame(_ a: Document, _ b: Document) throws {
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.depth, b.depth)
        func flatten(_ l: [Layer]) -> [Layer] { l.flatMap { x -> [Layer] in if case .group(let c) = x.content { return [x] + flatten(c) } else { return [x] } } }
        let la = flatten(a.layers), lb = flatten(b.layers)
        XCTAssertEqual(la.map(\.id), lb.map(\.id))
        XCTAssertEqual(la.map(\.name), lb.map(\.name))
        XCTAssertEqual(la.map(\.opacity), lb.map(\.opacity))
        XCTAssertEqual(la.map(\.blendMode), lb.map(\.blendMode))
        XCTAssertEqual(la.map(\.isClippingMask), lb.map(\.isClippingMask))
        XCTAssertEqual(la.map(\.isVisible), lb.map(\.isVisible))
        XCTAssertEqual(la.map(\.isLocked), lb.map(\.isLocked))
        XCTAssertEqual(la.map(\.position), lb.map(\.position))
        XCTAssertEqual(la.map { $0.masks.map(\.density) }, lb.map { $0.masks.map(\.density) })
        XCTAssertEqual(la.map { $0.masks.map(\.isInverted) }, lb.map { $0.masks.map(\.isInverted) })
        // Пиксели: рендер документа до и после — побитно одинаков.
        let ra = try CPURenderer.render(a), rb = try CPURenderer.render(b)
        XCTAssertEqual(ra.image, rb.image)
        XCTAssertEqual(ra.unsupported.map(\.id), rb.unsupported.map(\.id))
    }

    func testRoundTrip16() throws {
        let doc = sampleDocument(depth: .u16)
        let bytes = try DocumentFile.save(doc)
        try assertSame(doc, try DocumentFile.load(bytes))
        let zip = try ZipReader(bytes)
        XCTAssertTrue(zip.contains("preview.png"))
        XCTAssertNoThrow(try PNG.decode(try zip.read("preview.png")))
    }

    func testRoundTrip8() throws {
        let doc = sampleDocument(depth: .u8)
        try assertSame(doc, try DocumentFile.load(try DocumentFile.save(doc)))
    }

    func testRejectsForeignFilesAndNewerVersions() throws {
        XCTAssertThrowsError(try DocumentFile.load([1, 2, 3])) { XCTAssertEqual($0 as? DocumentFileError, .notADocument) }
        var w = ZipWriter()
        try w.add("hello.txt", [1])
        XCTAssertThrowsError(try DocumentFile.load(try w.finish())) { XCTAssertEqual($0 as? DocumentFileError, .notADocument) }
        let db = try SQLiteDatabase.serialize { db in
            try db.execute(DocumentFile.schema)
            try db.query("INSERT INTO info VALUES ('format_version', '99')")
        }
        var w2 = ZipWriter()
        try w2.add("document.sqlite", db)
        XCTAssertThrowsError(try DocumentFile.load(try w2.finish())) { XCTAssertEqual($0 as? DocumentFileError, .newerFormat(99)) }
    }
}
