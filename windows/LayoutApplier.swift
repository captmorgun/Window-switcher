import AppKit
import os.log

private let log = OSLog(subsystem: "com.windows.app", category: "LayoutApplier")
private let logFileURL = URL(fileURLWithPath: "/tmp/windows_layout_debug.log")
private let logFileLock = NSLock()
private func wlog(_ msg: String) {
    os_log("%{public}@", log: log, type: .info, msg)
    let line = "\(Date()) \(msg)\n"
    logFileLock.lock()
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logFileURL)
        }
    }
    logFileLock.unlock()
}

final class LayoutApplier {
    static let shared = LayoutApplier()
    private init() {}

    private struct Job {
        let entry: LayoutEntry
        let targetIdx: Int      // 1-based Desktop index
        let targetUUID: String?
    }

    func applyAll() {
        DispatchQueue.global(qos: .userInitiated).async {
            self._applyAll()
        }
    }

    private func _applyAll() {
        let layouts = AppSettings.shared.layouts
        guard !layouts.isEmpty else {
            wlog("[LayoutApplier] No layouts configured")
            return
        }

        let spaceUUIDs = getSpaceUUIDs()
        wlog("[LayoutApplier] Spaces: \(spaceUUIDs)")
        wlog("[LayoutApplier] Layouts: \(layouts.count)")

        var jobs: [Job] = []
        for (i, layout) in layouts.enumerated() {
            let uuid = i < spaceUUIDs.count ? spaceUUIDs[i] : nil
            for entry in layout.entries {
                jobs.append(Job(entry: entry, targetIdx: i + 1, targetUUID: uuid))
            }
        }

        _applyJobs(jobs)
    }

    private func _applyJobs(_ jobs: [Job]) {
        // Check which windows are already on the correct Desktop
        let allBundleIDs = Set(jobs.map { $0.entry.bundleID })
        let allRunningWIDs: [UInt32] = allBundleIDs.compactMap { findRunningApp(bundleID: $0) }
            .flatMap { windowIDsForPID($0.processIdentifier) }
        let currentSpaceMap = windowSpaceMap(for: allRunningWIDs)
        wlog("[LayoutApplier] Window→space map: \(currentSpaceMap)")

        var consumedWIDs = Set<UInt32>()
        var needsLaunch: [Job] = []
        var needsPosition: [Job] = []

        for job in jobs {
            let wids = NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == job.entry.bundleID }
                .flatMap { windowIDsForPID($0.processIdentifier) }
            let match = wids.first { !consumedWIDs.contains($0) && currentSpaceMap[$0] == job.targetIdx }
            if let wid = match {
                wlog("[LayoutApplier] '\(job.entry.appName)' window \(wid) already on Desktop \(job.targetIdx) → position")
                consumedWIDs.insert(wid)
                needsPosition.append(job)
            } else {
                wlog("[LayoutApplier] '\(job.entry.appName)' not on Desktop \(job.targetIdx) → launch")
                needsLaunch.append(job)
            }
        }

        // If any instance of a bundleID needs launch, kill ALL instances of it
        // (and promote its position-only jobs to launch too)
        let bundlesToKill = Set(needsLaunch.map { $0.entry.bundleID })
        let promoted = needsPosition.filter { bundlesToKill.contains($0.entry.bundleID) }
        needsLaunch += promoted
        needsPosition = needsPosition.filter { !bundlesToKill.contains($0.entry.bundleID) }

        if !bundlesToKill.isEmpty {
            for bundleID in bundlesToKill {
                for app in NSWorkspace.shared.runningApplications.filter({ $0.bundleIdentifier == bundleID }) {
                    wlog("[LayoutApplier] Killing '\(app.localizedName ?? bundleID)' pid \(app.processIdentifier)")
                    app.forceTerminate()
                }
            }
            var waited = 0.0
            while waited < 8.0 {
                let stillRunning = bundlesToKill.filter { b in
                    NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == b }
                }
                if stillRunning.isEmpty { break }
                Thread.sleep(forTimeInterval: 0.3)
                waited += 0.3
            }
            wlog("[LayoutApplier] All killed, waited \(String(format: "%.1f", waited))s")
            Thread.sleep(forTimeInterval: 1.5)
        }

        for job in needsLaunch {
            launchJob(job)
        }

        for job in needsPosition {
            positionJob(job)
        }
    }

    // Apply a single layout: full cycle (detect → kill → launch → move → position).
    func applyLayout(_ layout: AppLayout) {
        let layouts = AppSettings.shared.layouts
        let spaceUUIDs = getSpaceUUIDs()
        let idx = layouts.firstIndex { $0.id == layout.id } ?? 0
        let targetIdx = idx + 1
        let uuid = idx < spaceUUIDs.count ? spaceUUIDs[idx] : nil
        let jobs = layout.entries.map { Job(entry: $0, targetIdx: targetIdx, targetUUID: uuid) }
        DispatchQueue.global(qos: .userInitiated).async {
            self._applyJobs(jobs)
        }
    }

    // MARK: - Core launch logic

    private func launchJob(_ job: Job) {
        let entry = job.entry
        let spaceIDs = allSpaceIdsAndIndexes()
        guard let targetSpaceID = spaceIDs.first(where: { $0.1 == job.targetIdx })?.0 else {
            wlog("[LayoutApplier] ERROR: no space for Desktop \(job.targetIdx)")
            return
        }

        wlog("[LayoutApplier] Launching '\(entry.appName)' → Desktop \(job.targetIdx)...")

        // Switch to target space so the app opens there naturally
        DispatchQueue.main.sync {
            if let uuid = NSScreen.main?.uuid() {
                CGSManagedDisplaySetCurrentSpace(CGS_CONNECTION, uuid as CFString, targetSpaceID)
            }
        }
        Thread.sleep(forTimeInterval: 0.4)

        // Snapshot all existing WIDs for this bundleID before launching
        let widsBefore = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == entry.bundleID }
                .flatMap { windowIDsForPID($0.processIdentifier) }
        )

        guard let app = launchApp(bundleID: entry.bundleID, openURL: entry.openURL) else {
            wlog("[LayoutApplier] ERROR: could not launch '\(entry.appName)'")
            return
        }
        wlog("[LayoutApplier] Launched '\(entry.appName)' pid \(app.processIdentifier)")

        // Some apps (e.g. Terminal) launch without creating a window when another instance exists.
        // Wait briefly then force-open a window via AppleScript if needed.
        Thread.sleep(forTimeInterval: 1.0)
        let hasWindow = !windowIDsForPID(app.processIdentifier).isEmpty
        if !hasWindow {
            wlog("[LayoutApplier] '\(entry.appName)' has no window after 1s — forcing via AppleScript")
            let script = "tell application id \"\(entry.bundleID)\" to do script \"\""
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error { wlog("[LayoutApplier] AppleScript error: \(error)") }
        }

        // Wait for a NEW window (WID not in widsBefore) from this app.
        // Keep space switched to targetSpaceID so AX can see it.
        guard let (axWindow, wid) = waitForNewWindowExcluding(
            bundleID: entry.bundleID,
            excludedWIDs: widsBefore,
            targetSpaceID: targetSpaceID,
            timeout: 20.0
        ) else {
            wlog("[LayoutApplier] ERROR: timeout waiting for new window of '\(entry.appName)'")
            return
        }
        wlog("[LayoutApplier] Got new window \(wid) for '\(entry.appName)'")

        // Move window to target space via CGS
        let allSpaceIDs = spaceIDs.map { $0.0 }
        let otherSpaces = allSpaceIDs.filter { $0 != targetSpaceID }
        CGSAddWindowsToSpaces(CGS_CONNECTION, [wid] as NSArray, [targetSpaceID] as NSArray)
        if !otherSpaces.isEmpty {
            CGSRemoveWindowsFromSpaces(CGS_CONNECTION, [wid] as NSArray, otherSpaces as NSArray)
        }
        wlog("[LayoutApplier] Moved window \(wid) → Desktop \(job.targetIdx)")

        // Position
        DispatchQueue.main.sync {
            let screen = NSScreen.main ?? NSScreen.screens.first!
            WindowManager.setWindowFrame(axWindow, region: entry.snapRegionID.snapRegion, screen: screen)
            wlog("[LayoutApplier] Positioned '\(entry.appName)' → \(entry.snapRegionID.rawValue)")
        }
    }

    // MARK: - Position-only logic

    private func positionJob(_ job: Job) {
        let entry = job.entry
        wlog("[LayoutApplier] Positioning '\(entry.appName)' on Desktop \(job.targetIdx)...")

        let spaceIDs = allSpaceIdsAndIndexes()
        guard let targetSpaceID = spaceIDs.first(where: { $0.1 == job.targetIdx })?.0 else {
            wlog("[LayoutApplier] ERROR: no space for Desktop \(job.targetIdx)")
            return
        }

        // Switch to target space so AX can see the window
        DispatchQueue.main.sync {
            if let uuid = NSScreen.main?.uuid() {
                CGSManagedDisplaySetCurrentSpace(CGS_CONNECTION, uuid as CFString, targetSpaceID)
            }
        }
        Thread.sleep(forTimeInterval: 0.5)

        guard let app = findRunningApp(bundleID: entry.bundleID) else {
            wlog("[LayoutApplier] ERROR: '\(entry.appName)' not running")
            return
        }

        // Try standard AX first, fall back to allAXWindows (brute-force, sees other-space windows)
        let axWindow: AXUIElement
        if let win = waitForWindow(app: app, timeout: 3.0) {
            axWindow = win
        } else if let win = allAXWindows(pid: app.processIdentifier).first {
            axWindow = win
        } else {
            wlog("[LayoutApplier] ERROR: no window for '\(entry.appName)'")
            return
        }

        DispatchQueue.main.sync {
            let screen = NSScreen.main ?? NSScreen.screens.first!
            WindowManager.setWindowFrame(axWindow, region: entry.snapRegionID.snapRegion, screen: screen)
            wlog("[LayoutApplier] Positioned '\(entry.appName)' → \(entry.snapRegionID.rawValue)")
        }
    }

    // MARK: - Helpers

    private func findRunningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    private func launchApp(bundleID: String, openURL: String? = nil) -> NSRunningApplication? {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.createsNewApplicationInstance = true

        var result: NSRunningApplication?
        let sem = DispatchSemaphore(value: 0)

        if let path = openURL,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let fileURL = URL(fileURLWithPath: path)
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config) { app, error in
                if let error { wlog("[LayoutApplier] Launch error: \(error)") }
                result = app
                sem.signal()
            }
            sem.wait()
            return result
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            wlog("[LayoutApplier] ERROR: no app URL for '\(bundleID)'")
            return nil
        }
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error { wlog("[LayoutApplier] Launch error: \(error)") }
            result = app
            sem.signal()
        }
        sem.wait()
        return result
    }

    /// Waits for a new window of any process with bundleID that has a WID not in excludedWIDs.
    /// Uses CGWindowList to detect new WID (works across all spaces), then gets AXUIElement via allAXWindows.
    /// Returns (AXUIElement, WID) or nil on timeout.
    private func waitForNewWindowExcluding(
        bundleID: String,
        excludedWIDs: Set<UInt32>,
        targetSpaceID: CGSSpaceID,
        timeout: TimeInterval
    ) -> (AXUIElement, UInt32)? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastLogTime = Date.distantPast
        while Date() < deadline {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
            for app in apps {
                // CGWindowList sees all windows on all spaces — use it to detect new WID
                let wids = windowIDsForPID(app.processIdentifier)
                if Date().timeIntervalSince(lastLogTime) > 2.0 {
                    wlog("[LayoutApplier] Waiting for '\(bundleID)' pid \(app.processIdentifier): \(wids.count) CGWindowList WIDs, excludedWIDs=\(excludedWIDs.count)")
                    lastLogTime = Date()
                }
                for wid in wids {
                    guard !excludedWIDs.contains(wid) else { continue }
                    // Got new WID — now get its AXUIElement via allAXWindows (brute-force token search)
                    // Switch to target space first so AX can find it
                    DispatchQueue.main.sync {
                        if let uuid = NSScreen.main?.uuid() {
                            CGSManagedDisplaySetCurrentSpace(CGS_CONNECTION, uuid as CFString, targetSpaceID)
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.3)
                    let axWins = allAXWindows(pid: app.processIdentifier)
                    if let axWin = axWins.first(where: { cgWindowID(for: $0) == wid }) {
                        return (axWin, wid)
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return nil
    }

    private func waitForWindow(app: NSRunningApplication, timeout: TimeInterval) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let wins = windowsRef as? [AXUIElement], !wins.isEmpty {
                return wins[0]
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return nil
    }
}
