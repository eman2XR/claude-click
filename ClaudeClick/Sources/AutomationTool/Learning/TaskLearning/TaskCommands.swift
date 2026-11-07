//
// TaskCommands.swift
// CLI commands for task learning
//

import Foundation

/// Parse and execute task learning commands
func handleTaskCommand(_ args: [String]) async {
    guard args.count > 0 else {
        printTaskHelp()
        return
    }

    let command = args[0]

    switch command {
    case "teach-task":
        await handleTeachTask(Array(args.dropFirst()))
    case "search-tasks":
        await handleSearchTasks(Array(args.dropFirst()))
    case "list-tasks":
        handleListTasks()
    case "forget-task":
        handleForgetTask(Array(args.dropFirst()))
    case "record-success":
        handleRecordSuccess(Array(args.dropFirst()))
    case "record-failure":
        handleRecordFailure(Array(args.dropFirst()))
    case "add-note":
        handleAddNote(Array(args.dropFirst()))
    default:
        print("Unknown task command: \(command)")
        printTaskHelp()
    }
}

/// Teach a new task workflow
/// Usage: teach-task "phrase" app step1 step2 ...
private func handleTeachTask(_ args: [String]) async {
    guard args.count >= 3 else {
        print("Usage: claude-click teach-task \"phrase\" <app> <step1> <step2> ...")
        print("Example: claude-click teach-task \"create keynote presentation\" Keynote open:Keynote wait:2 click:\"New Document\" click:Create")
        return
    }

    let phrase = args[0]
    let app = args[1]
    let stepArgs = Array(args.dropFirst(2))

    // Parse steps
    var steps: [LearnedTask.TaskStep] = []
    for stepStr in stepArgs {
        let parts = stepStr.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count >= 1 else { continue }

        let type = parts[0]
        let stepArgs = parts.count > 1 ? parts[1].split(separator: ":").map(String.init) : []

        steps.append(LearnedTask.TaskStep(type: type, args: stepArgs))
    }

    guard !steps.isEmpty else {
        print("Error: No valid steps provided")
        return
    }

    // Generate embedding
    do {
        let embeddingEngine = EmbeddingEngine.shared
        try await embeddingEngine.load()
        let embedding = try await embeddingEngine.embed(phrase)

        // Create task
        let task = LearnedTask(
            id: UUID().uuidString,
            phrase: phrase,
            app: app,
            steps: steps,
            embedding: embedding,
            stats: LearnedTask.TaskStats()
        )

        // Save
        let store = TaskStore()
        store.upsert(task)

        print("✅ Task learned: \"\(phrase)\"")
        print("   App: \(app)")
        print("   Steps: \(steps.count)")
        print("   Embedding: \(embedding.count) dimensions")

    } catch {
        print("Error: Failed to create embedding: \(error.localizedDescription)")
    }
}

/// Search for tasks semantically and return full details
/// Usage: search-tasks "query" [--json] [--top N]
private func handleSearchTasks(_ args: [String]) async {
    guard args.count >= 1 else {
        print("Usage: claude-click search-tasks \"query\" [--json] [--top N]")
        return
    }

    let query = args[0]
    let jsonOutput = args.contains("--json")
    var topK = 5

    // Parse --top N argument
    if let topIndex = args.firstIndex(of: "--top"), topIndex + 1 < args.count,
       let n = Int(args[topIndex + 1]) {
        topK = n
    }

    do {
        let embeddingEngine = EmbeddingEngine.shared
        try await embeddingEngine.load()
        let queryEmbedding = try await embeddingEngine.embed(query)

        let store = TaskStore()
        let results = store.search(query: query, embedding: queryEmbedding, topK: topK)

        if results.isEmpty {
            if jsonOutput {
                print("{\"query\": \"\(query)\", \"results\": [], \"message\": \"No relevant tasks found\"}")
            } else {
                print("No relevant tasks found for: \"\(query)\"")
            }
            return
        }

        if jsonOutput {
            printTaskDetailsJSON(query, results)
        } else {
            printTaskDetailsHuman(query, results)
        }

    } catch {
        if jsonOutput {
            print("{\"error\": \"\(error.localizedDescription)\"}")
        } else {
            print("Error: \(error.localizedDescription)")
        }
    }
}

/// List all learned tasks
private func handleListTasks() {
    let store = TaskStore()
    let tasks = store.load()

    if tasks.isEmpty {
        print("No tasks learned yet.")
        print("")
        print("Teach a task with:")
        print("  claude-click teach-task \"phrase\" app step1 step2 ...")
        return
    }

    print("Learned tasks (\(tasks.count)):")
    print("")

    for task in tasks.sorted(by: { ($0.stats.successCount) > ($1.stats.successCount) }) {
        let rate = task.successRate
        let indicator = rate > 0.8 ? "✅" : rate > 0.5 ? "⚠️" : "❌"
        print("\(indicator) \"\(task.phrase)\"")
        print("   App: \(task.app)")
        print("   Steps: \(task.steps.count)")
        print("   Success: \(task.stats.successCount)/\(task.stats.successCount + task.stats.failCount) (\(String(format: "%.0f%%", rate * 100)))")
        if let last = task.stats.lastSuccess {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            print("   Last success: \(formatter.localizedString(for: last, relativeTo: Date()))")
        }
        if !task.notes.isEmpty {
            print("   Notes: \(task.notes.count)")
            for (i, note) in task.notes.prefix(2).enumerated() {
                print("     \(i+1). \(note)")
            }
            if task.notes.count > 2 {
                print("     ... and \(task.notes.count - 2) more")
            }
        }
        print("")
    }
}

/// Forget (delete) a task
private func handleForgetTask(_ args: [String]) {
    guard args.count >= 1 else {
        print("Usage: claude-click forget-task \"phrase\"")
        return
    }

    let phrase = args[0]
    let store = TaskStore()
    let tasks = store.load()

    guard let task = tasks.first(where: { $0.phrase.lowercased() == phrase.lowercased() }) else {
        print("No task found matching: \"\(phrase)\"")
        return
    }

    store.delete(id: task.id)
    print("✅ Forgot task: \"\(task.phrase)\"")
}

/// Record successful execution of a task
private func handleRecordSuccess(_ args: [String]) {
    guard args.count >= 1 else {
        print("Usage: claude-click record-success \"phrase\" [duration_seconds]")
        return
    }

    let phrase = args[0]
    let duration = args.count > 1 ? Double(args[1]) ?? 0.0 : 0.0

    let store = TaskStore()
    var tasks = store.load()

    guard let index = tasks.firstIndex(where: { $0.phrase.lowercased() == phrase.lowercased() }) else {
        print("No task found matching: \"\(phrase)\"")
        return
    }

    var task = tasks[index]
    task.stats.successCount += 1
    task.stats.lastSuccess = Date()

    // Update average duration
    if duration > 0 {
        let prevAvg = task.stats.avgDurationSec
        let count = task.stats.successCount
        task.stats.avgDurationSec = ((prevAvg * Double(count - 1)) + duration) / Double(count)
    }

    tasks[index] = task
    store.save(tasks)

    let rate = String(format: "%.0f%%", task.successRate * 100)
    print("✅ Recorded success for: \"\(task.phrase)\"")
    print("   Success rate: \(rate) (\(task.stats.successCount)/\(task.stats.successCount + task.stats.failCount))")
}

/// Record failed execution of a task
private func handleRecordFailure(_ args: [String]) {
    guard args.count >= 1 else {
        print("Usage: claude-click record-failure \"phrase\"")
        return
    }

    let phrase = args[0]

    let store = TaskStore()
    var tasks = store.load()

    guard let index = tasks.firstIndex(where: { $0.phrase.lowercased() == phrase.lowercased() }) else {
        print("No task found matching: \"\(phrase)\"")
        return
    }

    var task = tasks[index]
    task.stats.failCount += 1

    tasks[index] = task
    store.save(tasks)

    let rate = String(format: "%.0f%%", task.successRate * 100)
    print("⚠️ Recorded failure for: \"\(task.phrase)\"")
    print("   Success rate: \(rate) (\(task.stats.successCount)/\(task.stats.successCount + task.stats.failCount))")
}

/// Add a note to a task
private func handleAddNote(_ args: [String]) {
    guard args.count >= 2 else {
        print("Usage: claude-click add-note \"phrase\" \"note text\"")
        return
    }

    let phrase = args[0]
    let note = args[1]

    let store = TaskStore()
    var tasks = store.load()

    guard let index = tasks.firstIndex(where: { $0.phrase.lowercased() == phrase.lowercased() }) else {
        print("No task found matching: \"\(phrase)\"")
        return
    }

    var task = tasks[index]
    task.notes.append(note)

    tasks[index] = task
    store.save(tasks)

    print("📝 Added note to: \"\(task.phrase)\"")
    print("   Note: \(note)")
    print("   Total notes: \(task.notes.count)")
}

// MARK: - Output formatting

private func printTaskDetailsJSON(_ query: String, _ results: [TaskSearchResult]) {
    let taskDetails: [[String: Any]] = results.map { result in
        let steps: [[String: Any]] = result.task.steps.map { step in
            return [
                "type": step.type,
                "args": step.args
            ]
        }

        return [
            "task": result.task.phrase,
            "app": result.task.app,
            "similarity": result.similarity,
            "success_rate": result.successRate,
            "steps": steps,
            "notes": result.task.notes
        ]
    }

    let output: [String: Any] = [
        "query": query,
        "results": taskDetails
    ]

    if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

private func printTaskDetailsHuman(_ query: String, _ results: [TaskSearchResult]) {
    print("Tasks matching: \"\(query)\"")
    print("")

    for (i, result) in results.enumerated() {
        let sim = String(format: "%.0f%%", result.similarity * 100)
        let rate = String(format: "%.0f%%", result.successRate * 100)
        print("\(i+1). \"\(result.task.phrase)\" (similarity: \(sim), success: \(rate))")
        print("   App: \(result.task.app)")
        print("   Steps:")
        for (j, step) in result.task.steps.enumerated() {
            let args = step.args.joined(separator: " ")
            print("     \(j+1). \(step.type) \(args)")
        }
        if !result.task.notes.isEmpty {
            print("   Notes:")
            for (j, note) in result.task.notes.enumerated() {
                print("     \(j+1). \(note)")
            }
        }
        print("")
    }
}

private func printTaskHelp() {
    print("""
    Task Learning Commands:
      teach-task \"phrase\" <app> <step1> <step2> ...   Teach a new task workflow
      search-tasks \"query\" [--json] [--top N]         Search for tasks with full details
      list-tasks                                       List all learned tasks
      forget-task \"phrase\"                            Delete a learned task
      record-success \"phrase\" [duration]              Record successful execution
      record-failure \"phrase\"                         Record failed execution
      add-note \"phrase\" \"note text\"                  Add a note/tip to a task

    Examples:
      claude-click teach-task "create keynote" Keynote open:Keynote wait:2 click:"New Document"
      claude-click search-tasks "new presentation" --json
      claude-click search-tasks "make slideshow" --top 3
      claude-click record-success "create keynote" 8.5
      claude-click record-failure "search google"
      claude-click add-note "create keynote" "Sometimes fails if Keynote already has a window open"
      claude-click list-tasks

    Note: search-tasks returns full step details for Claude Code to read and adapt.
          Record success/failure after executing tasks to improve success rates.
          Use add-note to document issues, tips, or specific behaviors.
    """)
}
