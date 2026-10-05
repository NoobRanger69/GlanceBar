import AppKit
import Foundation
import Darwin

// A small menu-bar app: battery % + time-to-full/empty, live up/down network
// speed in the title, and a "Keep Awake" (caffeinate) toggle in the menu.
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var netTimer: Timer?
    var battTimer: Timer?

    // network sampling state
    let netInterval: TimeInterval = 2.0
    var prevRx: UInt64 = 0
    var prevTx: UInt64 = 0

    // cached pieces of the title
    var batteryTitle = "–%"
    var netTitle = "↓0 ↑0"

    // menu items we refresh
    var batteryDetailItem: NSMenuItem!
    var netDetailItem: NSMenuItem!
    var caffeineItem: NSMenuItem!

    // held caffeinate process (nil = off)
    var caffeine: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // monospaced digits keep the title from jittering as numbers change width
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
            button.title = "…"
        }

        let menu = NSMenu()
        batteryDetailItem = NSMenuItem(title: "Battery: …", action: nil, keyEquivalent: "")
        netDetailItem = NSMenuItem(title: "Network: …", action: nil, keyEquivalent: "")
        batteryDetailItem.isEnabled = false
        netDetailItem.isEnabled = false
        menu.addItem(batteryDetailItem)
        menu.addItem(netDetailItem)
        menu.addItem(.separator())

        caffeineItem = NSMenuItem(title: "Keep Awake", action: #selector(toggleCaffeine(_:)), keyEquivalent: "k")
        caffeineItem.target = self
        caffeineItem.state = .off
        menu.addItem(caffeineItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshAll), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let quit = NSMenuItem(title: "Quit GlanceBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu

        // prime network baseline so the first sample is a real delta, not a spike
        let (rx, tx) = Self.interfaceBytes()
        prevRx = rx; prevTx = tx

        updateBattery()
        rebuildTitle()

        netTimer = Timer.scheduledTimer(withTimeInterval: netInterval, repeats: true) { [weak self] _ in
            self?.updateNetwork()
        }
        battTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updateBattery()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let p = caffeine, p.isRunning { p.terminate() }
    }

    @objc func refreshAll() {
        updateBattery()
        updateNetwork()
    }

    // MARK: - Title

    func rebuildTitle() {
        statusItem.button?.title = "\(batteryTitle)  \(netTitle)"
    }

    // MARK: - Network

    @objc func updateNetwork() {
        let (rx, tx) = Self.interfaceBytes()
        let dRx = rx >= prevRx ? rx - prevRx : 0   // clamp counter wrap/reset
        let dTx = tx >= prevTx ? tx - prevTx : 0
        prevRx = rx; prevTx = tx

        let down = Double(dRx) / netInterval
        let up = Double(dTx) / netInterval
        netTitle = "↓\(Self.rate(down)) ↑\(Self.rate(up))"
        netDetailItem.title = "Network   ↓ \(Self.rate(down))/s   ↑ \(Self.rate(up))/s"
        rebuildTitle()
    }

    /// Sum rx/tx bytes across physical interfaces (en*) via getifaddrs/if_data.
    static func interfaceBytes() -> (UInt64, UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifap) }
        var ptr = ifap
        while let cur = ptr {
            let ifa = cur.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: ifa.ifa_name)
                if name.hasPrefix("en"), let d = ifa.ifa_data {   // en* = wifi/ethernet; skips lo/utun/awdl
                    let data = d.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(data.ifi_ibytes)
                    tx += UInt64(data.ifi_obytes)
                }
            }
            ptr = ifa.ifa_next
        }
        return (rx, tx)
    }

    /// Compact bytes-per-second, e.g. "1.2M", "340K", "12B".
    static func rate(_ bps: Double) -> String {
        if bps < 1024 { return String(format: "%.0fB", bps) }
        if bps < 1024 * 1024 { return String(format: "%.0fK", bps / 1024) }
        if bps < 1024 * 1024 * 1024 { return String(format: "%.1fM", bps / (1024 * 1024)) }
        return String(format: "%.1fG", bps / (1024 * 1024 * 1024))
    }

    /// Charger wattage from IOKit (fast; 0 when unplugged). Uses `ioreg`, not the slow system_profiler.
    static func wattage() -> Int {
        let out = run("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery"])
        if let r = out.range(of: #""Watts"=\d+"#, options: .regularExpression) {
            return Int(out[r].split(separator: "=")[1]) ?? 0
        }
        return 0
    }

    // MARK: - Battery

    @objc func updateBattery() {
        let out = Self.run("/usr/bin/pmset", ["-g", "batt"])
        let onAC = out.contains("'AC Power'")
        var pct = -1
        var state = ""
        var time: String? = nil

        if let line = out.split(separator: "\n").first(where: { $0.contains("InternalBattery") }) {
            let text = String(line)
            // percent: digits immediately before '%'
            if let r = text.range(of: #"(\d+)%"#, options: .regularExpression) {
                pct = Int(text[r].dropLast()) ?? -1
            }
            let parts = text.components(separatedBy: ";")
            if parts.count > 1 { state = parts[1].trimmingCharacters(in: .whitespaces) }
            if parts.count > 2 {
                let tail = parts[2]
                if !tail.contains("no estimate"),
                   let r = tail.range(of: #"\d+:\d{2}"#, options: .regularExpression) {
                    time = String(tail[r])
                }
            }
        }

        let pctStr = pct >= 0 ? "\(pct)%" : "–%"
        let watt = Self.wattage()

        // Title power segment: time-to-full / time-left (+ charger watts when plugged in).
        // The % lives in the stock macOS battery icon, so it's not repeated here.
        // Prefer the time estimate; fall back to % while macOS reports "(no estimate)"
        // (happens for a minute or two right after plugging/unplugging).
        let fallback = pct >= 0 ? "\(pct)%" : "–"

        // Classify charge state from pmset's words. Two substring traps make
        // order and guards matter: "discharging" contains "charging", and the
        // plugged-but-holding state "not charging" contains it too — so a bare
        // `contains("charging")` would mislabel both as charging.
        let isCharged = state.contains("charged")
        let isDischarging = state.contains("discharging")
        let isCharging = state.contains("charging") && !isDischarging && !state.contains("not charging")

        var power: String
        if isCharged {
            power = "⚡Full"
        } else if isCharging {
            power = "⚡" + (time ?? fallback)
        } else if onAC {
            // Plugged but holding (optimized-charging pause / charge limit /
            // finishing charge): no running countdown, so show the level, not
            // a stale "0:00".
            power = "⚡" + fallback
        } else {
            power = time ?? fallback
        }
        if onAC && watt > 0 { power += " \(watt)W" }
        batteryTitle = power

        var detail: String
        if isCharged {
            detail = "Battery   \(pctStr) · Charged"
        } else if isDischarging {
            detail = time != nil ? "Battery   \(pctStr) · \(time!) remaining" : "Battery   \(pctStr) · on battery"
        } else if isCharging {
            detail = time != nil ? "Battery   \(pctStr) · \(time!) to full" : "Battery   \(pctStr) · charging…"
        } else if onAC {
            detail = state.contains("not charging")
                ? "Battery   \(pctStr) · on AC · not charging"
                : "Battery   \(pctStr) · on AC power"
        } else {
            detail = "Battery   \(pctStr)"
        }
        if onAC && watt > 0 { detail += " · \(watt)W charger" }
        batteryDetailItem.title = detail
        rebuildTitle()
    }

    // MARK: - Caffeinate

    @objc func toggleCaffeine(_ sender: NSMenuItem) {
        if let p = caffeine, p.isRunning {
            p.terminate()
            caffeine = nil
            sender.state = .off
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-dimsu"]   // display, idle, disk, system; prevent all sleep
            do {
                try p.run()
                caffeine = p
                sender.state = .on
            } catch {
                sender.state = .off
            }
        }
    }

    // MARK: - Helper

    static func run(_ path: String, _ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
