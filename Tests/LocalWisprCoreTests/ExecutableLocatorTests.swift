@testable import LocalWisprCore
import Foundation
import Testing

@Test
func executableLocatorFindsSystemExecutable() {
    let executable = ExecutableLocator.find("sh")

    #expect(executable != nil)
    #expect(FileManager.default.isExecutableFile(atPath: executable?.path ?? ""))
}

@Test
func executableLocatorReturnsNilForMissingExecutable() {
    let executable = ExecutableLocator.find("definitely-not-a-local-wispr-test-executable")

    #expect(executable == nil)
}
