//
// EmbeddingEngine.swift
// claude-click task learning system
//

import Foundation
import CoreML

/// Manages text embeddings using MobileCLIP for semantic search
class EmbeddingEngine {

    private var tokenizer: CLIPTokenizer?
    private var textEncoder: MLModel?

    static let shared = EmbeddingEngine()

    private init() {}

    /// Load the tokenizer and text encoder model
    func load() async throws {
        // Load tokenizer
        self.tokenizer = CLIPTokenizer()

        // Load CoreML text encoder dynamically
        // For executables, find model in bundle
        let executablePath = ProcessInfo.processInfo.arguments[0]
        let executableURL = URL(fileURLWithPath: executablePath)
        let bundleURL = executableURL.deletingLastPathComponent().appendingPathComponent("AutomationTool_AutomationTool.bundle")

        guard let bundle = Bundle(url: bundleURL) else {
            throw EmbeddingError.modelNotFound
        }

        // With .copy, the mlpackage structure is preserved
        guard let modelURL = bundle.url(forResource: "mobileclip_s0_text", withExtension: "mlpackage") else {
            throw EmbeddingError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU

        // Compile and load
        let compiledURL = try await MLModel.compileModel(at: modelURL)
        self.textEncoder = try MLModel(contentsOf: compiledURL, configuration: config)
    }

    /// Generate embedding for a single text string
    /// - Parameter text: The text to embed (e.g., "create keynote presentation")
    /// - Returns: Float array of embedding vector (512 dimensions)
    func embed(_ text: String) async throws -> [Float] {
        guard let tokenizer = tokenizer, let encoder = textEncoder else {
            throw EmbeddingError.notLoaded
        }

        // Tokenize text (returns array of 77 token IDs)
        let inputIds = tokenizer.encode_full(text: text)

        // Convert to MLMultiArray [1, 77] int32
        let inputArray = try MLMultiArray(shape: [1, 77], dataType: .int32)
        for (index, element) in inputIds.enumerated() {
            inputArray[index] = NSNumber(value: element)
        }

        // Run text encoder
        let inputDict: [String: Any] = ["text": inputArray]
        let provider = try MLDictionaryFeatureProvider(dictionary: inputDict)
        let output = try encoder.prediction(from: provider)

        // Extract embedding (output key is "final_emb_1" based on our tests)
        guard let embeddingMultiArray = output.featureValue(for: "final_emb_1")?.multiArrayValue else {
            throw EmbeddingError.invalidOutput
        }

        // Extract embedding as Float array
        return extractFloatArray(from: embeddingMultiArray)
    }

    /// Compute cosine similarity between two embeddings
    /// - Parameters:
    ///   - a: First embedding vector
    ///   - b: Second embedding vector
    /// - Returns: Similarity score from -1.0 to 1.0 (higher = more similar)
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard normA > 0 && normB > 0 else { return 0.0 }
        return dotProduct / (normA * normB)
    }

    /// Helper to extract Float array from MLMultiArray
    private func extractFloatArray(from multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        var result: [Float] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            result.append(Float(truncating: multiArray[i]))
        }
        return result
    }
}

enum EmbeddingError: Error {
    case notLoaded
    case invalidInput
    case modelNotFound
    case invalidOutput
}
