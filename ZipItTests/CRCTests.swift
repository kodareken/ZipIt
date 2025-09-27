import Foundation
import Testing
@testable import ZipIt

struct CRCTests {
    @Test
    func testCRC32() {
        let s = "123456789".data(using: .utf8)!
        #expect(s.crc32 == 0xCBF43926)
    }

    @Test
    func testCRC16IBM() {
        let s = "123456789".data(using: .utf8)!
        let v = s.crc16IBM
        #expect(v == 0xBB3D || v == 0x3DBB)
    }

    @Test
    func testDOSTimePacking() {
        let comps = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: 2024, month: 1, day: 2, hour: 3, minute: 4, second: 6)
        let date = comps.date!
        let dos = DOSTime.from(date)
        // Quick sanity: decode back the lower time bits seconds/2 == 3
        #expect((dos & 0x1F) == 3)
    }
}
