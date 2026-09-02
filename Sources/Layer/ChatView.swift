import Combine
import SwiftUI

struct ChatView: View {
    @ObservedObject var conversation: ChatConversation
    let composerFocusRequests: AnyPublisher<Void, Never>
    let onOpenScreenRecordingSettings: () -> Void

    @FocusState private var composerIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversationView
            Divider()
            composer
        }
        .frame(minWidth: 560, minHeight: 520)
        .onReceive(composerFocusRequests) { _ in
            DispatchQueue.main.async {
                composerIsFocused = true
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Layer")
                    .font(.headline)
                Text("GPT-5.4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("New Chat") {
                conversation.startNewConversation()
            }
            .disabled(conversation.messages.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var conversationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
                            showSpinner: message.content.isEmpty && conversation.isResponding
                        )
                        .equatable()
                        .id(message.id)
                    }

                    if let notice = conversation.notice {
                        errorBanner(notice)
                            .id("chat-error")
                    }
                }
                .padding(20)
            }
            .onChange(of: scrollState) {
                scrollToBottom(using: proxy)
            }
        }
    }

    private func errorBanner(_ notice: Notice) -> some View {
        WarningBanner(message: notice.message) {
            Group {
                if notice.recovery == .screenRecordingSettings {
                    Button("System Settings") {
                        onOpenScreenRecordingSettings()
                    }
                } else {
                    SettingsLink {
                        Text("Settings")
                    }
                }
            }
            .controlSize(.small)

            Button {
                conversation.dismissNotice()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Layer", text: $conversation.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($composerIsFocused)
                .onSubmit {
                    conversation.submitDraft()
                }

            Button {
                conversation.submitDraft()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
            }
            .buttonStyle(.borderless)
            .disabled(!conversation.canSubmitDraft)
            .help("Send")
            .accessibilityLabel("Send message")
        }
        .padding(16)
    }

    private var scrollState: ScrollState {
        ScrollState(
            messageCount: conversation.messages.count,
            lastContent: conversation.messages.last?.content,
            noticeMessage: conversation.notice?.message
        )
    }

    private struct ScrollState: Equatable {
        let messageCount: Int
        let lastContent: String?
        let noticeMessage: String?
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        let scroll = {
            if conversation.notice != nil {
                proxy.scrollTo("chat-error", anchor: .bottom)
            } else if let lastMessage = conversation.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }

        if conversation.isResponding {
            scroll()
        } else {
            withAnimation(.easeOut(duration: 0.12), scroll)
        }
    }
}

private struct ChatMessageRow: View, Equatable {
    let message: ChatMessage
    let showSpinner: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .user ? "You" : "Layer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let attachment = message.screenAttachment {
                    ScreenAttachmentPreview(imageData: attachment.imageData)
                }

                if showSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 24, minHeight: 20)
                } else if message.role == .assistant {
                    AssistantMarkdownView(content: message.content)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        message.role == .user
                            ? Color.accentColor.opacity(0.16)
                            : Color(nsColor: .controlBackgroundColor)
                    )
            }

            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
        .frame(maxWidth: .infinity)
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
