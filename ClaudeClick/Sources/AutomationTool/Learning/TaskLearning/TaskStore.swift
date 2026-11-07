//
// TaskStore.swift
// claude-click task learning system
//

import Foundation

/// Represents a learned task workflow
struct LearnedTask: Codable {
    let id: String
    let phrase: String  // e.g., "create keynote presentation"
    let app: String
    let steps: [TaskStep]
    var embedding: [Float]?  // Cached embedding for fast search
    var stats: TaskStats
    var notes: [String]  // Arbitrary comments/tips about this task

    struct TaskStep: Codable {
        let type: String  // "open", "wait", "click", "type", etc.
        let args: [String]
    }

    struct TaskStats: Codable {
        var successCount: Int = 0
        var failCount: Int = 0
        var lastSuccess: Date?
        var avgDurationSec: Double = 0.0
    }

    var successRate: Double {
        let total = stats.successCount + stats.failCount
        guard total > 0 else { return 0.0 }
        return Double(stats.successCount) / Double(total)
    }

    // Custom decoder to handle missing 'notes' field in old JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        phrase = try container.decode(String.self, forKey: .phrase)
        app = try container.decode(String.self, forKey: .app)
        steps = try container.decode([TaskStep].self, forKey: .steps)
        embedding = try container.decodeIfPresent([Float].self, forKey: .embedding)
        stats = try container.decode(TaskStats.self, forKey: .stats)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    init(id: String, phrase: String, app: String, steps: [TaskStep], embedding: [Float]?, stats: TaskStats, notes: [String] = []) {
        self.id = id
        self.phrase = phrase
        self.app = app
        self.steps = steps
        self.embedding = embedding
        self.stats = stats
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, phrase, app, steps, embedding, stats, notes
    }
}

/// Manages persistent storage of learned tasks
class TaskStore {

    private let storePath: String

    init(storePath: String = "\(NSHomeDirectory())/.claude-click/tasks.json") {
        self.storePath = storePath
        ensureDirectory()
    }

    private func ensureDirectory() {
        let dir = (storePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Load all tasks from disk
    func load() -> [LearnedTask] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: storePath)) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LearnedTask].self, from: data)) ?? []
    }

    /// Save all tasks to disk
    func save(_ tasks: [LearnedTask]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(tasks) else {
            print("Error: Failed to encode tasks")
            return
        }

        try? data.write(to: URL(fileURLWithPath: storePath))
    }

    /// Add or update a task
    func upsert(_ task: LearnedTask) {
        var tasks = load()

        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }

        save(tasks)
    }

    /// Delete a task by ID
    func delete(id: String) {
        var tasks = load()
        tasks.removeAll { $0.id == id }
        save(tasks)
    }

    /// Search tasks by semantic similarity
    func search(query: String, embedding: [Float], topK: Int = 5) -> [TaskSearchResult] {
        let tasks = load()

        var results: [(task: LearnedTask, score: Float)] = []

        for task in tasks {
            guard let taskEmbedding = task.embedding else { continue }

            // Compute semantic similarity
            let similarity = cosineSimilarity(embedding, taskEmbedding)

            // Boost by success rate
            let boostedScore = similarity * Float(0.7 + 0.3 * task.successRate)

            results.append((task, boostedScore))
        }

        // Sort by score descending
        results.sort { $0.score > $1.score }

        return results.prefix(topK).map { result in
            TaskSearchResult(
                task: result.task,
                similarity: result.score,
                successRate: result.task.successRate
            )
        }
    }

    /// Simple keyword-based search fallback (no embeddings)
    func searchKeywords(query: String, topK: Int = 5) -> [LearnedTask] {
        let tasks = load()
        let queryLower = query.lowercased()
        let tokens = queryLower.split(separator: " ").map(String.init)

        var scored: [(task: LearnedTask, score: Int)] = []

        for task in tasks {
            let phraseLower = task.phrase.lowercased()
            let appLower = task.app.lowercased()

            var score = 0
            for token in tokens {
                if phraseLower.contains(token) { score += 2 }
                if appLower.contains(token) { score += 1 }
            }

            if score > 0 {
                scored.append((task, score))
            }
        }

        scored.sort { $0.score > $1.score }
        return scored.prefix(topK).map { $0.task }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard normA > 0 && normB > 0 else { return 0.0 }
        return dotProduct / (normA * normB)
    }
}

/// Result from semantic search
struct TaskSearchResult {
    let task: LearnedTask
    let similarity: Float  // 0.0 to 1.0
    let successRate: Double  // 0.0 to 1.0
}
