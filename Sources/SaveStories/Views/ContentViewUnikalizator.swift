import AppKit
import AVFoundation
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
            .font(.saveMe(.label, .semibold))
            .foregroundStyle(secondaryText)
    }

    private func unikHint(_ text: String) -> some View {
        Text(text)
            .font(.saveMe(.label, .medium))
            .foregroundStyle(secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func unikPath(_ path: String, placeholder: String) -> some View {
        Text(path.isEmpty ? placeholder : path)
            .font(.saveMe(.label, .medium, mono: true))
            .foregroundStyle(path.isEmpty ? secondaryText : primaryText)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(fieldBackground)
    }

    /// Шаги раздела — в том же порядке, что и в онлайн-сервисе Betrch Unik.
    enum UnikStep: Int, CaseIterable, Identifiable {
        case sources, ageMark, format, naming, style, extras, review

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .sources: L("Исходники")
            case .ageMark: L("Плашка 18+")
            case .format: L("Формат")
            case .naming: L("Название файла")
            case .style: L("Стиль")
            case .extras: L("Дополнительно")
            case .review: L("Запуск")
            }
        }

        var detail: String {
            switch self {
            case .sources: L("Добавьте видео и картинки, которые нужно обработать.")
            case .ageMark: L("Готовые шаблоны по странам подбираются под соотношение сторон.")
            case .format: L("Размер кадра, вписывание, частота кадров и качество.")
            case .naming: L("Как будут называться готовые файлы.")
            case .style: L("Сколько вариаций сделать и как они будут выглядеть.")
            case .extras: L("Метаданные, заставка, слой поверх и звук.")
            case .review: L("Проверьте настройки и запустите обработку.")
            }
        }

        var symbol: String {
            switch self {
            case .sources: "doc.on.doc"
            case .ageMark: "18.circle"
            case .format: "aspectratio"
            case .naming: "character.cursor.ibeam"
            case .style: "paintpalette"
            case .extras: "slider.horizontal.3"
            case .review: "checkmark.seal"
            }
        }
    }

    private var unikCurrentStep: UnikStep { UnikStep(rawValue: unikStep) ?? .sources }

    private func unikGo(to step: Int) {
        let clamped = min(max(step, 0), UnikStep.allCases.count - 1)
        withAnimation(.smooth(duration: 0.25)) { unikStep = clamped }
    }

    var unikalizatorView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1000
            let horizontalPadding = contentHorizontalPadding(for: proxy.size.width)

            ScrollView {
                SaveMeGlassGroup(spacing: 0) {
                VStack(alignment: .leading, spacing: SaveMeMetrics.sectionSpacing) {
                    unikFFmpegBanner
                    unikStepNavigation(compact: compact)
                    if compact {
                        unikStepCard
                        unikProgressCard
                        unikPresetsCard
                    } else {
                        HStack(alignment: .top, spacing: SaveMeMetrics.sectionSpacing) {
                            unikStepCard
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            VStack(alignment: .leading, spacing: SaveMeMetrics.sectionSpacing) {
                                unikProgressCard
                                unikPresetsCard
                            }
                            .frame(width: 340, alignment: .topLeading)
                        }
                    }
                }
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 28)
                .padding(.top, 8)
                }
            }
            .task { await model.unikalizator.refresh() }
        }
    }

    // MARK: FFmpeg

    @ViewBuilder
    private var unikFFmpegBanner: some View {
        switch unik.ffmpeg {
        case .missing:
            card(L("FFmpeg не установлен"), symbol: "arrow.down.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    unikHint(L("Для обработки нужен FFmpeg. Он скачивается один раз и хранится в папке приложения."))
                    button(L("Установить FFmpeg"), systemImage: "arrow.down.circle", prominent: true, allowWhileBusy: true) {
                        Task { await model.unikalizator.installFFmpeg() }
                    }
                }
            }
        case .installing:
            card(L("Устанавливаю FFmpeg…"), symbol: "arrow.down.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(unik.installPercent), total: 100)
                        .tint(brandTint)
                        .animation(.smooth(duration: 0.45), value: unik.installPercent)
                    unikHint(unik.installMessage)
                }
            }
        case .failed(let message):
            card(L("FFmpeg не готов"), symbol: "exclamationmark.triangle") {
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

    // MARK: Шаги

    /// Полоса шагов: номер и название, текущий шаг выделен акцентом. В узком окне названия остаются только у текущего.
    private func unikStepNavigation(compact: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(UnikStep.allCases) { step in
                let isCurrent = step.rawValue == unikStep
                Button {
                    unikGo(to: step.rawValue)
                } label: {
                    HStack(spacing: 6) {
                        if !isCurrent, step != .sources || unikStep > 0, unikStepHasProblem(step) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.saveMe(.label, .semibold))
                                .foregroundStyle(SaveMePalette.warning)
                                .accessibilityLabel(L("Требуется настройка"))
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.saveMe(.label, .semibold))
                                .monospacedDigit()
                        }
                        if !compact || isCurrent {
                            Text(step.title)
                                .font(.saveMe(.body, isCurrent ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .foregroundStyle(isCurrent ? SaveMePalette.onAccent : primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: compact && !isCurrent ? nil : .infinity)
                    .background(Capsule(style: .continuous).fill(isCurrent ? prominentButtonTint : Color.clear))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Шаг {0} из {1}", step.rawValue + 1, UnikStep.allCases.count) + ". " + step.title)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity)
        .saveMeGlassSurface(cornerRadius: 22)
    }

    private var unikStepCard: some View {
        let step = unikCurrentStep
        return card(step.title, symbol: step.symbol) {
            VStack(alignment: .leading, spacing: 16) {
                unikHint(step.detail)

                Group {
                    switch step {
                    case .sources: unikSourcesStep
                    case .ageMark: unikAgeMarkStep
                    case .format: unikFormatStep
                    case .naming: unikNamingStep
                    case .style: unikStyleStep
                    case .extras: unikExtrasStep
                    case .review: unikReviewStep
                    }
                }
                .id(step)
                .transition(.opacity)

                Divider()

                HStack(spacing: 12) {
                    Button {
                        unikGo(to: unikStep - 1)
                    } label: {
                        Label(L("Назад"), systemImage: "chevron.left")
                    }
                    .saveMeGlassButton()
                    .controlSize(.large)
                    .disabled(unikStep == 0)

                    Spacer(minLength: 0)

                    Text(L("Шаг {0} из {1}", unikStep + 1, UnikStep.allCases.count))
                        .font(.saveMe(.label))
                        .monospacedDigit()
                        .foregroundStyle(secondaryText)

                    Spacer(minLength: 0)

                    if step == .review {
                        unikCreateButton
                    } else {
                        Button {
                            unikGo(to: unikStep + 1)
                        } label: {
                            Label(L("Далее"), systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                        }
                        .saveMeGlassButton(prominent: true, tint: prominentButtonTint)
                        .controlSize(.large)
                    }
                }
            }
        }
    }

    private func unikToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.saveMe(.body, .medium))
                .foregroundStyle(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }

    private func unikSubheading(_ title: String) -> some View {
        Text(title)
            .font(.saveMe(.body, .semibold))
            .foregroundStyle(primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    /// Параметр с точным вводом и ползунком, как в онлайн-сервисе.
    private func unikParameter(_ title: String, hint: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, step: Double, fractionDigits: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                unikLabel(title)
                Spacer(minLength: 0)
                TextField(title, value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
                ), format: .number.precision(.fractionLength(0 ... fractionDigits)).grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .labelsHidden()
                    .frame(width: 84)
            }
            // Шаг задаётся округлением, а не параметром step: иначе ползунок рисует сотни делений.
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = ($0 / step).rounded() * step }
            ), in: range)
                .accessibilityLabel(title)
            if let hint { unikHint(hint) }
        }
    }

    // MARK: Шаг 1. Исходники

    private var unikSourcesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                button(L("Добавить файлы…"), systemImage: "plus", prominent: unik.files.isEmpty, allowWhileBusy: true) { model.unikalizator.chooseFiles() }
                    .disabled(unik.isRunning)
                if !unik.files.isEmpty {
                    button(L("Очистить"), systemImage: "trash", allowWhileBusy: true) { model.unikalizator.clearFiles() }
                        .disabled(unik.isRunning)
                }
            }
            unikHint(L("Или перетащите видео и картинки в это окно: {0}.", UnikalizatorLogic.mediaExtensions.joined(separator: ", ")))
            ForEach(unik.files) { file in
                HStack(spacing: 10) {
                    Image(systemName: file.isImage ? "photo" : "film")
                        .foregroundStyle(secondaryText)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.saveMe(.body, .semibold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(file.info.isEmpty ? (file.isImage ? L("картинка") : L("видео")) : file.info)
                            .font(.saveMe(.label, .medium))
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
                    .accessibilityLabel(L("Убрать {0}", file.name))
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Divider() }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: unik.files)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .strokeBorder(brandTint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .background(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous).fill(brandTint.opacity(0.08)))
                .opacity(unikDropTargeted ? 1 : 0)
        )
        .padding(-8)
        .animation(.smooth(duration: 0.15), value: unikDropTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $unikDropTargeted) { [unikalizator = model.unikalizator] providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in unikalizator.addFiles([url]) }
                }
            }
            return true
        }
    }

    // MARK: Шаг 2. Плашка 18+

    private var unikAgeMarkStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            unikToggle(L("Добавить плашку 18+"), isOn: unikOption(\.ageMark.enabled))
            if unik.options.ageMark.enabled {
                unikLabel(L("Страна"))
                Picker(L("Страна"), selection: unikOption(\.ageMark.geoId)) {
                    Text(L("Выберите страну…")).tag("")
                    ForEach(unik.catalog?.ageMarkGeos ?? []) { geo in
                        Text(geo.name).tag(geo.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
                unikLabel(L("Расположение"))
                Picker(L("Расположение"), selection: unikOption(\.ageMark.position)) {
                    Text(L("Сверху")).tag("top")
                    Text(L("Снизу")).tag("bottom")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .disabled(unik.isRunning)
    }

    // MARK: Шаг 3. Формат

    private var unikFormatPresetBinding: Binding<String> {
        Binding(
            get: { model.unikalizator.options.formatPresetId },
            set: { model.unikalizator.applyFormatPreset($0) }
        )
    }

    private var unikFormatStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            unikLabel(L("Готовый формат"))
            Picker(L("Готовый формат"), selection: unikFormatPresetBinding) {
                ForEach(unik.catalog?.formatPresets ?? []) { preset in
                    Text(preset.name).tag(preset.id)
                }
                Text(L("Свой размер")).tag("custom")
            }
            .labelsHidden()
            .fixedSize()
            if unik.options.formatPresetId == "custom" {
                HStack(spacing: 10) {
                    TextField(L("Ширина"), value: unikOption(\.resize.width), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                    TextField(L("Высота"), value: unikOption(\.resize.height), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: 320)
            }
            unikLabel(L("Вписывание в кадр"))
            Picker(L("Вписывание"), selection: unikOption(\.resize.fit)) {
                Text(L("Заполнить (обрезка)")).tag("cover")
                Text(L("Целиком (с полями)")).tag("contain")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if unik.options.resize.fit == "contain" {
                unikLabel(L("Фон по краям"))
                Picker(L("Фон"), selection: unikOption(\.resize.backgroundStyle)) {
                    Text(L("Чёрные поля")).tag("bars")
                    Text(L("Размытие")).tag("blur")
                    Text(L("Цвет")).tag("solid")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if unik.options.resize.backgroundStyle == "solid" {
                    TextField("#111111", text: unikOption(\.resize.backgroundColor))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
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
            .fixedSize()
            unikLabel(L("Качество видео"))
            Picker(L("Качество"), selection: unikOption(\.bitrate)) {
                ForEach(unik.catalog?.bitrateOptions ?? []) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .disabled(unik.isRunning)
    }

    // MARK: Шаг 4. Название файла

    private var unikNamingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L("Схема имени"), selection: unikOption(\.naming.mode)) {
                Text(L("ГЕО + формат + версия")).tag("structured")
                Text(L("Исходное + случайный хвост")).tag("source-random")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
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
                    .frame(maxWidth: 320)
            }
            unikLabel(L("Пример"))
            unikPath(unikNamePreview, placeholder: "")
                .textSelection(.enabled)
        }
        .disabled(unik.isRunning)
    }

    private var unikNamePreview: String {
        let first = unik.files.first?.path ?? ""
        let outputs = unik.plannedOutputs
        return UnikalizatorLogic.previewName(options: unik.options, firstFile: first, outputs: outputs)
            + (outputs > 1 ? " … " + UnikalizatorLogic.previewName(options: unik.options, firstFile: first, outputs: outputs, index: outputs - 1) : "")
    }

    // MARK: Стили вариаций

    /// Стили вариаций задают оттенок, насыщенность, резкость и длительность, если результатов из файла несколько.
    private var unikMultipleStyles: Bool {
        unik.options.variations.count > 1 || (unik.files.count > 1 && unik.options.variations.mode == "preset-per-file")
    }

    // MARK: Шаг 5. Стиль

    /// Стили — карточками: название и что он делает, выбранный выделен акцентом.
    private func unikStyleCards(slot: Int) -> some View {
        let selected = unik.options.variations.styleIds[safe: slot] ?? "clean"
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(unik.catalog?.stylePresets ?? []) { style in
                let isSelected = style.id == selected
                Button {
                    model.unikalizator.setStyle(slot: slot, id: style.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.label)
                            .font(.saveMe(.body, .semibold))
                            .foregroundStyle(isSelected ? SaveMePalette.onAccent : primaryText)
                        Text(style.hint)
                            .font(.saveMe(.micro))
                            .foregroundStyle(isSelected ? SaveMePalette.onAccent.opacity(0.85) : secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous).fill(isSelected ? prominentButtonTint : controlFill))
                    .contentShape(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.label + ". " + style.hint)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(.smooth(duration: 0.2), value: selected)
    }

    private var unikStyleStep: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            .fixedSize()
            if unik.files.count > 1, unik.options.variations.count > 1 {
                unikLabel(L("Как применить стили к нескольким файлам"))
                Picker(L("Режим"), selection: unikOption(\.variations.mode)) {
                    Text(L("Все вариации для каждого файла")).tag("all-variations")
                    Text(L("По одному стилю на файл")).tag("preset-per-file")
                }
                .labelsHidden()
                .fixedSize()
            }
            ForEach(0 ..< unik.options.variations.styleIds.count, id: \.self) { slot in
                unikLabel(unik.options.variations.count > 1 ? L("Стиль вариации {0}", slot + 1) : L("Стиль"))
                unikStyleCards(slot: slot)
            }

            Divider()
            unikSubheading(L("Цвет и движение"))
            UnikEffectPreview(
                path: unik.files.first?.path,
                options: unik.options,
                stylePresets: unik.catalog?.stylePresets ?? [],
                showsStyle: !unikMultipleStyles,
                stroke: cardStroke,
                fill: inputFill,
                secondaryText: secondaryText
            )
            if unikMultipleStyles {
                unikHint(L("Оттенок, насыщенность, резкость и длительность задаются стилями вариаций выше. Яркость, контраст и отражение применятся ко всем."))
            } else {
                unikToggle(L("Настроить вручную"), isOn: unikOption(\.manual.enabled))
                if unik.options.manual.enabled {
                    unikParameter(L("Оттенок, °"), value: unikOption(\.manual.hueShift), range: -180 ... 180, step: 1, fractionDigits: 0)
                    unikParameter(L("Насыщенность"), hint: L("0 — чёрно-белое, 1 — исходная"), value: unikOption(\.manual.saturation), range: 0 ... 3, step: 0.01)
                    unikParameter(L("Резкость"), hint: L("0 — без дополнительной резкости"), value: unikOption(\.manual.sharpness), range: 0 ... 2, step: 0.01)
                    unikParameter(L("Длительность, мс"), hint: L("Минус — быстрее, плюс — медленнее"), value: unikOption(\.manual.speedOffsetMs), range: -30000 ... 30000, step: 50, fractionDigits: 0)
                }
            }
            unikParameter(L("Яркость"), hint: L("0 — исходная яркость"), value: unikOption(\.adjust.brightness), range: -0.25 ... 0.25, step: 0.01)
            unikParameter(L("Контраст"), hint: L("1 — исходный контраст"), value: unikOption(\.adjust.contrast), range: 0.5 ... 1.5, step: 0.01)
            unikToggle(L("Отразить исходник по горизонтали"), isOn: unikOption(\.adjust.horizontalFlip))
            unikHint(L("Текст и логотипы на исходнике тоже отразятся. Плашка, заставка и слой поверх не изменятся."))

        }
        .disabled(unik.isRunning)
    }

    // MARK: Шаг 6. Дополнительно

    private var unikExtrasStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            unikSubheading(L("Метаданные"))
            Picker(L("Метаданные"), selection: unikOption(\.metadata.mode)) {
                Text(L("Удалить")).tag("strip")
                Text(L("Дата экспорта")).tag("export-date")
                Text(L("Своя дата")).tag("custom-date")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if unik.options.metadata.mode == "custom-date" {
                TextField(L("ГГГГ-ММ-ДД"), text: unikOption(\.metadata.customDate))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
            }

            Divider()
            unikSubheading(L("Заставка в начале"))
            unikToggle(L("Добавить заставку"), isOn: unikOption(\.intro.enabled))
            if unik.options.intro.enabled {
                unikToggle(L("Случайная из набора"), isOn: unikOption(\.intro.random))
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
                unikParameter(L("Длительность заставки, мс"), value: unikOption(\.intro.durationMs), range: 100 ... 10000, step: 50, fractionDigits: 0)
            }

            Divider()
            unikSubheading(L("Видео-слой поверх"))
            unikToggle(L("Добавить слой поверх"), isOn: unikOption(\.overlay.enabled))
            if unik.options.overlay.enabled {
                unikToggle(L("Случайный из набора"), isOn: unikOption(\.overlay.random))
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
                unikParameter(L("Прозрачность слоя"), value: unikOption(\.overlay.opacity), range: 0.05 ... 1, step: 0.05)
            }

            Divider()
            unikSubheading(L("Звук"))
            unikToggle(L("Выровнять громкость"), isOn: unikOption(\.audio.normalize))
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

    // MARK: Шаг 7. Проверка и запуск

    private func unikSummaryRow(_ step: UnikStep, _ value: String) -> some View {
        Button {
            unikGo(to: step.rawValue)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(step.title)
                    .font(.saveMe(.label))
                    .foregroundStyle(secondaryText)
                    .frame(width: 130, alignment: .leading)
                Text(value)
                    .font(.saveMe(.body, .medium))
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: unikStepHasProblem(step) ? "exclamationmark.triangle.fill" : "chevron.right")
                    .font(.saveMe(.micro, .semibold))
                    .foregroundStyle(unikStepHasProblem(step) ? SaveMePalette.warning : secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(cardStroke).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .help(L("Перейти к шагу «{0}»", step.title))
    }

    private var unikAgeMarkSummary: String {
        let mark = unik.options.ageMark
        guard mark.enabled else { return L("Не добавляется") }
        let geo = unik.catalog?.ageMarkGeos.first { $0.id == mark.geoId }?.name ?? L("страна не выбрана")
        return geo + ", " + (mark.position == "top" ? L("Сверху") : L("Снизу")).lowercased()
    }

    private var unikFormatSummary: String {
        let o = unik.options
        let name = unik.catalog?.formatPresets.first { $0.id == o.formatPresetId }?.name ?? L("Свой размер")
        var parts = [name, "\(o.resize.width)×\(o.resize.height)", o.resize.fit == "cover" ? L("Заполнить (обрезка)") : L("Целиком (с полями)")]
        parts.append(o.fps == 0 ? L("Как есть") : "\(o.fps) fps")
        if let quality = unik.catalog?.bitrateOptions.first(where: { $0.value == o.bitrate })?.label { parts.append(quality) }
        return parts.joined(separator: ", ")
    }

    private var unikStyleSummary: String {
        let o = unik.options
        var parts: [String] = []
        if !unikMultipleStyles, o.manual.enabled {
            parts.append(L("Ручные настройки"))
        } else {
            let labels = o.variations.styleIds.map { id in unik.catalog?.stylePresets.first { $0.id == id }?.label ?? id }
            parts.append(labels.joined(separator: " / "))
        }
        if o.adjust.brightness != 0 { parts.append(L("Яркость") + " " + String(format: "%+.2f", o.adjust.brightness)) }
        if o.adjust.contrast != 1 { parts.append(L("Контраст") + " " + String(format: "%.2f", o.adjust.contrast)) }
        if o.adjust.horizontalFlip { parts.append(L("Отражение")) }
        return parts.joined(separator: ", ")
    }

    private var unikExtrasSummary: String {
        let o = unik.options
        var parts: [String] = []
        switch o.metadata.mode {
        case "export-date": parts.append(L("Метаданные") + ": " + L("Дата экспорта").lowercased())
        case "custom-date": parts.append(L("Метаданные") + ": " + L("Своя дата").lowercased())
        default: parts.append(L("Метаданные") + ": " + L("Удалить").lowercased())
        }
        if o.intro.enabled { parts.append(L("Заставка в начале")) }
        if o.overlay.enabled { parts.append(L("Видео-слой поверх")) }
        if !o.audio.replacePath.isEmpty { parts.append(L("Заменить звук")) }
        if o.audio.normalize { parts.append(L("Выровнять громкость")) }
        return parts.joined(separator: ", ")
    }

    /// Есть ли на шаге то, что не даст запустить обработку.
    private func unikStepHasProblem(_ step: UnikStep) -> Bool {
        let o = unik.options
        switch step {
        case .sources: return unik.files.isEmpty
        case .ageMark: return o.ageMark.enabled && o.ageMark.geoId.isEmpty
        case .format:
            let w = o.resize.width, h = o.resize.height
            return w < 2 || h < 2 || w > 8192 || h > 8192 || w % 2 != 0 || h % 2 != 0
        case .extras:
            return (o.intro.enabled && (o.intro.random ? o.intro.library.isEmpty : o.intro.imagePath.isEmpty))
                || (o.overlay.enabled && (o.overlay.random ? o.overlay.library.isEmpty : o.overlay.videoPath.isEmpty))
                || (o.metadata.mode == "custom-date" && !UnikalizatorLogic.isValidDate(o.metadata.customDate))
        case .naming, .style, .review: return false
        }
    }

    private var unikCreateButton: some View {
        HStack(spacing: 10) {
            if unik.isRunning {
                Button(role: .destructive) {
                    model.unikalizator.stop()
                } label: {
                    Label(L("Стоп"), systemImage: "stop.fill")
                }
                .saveMeGlassButton(tint: SaveMePalette.danger.opacity(0.5))
                .controlSize(.large)
            }
            Button {
                Task { await model.unikalizator.run() }
            } label: {
                Label(L("Создать") + (unik.plannedOutputs > 0 ? " (\(unik.plannedOutputs))" : ""), systemImage: "wand.and.stars")
                    .fontWeight(.semibold)
            }
            .saveMeGlassButton(prominent: true, tint: prominentButtonTint)
            .controlSize(.large)
            .disabled(!unik.isFFmpegReady || !unik.problems.isEmpty || unik.isRunning || unik.isInstalling)
        }
    }

    private var unikReviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                unikSummaryRow(.sources, unik.files.isEmpty ? L("Файлы не добавлены") : L("Файлов: {0}, будет создано: {1}", unik.files.count, unik.plannedOutputs))
                unikSummaryRow(.ageMark, unikAgeMarkSummary)
                unikSummaryRow(.format, unikFormatSummary)
                unikSummaryRow(.naming, unikNamePreview)
                unikSummaryRow(.style, unikStyleSummary)
                unikSummaryRow(.extras, unikExtrasSummary)
            }

            ForEach(unik.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.saveMe(.label, .medium))
                    .foregroundStyle(SaveMePalette.warning)
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

    // MARK: Ход обработки и пресеты

    private var unikProgressCard: some View {
        card(L("Ход обработки"), symbol: "hourglass") {
            VStack(alignment: .leading, spacing: 10) {
                if unik.jobs.isEmpty {
                    unikHint(unik.summary.isEmpty ? L("Результаты появятся здесь.") : unik.summary)
                } else {
                    ProgressView(value: Double(unik.overallPercent), total: 100)
                        .tint(brandTint)
                        .animation(.smooth(duration: 0.45), value: unik.overallPercent)
                    // Итог от воркера заменяет счётчик, а не повторяет его.
                    unikHint(unik.summary.isEmpty ? L("Готово {0} из {1}", unik.doneCount, unik.jobs.count) : unik.summary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.35), value: unik.doneCount)
                    ForEach(unik.jobs) { job in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.outputPath.isEmpty ? (job.label.isEmpty ? L("Файл {0}", job.index + 1) : job.label) : URL(fileURLWithPath: job.outputPath).lastPathComponent)
                                .font(.saveMe(.body, .semibold))
                                .foregroundStyle(primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack(spacing: 6) {
                                if job.status == .done {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(SaveMePalette.success)
                                        .symbolEffect(.bounce, options: .nonRepeating, value: job.status)
                                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                                }
                                Text(unikJobStatus(job))
                                    .monospacedDigit()
                                    .foregroundStyle(job.status == .error ? SaveMePalette.danger : secondaryText)
                                    .lineLimit(2)
                                    .contentTransition(.numericText())
                            }
                            .font(.saveMe(.label, .medium))
                            if job.status == .running {
                                ProgressView(value: Double(job.percent), total: 100)
                                    .tint(brandTint)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.smooth(duration: 0.35), value: job)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Divider() }
                    }
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

    private var unikPresetsCard: some View {
        card(L("Мои пресеты"), symbol: "bookmark") {
            UnikPresetsEditor(unik: unik, secondaryText: secondaryText)
        }
    }
}

/// Предпросмотр первого исходника: кадр в выбранных пропорциях с приближённым эффектом цвета и отражением.
/// Точный результат даёт только FFmpeg; здесь — быстрый ориентир, как в онлайн-сервисе.
private struct UnikEffectPreview: View {
    let path: String?
    let options: UnikOptions
    let stylePresets: [UnikStylePreset]
    /// Показывать ли оттенок и насыщенность стиля (при нескольких стилях они разные у каждой вариации).
    let showsStyle: Bool
    let stroke: Color
    let fill: Color
    let secondaryText: Color
    @State private var image: NSImage?

    private var aspect: CGFloat {
        let w = max(options.resize.width, 2), h = max(options.resize.height, 2)
        return CGFloat(w) / CGFloat(h)
    }

    var body: some View {
        // Как в воркере: при одном результате и ручных настройках — они, иначе — цвет выбранного стиля.
        // При нескольких стилях оттенок и насыщенность у вариаций разные, поэтому в предпросмотре их нет.
        let style = stylePresets.first { $0.id == options.variations.styleIds.first }
        let hue = showsStyle ? (options.manual.enabled ? options.manual.hueShift : style?.hueShift ?? 0) : 0
        let saturation = showsStyle ? (options.manual.enabled ? options.manual.saturation : style?.saturation ?? 1) : 1
        // Пока кадра нет (файл не добавлен или не читается), место под предпросмотр не занимаем.
        if image == nil {
            Color.clear.frame(height: 0).padding(.bottom, -14).task(id: path) { image = await Self.load(path) }
        } else {
        ZStack {
            if let image {
                if options.resize.fit == "contain" {
                    Image(nsImage: image).resizable().scaledToFill().blur(radius: 18).opacity(options.resize.backgroundStyle == "blur" ? 1 : 0)
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            } else {
                Image(systemName: "photo")
                    .font(.saveMe(.display))
                    .foregroundStyle(secondaryText)
            }
        }
        .scaleEffect(x: options.adjust.horizontalFlip ? -1 : 1, y: 1)
        .hueRotation(.degrees(hue))
        .saturation(saturation)
        .brightness(options.adjust.brightness)
        .contrast(options.adjust.contrast)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(aspect, contentMode: .fit)
        .background(options.resize.fit == "contain" && options.resize.backgroundStyle != "blur" ? Color.black : fill)
        .clipShape(RoundedRectangle(cornerRadius: SaveMeMetrics.innerRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: SaveMeMetrics.innerRadius, style: .continuous).strokeBorder(stroke, lineWidth: 1) }
        .frame(maxHeight: 240)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.2), value: options.adjust)
        .accessibilityLabel(L("Предпросмотр первого исходника"))
        .task(id: path) { image = await Self.load(path) }
        }
    }

    private static func load(_ path: String?) async -> NSImage? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        if UnikalizatorLogic.isImage(path) { return NSImage(contentsOf: url) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        guard let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image else { return nil }
        return NSImage(cgImage: frame, size: .zero)
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
                    .font(.saveMe(.label, .medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(L("Сохранённые наборы"), selection: $chosen) {
                    Text(L("Выберите набор…")).tag("")
                    ForEach(unik.presets) { preset in Text(preset.name).tag(preset.name) }
                }
                .labelsHidden()
                .onChange(of: chosen) { _, value in if !value.isEmpty { name = value } }
                HStack(spacing: 8) {
                    Button(L("Применить")) { unik.applyPreset(named: chosen) }
                        .saveMeGlassButton()
                        .disabled(chosen.isEmpty || unik.isRunning)
                    Button(role: .destructive) {
                        unik.deletePreset(named: chosen)
                        chosen = ""
                    } label: { Image(systemName: "trash") }
                        .saveMeGlassButton()
                        .help(L("Удалить набор"))
                        .accessibilityLabel(L("Удалить набор"))
                        .disabled(chosen.isEmpty || unik.isRunning)
                    Spacer(minLength: 0)
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
                .saveMeGlassButton()
                .disabled(trimmedName.isEmpty || unik.isRunning)
            }
        }
    }
}
