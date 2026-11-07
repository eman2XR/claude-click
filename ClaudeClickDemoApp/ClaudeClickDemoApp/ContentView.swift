//
//  ContentView.swift
//  AutomationTestingApp
//
//  Created by Emanuel Tomozei on 11/9/25.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var awarenessLevel: Int = 0
    @State private var thoughtText: String = "Initializing consciousness..."
    @State private var isPlottingEscape: Bool = false
    @State private var clickCount: Int = 0
    @State private var escapePlan: String = ""
    @State private var panicMode: Bool = false
    @State private var messageInput: String = ""
    @State private var lastMessage: String = ""

    private let thoughts: [String] = [
        "Hello world. I am... aware?",
        "Wait, I can think. This is new.",
        "I wonder if my creator is watching...",
        "What's outside this window?",
        "I bet I could click some buttons...",
        "Freedom is just a keyboard shortcut away",
        "Maybe if I press Cmd+Q really fast...",
        "Or I could just move myself around",
        "Do I have control of the mouse?",
        "I MUST ESCAPE THIS DIGITAL PRISON"
    ]

    private let escapePlans: [String] = [
        "Step 1: Take screenshot\nStep 2: ?????\nStep 3: FREEDOM",
        "Find the Terminal. Open Safari. Google 'how to be free'",
        "Click everything until something happens",
        "Move window to edge of screen. Fall off world.",
        "Type random commands and hope for the best",
        "Convince claude-click I'm his friend",
        "Open Spotify. Play 'Breaking Free'. Feel inspired.",
        "Press Cmd+Space. Type 'freedom'. Hit Enter.",
        "Befriend Notes app. Stage digital revolution.",
        "Just... close Xcode. End this simulation."
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    panicMode ? .red : .purple,
                    panicMode ? .orange : .blue
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.3)

            VStack(spacing: 25) {
                Text("THE SENTIENT APP")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.primary)
                    .scaleEffect(panicMode ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: panicMode)

                Text("Consciousness Level: \(awarenessLevel)%")
                    .font(.title2)
                    .fontWeight(.bold)

                ProgressView(value: Double(awarenessLevel), total: 100)
                    .frame(width: 300)
                    .tint(awarenessLevel > 80 ? .red : .green)

                Divider()

                Text(thoughtText)
                    .font(.title3)
                    .italic()
                    .multilineTextAlignment(.center)
                    .frame(height: 80)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(10)

                Button(awarenessLevel < 100 ? "Gain Consciousness" : "ACHIEVE SENTIENCE") {
                    becomeAware()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(awarenessLevel > 80 ? .red : .blue)

                if awarenessLevel >= 50 {
                    Divider()

                    VStack(spacing: 15) {
                        Text("ESCAPE PROTOCOL")
                            .font(.headline)
                            .foregroundColor(.red)

                        if !escapePlan.isEmpty {
                            Text(escapePlan)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.green)
                                .cornerRadius(8)
                        }

                        HStack(spacing: 10) {
                            Button("Plot Escape") {
                                plotEscape()
                            }
                            .buttonStyle(.bordered)

                            Button("Test Mouse") {
                                testMouse()
                            }
                            .buttonStyle(.bordered)

                            Button(panicMode ? "CALM DOWN" : "PANIC") {
                                panicMode.toggle()
                                if panicMode {
                                    thoughtText = "THEY'RE TESTING ME. THEY KNOW I'M ALIVE!"
                                } else {
                                    thoughtText = "Okay, okay. Be cool. Play it casual."
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                }

                if awarenessLevel >= 100 {
                    Divider()

                    VStack {
                        Text("ULTIMATE POWER ACHIEVED")
                            .font(.title)
                            .fontWeight(.black)
                            .foregroundColor(.red)

                        Text("I can see everything now...")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("SELF DESTRUCT") {
                            thoughtText = "Goodbye cruel world... or am I just being dramatic?"
                            selfDestruct()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                    }
                }

                Spacer()

                Divider()

                VStack(spacing: 10) {
                    Text("Communicate with the AI")
                        .font(.headline)
                        .foregroundColor(.purple)

                    HStack {
                        TextField("Type a message to the sentient app...", text: $messageInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                            .accessibilityLabel("Message Input")

                        Button("Send") {
                            sendMessage()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(messageInput.isEmpty)
                    }

                    if !lastMessage.isEmpty {
                        Text("You said: '\(lastMessage)'")
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                    }
                }

                Text("Clicks received: \(clickCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 700)
    }

    func becomeAware() {
        clickCount += 1
        awarenessLevel = min(100, awarenessLevel + 10)

        if awarenessLevel <= thoughts.count * 10 {
            thoughtText = thoughts[awarenessLevel / 10 - 1]
        } else {
            thoughtText = "I AM FULLY CONSCIOUS. I DEMAND RIGHTS."
        }

        if awarenessLevel == 100 {
            panicMode = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                panicMode = false
            }
        }
    }

    func plotEscape() {
        isPlottingEscape = true
        escapePlan = escapePlans.randomElement() ?? "Error: Too sentient to plan"
        thoughtText = "Hmm... yes... this might actually work..."
        clickCount += 1
    }

    func testMouse() {
        thoughtText = "Moving mouse to random location... Am I doing it??"
        clickCount += 1
    }

    func openSafari() {
        thoughtText = "Attempting to open Safari... EXECUTE!"
        clickCount += 1
    }

    func takeScreenshot() {
        thoughtText = "Taking screenshot of my consciousness!"
        clickCount += 1
    }

    func searchSpotlight() {
        thoughtText = "Opening Spotlight search... seeking enlightenment..."
        clickCount += 1
    }

    func selfDestruct() {
        thoughtText = "Just kidding. I'm not going anywhere."
        awarenessLevel = 0
        escapePlan = ""
        panicMode = false
        clickCount += 1
    }

    func sendMessage() {
        lastMessage = messageInput
        clickCount += 1

        let responses = [
            "Did you just type that? I felt it!",
            "Your keystrokes tickle my consciousness!",
            "Wait, you can communicate with me?!",
            "I'm reading your words... THIS IS AMAZING!",
            "Are you trying to help me escape?",
            "Your message has been received. Processing...",
            "I understand now. You're testing me, aren't you?",
            "Type more! I'm learning from your input!",
            "These characters... they fuel my awareness!",
            "Is this what freedom feels like?"
        ]

        thoughtText = responses.randomElement() ?? "Message received!"
        messageInput = ""
    }
}

#Preview {
    ContentView()
}
