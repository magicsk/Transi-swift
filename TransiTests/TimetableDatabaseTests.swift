import XCTest
@testable import Transi

final class TimetableDatabaseTests: XCTestCase {
    var timetableDb: TimetableDatabase!

    override func setUp() {
        super.setUp()
        timetableDb = TimetableDatabase()
    }

    override func tearDown() {
        timetableDb = nil
        super.tearDown()
    }

    func testDayOfWeekColumn() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 7
        let date = Calendar.current.date(from: components)!

        XCTAssertEqual(timetableDb.dayOfWeekColumn(for: date), "saturday")
    }
}
