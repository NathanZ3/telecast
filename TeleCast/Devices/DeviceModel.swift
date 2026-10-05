import Foundation
import Observation
import CastCore
import CastNet

struct SavedTV: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var descriptionURL: URL
    var renderer: RendererDescription
    var capabilities: RendererCapabilities
    var tests: TVTestResults?
    var lastSeen: Date

    var isAudioOnly: Bool { !capabilities.hasVideo }

    var subtitle: String {
        let model = [renderer.manufacturer, renderer.modelName].compactMap { $0 }.joined(separator: " ")
        return model.isEmpty ? renderer.host : "\(model) · \(renderer.host)"
    }
}

struct DevicesData: Codable {
    var tvs: [SavedTV] = []
    var selectedID: String?
}

/// Known TVs, discovery, selection and the TV compatibility test.
@MainActor
@Observable
final class DeviceModel {
    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored let relay: RelayServer
    @ObservationIgnored private let discovery = RendererDiscovery()
    @ObservationIgnored private let store = JSONFileStore(
        url: JSONFileStore<DevicesData>.applicationSupportURL(named: "devices"), defaultValue: DevicesData())

    private(set) var tvs: [SavedTV] = []
    private(set) var selectedID: String?
    private(set) var isScanning = false
    private(set) var lastScanFoundNothing = false
    private(set) var isTesting = false
    private(set) var currentTest: TVTestCase?
    private(set) var testResults: [String: Bool] = [:]

    var selected: SavedTV? { tvs.first { $0.id == selectedID } }

    init(relay: RelayServer) {
        self.relay = relay
        let data = store.load()
        tvs = data.tvs
        selectedID = data.selectedID
    }

    /// Re-reads saved TVs (fast, no sweep) at launch.
    func restore() async {
        for tv in tvs {
            if let fresh = try? await discovery.load(descriptionURL: tv.descriptionURL) {
                merge(fresh)
            }
        }
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let found = await discovery.discover(known: tvs.map(\.descriptionURL))
        for renderer in found {
            merge(renderer)
        }
        lastScanFoundNothing = found.isEmpty
        if selected == nil, let first = tvs.first(where: { !$0.isAudioOnly }) {
            select(first.id)
        }
        save()
    }

    func add(ip: String) async -> Bool {
        guard let found = await discovery.probe(ip: ip) else { return false }
        merge(found)
        select(found.id)
        return true
    }

    func select(_ id: String) {
        selectedID = id
        save()
    }

    func remove(_ id: String) {
        tvs.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        save()
    }

    func control(for tv: SavedTV) -> DLNARendererControl {
        DLNARendererControl(renderer: tv.renderer)
    }

    func runTest(on tvID: String) async {
        guard let tv = tvs.first(where: { $0.id == tvID }), !isTesting else { return }
        isTesting = true
        testResults = [:]
        currentTest = nil
        defer {
            isTesting = false
            currentTest = nil
        }
        KeepAlive.shared.start()
        let runner = TVTestRunner(server: relay, renderer: control(for: tv), capabilities: tv.capabilities)
        let results = await runner.run { [weak self] testCase, passed in
            Task { @MainActor in
                guard let self else { return }
                if let passed {
                    self.testResults[testCase.rawValue] = passed
                    self.currentTest = nil
                } else {
                    self.currentTest = testCase
                }
            }
        }
        KeepAlive.shared.stop()
        if let index = tvs.firstIndex(where: { $0.id == tvID }) {
            tvs[index].tests = results
            save()
        }
    }

    private func merge(_ renderer: DiscoveredRenderer) {
        let description = renderer.description
        if let index = tvs.firstIndex(where: { $0.id == description.udn }) {
            tvs[index].name = description.friendlyName
            tvs[index].descriptionURL = description.descriptionURL
            tvs[index].renderer = description
            if renderer.capabilities.isKnown {
                tvs[index].capabilities = renderer.capabilities
            }
            tvs[index].lastSeen = Date()
        } else {
            tvs.append(SavedTV(id: description.udn, name: description.friendlyName,
                               descriptionURL: description.descriptionURL, renderer: description,
                               capabilities: renderer.capabilities, tests: nil, lastSeen: Date()))
        }
        tvs.sort { lhs, rhs in
            if lhs.isAudioOnly != rhs.isAudioOnly { return !lhs.isAudioOnly }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        save()
    }

    private func save() {
        store.save(DevicesData(tvs: tvs, selectedID: selectedID))
    }
}
