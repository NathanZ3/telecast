import Foundation

/// Orders the strategies to try for a video on a given TV ("mode auto").
public enum StrategyPlanner {
    public static func plan(profile: ContentProfile, capabilities: RendererCapabilities, preflight: PreflightResult,
                            preference: CastModePreference, remembered: CastStrategy?,
                            tests: TVTestResults?) throws -> [CastStrategy] {
        if profile.drm { throw PlanError.drm }
        if profile.kind == .dash { throw PlanError.dashUnsupported }
        if preference == .alwaysDirect { return [.direct] }

        var order: [CastStrategy] = []
        switch profile.kind {
        case .progressive:
            order = preflight.directReachable ? [.direct, .relayProgressive] : [.relayProgressive]
        case .hls:
            var continuous: CastStrategy?
            if !profile.hasSeparateAudio {
                continuous = profile.segmentFormat == .fmp4 ? .relayFMP4 : .relayTS
            }
            if let continuous, !capabilities.announcesHLS {
                order = [continuous, .relayHLS]
            } else {
                order = preflight.directReachable ? [.direct, .relayHLS] : [.relayHLS]
                if let continuous { order.append(continuous) }
            }
        case .dash:
            throw PlanError.dashUnsupported
        }

        if preference == .alwaysRelay {
            order.removeAll { $0 == .direct }
        }
        if let tests {
            let failing = order.filter { knownToFail($0, profile: profile, tests: tests) }
            order = order.filter { !failing.contains($0) } + failing
        }
        if let remembered, let index = order.firstIndex(of: remembered) {
            order.remove(at: index)
            order.insert(remembered, at: 0)
        }
        return order
    }

    static func knownToFail(_ strategy: CastStrategy, profile: ContentProfile, tests: TVTestResults) -> Bool {
        let testCase: TVTestCase
        switch strategy {
        case .direct, .relayProgressive, .relayHLS:
            if profile.kind == .progressive {
                testCase = .mp4
            } else {
                testCase = profile.segmentFormat == .fmp4 ? .hlsFMP4 : .hlsTS
            }
        case .relayTS:
            testCase = .liveTS
        case .relayFMP4:
            testCase = .liveFMP4
        }
        return tests.result(testCase) == false
    }
}
