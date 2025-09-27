import Foundation

@main
struct Main {
    static func main() throws {
        let archiver = RARArchiver(solid: false, recoveryRecord: false)
        let text = "Hello RAR from ZipIt\n"
        try archiver.addFile(name: "hello.txt", data: text.data(using: .utf8)!)
        let rar = try archiver.createArchive()
        let outPath = "/tmp/zipit_rar_mvp.rar"
        try rar.write(to: URL(fileURLWithPath: outPath))
        print(outPath)
    }
}
