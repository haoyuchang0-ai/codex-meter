import Foundation

@main
struct QuotaModelsTests {
    static func main() throws {
        try parsesRateLimitResponse()
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
