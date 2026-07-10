import Foundation

@main
struct QuotaModelsTests {
    static func main() throws {
        try parsesRateLimitResponse()
        try parsesActivityResponse()
        try parsesActivityTaskListResponse()
    }

    private static func parsesActivityTaskListResponse() throws {
        let json = """
        {
          "fetchedAt": "2026-07-10T02:23:05.016Z",
          "source": "local",
          "tasks": [
            {
              "threadId": "019f0000-0000-7000-8000-000000000001",
              "title": "Quota window polish",
              "status": "working",
              "updatedAt": "2026-07-10T02:23:04.016Z"
            }
          ]
        }
        """
        let snapshot = try JSONDecoder().decode(ActivityTaskListSnapshot.self, from: Data(json.utf8))
        assertEqual(snapshot.tasks.count, 1)
        assertEqual(snapshot.tasks[0].threadId, "019f0000-0000-7000-8000-000000000001")
        assertEqual(snapshot.tasks[0].title, "Quota window polish")
        assertEqual(snapshot.tasks[0].status, "working")
    }

    private static func parsesActivityResponse() throws {
        let json = """
        {
          "status": "waiting",
          "updatedAt": "2026-07-10T02:23:05.016Z",
          "activeCount": 2,
          "waitingCount": 1,
          "source": "local",
          "hooksInstalled": true
        }
        """
        let snapshot = try JSONDecoder().decode(ActivitySnapshot.self, from: Data(json.utf8))
        assertEqual(snapshot.status, "waiting")
        assertEqual(snapshot.activeCount, 2)
        assertEqual(snapshot.waitingCount, 1)
        assertEqual(snapshot.hooksInstalled, true)
    }

    private static func parsesRateLimitResponse() throws {
        let json = """
        {
          "fetchedAt": "2026-07-09T07:24:41.055Z",
          "source": "codex-app-server",
          "title": "Codex",
          "planType": "pro",
          "resetCreditsAvailable": 1,
          "windows": [
            {
              "key": "primary",
              "label": "Primary",
              "status": "ok",
              "usedPercent": 33,
              "remainingPercent": 67,
              "resetsAtEpochSeconds": 1783582771,
              "windowDurationMins": 300
            },
            {
              "key": "secondary",
              "label": "Secondary",
              "status": "ok",
              "usedPercent": 41,
              "remainingPercent": 59,
              "resetsAtEpochSeconds": 1784079173,
              "windowDurationMins": 10080
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)

        assertEqual(snapshot.planType, "pro")
        assertEqual(snapshot.windows.count, 2)
        assertEqual(snapshot.windows[0].key, "primary")
        assertEqual(snapshot.windows[0].remainingPercent, 67)
        assertEqual(snapshot.windows[1].key, "secondary")
        assertEqual(snapshot.windows[1].remainingPercent, 59)
        assertEqual(snapshot.resetCreditsAvailable, 1)
    }

    private static func assertEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if actual != expected {
            fatalError("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }
}
