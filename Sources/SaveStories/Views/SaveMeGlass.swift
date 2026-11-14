import SwiftUI

// Дизайн-система SaveMe в стиле Liquid Glass (macOS 26/27).
// Панели и элементы управления — системное стекло; при «Уменьшении прозрачности»,
// «Увеличении контраста» и на macOS 14–15 используются плотные материалы.

enum SaveMeMetrics {
    static let cardRadius: CGFloat = 26
    static let controlRadius: CGFloat = 16
    static let itemRadius: CGFloat = 16
    static let innerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
}

/// Все цвета интерфейса объявлены здесь; в представлениях — только эти имена.
enum SaveMePalette {
    /// Фирменный изумрудный акцент: основное действие, выделение и состояние, больше ничего.
    static func brand(dark: Bool) -> Color {
        dark ? Color(red: 0.30, green: 0.78, blue: 0.62) : Color(red: 0.07, green: 0.47, blue: 0.37)
    }

    /// Заливка акцентных кнопок: достаточно тёмная для белого текста в обеих темах.
    static func brandFill(dark: Bool) -> Color {
        dark ? Color(red: 0.11, green: 0.53, blue: 0.41) : Color(red: 0.07, green: 0.47, blue: 0.37)
    }

    // Цвета состояния.
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let info = Color.blue
    static let neutral = Color.gray

    static let onAccent = Color.white

    static func secondaryText(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.74) : Color.black.opacity(0.64)
    }

    /// «Колодец» поля ввода внутри стеклянной панели.
    static func well(dark: Bool) -> Color {
        dark ? Color.black.opacity(0.26) : Color.white.opacity(0.62)
    }

    /// Заливка второстепенных кнопок и меток внутри панели.
    static func control(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color.white.opacity(0.46)
    }

    static func hairline(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

/// Фиксированная шкала кеглей (шаг около 1,15–1,2). Других размеров в интерфейсе нет.
enum SaveMeTextRole: CGFloat {
    case micro = 11
    case label = 12
    case body = 13
    case title = 15
    case heading = 18
    case display = 22
}

extension Font {
    /// Шрифт интерфейса: SF Rounded, для путей, ссылок и логов — моноширинный.
    static func saveMe(_ role: SaveMeTextRole, _ weight: Font.Weight = .regular, mono: Bool = false) -> Font {
        .system(size: role.rawValue, weight: weight, design: mono ? .monospaced : .rounded)
    }
}

/// Снимки экрана для CI делаются внеэкранной отрисовкой, а она не умеет рисовать системное стекло (выходит чёрным).
/// Поэтому при `--design-preview --preview-screenshot=…` поверхности рисуются плотными, как при «Уменьшении прозрачности».
enum SaveMeRendering {
    static let forceSolid: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--design-preview") && PreviewCapture.screenshotPath != nil
    }()
}

// MARK: - Кнопки

private struct SaveMeGlassButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let prominent: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            styled(content).modifier(OptionalTint(tint: tint))
        } else {
            // Второстепенные кнопки — нейтральное стекло, а не акцентный цвет окна.
            styled(content).tint(tint)
        }
    }

    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency, contrast != .increased, !SaveMeRendering.forceSolid {
            if prominent {
                content.buttonStyle(.glassProminent).buttonBorderShape(.capsule)
            } else {
                content.buttonStyle(.glass).buttonBorderShape(.capsule)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

private struct OptionalTint: ViewModifier {
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let tint { content.tint(tint) } else { content }
    }
}

// MARK: - Стеклянная поверхность

private struct SaveMeGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency || contrast == .increased || SaveMeRendering.forceSolid {
            content
                .background {
                    ZStack {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                        if let tint { shape.fill(tint.opacity(0.5)) }
                    }
                }
                .overlay { shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
                .clipShape(shape)
        } else if #available(macOS 26, *) {
            content
                .clipShape(shape)
                .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.regularMaterial)
                        if let tint { shape.fill(tint) }
                    }
                }
                .overlay {
                    shape.strokeBorder(SaveMePalette.hairline(dark: colorScheme == .dark), lineWidth: 1)
                }
                .clipShape(shape)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.07), radius: 14, y: 6)
        }
    }
}

extension View {
    func saveMeGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        modifier(SaveMeGlassButtonModifier(prominent: prominent, tint: tint))
    }

    /// Панель из Liquid Glass со скруглением `cornerRadius`.
    func saveMeGlassSurface(cornerRadius: CGFloat = SaveMeMetrics.cardRadius, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(SaveMeGlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// Мягкий край прокрутки под стеклянной панелью инструментов.
    @ViewBuilder
    func saveMeSoftScrollEdge() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

/// Объединяет соседние стеклянные элементы: общий проход отрисовки и слияние форм.
struct SaveMeGlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let spacing: CGFloat
    @ViewBuilder var content: Content

    @ViewBuilder
    var body: some View {
        if #available(macOS 26, *), !reduceTransparency, contrast != .increased, !SaveMeRendering.forceSolid {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Фон окна

/// Статичный цветной фон, который преломляется в стеклянных панелях. Не анимируется — не тратит GPU в простое.
struct SaveMeBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                Color(nsColor: .windowBackgroundColor)
            } else if #available(macOS 15, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.55, 0.45], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1],
                    ],
                    colors: colorScheme == .dark ? Self.darkMesh : Self.lightMesh,
                    smoothsColors: true
                )
            } else {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Self.darkMesh[0], Self.darkMesh[4], Self.darkMesh[8]]
                        : [Self.lightMesh[0], Self.lightMesh[4], Self.lightMesh[8]],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }

    // Нейтральная основа с одним оттенком — фирменным зелёным; стеклу есть что преломлять.
    private static let lightMesh: [Color] = [
        Color(red: 0.97, green: 0.96, blue: 0.93), Color(red: 0.95, green: 0.97, blue: 0.95), Color(red: 0.90, green: 0.96, blue: 0.93),
        Color(red: 0.95, green: 0.96, blue: 0.94), Color(red: 0.94, green: 0.98, blue: 0.96), Color(red: 0.86, green: 0.95, blue: 0.91),
        Color(red: 0.91, green: 0.95, blue: 0.93), Color(red: 0.84, green: 0.94, blue: 0.89), Color(red: 0.76, green: 0.91, blue: 0.84),
    ]

    private static let darkMesh: [Color] = [
        Color(red: 0.07, green: 0.08, blue: 0.08), Color(red: 0.06, green: 0.09, blue: 0.09), Color(red: 0.05, green: 0.12, blue: 0.11),
        Color(red: 0.07, green: 0.08, blue: 0.09), Color(red: 0.06, green: 0.11, blue: 0.10), Color(red: 0.04, green: 0.16, blue: 0.13),
        Color(red: 0.06, green: 0.09, blue: 0.09), Color(red: 0.04, green: 0.15, blue: 0.12), Color(red: 0.04, green: 0.22, blue: 0.17),
    ]
}
