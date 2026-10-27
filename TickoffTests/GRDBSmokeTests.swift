import Foundation
import GRDB
import Testing

@testable import Tickoff

struct GRDBSmokeTests {
    @Test func inMemoryDatabaseRoundTripsARow() throws {
        let queue = try DatabaseQueue()
        let title = try queue.write { db -> String? in
            try db.execute(sql: "CREATE TABLE t (title TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO t (title) VALUES (?)", arguments: ["hello"])
            return try String.fetchOne(db, sql: "SELECT title FROM t")
        }
        #expect(title == "hello")
    }

    @Test func appBundleHasTheExpectedIdentifierAndMinimumSystem() throws {
        let app = try #require(Bundle(identifier: "io.github.fiqriismail.tickoff"))
        #expect(app.infoDictionary?["LSMinimumSystemVersion"] as? String == "14.0")
    }
}
