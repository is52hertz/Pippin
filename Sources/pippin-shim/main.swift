import Foundation
import PippinShim

@main
struct PippinShimMain {
    static func main() async {
        do {
            try await PippinShimRuntime().run()
        } catch let failure as ShimFailure {
            FileHandle.standardError.write(Data("\(failure.diagnostic)\n".utf8))
            exit(EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(
                Data("pippin-shim: an unexpected transport failure occurred. Restart Pippin.app and reconnect the MCP client.\n".utf8)
            )
            exit(EXIT_FAILURE)
        }
    }
}
