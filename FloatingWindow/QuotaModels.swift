import Foundation

struct QuotaSnapshot: Decodable {
    let fetchedAt: String?
    let source: String?
    let title: String?
    let planType: String?
    let resetCreditsAvailable: Int?
    let windows: [QuotaWindow]
}

struct QuotaWindow: Decodable {
    let key: String
    let label: String
    let status: String
    let usedPercent: Int?
    let remainingPercent: Int?
    let resetsAtEpochSeconds: Int?
    let windowDurationMins: Int?
}

struct ActivitySnapshot: Decodable {
    let status: String
    let updatedAt: String?
    let activeCount: Int
    let waitingCount: Int
    let source: String?
    let hooksInstalled: Bool
}
