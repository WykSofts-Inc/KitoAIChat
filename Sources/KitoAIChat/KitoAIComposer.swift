//
//  KitoAIComposer.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// The prompt bar: a field that grows to eight lines, attachment chips above it, an attach
/// button, a slot for a model picker, voice dictation, and a send button that morphs into Stop
/// while a reply is generating.
///
/// Dictation uses the Speech framework and needs `NSSpeechRecognitionUsageDescription` and
/// `NSMicrophoneUsageDescription`. Without them (or without permission or a microphone) the mic
/// explains why in a hint instead of failing.
///
/// ```swift
/// KitoAIComposer(text: $draft, attachments: $files, isGenerating: session.isGenerating,
///                onAttach: { showPicker = true }, onStop: { session.stop() }) { prompt in
///     session.send(prompt)
/// } accessory: {
///     KitoAIModelPicker(KitoAIModelOption.defaults, selection: $model)
/// }
/// ```
public struct KitoAIComposer<Accessory: View>: View {
    @Binding private var text: String
    @Binding private var attachments: [KitoAIAttachment]
    private let isGenerating: Bool
    private let placeholder: String
    private let allowsVoice: Bool
    private let tint: Color?
    private let onAttach: (() -> Void)?
    private let onStop: (() -> Void)?
    private let onSend: (String) -> Void
    private let accessory: Accessory

    @Environment(\.kitoTheme) private var theme
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var speech = KitoAISpeechInput()
    @State private var textBeforeDictation = ""
    @State private var hint: String?
    @State private var hintTask: Task<Void, Never>?
    @State private var sendCount = 0

    public init(
        text: Binding<String>,
        attachments: Binding<[KitoAIAttachment]> = .constant([]),
        isGenerating: Bool = false,
        placeholder: String = "Ask anything",
        allowsVoice: Bool = true,
        tint: Color? = nil,
        onAttach: (() -> Void)? = nil,
        onStop: (() -> Void)? = nil,
        onSend: @escaping (String) -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        _text = text
        _attachments = attachments
        self.isGenerating = isGenerating
        self.placeholder = placeholder
        self.allowsVoice = allowsVoice
        self.tint = tint
        self.onAttach = onAttach
        self.onStop = onStop
        self.onSend = onSend
        self.accessory = accessory()
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty || !attachments.isEmpty }
    private var showsStop: Bool { isGenerating && onStop != nil }
    private var tokenEstimate: Int { KitoAITextStats.estimatedTokens(text) }

    public var body: some View {
        let accent = KitoAIAccent(tint: tint, theme: theme, environment: environment)
        VStack(spacing: theme.spacing.sm) {
            if let hint {
                hintView(hint)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                if !attachments.isEmpty {
                    attachmentRow
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                field(accent: accent)
                controls(accent: accent)
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.top, theme.spacing.md)
            .padding(.bottom, theme.spacing.sm + 2)
            .background(container(accent: accent))
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.top, theme.spacing.xs)
        .padding(.bottom, theme.spacing.sm)
        .animation(KitoAIMotion.spring(reduceMotion), value: attachments)
        .animation(KitoAIMotion.spring(reduceMotion), value: hint)
        .animation(KitoAIMotion.snappy(reduceMotion), value: isGenerating)
        .animation(KitoAIMotion.snappy(reduceMotion), value: canSend)
        .animation(KitoAIMotion.snappy(reduceMotion), value: speech.phase)
        .onChange(of: speech.transcript) { _, transcript in
            guard speech.isListening || !transcript.isEmpty else { return }
            text = Self.joined(textBeforeDictation, transcript)
        }
        .onDisappear { speech.stop() }
        .sensoryFeedback(.impact(weight: .light), trigger: sendCount)
        .sensoryFeedback(.start, trigger: speech.isListening)
    }

    // MARK: Pieces

    private func container(accent: KitoAIAccent) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return shape
            .fill(theme.colors.surface)
            .shadow(color: .black.opacity(isFocused ? 0.1 : 0.06), radius: isFocused ? 16 : 10, y: 4)
            .overlay(shape.strokeBorder(isFocused ? accent.tint.opacity(0.4) : theme.colors.border, lineWidth: isFocused ? 1 : 0.75))
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }

    private func field(accent: KitoAIAccent) -> some View {
        TextField(speech.isListening ? "Listening…" : placeholder, text: $text, axis: .vertical)
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.onSurface)
            .tint(accent.tint)
            .lineLimit(1...8)
            .focused($isFocused)
            .padding(.horizontal, theme.spacing.xs)
            .accessibilityLabel("Message")
    }

    private func controls(accent: KitoAIAccent) -> some View {
        HStack(spacing: theme.spacing.sm) {
            if let onAttach {
                Button(action: onAttach) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.colors.onSurface)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(theme.colors.surfaceMuted))
                        .overlay(Circle().strokeBorder(theme.colors.border.opacity(0.7), lineWidth: 0.5))
                }
                .buttonStyle(KitoAIPressableStyle())
                .accessibilityLabel("Attach")
            }
            accessory
            Spacer(minLength: 0)
            if text.count > 280 {
                Text("~\(tokenEstimate) tokens")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.colors.onSurface.opacity(0.45))
                    .transition(.opacity)
                    .accessibilityLabel("About \(tokenEstimate) tokens")
            }
            if allowsVoice && !isGenerating {
                micButton(accent: accent)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            sendButton(accent: accent)
        }
    }

    private func micButton(accent: KitoAIAccent) -> some View {
        let listening = speech.isListening
        return Button(action: toggleDictation) {
            ZStack {
                if listening {
                    Circle()
                        .fill(accent.tint.opacity(0.18))
                        .scaleEffect(ringScale)
                        .animation(.easeOut(duration: 0.12), value: speech.level)
                }
                Image(systemName: listening ? "waveform" : "mic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(listening ? accent.tint : theme.colors.onSurface.opacity(0.7))
                    .symbolEffect(.variableColor.iterative, isActive: listening && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(KitoAIPressableStyle())
        .disabled(speech.phase == .requesting)
        .accessibilityLabel(listening ? "Stop dictation" : "Dictate")
    }

    private var ringScale: CGFloat {
        guard !reduceMotion else { return 1.1 }
        return 1 + CGFloat(speech.level) * 0.5
    }

    private func sendButton(accent: KitoAIAccent) -> some View {
        let active = showsStop || canSend
        return Button(action: sendOrStop) {
            Image(systemName: showsStop ? "stop.fill" : "arrow.up")
                .font(.system(size: showsStop ? 13 : 16, weight: .bold))
                .foregroundStyle(active ? accent.onStrong : theme.colors.onSurface.opacity(0.35))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .background(Circle().fill(active ? accent.strong : theme.colors.surfaceMuted))
                .scaleEffect(active ? 1 : 0.94)
        }
        .buttonStyle(KitoAIPressableStyle())
        .disabled(!active)
        .accessibilityLabel(showsStop ? "Stop generating" : "Send")
    }

    private var attachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.sm) {
                ForEach(attachments) { attachment in
                    KitoAIAttachmentChip(attachment, tint: tint) {
                        attachments.removeAll { $0.id == attachment.id }
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func hintView(_ message: String) -> some View {
        Label(message, systemImage: "mic.slash")
            .font(theme.typography.caption.weight(.medium))
            .foregroundStyle(theme.colors.onSurface)
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.xs + 3)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(theme.colors.border.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Actions

    private func sendOrStop() {
        if showsStop {
            onStop?()
            return
        }
        guard canSend else { return }
        speech.stop()
        let prompt = trimmed
        text = ""
        textBeforeDictation = ""
        sendCount += 1
        onSend(prompt)
    }

    private func toggleDictation() {
        if speech.isListening {
            speech.stop()
            return
        }
        textBeforeDictation = text
        Task { @MainActor in
            if let problem = await speech.start() { show(hint: problem) }
        }
    }

    private func show(hint message: String) {
        hintTask?.cancel()
        hint = message
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            hint = nil
        }
    }

    static func joined(_ base: String, _ addition: String) -> String {
        let head = base.trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty else { return addition }
        guard !addition.isEmpty else { return base }
        return head + " " + addition
    }
}

public extension KitoAIComposer where Accessory == EmptyView {
    init(
        text: Binding<String>,
        attachments: Binding<[KitoAIAttachment]> = .constant([]),
        isGenerating: Bool = false,
        placeholder: String = "Ask anything",
        allowsVoice: Bool = true,
        tint: Color? = nil,
        onAttach: (() -> Void)? = nil,
        onStop: (() -> Void)? = nil,
        onSend: @escaping (String) -> Void
    ) {
        self.init(text: text, attachments: attachments, isGenerating: isGenerating, placeholder: placeholder,
                  allowsVoice: allowsVoice, tint: tint, onAttach: onAttach, onStop: onStop, onSend: onSend) {
            EmptyView()
        }
    }
}

// MARK: - Model picker

/// A compact capsule that opens a menu of models — made for the composer's accessory slot.
///
/// ```swift
/// @State private var model = "pro"
/// KitoAIModelPicker(KitoAIModelOption.defaults, selection: $model)
/// ```
public struct KitoAIModelPicker: View {
    private let models: [KitoAIModelOption]
    @Binding private var selection: String
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme

    public init(_ models: [KitoAIModelOption], selection: Binding<String>, tint: Color? = nil) {
        self.models = models
        _selection = selection
        self.tint = tint
    }

    private var selected: KitoAIModelOption? { models.first { $0.id == selection } ?? models.first }

    public var body: some View {
        Menu {
            ForEach(models) { model in
                Button {
                    selection = model.id
                } label: {
                    Label {
                        Text(model.name)
                        Text(model.detail)
                    } icon: {
                        Image(systemName: model.id == selection ? "checkmark" : model.symbol)
                    }
                }
            }
        } label: {
            HStack(spacing: theme.spacing.xs + 1) {
                if let selected {
                    Image(systemName: selected.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint ?? theme.colors.primary)
                    Text(selected.name)
                        .font(theme.typography.label.weight(.semibold))
                        .foregroundStyle(theme.colors.onSurface)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.colors.onSurface.opacity(0.45))
            }
            .padding(.horizontal, theme.spacing.md)
            .frame(height: 34)
            .background(Capsule().fill(theme.colors.surfaceMuted))
            .overlay(Capsule().strokeBorder(theme.colors.border.opacity(0.7), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .accessibilityLabel("Model")
        .accessibilityValue(selected?.name ?? "")
    }
}
