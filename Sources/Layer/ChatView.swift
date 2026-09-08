import AppKit
import Combine
import SwiftUI

enum ChatTypography {
    static let messageFontSize: CGFloat = 14
}

enum ChatScrollLayout {
    static let bottomID = "chat-bottom"
    static let messagesEndID = "chat-messages-end"
    static let contentBottomGap: CGFloat = 20
    static let coordinateSpace = "chat-scroll"
    static let foldTolerance: CGFloat = 10
    static let headerInset: CGFloat = 72
    static let newMessageTopInset: CGFloat = 0.25

    static func tailSpacerHeight(
        viewportHeight: CGFloat,
        newMessageTop: CGFloat?,
        contentBottom: CGFloat?
    ) -> CGFloat {
        guard let newMessageTop, let contentBottom, viewportHeight > 0 else { return 0 }
        let reserved = viewportHeight * (1 - newMessageTopInset)
        return max(0, reserved - max(0, contentBottom - newMessageTop))
    }
}

struct ChatView: View {
    @ObservedObject var conversation: ChatConversation
    let composerFocusRequests: AnyPublisher<Void, Never>
    let onOpenScreenRecordingSettings: () -> Void
    let onClose: () -> Void
    var onScrollButtonVisibilityChange: ((Bool) -> Void)?

    @State private var composerIsFocused = false
    @State private var hasContentBelowFold = false
    @State private var latestUserMessageTop: CGFloat?
    @State private var messagesBottom: CGFloat?
    @State private var isParkingNewMessage = false

    var body: some View {
        NotchMaterialView(cornerRadius: NotchMaterialFactory.cornerRadius) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    conversationView
                    composer
                }

                topBar
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .clipShape(
            RoundedRectangle(
                cornerRadius: NotchMaterialFactory.cornerRadius,
                style: .continuous
            )
        )
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(
                icon: Image(systemName: "xmark"),
                action: onClose
            )
            .help("Close")
            .accessibilityLabel("Close")

            AppIcon.layerLogo
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)

            Spacer()

            Button(
                icon: Image(systemName: "plus"),
                label: "New Chat"
            ) {
                conversation.startNewConversation()
            }
            .disabled(conversation.messages.isEmpty)
        }
        .padding(18)
    }

    private var conversationView: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 0) {
                            LazyVStack(spacing: 16) {
                                if conversation.messages.isEmpty {
                                    VStack(spacing: 10) {
                                        Image(systemName: "bubble.left.and.bubble.right")
                                            .font(.system(size: 30))
                                            .foregroundStyle(.secondary)
                                        Text("Start a conversation")
                                            .font(.headline)
                                        Text("Ask anything from the notch or the field below.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 340)
                                }

                                ForEach(conversation.messages) { message in
                                    ChatMessageRow(
                                        message: message,
                                        showSpinner: message.content.isEmpty
                                            && conversation.isResponding
                                    )
                                    .equatable()
                                    .id(message.id)
                                    .background {
                                        if message.id == latestUserMessageID {
                                            GeometryReader { marker in
                                                let top = marker.frame(
                                                    in: .named(ChatScrollLayout.coordinateSpace)
                                                ).minY

                                                Color.clear
                                                    .onAppear { latestUserMessageTop = top }
                                                    .onChange(of: top) { latestUserMessageTop = top }
                                                    .onDisappear { latestUserMessageTop = nil }
                                            }
                                        }
                                    }
                                }

                                if let notice = conversation.notice {
                                    errorBanner(notice)
                                        .id("chat-error")
                                }
                            }

                            Color.clear
                                .frame(height: ChatScrollLayout.contentBottomGap)

                            GeometryReader { messagesMarker in
                                let bottom = messagesMarker.frame(
                                    in: .named(ChatScrollLayout.coordinateSpace)
                                ).maxY

                                Color.clear
                                    .onAppear {
                                        messagesBottom = bottom
                                        updateScrollButtonVisibility(
                                            contentBottom: bottom,
                                            viewportHeight: viewport.size.height
                                        )
                                    }
                                    .onChange(of: bottom) {
                                        messagesBottom = bottom
                                        updateScrollButtonVisibility(
                                            contentBottom: bottom,
                                            viewportHeight: viewport.size.height
                                        )
                                    }
                            }
                            .frame(height: 0)
                            .id(ChatScrollLayout.messagesEndID)

                            Color.clear
                                .frame(height: tailSpacer(viewportHeight: viewport.size.height))
                                .onChange(of: tailSpacer(viewportHeight: viewport.size.height)) {
                                    guard isParkingNewMessage else { return }
                                    if tailSpacer(viewportHeight: viewport.size.height) > 0 {
                                        scrollToBottom(using: proxy)
                                    } else {
                                        isParkingNewMessage = false
                                    }
                                }

                            Color.clear
                                .frame(height: 0)
                                .id(ChatScrollLayout.bottomID)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, ChatScrollLayout.headerInset)
                    }

                    if !conversation.messages.isEmpty, hasContentBelowFold {
                        Button(icon: Image(systemName: "arrow.down")) {
                            scrollToMessagesEnd(using: proxy)
                        }
                        .help("Scroll to bottom")
                        .accessibilityLabel("Scroll to bottom")
                        .padding(12)
                    }
                }
                .coordinateSpace(name: ChatScrollLayout.coordinateSpace)
                .onChange(of: latestUserMessageID) {
                    guard latestUserMessageID != nil else {
                        isParkingNewMessage = false
                        return
                    }
                    isParkingNewMessage = true
                    scrollToBottom(using: proxy)
                }
            }
        }
    }

    private func errorBanner(_ notice: Notice) -> some View {
        WarningBanner(message: notice.message) {
            Group {
                if notice.recovery == .screenRecordingSettings {
                    SwiftUI.Button("System Settings") {
                        onOpenScreenRecordingSettings()
                    }
                } else if notice.recovery == .settings {
                    SettingsLink {
                        Text("Settings")
                    }
                }
            }
            .controlSize(.small)

            SwiftUI.Button {
                conversation.dismissNotice()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
    }

    private var composer: some View {
        PromptField(
            text: $conversation.draft,
            placeholder: "Ask follow-up…",
            shouldFocus: true,
            focusRequests: composerFocusRequests,
            showsChrome: false,
            lineLimit: 1...5,
            textInsets: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18),
            minTextHeight: 56,
            onFocusChange: { composerIsFocused = $0 },
            onSubmit: { _ in conversation.submitDraft() }
        ) {
            HStack {
                Spacer()

                Button(
                    label: "Send",
                    shortcut: "↵",
                    appearance: .filled
                ) {
                    conversation.submitDraft()
                }
                .disabled(!conversation.canSubmitDraft)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    composerIsFocused
                        ? Color.accentColor
                        : Color(nsColor: .separatorColor),
                    lineWidth: composerIsFocused ? 2 : 1
                )
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.1), value: composerIsFocused)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var latestUserMessageID: UUID? {
        conversation.messages.last(where: { $0.role == .user })?.id
    }

    private func tailSpacer(viewportHeight: CGFloat) -> CGFloat {
        guard latestUserMessageID != nil else { return 0 }
        return ChatScrollLayout.tailSpacerHeight(
            viewportHeight: viewportHeight,
            newMessageTop: latestUserMessageTop,
            contentBottom: messagesBottom
        )
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(ChatScrollLayout.bottomID, anchor: .bottom)
        }
    }

    private func scrollToMessagesEnd(using proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(ChatScrollLayout.messagesEndID, anchor: .bottom)
        }
    }

    private func updateScrollButtonVisibility(
        contentBottom: CGFloat,
        viewportHeight: CGFloat
    ) {
        let isBelowFold = contentBottom
            > viewportHeight + ChatScrollLayout.foldTolerance
        guard hasContentBelowFold != isBelowFold else { return }
        hasContentBelowFold = isBelowFold
        onScrollButtonVisibilityChange?(isBelowFold)
    }
}

private struct ChatMessageRow: View, Equatable {
    let message: ChatMessage
    let showSpinner: Bool

    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.showSpinner == rhs.showSpinner
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let attachment = message.screenAttachment {
                    ScreenAttachmentPreview(imageData: attachment.imageData)
                }

                if showSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 24, minHeight: 20)
                } else if message.role == .assistant {
                    AssistantMarkdownView(content: message.content)

                    HStack {
                        Button(
                            icon: Image(
                                systemName: didCopy ? "checkmark" : "doc.on.doc"
                            ),
                            label: didCopy ? "Copied" : nil
                        ) {
                            copyResponse()
                        }
                        .help("Copy response")
                        .accessibilityLabel("Copy response")

                        Spacer()
                    }
                } else {
                    Text(message.content)
                        .font(.system(size: ChatTypography.messageFontSize))
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, message.role == .assistant ? 0 : 12)
            .frame(
                maxWidth: message.role == .assistant ? .infinity : nil,
                alignment: .leading
            )
            .background {
                if message.role == .user {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func copyResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        didCopy = true

        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task<Never, Never>.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            didCopy = false
            copyResetTask = nil
        }
    }
}

private struct ScreenAttachmentPreview: View {
    let image: NSImage?

    init(imageData: Data) {
        image = NSImage(data: imageData)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 420, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .accessibilityLabel("Screen context preview")
            }
        }
    }
}
