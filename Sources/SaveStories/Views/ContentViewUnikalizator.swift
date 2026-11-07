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
                        eyebrow: "Уникализатор",
                        title: "Обработка видео и картинок",
                        subtitle: "Готовые форматы, вариации со стилями, плашка 18+, заставка и слой поверх. Всё считается на этом компьютере."
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
            card("FFmpeg не установлен") {
                VStack(alignment: .leading, spacing: 10) {
                    unikHint("Для обработки нужен FFmpeg. Он скачивается один раз и хранится в папке приложения.")
                    button("Установить FFmpeg", systemImage: "arrow.down.circle", prominent: true, allowWhileBusy: true) {
                        Task { await model.unikalizator.installFFmpeg() }
                    }
                }
            }
        case .installing:
            card("Устанавливаю FFmpeg…") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(unik.installPercent), total: 100)
                    unikHint(unik.installMessage)
                }
            }
        case .failed(let message):
            card("FFmpeg не готов") {
                VStack(alignment: .leading, spacing: 10) {
                    unikHint(message)
                    button("Повторить", systemImage: "arrow.clockwise", allowWhileBusy: true) {
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
        card("Запуск") {
            VStack(alignment: .leading, spacing: 12) {
                if unik.files.isEmpty {
                    unikHint("Добавьте файлы, чтобы начать.")
                } else {
                    Text("Файлов: \(unik.files.count) · будет создано: \(unik.plannedOutputs)")
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
                        "Создать" + (unik.plannedOutputs > 0 ? " · \(unik.plannedOutputs)" : ""),
                        systemImage: "wand.and.stars",
                        prominent: true,
                        allowWhileBusy: true
                    ) {
                        Task { await model.unikalizator.run() }
                    }
                    .disabled(!unik.isFFmpegReady || !unik.problems.isEmpty || unik.isRunning || unik.isInstalling)

                    if unik.isRunning {
                        button("Стоп", systemImage: "stop.fill", tint: .red, allowWhileBusy: true) {
                            model.unikalizator.stop()
                        }
                    }
                }
                unikLabel("Папка для результатов")
                unikPath(unik.outputDirectory.path, placeholder: "Папка не выбрана")
                HStack(spacing: 10) {
                    button("Выбрать…", systemImage: "folder", allowWhileBusy: true) { model.unikalizator.chooseOutputDirectory() }
                        .disabled(unik.isRunning)
                    button("Показать", systemImage: "arrow.up.forward.app", allowWhileBusy: true) { model.unikalizator.revealOutput() }
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
        card("Ход обработки") {
            VStack(alignment: .leading, spacing: 10) {
                if unik.jobs.isEmpty {
                    unikHint(unik.summary.isEmpty ? "Результаты появятся здесь." : unik.summary)
                } else {
                    ProgressView(value: Double(unik.overallPercent), total: 100)
                    unikHint("Готово \(unik.doneCount) из \(unik.jobs.count)")
                    ForEach(unik.jobs) { job in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.outputPath.isEmpty ? (job.label.isEmpty ? "Файл \(job.index + 1)" : job.label) : URL(fileURLWithPath: job.outputPath).lastPathComponent)
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
        case .queued: "В очереди"
        case .running: "Обработка… \(job.percent)%"
        case .done: "Готово"
        case .error: job.message.isEmpty ? "Ошибка" : job.message
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
        card("Мои пресеты") {
            UnikPresetsEditor(unik: unik, secondaryText: secondaryText)
        }
    }

    private var unikFilesCard: some View {
        card("Файлы") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    button("Добавить файлы…", systemImage: "plus", prominent: true, allowWhileBusy: true) { model.unikalizator.chooseFiles() }
                        .disabled(unik.isRunning)
                    if !unik.files.isEmpty {
                        button("Очистить", systemImage: "trash", allowWhileBusy: true) { model.unikalizator.clearFiles() }
                            .disabled(unik.isRunning)
                    }
                }
                unikHint("Или перетащите видео и картинки в это окно: \(UnikalizatorLogic.mediaExtensions.joined(separator: ", ")).")
                ForEach(unik.files) { file in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(file.info.isEmpty ? (file.isImage ? "картинка" : "видео") : file.info)
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
                        .help("Убрать \(file.name)")
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
        card("Формат и экспорт") {
            VStack(alignment: .leading, spacing: 12) {
                unikLabel("Готовый формат")
                Picker("Готовый формат", selection: unikFormatPresetBinding) {
                    ForEach(unik.catalog?.formatPresets ?? []) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                    Text("Свой размер").tag("custom")
                }
                .labelsHidden()
                if unik.options.formatPresetId == "custom" {
                    HStack(spacing: 10) {
                        TextField("Ширина", value: unikOption(\.resize.width), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                        TextField("Высота", value: unikOption(\.resize.height), format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                unikLabel("Вписывание в кадр")
                Picker("Вписывание", selection: unikOption(\.resize.fit)) {
                    Text("Заполнить (обрезка)").tag("cover")
                    Text("Целиком (с полями)").tag("contain")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if unik.options.resize.fit == "contain" {
                    unikLabel("Фон по краям")
                    Picker("Фон", selection: unikOption(\.resize.backgroundStyle)) {
                        Text("Чёрные поля").tag("bars")
                        Text("Размытие").tag("blur")
                        Text("Цвет").tag("solid")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if unik.options.resize.backgroundStyle == "solid" {
                        TextField("#111111", text: unikOption(\.resize.backgroundColor))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                unikLabel("Частота кадров")
                Picker("FPS", selection: unikOption(\.fps)) {
                    Text("Как есть").tag(0)
                    ForEach(unik.catalog?.fpsOptions ?? [25, 30, 50, 60], id: \.self) { fps in
                        Text("\(fps)").tag(fps)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                unikLabel("Качество видео")
                Picker("Качество", selection: unikOption(\.bitrate)) {
                    ForEach(unik.catalog?.bitrateOptions ?? []) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                Toggle("Выровнять громкость", isOn: unikOption(\.audio.normalize))
                unikLabel("Метаданные")
                Picker("Метаданные", selection: unikOption(\.metadata.mode)) {
                    Text("Удалить").tag("strip")
                    Text("Дата экспорта").tag("export-date")
                    Text("Своя дата").tag("custom-date")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if unik.options.metadata.mode == "custom-date" {
                    TextField("ГГГГ-ММ-ДД", text: unikOption(\.metadata.customDate))
                        .textFieldStyle(.roundedBorder)
                }
            }
            .disabled(unik.isRunning)
        }
    }

    private var unikVariationsCard: some View {
        card("Вариации и стиль") {
            VStack(alignment: .leading, spacing: 12) {
                unikLabel("Сколько вариаций из каждого файла")
                Picker("Вариации", selection: Binding(
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
                    unikLabel("Как применить стили к нескольким файлам")
                    Picker("Режим", selection: unikOption(\.variations.mode)) {
                        Text("Все вариации для каждого файла").tag("all-variations")
                        Text("По одному стилю на файл").tag("preset-per-file")
                    }
                    .labelsHidden()
                }
                ForEach(0 ..< unik.options.variations.styleIds.count, id: \.self) { slot in
                    unikLabel(unik.options.variations.count > 1 ? "Стиль вариации \(slot + 1)" : "Стиль")
                    Picker("Стиль", selection: Binding(
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
                    Toggle("Настроить вручную", isOn: unikOption(\.manual.enabled))
                    if unik.options.manual.enabled {
                        unikSlider("Оттенок", value: unikOption(\.manual.hueShift), range: -180 ... 180, step: 1, format: "%.0f°")
                        unikSlider("Насыщенность", value: unikOption(\.manual.saturation), range: 0 ... 3, step: 0.05, format: "%.2f")
                        unikSlider("Резкость", value: unikOption(\.manual.sharpness), range: 0 ... 2, step: 0.05, format: "%.2f")
                        unikSlider("Длительность, мс", value: unikOption(\.manual.speedOffsetMs), range: -2000 ... 3000, step: 50, format: "%+.0f")
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
        card("Плашка 18+") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Добавить плашку 18+", isOn: unikOption(\.ageMark.enabled))
                unikHint("Готовые шаблоны по странам подбираются под соотношение сторон.")
                if unik.options.ageMark.enabled {
                    unikLabel("Страна")
                    Picker("Страна", selection: unikOption(\.ageMark.geoId)) {
                        Text("Выберите страну…").tag("")
                        ForEach(unik.catalog?.ageMarkGeos ?? []) { geo in
                            Text(geo.name).tag(geo.id)
                        }
                    }
                    .labelsHidden()
                    unikLabel("Расположение")
                    Picker("Расположение", selection: unikOption(\.ageMark.position)) {
                        Text("Сверху").tag("top")
                        Text("Снизу").tag("bottom")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .disabled(unik.isRunning)
        }
    }

    private var unikExtrasCard: some View {
        card("Дополнительно") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Заставка в начале", isOn: unikOption(\.intro.enabled))
                if unik.options.intro.enabled {
                    Toggle("Случайная из набора", isOn: unikOption(\.intro.random))
                    if unik.options.intro.random {
                        unikPath(unik.options.intro.library.isEmpty ? "" : "Набор: \(unik.options.intro.library.count) файл(ов)", placeholder: "Набор картинок не выбран")
                        button("Выбрать набор…", systemImage: "photo.on.rectangle", allowWhileBusy: true) {
                            let picked = model.unikalizator.chooseFiles(title: "Картинки для заставок", extensions: UnikalizatorLogic.imageExtensions, multiple: true)
                            if !picked.isEmpty { model.unikalizator.options.intro.library = picked }
                        }
                    } else {
                        unikPath(unik.options.intro.imagePath, placeholder: "Картинка не выбрана")
                        button("Выбрать картинку…", systemImage: "photo", allowWhileBusy: true) {
                            if let path = model.unikalizator.chooseFiles(title: "Картинка для заставки", extensions: UnikalizatorLogic.imageExtensions, multiple: false).first {
                                model.unikalizator.options.intro.imagePath = path
                            }
                        }
                    }
                    unikSlider("Длительность заставки, мс", value: unikOption(\.intro.durationMs), range: 100 ... 3000, step: 50, format: "%.0f")
                }
                Divider()
                Toggle("Видео-слой поверх", isOn: unikOption(\.overlay.enabled))
                if unik.options.overlay.enabled {
                    Toggle("Случайный из набора", isOn: unikOption(\.overlay.random))
                    if unik.options.overlay.random {
                        unikPath(unik.options.overlay.library.isEmpty ? "" : "Набор: \(unik.options.overlay.library.count) файл(ов)", placeholder: "Набор видео не выбран")
                        button("Выбрать набор…", systemImage: "film.stack", allowWhileBusy: true) {
                            let picked = model.unikalizator.chooseFiles(title: "Видео для слоя поверх", extensions: UnikalizatorLogic.videoExtensions, multiple: true)
                            if !picked.isEmpty { model.unikalizator.options.overlay.library = picked }
                        }
                    } else {
                        unikPath(unik.options.overlay.videoPath, placeholder: "Видео не выбрано")
                        button("Выбрать видео…", systemImage: "film", allowWhileBusy: true) {
                            if let path = model.unikalizator.chooseFiles(title: "Видео для слоя поверх", extensions: UnikalizatorLogic.videoExtensions, multiple: false).first {
                                model.unikalizator.options.overlay.videoPath = path
                            }
                        }
                    }
                    unikSlider("Прозрачность слоя", value: unikOption(\.overlay.opacity), range: 0.05 ... 1, step: 0.05, format: "%.2f")
                }
                Divider()
                unikLabel("Заменить звук")
                unikPath(unik.options.audio.replacePath, placeholder: "Оставить звук из видео")
                HStack(spacing: 10) {
                    button("Выбрать звук…", systemImage: "music.note", allowWhileBusy: true) {
                        if let path = model.unikalizator.chooseFiles(title: "Новая звуковая дорожка", extensions: UnikalizatorLogic.audioExtensions, multiple: false).first {
                            model.unikalizator.options.audio.replacePath = path
                        }
                    }
                    if !unik.options.audio.replacePath.isEmpty {
                        button("Сбросить", systemImage: "xmark", allowWhileBusy: true) { model.unikalizator.options.audio.replacePath = "" }
                    }
                }
            }
            .disabled(unik.isRunning)
        }
    }

    private var unikNamingCard: some View {
        card("Название файла") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Схема имени", selection: unikOption(\.naming.mode)) {
                    Text("ГЕО + формат + версия").tag("structured")
                    Text("Исходное + случайный хвост").tag("source-random")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if unik.options.naming.mode == "structured" {
                    HStack(spacing: 10) {
                        TextField("ГЕО (AU)", text: unikOption(\.naming.geo))
                            .textFieldStyle(.roundedBorder)
                        TextField("Тип (instagram)", text: unikOption(\.naming.presetToken))
                            .textFieldStyle(.roundedBorder)
                        TextField("Версия (v1)", text: unikOption(\.naming.versionToken))
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    TextField("Хвост (пусто — случайный)", text: unikOption(\.naming.randomTail))
                        .textFieldStyle(.roundedBorder)
                }
                let first = unik.files.first?.path ?? ""
                let outputs = unik.plannedOutputs
                Text("Пример: " + UnikalizatorLogic.previewName(options: unik.options, firstFile: first, outputs: outputs)
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
                Text("Настройте раздел и сохраните набор под своим именем, например «Reels DE 18+».")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    Picker("Сохранённые наборы", selection: $chosen) {
                        Text("Выберите набор…").tag("")
                        ForEach(unik.presets) { preset in Text(preset.name).tag(preset.name) }
                    }
                    .labelsHidden()
                    .onChange(of: chosen) { _, value in if !value.isEmpty { name = value } }
                    Button("Применить") { unik.applyPreset(named: chosen) }
                        .disabled(chosen.isEmpty || unik.isRunning)
                    Button(role: .destructive) {
                        unik.deletePreset(named: chosen)
                        chosen = ""
                    } label: { Image(systemName: "trash") }
                        .help("Удалить набор")
                        .disabled(chosen.isEmpty || unik.isRunning)
                }
            }
            HStack(spacing: 8) {
                TextField("Название набора", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(unik.isRunning)
                Button(nameExists ? "Заменить" : "Сохранить") {
                    unik.savePreset(named: name)
                    chosen = trimmedName
                }
                .disabled(trimmedName.isEmpty || unik.isRunning)
            }
        }
    }
}
