// Run after registering the current Framed.app with Launch Services.
// Uses disposable fixtures; no existing projects are modified.
import AppKit
import UniformTypeIdentifiers

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let package = root.appendingPathComponent("Package.framed", isDirectory: true)
try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
try Data("{}".utf8).write(to: package.appendingPathComponent("project.json"))
let legacy = root.appendingPathComponent("Legacy.framed")
try Data("{}".utf8).write(to: legacy)
let values = try package.resourceValues(forKeys: [.isPackageKey, .contentTypeKey])
let legacyValues = try legacy.resourceValues(forKeys: [.isPackageKey, .contentTypeKey])
print("Package: type=\(values.contentType?.identifier ?? "nil"), isPackage=\(values.isPackage ?? false), FinderPackage=\(NSWorkspace.shared.isFilePackage(atPath: package.path))")
print("Legacy: type=\(legacyValues.contentType?.identifier ?? "nil"), isPackage=\(legacyValues.isPackage ?? false)")
precondition(values.contentType?.identifier == "com.georgebabichev.framed.project-package")
precondition(values.isPackage == true)
precondition(NSWorkspace.shared.isFilePackage(atPath: package.path))
precondition(legacyValues.contentType?.identifier == "com.georgebabichev.framed.project")
precondition(legacyValues.isPackage != true)
print("PASS: macOS identifies packages and legacy JSON separately with the same .framed extension")
