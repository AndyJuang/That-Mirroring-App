import SwiftUI
import AppKit

typealias ViewState<Value> = SwiftUI.State<Value>

struct Fixture {
    let name: String
    let devices: [AndroidDevice]
    let selected: String?
    let status: String
}

let pixel = AndroidDevice(serial: "A1", state: "device", model: "Pixel 11 Pro with a very long model name", isUSB: true)
let locked = AndroidDevice(serial: "B2", state: "unauthorized", model: "Galaxy S30", isUSB: true)
let fixtures = [
    Fixture(name: "no-device", devices: [], selected: nil, status: "No authorized USB device. Check the four steps below."),
    Fixture(name: "unauthorized", devices: [locked], selected: nil, status: "Galaxy S30: Not authorized. Follow the steps below, then click Refresh."),
    Fixture(name: "connected-idle", devices: [pixel], selected: nil, status: "Choose an Android device to start."),
    Fixture(name: "mirroring", devices: [pixel, locked], selected: "A1", status: "Pixel 11 is open in That Mirroring. Use the Mac mouse and keyboard."),
]

@MainActor func render() {
    let outDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
    for fixture in fixtures {
        for width in [380.0, 640.0] {
            let view = AndroidSetupContent(
                devices: fixture.devices, selectedSerial: fixture.selected, status: fixture.status, isRefreshing: false,
                options: .constant(AndroidWindowOptions()), scrolls: false,
                onStart: { _ in }, onStop: {}, onRefresh: {}, onBack: {})
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(white: 0.12))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            renderer.colorMode = .nonLinear
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("failed: \(fixture.name) \(Int(width))"); continue
            }
            let file = outDirectory.appendingPathComponent("\(fixture.name)-\(Int(width)).png")
            try? png.write(to: file)
            print(file.lastPathComponent)
        }
    }
}

MainActor.assumeIsolated { render() }
