import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: GenerateICNS <iconset-dir> <output.icns>\n", stderr)
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])

let entries: [(type: String, file: String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndianBytes(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

var body = Data()
for entry in entries {
    guard let typeData = entry.type.data(using: .ascii), typeData.count == 4 else {
        throw CocoaError(.fileWriteUnknown)
    }
    let pngURL = iconset.appendingPathComponent(entry.file)
    let png = try Data(contentsOf: pngURL)
    body.append(typeData)
    body.append(bigEndianBytes(UInt32(png.count + 8)))
    body.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianBytes(UInt32(body.count + 8)))
icns.append(body)
try icns.write(to: output, options: .atomic)
print("wrote \(entries.count) icon representations to \(output.path)")
