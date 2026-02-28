import SwiftUI

struct ContentView: View {
    @State private var settings = AppSettings.shared
    @State private var accessibilityGranted = AccessibilityHelper.isGranted()

    var body: some View {
        Form {
            Section("Modifier Key") {
                Picker("Modifier", selection: $settings.modifierKey) {
                    ForEach(ModifierKey.allCases) { key in
                        Text("\(key.symbol) \(key.rawValue)").tag(key)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Window Sizes") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Left width:")
                        Text("\(Int(settings.leftWidthPercent))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    Slider(value: $settings.leftWidthPercent, in: 20...80, step: 5)
                    Text(
                        "Left: \(Int(settings.leftWidthPercent))% / Right: \(Int(settings.rightWidthPercent))%"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Top height:")
                        Text("\(Int(settings.topHeightPercent))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    Slider(value: $settings.topHeightPercent, in: 20...80, step: 5)
                    Text(
                        "Top: \(Int(settings.topHeightPercent))% / Bottom: \(Int(settings.bottomHeightPercent))%"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Preview") {
                SnapPreview(
                    leftPercent: settings.leftWidthPercent,
                    topPercent: settings.topHeightPercent
                )
                .frame(height: 120)
            }

            Section("Permissions") {
                HStack {
                    Circle()
                        .fill(accessibilityGranted ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text("Accessibility")
                    Spacer()
                    if !accessibilityGranted {
                        Button("Grant") {
                            AccessibilityHelper.requestAccess()
                        }
                    } else {
                        Text("OK").foregroundStyle(.secondary)
                    }
                }

                Button("Refresh Status") {
                    accessibilityGranted = AccessibilityHelper.isGranted()
                }

                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }

            Section("Window Switcher") {
                Toggle("Enable \(settings.modifierKey.symbol) + Tab window switcher", isOn: $settings.windowSwitcherEnabled)
                if settings.windowSwitcherEnabled {
                    Label {
                        Text("Experimental feature. Works best within a single Space — switching to windows on other Spaces may be unreliable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "flask")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Window Control") {
                Toggle("Enable window control hotkeys", isOn: $settings.windowControlEnabled)
                if settings.windowControlEnabled {
                    let mod = settings.modifierKey.symbol
                    KeyBindingRow(mod: mod, key: $settings.controlKeyMaximize,      label: "Maximize / Restore")
                    KeyBindingRow(mod: mod, key: $settings.controlKeyMinimizeAll,   label: "Minimize all windows")
                    KeyBindingRow(mod: mod, key: $settings.controlKeyMinimizeActive,label: "Minimize active window")
                    KeyBindingRow(mod: mod, key: $settings.controlKeyCloseActive,   label: "Close active window")
                    VStack(alignment: .leading, spacing: 6) {
                        KeyBindingRow(mod: mod, key: $settings.controlKeyCenter, label: "Center window")
                        HStack {
                            Slider(value: $settings.centerWidthPercent, in: 30...90, step: 5)
                            Text("\(Int(settings.centerWidthPercent))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }

            AppLayoutsSection()

            Section("Hotkeys") {
                let mod = settings.modifierKey.symbol
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    if settings.windowSwitcherEnabled {
                        GridRow {
                            Text("\(mod) + Tab")
                            Text("Switch windows (experimental)").foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("").gridCellColumns(2)
                        }
                    }
                    if settings.windowControlEnabled {
                        GridRow {
                            Text("\(mod) + \(settings.controlKeyMaximize)")
                            Text("Maximize / Restore").foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("\(mod) + \(settings.controlKeyMinimizeAll)")
                            Text("Minimize all windows").foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("\(mod) + \(settings.controlKeyMinimizeActive)")
                            Text("Minimize active window").foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("\(mod) + \(settings.controlKeyCloseActive)")
                            Text("Close active window").foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("\(mod) + \(settings.controlKeyCenter)")
                            Text("Center (\(Int(settings.centerWidthPercent))%)").foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("").gridCellColumns(2)
                        }
                    }
                    GridRow {
                        Text("\(mod) + \u{2190}")
                        Text("Left half").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("\(mod) + \u{2192}")
                        Text("Right half").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("\(mod) + \u{2191}")
                        Text("Top half").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("\(mod) + \u{2193}")
                        Text("Bottom half").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("\(mod) + \u{2190} + \u{2191}")
                        Text("Top left quarter").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("\(mod) + \u{2190} + \u{2193}")
                        Text("Bottom left quarter").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("\(mod) + \u{2192} + \u{2191}")
                        Text("Top right quarter").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("\(mod) + \u{2192} + \u{2193}")
                        Text("Bottom right quarter").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("").gridCellColumns(2)
                    }
                    GridRow {
                        Text("⇧ + \(mod) + \u{2190} + \u{2191}")
                        Text("Top left eighth").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("⇧ + \(mod) + \u{2190} + \u{2193}")
                        Text("Bottom left eighth").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("⇧ + \(mod) + \u{2192} + \u{2191}")
                        Text("Top right eighth").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("⇧ + \(mod) + \u{2192} + \u{2193}")
                        Text("Bottom right eighth").foregroundStyle(.secondary)
                    }
                }
                .font(.system(.body, design: .monospaced))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Key Binding Row

struct KeyBindingRow: View {
    let mod: String
    @Binding var key: String
    let label: String

    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                KbdBadge(text: mod)
                Text("+")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 1)
                KbdBadge(text: key.isEmpty ? "?" : key, editable: true, focused: $focused) { newVal in
                    let upper = newVal.uppercased()
                    let filtered = upper.filter { $0.isLetter }
                    if let last = filtered.last { key = String(last) }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

struct KbdBadge: View {
    let text: String
    var editable: Bool = false
    var focused: FocusState<Bool>.Binding? = nil
    var onInput: ((String) -> Void)? = nil

    @State private var editText: String = ""

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1.5)

            if editable, let focused = focused, let onInput = onInput {
                TextField("", text: $editText)
                    .focused(focused)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .opacity(0)
                    .frame(width: 28, height: 22)
                    .onChange(of: editText) { _, newVal in
                        onInput(newVal)
                        editText = ""
                    }
                Text(text)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .allowsHitTesting(false)
            } else {
                Text(text)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
        .frame(width: 28, height: 22)
    }
}

// MARK: - Snap Preview

struct SnapPreview: View {
    let leftPercent: Double
    let topPercent: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let splitX = w * leftPercent / 100
            let splitY = h * topPercent / 100

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.secondary, lineWidth: 1)

                Path { path in
                    path.move(to: CGPoint(x: splitX, y: 0))
                    path.addLine(to: CGPoint(x: splitX, y: h))
                }
                .stroke(.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                Path { path in
                    path.move(to: CGPoint(x: 0, y: splitY))
                    path.addLine(to: CGPoint(x: w, y: splitY))
                }
                .stroke(.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                VStack {
                    HStack {
                        Text("\(Int(leftPercent))%")
                            .frame(width: splitX, height: splitY)
                        Text("\(Int(100 - leftPercent))%")
                            .frame(width: w - splitX, height: splitY)
                    }
                    HStack {
                        Text("\(Int(leftPercent))%")
                            .frame(width: splitX, height: h - splitY)
                        Text("\(Int(100 - leftPercent))%")
                            .frame(width: w - splitX, height: h - splitY)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}
