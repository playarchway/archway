import Foundation
import Testing
@testable import ArchwayCore

/// A minimal 64-bit executable whose import table names `imports` and whose delay-load table names `delayed`.
private func executable(imports: [String], delayed: [String] = [], machine: UInt16 = 0x8664) -> Data {
    var data = Data(count: 0x400)
    func put16(_ value: Int, at offset: Int) { data[offset] = UInt8(value & 0xFF); data[offset + 1] = UInt8(value >> 8 & 0xFF) }
    func put32(_ value: Int, at offset: Int) { put16(value & 0xFFFF, at: offset); put16(value >> 16, at: offset + 2) }
    put16(0x5A4D, at: 0)
    let pe = 0x40
    put32(0x40, at: 0x3C)
    put32(0x4550, at: pe)
    put16(Int(machine), at: pe + 4)
    put16(1, at: pe + 6)                       // one section
    let optionalSize = 240
    put16(optionalSize, at: pe + 20)
    let optional = pe + 24
    put16(0x20B, at: optional)                  // PE32+
    let directories = optional + 112
    // The section maps addresses 0x1000… to file offsets 0x200….
    let section = optional + optionalSize
    put32(0x200, at: section + 8)
    put32(0x1000, at: section + 12)
    put32(0x200, at: section + 16)
    put32(0x200, at: section + 20)
    func address(_ offset: Int) -> Int { offset - 0x200 + 0x1000 }

    var names = 0x300
    func name(_ text: String) -> Int {
        let start = names
        for (index, byte) in text.utf8.enumerated() { data[start + index] = byte }
        names += text.utf8.count + 1
        return address(start)
    }
    let importTable = 0x200
    for (index, dll) in imports.enumerated() { put32(name(dll), at: importTable + index * 20 + 12) }
    put32(address(importTable), at: directories + 8)
    let delayTable = 0x280
    for (index, dll) in delayed.enumerated() { put32(name(dll), at: delayTable + index * 32 + 4) }
    if !delayed.isEmpty { put32(address(delayTable), at: directories + 13 * 8) }
    return data
}

@Test func portableExecutableReadsImportsAndArchitecture() throws {
    let image = try PortableExecutable(data: executable(imports: ["KERNEL32.dll", "MSVCP140.dll"], delayed: ["VCRUNTIME140_1.dll"]))
    #expect(image.architecture == .x64)
    #expect(image.importedDLLs == ["KERNEL32.dll", "MSVCP140.dll", "VCRUNTIME140_1.dll"])
    #expect(try PortableExecutable(data: executable(imports: ["user32.dll"], machine: 0x14C)).architecture == .x86)
    #expect(throws: PortableExecutable.Failure.self) { try PortableExecutable(data: Data("#!/bin/sh\n".utf8)) }
}

@Test func windowsRuntimesFollowTheImports() throws {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let folder = package.appendingPathComponent(".build/test-temp/runtimes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let game = folder.appendingPathComponent("Game.exe")
    try executable(imports: ["kernel32.dll", "msvcp140.dll", "MSVCR120.dll"]).write(to: game)
    let tool = folder.appendingPathComponent("Project/Binaries/Win32/Tool.exe")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try executable(imports: ["msvcr100.dll"], machine: 0x14C).write(to: tool)
    let redist = folder.appendingPathComponent("_CommonRedist/vcredist/vc_redist.x86.exe")
    try FileManager.default.createDirectory(at: redist.deletingLastPathComponent(), withIntermediateDirectories: true)
    try executable(imports: ["msvcr110.dll"], machine: 0x14C).write(to: redist)

    #expect(WindowsRuntime.executables(in: folder).map(\.lastPathComponent).sorted() == ["Game.exe", "Tool.exe"])
    #expect(WindowsRuntime.required(by: WindowsRuntime.executables(in: folder)) == [
        WindowsRuntime(family: .vc2015, architecture: .x64),
        WindowsRuntime(family: .vc2013, architecture: .x64),
        WindowsRuntime(family: .vc2010, architecture: .x86),
    ])
}
