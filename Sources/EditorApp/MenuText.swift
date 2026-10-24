/// Главное меню: состав, порядок, клавиши, названия на английском и русском, значки SF Symbols.
/// Строка: `идентификатор | клавиши | English | Русский [| значок]`, отступ в 2 пробела — вложенность, `-` — разделитель.
/// Клавиши: модификаторы ⌃⌥⇧⌘ и сама клавиша (буква, знак, ↑↓←→, ⌫, Space). {app} — имя приложения.
/// Какие команды уже работают, решает EditorSession / окно; остальные показываются выключенными.
let mainMenuText = #"""
app | | {app} | {app}
  app.about |  | About {app} | О приложении {app}
  -
  app.settings | ⌘, | Settings… | Настройки… | gear
  -
  app.services |  | Services | Службы | gearshape.2
  -
  app.hide | ⌘H | Hide {app} | Скрыть {app} | eye.slash
  app.hideOthers | ⌥⌘H | Hide Others | Скрыть остальные | eye.slash
  app.showAll |  | Show All | Показать все | eye
  -
  app.quit | ⌘Q | Quit {app} | Завершить {app} | xmark
file | | File | Файл
  file.new | ⌘N | New… | Новый… | plus
  file.newFromClipboard | ⌥N | New from Clipboard | Новый из буфера обмена | document.on.clipboard
  file.newFromPhotos | ⌥⌘N | New from Photos… | Новый из Фото… | photo.on.rectangle
  file.open | ⌘O | Open… | Открыть…
  file.openRecent |  | Open Recent | Открыть недавние | clock
    file.clearRecent |  | Clear Menu | Очистить меню
  -
  file.close | ⌘W | Close | Закрыть
  file.save | ⌘S | Save… | Сохранить…
  file.saveAs | ⇧⌘S | Save As… | Сохранить как…
  file.revert |  | Revert to Saved | Вернуть к сохраненному
  -
  file.export | ⌘E | Export… | Экспортировать… | square.and.arrow.up.on.square
  file.exportWeb | ⇧⌘E | Export for Web… | Экспорт для веб-использования… | square.and.arrow.up.on.square
  -
  file.share |  | Share | Поделиться | square.and.arrow.up
  -
  file.import |  | Import… | Импортировать… | square.and.arrow.down.on.square
  -
  file.print | ⌘P | Print… | Напечатать…
edit | | Edit | Правка
  edit.undo | ⌘Z | Undo | Отменить
  edit.redo | ⇧⌘Z | Redo | Повторить
  -
  edit.cut | ⌘X | Cut | Вырезать
  edit.copy | ⌘C | Copy | Скопировать
  edit.copyMerged | ⌥⇧⌘C | Copy Merged | Скопировать совмещенные слои
  edit.paste | ⌘V | Paste | Вставить
  edit.pasteMatchStyle | ⌥⇧⌘V | Paste and Match Style | Вставить и согласовать стиль
  edit.pasteMatchColors | ⌃⌥⇧⌘V | Paste and Match Colors | Вставить и согласовать цвета
  edit.duplicate | ⇧⌘D | Duplicate | Дублировать
  -
  edit.delete | ⌫ | Delete | Удалить
  edit.removeBackground | ⇧⌫ | Remove Background | Удалить фон | circle.rectangle.filled.pattern.diagonalline
  -
  edit.transform | ⌘T | Transform… | Преобразование… | custom.squareshape.controlhandles.static
  edit.warp | J | Warp… | Искажение… | custom.warp
  -
  edit.selectAll | ⌘A | Select All | Выбрать все | rectangle.dashed
  edit.deselect | ⌘D | Deselect | Отменить выбор | custom.rectangle.dashed.xmark.v1
  edit.reselect |  | Reselect | Выбрать заново | custom.rectangle.dashed.arrow.clockwise
  edit.invertSelection | ⇧⌘I | Invert Selection | Инвертировать выбранное | rectangle.righthalf.filled
  -
  edit.selectSubject | ⌃S | Select Subject | Выбрать объект | person.fill.viewfinder
  edit.selectAndMask | ⌥⌘R | Select and Mask… | Выбрать и маскировать…
  edit.smartRefine | ⌥⇧⌘R | Smart Refine | Смарт-уточнение
  edit.selectColorRange |  | Select Color Range… | Выбрать цветовой диапазон…
  edit.loadSelection | ⌥⌘L | Load Selection | Загрузить выбор | custom.rectangle.dashed.plus
  edit.loadGraySelection | ⌥⇧⌘L | Load Grayscale Selection | Загрузить выбор шкалы серого
insert | | Insert | Вставка
  insert.emptyLayer | ⇧⌘N | Empty Layer | Пустой слой | square.3.layers.3d
  -
  insert.adjustments | ⇧⌘A | Color Adjustments | Цветокоррекция | icon-menu-adjustments
  insert.effects | ⇧⌘F | Effects | Эффекты | icon-menu-effects
  -
  insert.text | ⇧⌘T | Text | Текст | icon-menu-type
  insert.circularText | ⌥⇧⌘T | Circular Text | Круговой текст | icon-menu-circulartype
  insert.shape |  | Shape | Фигура | square.on.circle
    insert.shape.rect |  | Rectangle | Прямоугольник | squareshape
    insert.shape.roundRect |  | Rounded Rectangle | Прямоугольник с закругленными углами | square
    insert.shape.oval |  | Oval | Овал | oval
    insert.shape.polygon |  | Polygon | Многоугольник | pentagon
    insert.shape.star |  | Star | Звезда | star
    insert.shape.line |  | Line | Линия | line.diagonal
    -
    insert.shape.pen |  | Draw with Pen | Рисовать пером | icon-menu-draw
  insert.generateShape |  | Generate Shape… | Сгенерировать фигуру… | custom.sparkle.square.on.circle
  -
  insert.photos | ⇧⌘P | Photos or Videos… | Фото или видео… | photo.on.rectangle
  insert.takePhoto |  | Take Photo… | Снять фото… | camera
  -
  insert.choose | ⇧⌘V | Choose… | Выбрать… | folder
image | | Image | Изображение
  image.size | ⌥⌘I | Image Size… | Размер изображения… | square.resize
  image.canvasSize | ⌥⌘C | Canvas Size… | Размер холста… | square.arrowtriangle.4.outward
  image.rotate |  | Rotate Image | Поворот изображения | rectangle.landscape.rotate
    image.rotate180 |  | 180° | 180° | rectangle.landscape.rotate
    image.rotateRight |  | 90° Right | 90° вправо | rotate.right
    image.rotateLeft |  | 90° Left | 90° влево | rotate.left
    -
    image.flipH |  | Flip Horizontally | Перевернуть горизонтально | arrow.trianglehead.left.and.right.righttriangle.left.righttriangle.right
    image.flipV |  | Flip Vertically | Перевернуть вертикально | arrow.trianglehead.up.and.down.righttriangle.up.righttriangle.down
  -
  image.superResolution | ⌥⌘U | Super Resolution | Супер-разрешение | custom.super-resolution
  -
  image.trim |  | Trim Canvas… | Обрезать холст… | squareshape.dotted.squareshape
  image.revealCanvas |  | Reveal Canvas | Раскрыть холст | squareshape.squareshape.dotted
  -
  image.colorProfile | ⇧⌘K | Color Profile… | Цветовой профиль… | swatchpalette
  image.colorDepth |  | Color Depth… | Глубина цвета… | cube.transparent
  -
  image.hdr | ⌥H | Display HDR Content | Отобразить контент HDR | custom.text.hdr.variable
tools | | Tools | Инстр.
  tool.arrange | V | Arrange | Расстановка | icon-menu-arrange
  -
  tool.style | S | Style | Стиль | icon-menu-style
  tool.adjustments | A | Color Adjustments | Цветокоррекция | icon-menu-adjustments
  tool.effects | F | Effects | Эффекты | icon-menu-effects
  -
  tools.select |  | Select | Выбрать | icon-menu-select
    tool.lassoToggle | ⇧L | Toggle Lasso Tools | Показать/скрыть инструменты лассо
    tool.lassoLast | L | Last Used Lasso Tool | Last Used Lasso Tool
    tool.lassoFree | L | Free Selection | Свободный выбор | icon-menu-freeselection
    tool.lassoPolygon |  | Polygonal Selection | Выбор многоугольником | icon-menu-polygonal
    tool.lassoMagnetic |  | Magnetic Selection | Выбор магнитом | icon-menu-magnetic
    -
    tool.selectRect | M | Rectangular Selection | Выбор прямоугольником | icon-menu-rectangularselection
    tool.selectOval | Y | Oval Selection | Выбор овалом | icon-menu-ovalselection
    -
    tool.selectColumn |  | Column Selection | Выбор столбцом | icon-menu-columnselection
    -
    tool.selectColor | W | Color Selection | Выбор цвета | icon-menu-colorselection
    tool.selectQuick | Q | Quick Selection | Быстрый выбор | icon-menu-quickselection
    -
    tools.selectSubject | ⌃S | Select Subject | Выбрать объект | person.fill.viewfinder
    tools.selectAndMask | ⌥⌘R | Select and Mask… | Выбрать и маскировать…
    tools.selectColorRange |  | Select Color Range… | Выбрать цветовой диапазон…
    tools.transformSelection |  | Transform Selection… | Преобразовать выбранное…
    tools.loadSelection |  | Load Selection | Загрузить выбор | custom.rectangle.dashed.plus
  tool.paint | B | Paint | Закраска | icon-menu-paint
  tool.pixelPaint |  | Pixel Paint | Закраска пикселями | icon-menu-pixel
  tool.gradient | G | Gradient Fill | Градиентная заливка | icon-menu-gradient
  tool.fill | N | Color Fill | Заливка цветом | icon-menu-fill
  tool.erase | E | Erase | Ластик | icon-menu-erase
  tool.smartErase |  | Smart Erase | Смарт-ластик | icon-menu-smarterase
  tools.retouch |  | Retouch | Ретушь | icon-menu-retouch
    tool.repair | R | Repair | Исправление | icon-menu-repair
    tool.clone | O | Clone | Штамп | icon-menu-clone
    -
    tool.lighten |  | Lighten | Осветление | icon-menu-lighten
    tool.darken |  | Darken | Затемнение | icon-menu-darken
    -
    tool.sharpen |  | Sharpen | Резче | icon-menu-sharpen
    tool.soften |  | Soften | Смягчить | icon-menu-soften
    tool.smudge |  | Smudge | Смазывать пальцем | icon-menu-smudge
    -
    tool.saturate |  | Saturate | Насыщенность | icon-menu-saturate
    tool.desaturate |  | Desaturate | Убрать насыщенность | icon-menu-desature
  tools.reshape |  | Reshape | Изменение формы | icon-menu-reshape
    tool.distort |  | Distort | Искажение | icon-menu-distort
    tool.bump |  | Bump | Вздутие | icon-menu-bump
    tool.pinch |  | Pinch | Щипок | icon-menu-pinch
    tool.twirl |  | Twirl | Закручивание | icon-menu-twirl
  -
  tools.draw |  | Draw | Рисовать | icon-menu-draw
    tool.shape | U | Shape | Фигура | square.fill.on.circle.fill
    tool.shapeRect |  | Rectangle | Прямоугольник | squareshape.fill
    tool.shapeRoundRect |  | Rounded Rectangle | Прямоугольник с закругленными углами | square.fill
    tool.shapeOval |  | Oval | Овал | circle.fill
    tool.shapePolygon |  | Polygon | Многоугольник | icon-menu-polygon
    tool.shapeStar |  | Star | Звезда | icon-menu-star
    tool.shapeLine |  | Line | Линия | icon-menu-line
    tool.shapeToggle | ⇧U | Toggle Shape Tools | Показать/скрыть инструменты фигур
    -
    tool.pen | P | Pen | Перо | icon-menu-pen
    tool.freeformPen |  | Freeform Pen | Перо свободной формы | icon-menu-freeformpen
    tool.penToggle | ⇧P | Toggle Pen Tools | Показать/скрыть инструменты пера
  tools.type |  | Type | Текст | icon-menu-type
    tool.type | T | Type | Текст | icon-menu-type
    tool.circularType |  | Circular Type | Круговой текст | icon-menu-circulartype
    tool.pathType |  | Path Type | Текст по пути | icon-menu-pathtype
    tool.freeformType |  | Freeform Type | Текст свободной формы | icon-menu-freeformtype
    tool.typeToggle | ⇧T | Toggle Text Tools | Показать/скрыть инструменты текста
  -
  tool.zoom | Z | Zoom | Изменить масштаб | icon-menu-zoom
  tool.hand | H | Hand | Рука | icon-menu-hand
  tool.colorPicker | I | Color Picker | Выбор цвета | icon-menu-picker
  -
  tool.crop | C | Crop | Обрезка | icon-menu-crop
  tool.exportWeb | K | Export for Web | Экспорт для веб-использования | icon-menu-export
format | | Format | Формат
  format.font |  | Font | Шрифт | textformat
    format.font.show |  | Show Fonts | Показать шрифты
    -
    format.font.bold |  | Bold | Жирный | bold
    format.font.italic |  | Italic | Курсив | italic
    format.font.underline |  | Underline | Подчеркивание | underline
    format.font.strike |  | Strikethrough | Зачеркивание | strikethrough
    format.font.outline |  | Outline | Контур
    -
    format.font.bigger |  | Bigger | Больше | textformat.size.larger
    format.font.smaller |  | Smaller | Меньше | textformat.size.smaller
    -
    format.font.replace |  | Replace Fonts… | Заменить шрифты… | character.book.closed
  format.text |  | Text | Текст | text.alignleft
    format.text.left |  | Align Left | Выровнять по левому краю | text.alignleft
    format.text.center |  | Align Center | Выровнять по центру | text.aligncenter
    format.text.right |  | Align Right | Выровнять по правому краю | text.alignright
    format.text.justify |  | Justify | По формату | text.justify
    -
    format.text.top |  | Align Top | Выровнять по верхнему краю | arrow.up.to.line
    format.text.middle |  | Align Middle | Выровнять по центру | arrow.down.and.line.horizontal.and.arrow.up
    format.text.bottom |  | Align Bottom | Выровнять по нижнему краю | arrow.down.to.line
  -
  format.image |  | Image | Изображение | photo
    format.fillColor | ⌥⌘F | Fill with Color… | Залить цветом…
    format.fillForeground | ⌥⌫ | Fill with Foreground Color | Заливка цветом переднего плана
    format.fillBackground | ⌘⌫ | Fill with Background Color | Заливка цветом заднего плана
    -
    format.invertColors | ⌘I | Invert Colors | Инвертировать цвета
    -
    format.decontaminate |  | Decontaminate Colors | Очистить цвета
    -
    format.preserveTransparency |  | Preserve Transparency | Сохранить прозрачность
  format.shape |  | Shape | Фигура | square.on.circle
    format.shape.makeEditable |  | Make Editable | Разрешить редактирование | beziercurve
    -
    format.shape.unite |  | Unite Shapes | Слить фигуры | square.on.square.unite
    format.shape.subtract |  | Subtract Shapes | Вычесть фигуры | square.on.square.subtract
    format.shape.intersect |  | Intersect Shapes | Пересечь фигуры | square.on.square.intersect
    format.shape.exclude |  | Exclude Shapes | Исключить фигуры | square.on.square.exclude
  format.mask |  | Mask | Маска | circle.square.fill
    mask.add |  | Add Mask | Добавить маску
    mask.withShape |  | Mask with Shape | Маскировать фигурой
      mask.shape.rect |  | Rectangle | Прямоугольник
      mask.shape.roundRect |  | Rounded Rectangle | Прямоугольник с закругленными углами
      mask.shape.oval |  | Oval | Овал
      mask.shape.polygon |  | Polygon | Многоугольник
      mask.shape.star |  | Star | Звезда
      mask.shape.pen |  | Draw with Pen | Рисовать пером
    -
    mask.chooseImage |  | Choose Image Mask… | Выбрать маску изображения…
    -
    mask.revealAll |  | Add Reveal All Mask | Добавить раскрытие всех масок
    mask.hideAll |  | Add Hide All Mask | Добавить скрытие всех масок
    mask.fromSelection |  | Add Mask from Selection | Добавить маску из выбранного
    mask.remove |  | Remove Mask | Удалить маску
    -
    mask.edit |  | Edit Mask | Изменить маску
    mask.refine |  | Refine Mask… | Уточнить маску…
    mask.merge |  | Merge Masks | Объединить маски
    -
    mask.enable |  | Enable Mask | Включить маску
    mask.disable |  | Disable Mask | Отключить маску
    -
    mask.clipping | ⌥⌘G | Create Clipping Mask | Создать обтравочную маску
  -
  format.styles |  | Styles | Стили | icon-menu-style
    format.styles.copy |  | Copy Styles | Скопировать стили | custom.eyedropper.circle
    format.styles.paste |  | Paste Styles | Вставить стили | custom.eyedropper.circle.fill
    -
    format.styles.reset |  | Reset Styles | Сбросить стили | arrow.trianglehead.counterclockwise
  format.adjustments |  | Color Adjustments | Цветокоррекция | icon-menu-adjustments
    -
    format.adjustments.copy |  | Copy Adjustments | Скопировать корректировки | slider.horizontal.2.square.on.square
    format.adjustments.paste |  | Paste Adjustments | Вставить корректировки | slider.horizontal.2.square.badge.arrow.down
    -
    format.adjustments.reset |  | Reset Adjustments | Сбросить корректировки | arrow.trianglehead.counterclockwise
  format.effects |  | Effects | Эффекты | icon-menu-effects
    format.effects.copy |  | Copy Effects | Скопировать эффекты | slider.horizontal.2.square.on.square
    format.effects.paste |  | Paste Effects | Вставить эффекты | slider.horizontal.2.square.badge.arrow.down
    -
    format.effects.reset |  | Reset Effects | Сбросить эффекты | arrow.trianglehead.counterclockwise
  -
  format.replaceLayer |  | Replace Layer | Заменить Слой | custom.replace.layer
    format.replace.files | ⇧⌘R | Files… | Файлы… | folder
    -
    format.replace.clipboard |  | Clipboard | Буфер обмена | clipboard
  -
  format.strokeBrush | ⌥⌘B | Stroke with Brush… | Штрих кистью…
  -
  format.denoise | ⌃⇧D | Denoise… | Снижение шума… | custom.noise.slash
  format.deband | ⌃⇧B | Deband… | Депостеризация… | custom.deband.slash
  -
  format.toShape |  | Convert to Shape | Преобразовать в фигуру | custom.convert.into.shape
  format.toPixels |  | Convert to Pixels | Преобразовать в пиксели | custom.convert.to.pixels
arrange | | Arrange | Расстановка
  arrange.forward | ⌘] | Bring Forward | Вперед | square.2.layers.3d.top.filled
  arrange.front | ⌥⌘] | Bring to Front | На передний план | square.3.layers.3d.top.filled
  arrange.backward | ⌘[ | Send Backward | Назад | square.2.layers.3d.bottom.filled
  arrange.back | ⌥⌘[ | Send to Back | На задний план | square.3.layers.3d.bottom.filled
  -
  arrange.align |  | Align Layers | Выровнять слои | align.horizontal.center
    align.top | ⌃⌘↑ | Top Edges | Верхние края | align.vertical.top
    align.vcenter | ⌃⌘V | Vertical Centers | Центры по вертикали | align.vertical.center
    align.bottom | ⌃⌘↓ | Bottom Edges | Нижние края | align.vertical.bottom
    -
    align.left | ⌃⌘← | Left Edges | Левые края | align.horizontal.left
    align.hcenter | ⌃⌘H | Horizontal Centers | Центры по горизонтали | align.horizontal.center
    align.right | ⌃⌘→ | Right Edges | Правые края | align.horizontal.right
  arrange.distribute |  | Distribute Layers | Распределить слои | distribute.horizontal.center
    distribute.top |  | Top Edges | Верхние края | distribute.vertical.top
    distribute.vcenter |  | Vertical Centers | Центры по вертикали | distribute.vertical.center
    distribute.bottom |  | Bottom Edges | Нижние края | distribute.vertical.bottom
    -
    distribute.left |  | Left Edges | Левые края | distribute.horizontal.left
    distribute.hcenter |  | Horizontal Centers | Центры по горизонтали | distribute.horizontal.center
    distribute.right |  | Right Edges | Правые края | distribute.horizontal.right
    -
    distribute.vspacing | ⌃⌥⌘V | Vertical Spacing | Расположение по вертикали | distribute.vertical
    distribute.hspacing | ⌃⌥⌘H | Horizontal Spacing | Расположение по горизонтали | distribute.horizontal
  -
  arrange.transform |  | Transform | Преобразование | custom.squareshape.controlhandles.static
    arrange.transform.resize |  | Resize… | Изменить размер…
    arrange.transform.skew |  | Skew… | Наклон…
    arrange.transform.distort |  | Distort… | Исказить…
    arrange.transform.perspective |  | Perspective… | Перспектива…
  arrange.warp |  | Warp… | Искажение… | custom.warp
  -
  arrange.rotate180 |  | Rotate 180° | Повернуть на 180° | rectangle.landscape.rotate
  arrange.rotateRight |  | Rotate 90° Right | Повернуть на 90° вправо | rotate.right
  arrange.rotateLeft |  | Rotate 90° Left | Повернуть на 90° влево | rotate.left
  -
  arrange.flipH |  | Flip Horizontally | Перевернуть горизонтально | arrow.trianglehead.left.and.right.righttriangle.left.righttriangle.right
  arrange.flipV |  | Flip Vertically | Перевернуть вертикально | arrow.trianglehead.up.and.down.righttriangle.up.righttriangle.down
  -
  arrange.toggleVisibility | ⌥⌘, | Toggle Visibility | Изменить видимость
  arrange.hide |  | Hide | Скрыть | eye.slash
  arrange.show |  | Show | Показать | eye
  -
  arrange.lock |  | Lock | Закрепить | lock
  arrange.unlock |  | Unlock | Разблокировать | lock.open
  -
  arrange.group | ⌘G | Group | Сгруппировать | square.on.square.squareshape.controlhandles
  arrange.ungroup | ⇧⌘G | Ungroup | Без группы | squareshape.controlhandles.on.squareshape.controlhandles
  -
  arrange.merge | ⌥⌘E | Merge | Объединить | custom.merge
  arrange.mergeAll | ⌥⇧⌘E | Merge All | Объединить все | custom.merge
view | | View | Вид
  view.zoomIn | ⌘+ | Zoom In | Увеличить
  view.zoomOut | ⌘- | Zoom Out | Уменьшить
  view.zoomFit | ⌘0 | Zoom to Fit | Изменить масштаб под размер
  view.actualSize | ⌥⌘0 | Actual Size | Реальный размер
  -
  view.canvasRotation |  | Canvas Rotation | Вращение холста
    view.resetRotation |  | Reset Canvas Rotation | Сбросить вращение холста
  -
  view.hideTools | ⌥T | Hide Tools | Скрыть инструменты
  pxm.view.hideToolOptions |  | Hide Tool Options | Скрыть опции инструментов
  -
  view.hideLayers | ⌥L | Hide Layers | Скрыть слои | square.3.layers.3d
  -
  view.rulers | ⌘R | Show Rulers | Показать линейки | ruler.ruler
  view.overlays |  | Overlays | Оверлеи | doc.master
    view.overlay.guides | ⌥⌘; | Guides | Направляющие | custom.guides
    view.overlay.grid | ⌥⌘' | Grid | Сетка | squareshape.split.3x3
    view.overlay.pixelGrid |  | Pixel Grid | Сетка пикселей | custom.pixel.grid.3x3
  view.guides |  | Guides | Направляющие | custom.guides
    view.guides.add |  | Add Guide… | Добавить направляющую… | custom.guides.add
    view.guides.lock |  | Lock Guides | Блокировать направляющие | lock
    view.guides.clear |  | Clear Guides | Удалить направляющие | trash
  -
  view.infoBar | ⌘/ | Show Info Bar | Показать панель информации
  -
  view.splitComparison | ⌃C | Split Comparison | Разделенный экран | arrowtriangle.left.and.line.vertical.and.arrowtriangle.right.fill
  -
  view.colors | ⇧⌘C | Show Colors | Показать цвета
  view.documentInfo | ⌥⇧⌘I | Show Document Info | Показать сведения о документе | info.circle
  -
  view.fullScreen | ⌃⌘F | Enter Full Screen | Перейти в полноэкранный режим
window | | Window | Окно
  window.minimize | ⌘M | Minimize | Убрать в Dock
  window.zoom |  | Zoom | Изменить масштаб
  -
  window.layout |  | Workspace Layout | Макет рабочего пространства
    layout.default |  | Default | По умолчанию
    layout.photography |  | Photography | Фотография
    layout.design |  | Design | Дизайн
    layout.illustration |  | Illustration | Иллюстрация
    layout.painting |  | Painting | Рисование
  -
  window.customizeTools |  | Customize Tools… | Настроить инструменты…
  window.customizeLayout |  | Customize Layout… | Настроить макет…
  -
  window.showTabBar |  | Show Tab Bar | Показать панель вкладок
  window.tabOverview | ⇧⌘\ | Show Tab Overview | Показать обзор вкладок
  -
  window.bringAllToFront |  | Bring All to Front | Все окна — на передний план
help | | Help | Справка
  help.main | ⌘? | {app} Help | Справка {app} | questionmark.circle
  help.shortcuts |  | Keyboard Shortcuts | Сочетания клавиш | keyboard
"""#
