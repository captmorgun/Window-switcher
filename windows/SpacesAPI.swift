import AppKit

// MARK: - Private API declarations
// Adapted from alt-tab-macos (https://github.com/lwouis/alt-tab-macos), GPL-3.0

extension NSScreen {
    func uuid() -> String? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)
        else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String?
    }
}

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: Int32, _ spaces: CFArray, _ options: Int32, _ setTags: inout Int64, _ clearTags: inout Int64) -> CFArray

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: UInt32, _ windows: CFArray) -> CFArray

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: CGSConnectionID, _ display: CFString) -> CGSSpaceID

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ display: CFString, _ spaceID: CGSSpaceID)

@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)


@_silgen_name("_SLPSSetFrontProcessWithOptions")
func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: UInt32, _ options: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> Void

// GetProcessForPID is deprecated in Swift but accessible via @_silgen_name
@_silgen_name("GetProcessForPID")
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout UInt32) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

var CGS_CONNECTION: CGSConnectionID { CGSConnectionID(bitPattern: Int32(SLSMainConnectionID())) }

// MARK: - Space UUID helpers (com.apple.spaces.plist)

/// Returns ordered Space UUIDs for all displays, index 0 = Desktop 1.
/// Reads from com.apple.spaces.plist (no SIP required).
func getSpaceUUIDs() -> [String] {
    let plistURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")

    guard let data = try? Data(contentsOf: plistURL),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let sdc = plist["SpacesDisplayConfiguration"] as? [String: Any],
          let mgmt = sdc["Management Data"] as? [String: Any],
          let monitors = mgmt["Monitors"] as? [[String: Any]]
    else {
        print("[SpacesAPI] Failed to read com.apple.spaces.plist")
        return []
    }

    var uuids: [String] = []
    for monitor in monitors {
        guard let spaces = monitor["Spaces"] as? [[String: Any]] else { continue }
        for space in spaces {
            // Skip fullscreen / TileLayoutManager spaces
            if space["TileLayoutManager"] != nil { continue }
            if let type = space["type"] as? Int, type != 0 { continue }
            if let uuid = space["uuid"] as? String {
                uuids.append(uuid)
            }
        }
    }
    print("[SpacesAPI] Space UUIDs: \(uuids)")
    return uuids
}

/// Assigns an app to a specific Space via cfprefsd (defaults write).
/// Pass nil for uuid to remove the assignment ("None").
/// Returns true on success.
@discardableResult
func assignApp(bundleID: String, toSpaceUUID uuid: String?) -> Bool {
    if let uuid {
        // Write through cfprefsd so Dock picks it up from cache
        let result = runProcess("/usr/bin/defaults", args: [
            "write", "com.apple.spaces",
            "app-bindings", "-dict-add", bundleID, uuid
        ])
        guard result == 0 else {
            print("[SpacesAPI] defaults write failed for \(bundleID)")
            return false
        }
    } else {
        // Remove: read current dict, delete key, write back
        runProcess("/usr/bin/defaults", args: [
            "delete", "com.apple.spaces", "app-bindings"  // handled per-key below
        ])
        // Use PlistBuddy for key deletion (defaults doesn't support per-key delete in dict)
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.spaces.plist").path
        runPlistBuddy(["-c", "Delete :app-bindings:\(bundleID)", plistPath])
    }
    print("[SpacesAPI] Assigned \(bundleID) → \(uuid ?? "None")")
    return true
}

/// Writes all app→space bindings at once via cfprefsd.
func assignAllApps(_ bindings: [String: String]) {
    guard !bindings.isEmpty else { return }
    // Dock on macOS 26 uses lowercased bundle IDs as keys
    var args = ["write", "com.apple.spaces", "app-bindings", "-dict"]
    for (bundleID, uuid) in bindings {
        args.append(bundleID.lowercased())
        args.append(uuid)
    }
    runProcess("/usr/bin/defaults", args: args)
    print("[SpacesAPI] Wrote \(bindings.count) app-bindings via cfprefsd")
}

/// Restart Dock so space assignments take effect.
func restartDock() {
    let task = Process()
    task.launchPath = "/usr/bin/killall"
    task.arguments = ["Dock"]
    try? task.run()
    task.waitUntilExit()
    print("[SpacesAPI] Dock restarted")
}

/// Wait until Dock is running again after killall (up to 8 seconds).
func waitForDock() {
    let deadline = Date().addingTimeInterval(8.0)
    while Date() < deadline {
        let dockRunning = NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == "com.apple.dock" }
        if dockRunning {
            // Extra settle time so Dock fully loads the new bindings
            print("[SpacesAPI] Dock process appeared, waiting for bindings to load...")
            Thread.sleep(forTimeInterval: 3.0)
            print("[SpacesAPI] Dock is up")
            return
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    print("[SpacesAPI] WARNING: Dock did not come back in time")
}

// MARK: - AX helpers

/// Returns the CGWindowID for an AXUIElement window, or nil on failure.
func cgWindowID(for axWindow: AXUIElement) -> UInt32? {
    var wid: UInt32 = 0
    let err = _AXUIElementGetWindow(axWindow, &wid)
    return err == .success ? wid : nil
}

/// Returns all AX windows for a pid, including windows on other Spaces.
/// Combines kAXWindowsAttribute (misses other-Space windows) with brute-force token iteration
/// (misses newly launched windows). Union of both covers all cases.
/// Adapted from alt-tab-macos (https://github.com/lwouis/alt-tab-macos), GPL-3.0
func allAXWindows(pid: pid_t) -> [AXUIElement] {
    // Standard approach — returns current-space windows
    let appEl = AXUIElementCreateApplication(pid)
    var ref: CFTypeRef?
    var standard: [AXUIElement] = []
    if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
       let wins = ref as? [AXUIElement] {
        standard = wins
    }

    // Brute-force approach — iterates AXUIElementID 0..<1000, catches other-Space windows
    // Token layout: pid(4) | 0(4) | 0x636f636f(4) | axUiElementId(8)
    var remoteToken = Data(count: 20)
    remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
    remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
    remoteToken.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
    var bruteForce: [AXUIElement] = []
    let deadline = Date().addingTimeInterval(0.1)
    for axId: UInt64 in 0..<1000 {
        remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: axId) { Data($0) })
        guard let el = _AXUIElementCreateWithRemoteToken(remoteToken as CFData)?.takeRetainedValue()
        else { continue }
        var subroleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleRef) == .success,
              let subrole = subroleRef as? String,
              subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
        else { continue }
        bruteForce.append(el)
        if Date() > deadline { break }
    }

    // Union via wid deduplication
    var seen = Set<UInt32>()
    var result: [AXUIElement] = []
    for win in standard + bruteForce {
        guard let wid = cgWindowID(for: win), wid != 0, seen.insert(wid).inserted else { continue }
        result.append(win)
    }
    return result
}

// MARK: - Space mapping
// Adapted from alt-tab-macos (https://github.com/lwouis/alt-tab-macos), GPL-3.0

/// Builds ordered list of (spaceID, spaceIndex) for all normal spaces across all displays.
func allSpaceIdsAndIndexes() -> [(CGSSpaceID, Int)] {
    var result: [(CGSSpaceID, Int)] = []
    var idx = 1
    let displays = CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as? [[String: Any]] ?? []
    for display in displays {
        guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
        for space in spaces {
            if let type = space["type"] as? Int, type != 0 { continue }  // skip fullscreen
            guard let id = space["id64"] as? CGSSpaceID else { continue }
            result.append((id, idx))
            idx += 1
        }
    }
    return result
}

/// Returns the 1-based index of the currently active Space on the main display.
func currentSpaceIndex() -> Int {
    guard let uuid = NSScreen.main?.uuid() else { return 1 }
    let currentID = CGSManagedDisplayGetCurrentSpace(CGS_CONNECTION, uuid as CFString)
    return allSpaceIdsAndIndexes().first { $0.0 == currentID }?.1 ?? 1
}


/// Returns all normal window IDs for a given PID using CGWindowList (no AX required).
func windowIDsForPID(_ pid: pid_t) -> [UInt32] {
    let opts = CGWindowListOption([.optionAll])
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { info -> UInt32? in
        guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
              let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let wid = info[kCGWindowNumber as String] as? UInt32
        else { return nil }
        return wid
    }
}

/// Returns [windowID: spaceIndex] using CGSCopySpacesForWindows — the correct API
/// that maps each window to its space directly (same approach as alt-tab-macos).
func windowSpaceMap(for windowIDs: [UInt32]) -> [UInt32: Int] {
    guard !windowIDs.isEmpty else { return [:] }
    let idsAndIndexes = allSpaceIdsAndIndexes()
    // Build spaceID → spaceIndex lookup
    var spaceIndexByID: [CGSSpaceID: Int] = [:]
    for (sid, idx) in idsAndIndexes { spaceIndexByID[sid] = idx }

    var result: [UInt32: Int] = [:]
    // Query all windows at once — CGSCopySpacesForWindows returns array of spaceIDs per window
    // We query each window individually to get its primary space
    for wid in windowIDs {
        let spaces = CGSCopySpacesForWindows(CGS_CONNECTION, 0x7, [wid] as CFArray) as? [CGSSpaceID] ?? []
        if let firstSpace = spaces.first, let idx = spaceIndexByID[firstSpace] {
            result[wid] = idx
        }
    }
    return result
}

// MARK: - Private

@discardableResult
private func runProcess(_ path: String, args: [String]) -> Int32 {
    let task = Process()
    task.launchPath = path
    task.arguments = args
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
    return task.terminationStatus
}

@discardableResult
private func runPlistBuddy(_ args: [String]) -> Int32 {
    runProcess("/usr/libexec/PlistBuddy", args: args)
}
