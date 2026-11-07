import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    private var unik: UnikalizatorModel { model.unikalizator }

    private func unikOption<T>(_ keyPath: WritableKeyPath<UnikOptions, T>) -> Binding<T> {
        Binding(
            get: { model.unikalizator.options[keyPath: keyPath] },
            set: { model.unikalizator.options[keyPath: keyPath] = $0 }
        )
    }

    private func unikLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(secondaryText)
    }

    private func unikHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func unikPath(_ path: String, placeholder: String) -> some View {
        Text(path.isEmpty ? placeholder : path)
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .foregroundStyle(path.isEmpty ? secondaryText : primaryText)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var unikalizatorView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1000
            let horizontalPadding = contentHorizontalPadding(for: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHero(
                        eyebrow: L("Уникализатор"),
                        title: L("Обработка видео и картинок"),
                        subtitle: L("Готовые форматы, вариации со стилями, плашка 18+, заставка и слой поверх. Всё считается на этом компьютере.")
                    )
                    unikFFmpegBanner
                    if compact {
                        unikRunCard
                        unikProgressCard
                        unikSettingsColumn
                    } else {
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 18) { unikSettingsColumn }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            VStack(alignment: .leading, spacing: 18) {
                                unikRunCard
                                unikProgressCard
                            }
                            .frame(width: 340, alignment: .topLeading)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 28)
                .padding(.top, 4)
            }
            .task { await model.unikalizator.refresh() }
        }
    }

    // MARK: FFmpeg

    @ViewBuilder
    private var unikFFmpegBanner: some View {
        switch unik.ffmpeg {
        case .missing:
            card(L("FFmpeg не установлен")) {
                VStack(alignment: .leading, spacing: 10) {
                    unikHint(L("Для обработки нужен FFmpeg. Он скачивается один раз и хранится в папке приложения."))
                    button(L("Установить FFmpeg"), systemImage: "arrow.down.circle", prominent: true, allowWhileBusy: true) {
                        Task { await model.unikalizator.installFFmpeg() }
                    }
                }
            }
        case .installing:
            card(L("Устанавливаю FFmpeg…")) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(unik.installPercent), total: 100)
                    unikHint(unik.installMessage)
                }
            }
        case .failed(let message):
            card(L("FFmpeg не готов")) {
                VStack(alignment: .leading, spacing: 10) {
                    unikHint(message)
                    button(L("Повторить"), systemImage: "arrow.clockwise", allowWhileBusy: true) {
                        Task { await model.unikalizator.installFFmpeg() }
                    }
                }
            }
        case .ready, .unknown:
            EmptyView()
        }
    }

    // MARK: Запуск и ход обработки

    private var unikRunCard: some View {
        card(L("Запуск")) {
            VStack(alignment: .leading, spacing: 12) {
                if unik.files.isEmpty {
                    unikHint(L("Добавьте файлы, чтобы начать."))
                } else {
                    Text(L("Файлов: {0} · будет создано: {1}", unik.files.count, unik.plannedOutputs))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)
                }
                if !unik.problems.isEmpty, !unik.files.isEmpty {
                    ForEach(unik.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 10) {
                    button(
                        L("Создать") + (unik.plannedOutputs > 0 ? " · \(unik.plannedOutputs)" : ""),
                        systemImage: "wand.and.stars",
                        prominent: true,
                        allowWhileBusy: true
                    ) {
                        Task { await model.unikalizator.run() }
                    }
                    .disabled(!unik.isFFmpegReady || !unik.problems.isEmpty || unik.isRunning || unik.isInstalling)

                    if unik.isRunning {
                        button(L("Стоп"), systemImage: "stop.fill", tint: .red, allowWhileBusy: true) {
                            model.unikalizator.stop()
                        }
                    }
                }
                unikLabel(L("Папка для результатов"))
                unikPath(unik.outputDirectory.path, placeholder: L("Папка не выбрана"))
                HStack(spacing: 10) {
                    button(L("Выбрать…"), systemImage: "folder", allowWhileBusy: true) { model.unikalizator.chooseOutputDirectory() }
                        .disabled(unik.isRunning)
                    button(L("Показать"), systemImage: "arrow.up.forward.app", allowWhileBusy: true) { model.unikalizator.revealOutput() }
                }
                if case .ready(let version) = unik.ffmpeg, !version.isEmpty {
                    unikHint("FFmpeg \(version)")
                }
                if let notice = unik.notice {
                    unikHint(notice)
                }
            }
        }
    }

    private var unikProgressCard: some View {
        card(L("Ход обработки")) {
            VStack(alignment: .leading, spacing: 10) {
                if unik.jobs.isEmpty {
                    unikHint(unik.summary.isEmpty ? L("Результаты появятся здесь.") : unik.summary)
                } else {
                    ProgressView(value: Double(unik.overallPercent), total: 100)
                    unikHint(L("Готово {0} из {1}", unik.doneCount, unik.jobs.count))
                    ForEach(unik.jobs) { job in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.outputPath.isEmpty ? (job.label.isEmpty ? L("Файл {0}", job.index + 1) : job.label) : URL(fileURLWithPath: job.outputPath).lastPathComponent)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(unikJobStatus(job))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(job.status == .error ? Color.red : secondaryText)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !unik.summary.isEmpty { unikHint(unik.summary) }
                }
            }
        }
    }

    private func unikJobStatus(_ job: UnikJob) -> String {
        switch job.status {
        case .queued: L("В очереди")
        case .running: L("Обработка… {0}%", job.percent)
        case .done: L("Готово")
        case .error: job.message.isEmpty ? L("Ошибка") : job.message
        }
    }

    // MARK: Настройки

    @ViewBuilder
    private var unikSettingsColumn: some View {
        unikFilesCard
        unikPresetsCard
        unikFormatCard
        unikVariationsCard
        unikAgeMarkCard
        unikExtrasCard
        unikNamingCard
    }

    private var unikPresetsCard: some View {
        card(L("Мои пресеты")) {
            UnikPresetsEditor(unik: unik, secondaryText: secondaryText)
        }
    }

    private var unikFilesCard: some View {
        card(L("Файлы")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    button(L("Добавить файлы…"), systemImage: "plus", prominent: true, allowWhileBusy: true) { model.unikalizator.chooseFiles() }
                        .disabled(unik.isRunning)
                    if !unik.files.isEmpty {
                        button(L("Очистить"), systemImage: "trash", allowWhileBusy: true) { model.unikalizator.clearFiles() }
                            .disabled(unik.isRunning)
                    }
                }
                unikHint(L("Или перетащите видео и картинки в это окно: {0}.", UnikalizatorLogic.mediaExtensions.joined(separator: ", ")))
                ForEach(unik.files) { file in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(file.info.isEmpty ? (file.isImage ? L("картинка") : L("видео")) : file.info)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(secondaryText)
                        }
                        Spacer(minLength: 8)
                        Button {
                            model.unikalizator.removeFile(file)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(secondaryText)
                        .disabled(unik.isRunning)
                        .help(L("Убрать {0}", file.name))
                    }
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { [unikalizator = model.unikalizator] providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in unikalizator.addFiles([url]) }
                }
            }
            return true
        }
    }

    private var unikFormatPresetBinding: Binding<String> {
        Binding(
            get: { model.unikalizator.options.formatPresetId },
            set: { model.unikalizator.applyFormatPreset($0) }
        )
    }

    private var unikFormatCard: some View {
        card(L("Формат и экспорт")) {
            VStack(alignment: .leading, spacing: 12) {
                unikLabel(L("Готовый формат"))
                Picker(L("Готовый формат"), selection: unikFormatPresetBinding) {
                    ForEach(unik.catalog?.formatPresets ?? []) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                    Text(L("Свой размер")).tag("custom")
                }
                .labelsHidden()
                if unik.options.formatPresetId == "custom" {
                    HStack(spacing: 10) {
                        TextField(L("Ширина"), value: unikOption(\.resize.width), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                        TextField(L("Высота"), value: unikOption(\.resize.height), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                unikLabel(L("Вписывание в кадр"))
                Picker(L("Вписывание"), selection: unikOption(\.resize.fit)) {
                    Text(L("Заполнить (обрезка)")).tag("cover")
                    Text(L("Целиком (с полями)")).tag("contain")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if unik.options.resize.fit == "contain" {
                    unikLabel(L("Фон по краям"))
                    Picker(L("Фон"), selection: unikOption(\.resize.backgroundStyle)) {
                        Text(L("Чёрные поля")).tag("bars")
                        Text(L("Размытие")).tag("blur")
                        Text(L("Цвет")).tag("solid")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if unik.options.resize.backgroundStyle == "solid" {
                        TextField("#111111", text: unikOption(\.resize.backgroundColor))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                unikLabel(L("Частота кадров"))
                Picker("FPS", selection: unikOption(\.fps)) {
                    Text(L("Как есть")).tag(0)
                    ForEach(unik.catalog?.fpsOptions ?? [25, 30, 50, 60], id: \.self) { fps in
                        Text("\(fps)").tag(fps)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                unikLabel(L("Качество видео"))
                Picker(L("Качество"), selection: unikOption(\.bitrate)) {
                    ForEach(unik.catalog?.bitrateOptions ?? []) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                Toggle(L("Выровнять громкость"), isOn: unikOption(\.audio.normalize))
                unikLabel(L("Метаданные"))
                Picker(L("Метаданные"), selection: unikOption(\.metadata.mode)) {
                    Text(L("Удалить")).tag("strip")
                    Text(L("Дата экспорта")).tag("export-date")
                    Text(L("Своя дата")).tag("custom-date")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if unik.options.metadata.mode == "custom-date" {
                    TextField(L("ГГГГ-ММ-ДД"), text: unikOption(\.metadata.customDate))
                        .textFieldStyle(.roundedBorder)
                }
            }
            .disabled(unik.isRunning)
        }
    }

    private var unikVariationsCard: some View {
        card(L("Вариации и стиль")) {
            VStack(alignment: .leading, spacing: 12) {
                unikLabel(L("Сколько вариаций из каждого файла"))
                Picker(L("Вариации"), selection: Binding(
                    get: { model.unikalizator.options.variations.count },
                    set: { model.unikalizator.setVariationCount($0) }
                )) {
                    ForEach(unik.catalog?.variationOptions ?? [1, 2, 3, 5], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if unik.files.count > 1, unik.options.variations.count > 1 {
                    unikLabel(L("Как применить стили к нескольким файлам"))
                    Picker(L("Режим"), selection: unikOption(\.variations.mode)) {
                        Text(L("Все вариации для каждого файла")).tag("all-variations")
                        Text(L("По одному стилю на файл")).tag("preset-per-file")
                    }
                    .labelsHidden()
                }
                ForEach(0 ..< unik.options.variations.styleIds.count, id: \.self) { slot in
                    unikLabel(unik.options.variations.count > 1 ? L("Стиль вариации {0}", slot + 1) : L("Стиль"))
                    Picker(L("Стиль"), selection: Binding(
                        get: { model.unikalizator.options.variations.styleIds[safe: slot] ?? "clean" },
                        set: { model.unikalizator.setStyle(slot: slot, id: $0) }
                    )) {
                        ForEach(unik.catalog?.stylePresets ?? []) { style in
                            Text("\(style.label) — \(style.hint)").tag(style.id)
                        }
                    }
                    .labelsHidden()
                }
                if unik.options.variations.count == 1 {
                    Toggle(L("Настроить вручную"), isOn: unikOption(\.manual.enabled))
                    if unik.options.manual.enabled {
                        unikSlider(L("Оттенок"), value: unikOption(\.manual.hueShift), range: -180 ... 180, step: 1, format: "%.0f°")
                        unikSlider(L("Насыщенность"), value: unikOption(\.manual.saturation), range: 0 ... 3, step: 0.05, format: "%.2f")
                        unikSlider(L("Резкость"), value: unikOption(\.manual.sharpness), range: 0 ... 2, step: 0.05, format: "%.2f")
                        unikSlider(L("Длительность, мс"), value: unikOption(\.manual.speedOffsetMs), range: -2000 ... 3000, step: 50, format: "%+.0f")
                    }
                }
            }
            .disabled(unik.isRunning)
        }
    }

    private func unikSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            unikLabel("\(title): " + String(format: format, value.wrappedValue))
            Slider(value: value, in: range, step: step)
        }
    }

    private var unikAgeMarkCard: some View {
        card(L("Плашка 18+")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L("Добавить плашку 18+"), isOn: unikOption(\.ageMark.enabled))
                unikHint(L("Готовые шаблоны по странам подбираются под соотношение сторон."))
                if unik.options.ageMark.enabled {
                    unikLabel(L("Страна"))
                    Picker(L("Страна"), selection: unikOption(\.ageMark.geoId)) {
                        Text(L("Выберите страну…")).tag("")
                        ForEach(unik.catalog?.ageMarkGeos ?? []) { geo in
                            Text(geo.name).tag(geo.id)
                        }
                    }
                    .labelsHidden()
                    unikLabel(L("Расположение"))
                    Picker(L("Расположение"), selection: unikOption(\.ageMark.position)) {
                        Text(L("Сверху")).tag("top")
                        Text(L("Снизу")).tag("bottom")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .disabled(unik.isRunning)
        }
    }

    private var unikExtrasCard: some View {
        card(L("Дополнительно")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L("Заставка в начале"), isOn: unikOption(\.intro.enabled))
                if unik.options.intro.enabled {
                    Toggle(L("Случайная из набора"), isOn: unikOption(\.intro.random))
                    if unik.options.intro.random {
                        unikPath(unik.options.intro.library.isEmpty ? "" : L("Набор: {0} файл(ов)", unik.options.intro.library.count), placeholder: L("Набор картинок не выбран"))
                        button(L("Выбрать набор…"), systemImage: "photo.on.rectangle", allowWhileBusy: true) {
                            let picked = model.unikalizator.chooseFiles(title: L("Картинки для заставок"), extensions: UnikalizatorLogic.imageExtensions, multiple: true)
                            if !picked.isEmpty { model.unikalizator.options.intro.library = picked }
                        }
                    } else {
                        unikPath(unik.options.intro.imagePath, placeholder: L("Картинка не выбрана"))
                        button(L("Выбрать картинку…"), systemImage: "photo", allowWhileBusy: true) {
                            if let path = model.unikalizator.chooseFiles(title: L("Картинка для заставки"), extensions: UnikalizatorLogic.imageExtensions, multiple: false).first {
                                model.unikalizator.options.intro.imagePath = path
                            }
                        }
                    }
                    unikSlider(L("Длительность заставки, мс"), value: unikOption(\.intro.durationMs), range: 100 ... 3000, step: 50, format: "%.0f")
                }
                Divider()
                Toggle(L("Видео-слой поверх"), isOn: unikOption(\.overlay.enabled))
                if unik.options.overlay.enabled {
                    Toggle(L("Случайный из набора"), isOn: unikOption(\.overlay.random))
                    if unik.options.overlay.random {
                        unikPath(unik.options.overlay.library.isEmpty ? "" : L("Набор: {0} файл(ов)", unik.options.overlay.library.count), placeholder: L("Набор видео не выбран"))
                        button(L("Выбрать набор…"), systemImage: "film.stack", allowWhileBusy: true) {
                            let picked = model.unikalizator.chooseFiles(title: L("Видео для слоя поверх"), extensions: UnikalizatorLogic.videoExtensions, multiple: true)
                            if !picked.isEmpty { model.unikalizator.options.overlay.library = picked }
                        }
                    } else {
                        unikPath(unik.options.overlay.videoPath, placeholder: L("Видео не выбрано"))
                        button(L("Выбрать видео…"), systemImage: "film", allowWhileBusy: true) {
                            if let path = model.unikalizator.chooseFiles(title: L("Видео для слоя поверх"), extensions: UnikalizatorLogic.videoExtensions, multiple: false).first {
                                model.unikalizator.options.overlay.videoPath = path
                            }
                        }
                    }
                    unikSlider(L("Прозрачность слоя"), value: unikOption(\.overlay.opacity), range: 0.05 ... 1, step: 0.05, format: "%.2f")
                }
                Divider()
                unikLabel(L("Заменить звук"))
                unikPath(unik.options.audio.replacePath, placeholder: L("Оставить звук из видео"))
                HStack(spacing: 10) {
                    button(L("Выбрать звук…"), systemImage: "music.note", allowWhileBusy: true) {
                        if let path = model.unikalizator.chooseFiles(title: L("Новая звуковая дорожка"), extensions: UnikalizatorLogic.audioExtensions, multiple: false).first {
                            model.unikalizator.options.audio.replacePath = path
                        }
                    }
                    if !unik.options.audio.replacePath.isEmpty {
                        button(L("Сбросить"), systemImage: "xmark", allowWhileBusy: true) { model.unikalizator.options.audio.replacePath = "" }
                    }
                }
            }
            .disabled(unik.isRunning)
        }
    }

    private var unikNamingCard: some View {
        card(L("Название файла")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(L("Схема имени"), selection: unikOption(\.naming.mode)) {
                    Text(L("ГЕО + формат + версия")).tag("structured")
                    Text(L("Исходное + случайный хвост")).tag("source-random")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if unik.options.naming.mode == "structured" {
                    HStack(spacing: 10) {
                        TextField(L("ГЕО (AU)"), text: unikOption(\.naming.geo))
                            .textFieldStyle(.roundedBorder)
                        TextField(L("Тип (instagram)"), text: unikOption(\.naming.presetToken))
                            .textFieldStyle(.roundedBorder)
                        TextField(L("Версия (v1)"), text: unikOption(\.naming.versionToken))
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    TextField(L("Хвост (пусто — случайный)"), text: unikOption(\.naming.randomTail))
                        .textFieldStyle(.roundedBorder)
                }
                let first = unik.files.first?.path ?? ""
                let outputs = unik.plannedOutputs
                Text(L("Пример: ") + UnikalizatorLogic.previewName(options: unik.options, firstFile: first, outputs: outputs)
                    + (outputs > 1 ? " … " + UnikalizatorLogic.previewName(options: unik.options, firstFile: first, outputs: outputs, index: outputs - 1) : ""))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)
                    .textSelection(.enabled)
            }
            .disabled(unik.isRunning)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}


/// Сохранить текущие настройки под именем, применить или удалить сохранённый набор.
private struct UnikPresetsEditor: View {
    @ObservedObject var unik: UnikalizatorModel
    let secondaryText: Color
    @State private var chosen = ""
    @State private var name = ""

    private var trimmedName: String { UnikalizatorLogic.cleanPresetName(name) }
    private var nameExists: Bool {
        unik.presets.contains { $0.name.compare(trimmedName, options: .caseInsensitive) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if unik.presets.isEmpty {
                Text(L("Настройте раздел и сохраните набор под своим именем, например «Reels DE 18+»."))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    Picker(L("Сохранённые наборы"), selection: $chosen) {
                        Text(L("Выберите набор…")).tag("")
                        ForEach(unik.presets) { preset in Text(preset.name).tag(preset.name) }
                    }
                    .labelsHidden()
                    .onChange(of: chosen) { _, value in if !value.isEmpty { name = value } }
                    Button(L("Применить")) { unik.applyPreset(named: chosen) }
                        .disabled(chosen.isEmpty || unik.isRunning)
                    Button(role: .destructive) {
                        unik.deletePreset(named: chosen)
                        chosen = ""
                    } label: { Image(systemName: "trash") }
                        .help(L("Удалить набор"))
                        .disabled(chosen.isEmpty || unik.isRunning)
                }
            }
            HStack(spacing: 8) {
                TextField(L("Название набора"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(unik.isRunning)
                Button(nameExists ? L("Заменить") : L("Сохранить")) {
                    unik.savePreset(named: name)
                    chosen = trimmedName
                }
                .disabled(trimmedName.isEmpty || unik.isRunning)
            }
        }
    }
}
