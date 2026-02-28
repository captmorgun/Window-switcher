import AppKit
import SwiftUI

// MARK: - App Layouts Section

struct AppLayoutsSection: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Section("App Layouts") {
            Toggle("Apply layouts on startup", isOn: $settings.layoutsEnabled)

            if settings.layoutsEnabled {
                Label {
                    Text("Each layout is applied to the corresponding Space in order (Layout 1 → Space 1, etc). Create the desired number of Spaces in macOS first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach($settings.layouts) { $layout in
                LayoutRow(layout: $layout, onDelete: {
                    settings.layouts.removeAll { $0.id == layout.id }
                })
            }

            Button {
                let n = settings.layouts.count + 1
                settings.layouts.append(AppLayout(name: "Layout \(n)", entries: []))
            } label: {
                Label("Add Layout", systemImage: "plus")
            }
        }
    }
}

// MARK: - Layout Row

private struct LayoutRow: View {
    @Binding var layout: AppLayout
    let onDelete: () -> Void

    @State private var showAppPicker = false
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach($layout.entries) { $entry in
                EntryRow(entry: $entry, onDelete: {
                    layout.entries.removeAll { $0.id == entry.id }
                })
            }

            HStack {
                Button {
                    showAppPicker = true
                } label: {
                    Label("Add App", systemImage: "plus.circle")
                        .font(.callout)
                }
                .sheet(isPresented: $showAppPicker) {
                    AppPickerSheet { bundleID, appName in
                        layout.entries.append(LayoutEntry(
                            bundleID: bundleID,
                            appName: appName,
                            snapRegionID: .leftHalf
                        ))
                    }
                }

                Spacer()

                Button {
                    LayoutApplier.shared.applyLayout(layout)
                } label: {
                    Label("Apply Now", systemImage: "play.circle")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            }
            .padding(.top, 2)
        } label: {
            HStack {
                TextField("Layout name", text: $layout.name)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Entry Row

private struct EntryRow: View {
    @Binding var entry: LayoutEntry
    let onDelete: () -> Void

    private var urlLabel: String? {
        guard let path = entry.openURL else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(bundleID: entry.bundleID)
                .frame(width: 20, height: 20)

            Text(entry.appName)
                .lineLimit(1)
                .truncationMode(.tail)

            if let label = urlLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Picker("", selection: $entry.snapRegionID) {
                ForEach(SnapRegionID.allCases) { region in
                    Text(region.displayName).tag(region)
                }
            }
            .labelsHidden()
            .frame(width: 145)

            Button {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.title = "Choose for \(entry.appName)"
                if panel.runModal() == .OK, let url = panel.url {
                    entry.openURL = url.path
                }
            } label: {
                Image(systemName: entry.openURL == nil ? "folder.badge.plus" : "folder.fill.badge.plus")
                    .foregroundColor(entry.openURL == nil ? .secondary : .blue)
            }
            .buttonStyle(.borderless)
            .help(entry.openURL == nil ? "Set file or folder to open" : "Change: \(entry.openURL!)")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
        .padding(.leading, 4)
    }
}

// MARK: - App Icon

private struct AppIconView: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let iconFile = bundle.infoDictionary?["CFBundleIconFile"] as? String {
            let iconURL = bundle.url(forResource: iconFile, withExtension: iconFile.hasSuffix(".icns") ? "" : "icns")
                ?? bundle.url(forResource: iconFile, withExtension: "")
            if let iconURL, let image = NSImage(contentsOf: iconURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                fallbackIcon
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "app.dashed")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.secondary)
    }
}

// MARK: - App Picker Sheet

struct AppPickerSheet: View {
    let onSelect: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var apps: [InstalledApp] = []

    var filtered: [InstalledApp] {
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose App")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 8)

            List(filtered) { app in
                HStack(spacing: 10) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                    Text(app.name)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(app.bundleID, app.name)
                    dismiss()
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 320, height: 440)
        .onAppear { apps = loadInstalledApps() }
    }
}

// MARK: - Installed App model

struct InstalledApp: Identifiable {
    let id: String  // bundleID
    var bundleID: String { id }
    let name: String
    let icon: NSImage?
}

private func loadInstalledApps() -> [InstalledApp] {
    let fm = FileManager.default
    let appDirs = ["/Applications", "/Applications/Utilities",
                   "/System/Applications", "/System/Applications/Utilities",
                   "\(NSHomeDirectory())/Applications"]

    var result: [InstalledApp] = []
    var seen = Set<String>()

    for dir in appDirs {
        let url = URL(fileURLWithPath: dir)
        guard let items = try? fm.contentsOfDirectory(at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { continue }

        for item in items where item.pathExtension == "app" {
            guard let bundle = Bundle(url: item),
                  let bid = bundle.bundleIdentifier,
                  !seen.contains(bid) else { continue }
            seen.insert(bid)

            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? item.deletingPathExtension().lastPathComponent

            let icon = NSWorkspace.shared.icon(forFile: item.path)
            result.append(InstalledApp(id: bid, name: name, icon: icon))
        }
    }

    return result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
}
