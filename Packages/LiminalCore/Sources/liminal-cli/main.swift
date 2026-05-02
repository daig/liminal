import Foundation
import LiminalCore

@main
struct LiminalCLI {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()

        guard let path = arguments.first else {
            print("usage: liminal <path>")
            return
        }

        do {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let parsed = try LiminalParser().parse(source)
            let document = LiminalLowerer().lower(parsed)
            let rendered = LiminalPrinter().print(document)
            print(rendered)
        } catch {
            FileHandle.standardError.write(Data("liminal: \(error)\n".utf8))
        }
    }
}
