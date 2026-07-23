import Foundation

// Provider-neutral contracts only. The application deliberately ships without
// an AI vendor implementation; a future adapter must return files/observations
// and can never mutate the storyboard directly.

struct StoryboardImageGenerationRequest: Codable, Equatable {
    var prompt: String
    var referenceAssetIDs: [UUID]
    var maskAssetID: UUID?
    var width: Int
    var height: Int
    var candidateCount: Int
}

struct StoryboardGeneratedImage: Codable, Equatable {
    var data: Data
    var fileExtension: String
    var provider: String
    var model: String
    var revisedPrompt: String?
}

protocol StoryboardImageGenerationProvider {
    var providerName: String { get }
    func generate(_ request: StoryboardImageGenerationRequest) async throws -> [StoryboardGeneratedImage]
}

struct StoryboardVisualAnalysisRequest: Codable, Equatable {
    var assetID: UUID
    var requestedSignals: [String]
    var context: String
}

struct StoryboardVisualObservation: Identifiable, Codable, Equatable {
    var id: UUID
    var signal: String
    var value: String
    var confidence: Double?
    var evidence: String?

    init(
        id: UUID = UUID(),
        signal: String,
        value: String,
        confidence: Double? = nil,
        evidence: String? = nil
    ) {
        self.id = id
        self.signal = signal
        self.value = value
        self.confidence = confidence
        self.evidence = evidence
    }
}

protocol StoryboardVisualAnalysisProvider {
    var providerName: String { get }
    func analyze(_ request: StoryboardVisualAnalysisRequest) async throws -> [StoryboardVisualObservation]
}

struct StoryboardAIProviderRegistry {
    var imageGeneration: StoryboardImageGenerationProvider?
    var visualAnalysis: StoryboardVisualAnalysisProvider?

    static let unconfigured = StoryboardAIProviderRegistry(
        imageGeneration: nil,
        visualAnalysis: nil
    )

    var statusDescription: String {
        imageGeneration == nil && visualAnalysis == nil
            ? "AI 接口已预留，当前未配置服务"
            : "已配置外部 AI 适配器"
    }
}
