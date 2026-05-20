// FILE: WorkspaceImagePreview.swift
// Purpose: Loads, caches, and presents workspace image/text previews from assistant links.
// Layer: Turn UI preview service
// Exports: AssistantWorkspaceImagePreviewScreen, WorkspaceLinkedFilePreviewScreen, WorkspaceImagePreviewCache
// Depends on: Foundation, ImageIO, SwiftUI, UIKit, CodexService workspace preview APIs

import Foundation
import ImageIO
import SwiftUI
import UIKit

struct AssistantWorkspaceImagePreviewRequest: Identifiable {
    let id = UUID()
    let reference: AssistantMarkdownImageReference
    let currentWorkingDirectory: String?
    let initialPayload: PreviewImagePayload?
}

struct WorkspaceFilePreviewRequest: Identifiable, Equatable {
    let path: String
    let currentWorkingDirectory: String?

    var id: String {
        "\(currentWorkingDirectory ?? "")|\(path)"
    }
}

fileprivate enum WorkspaceLinkedFilePreviewKind {
    case imageFirst
    case textFirst
}

enum WorkspaceFileLinkResolver {
    private static let textFileExtensions: Set<String> = [
        "c", "cc", "cpp", "css", "go", "h", "html", "java", "js", "json", "jsx",
        "kt", "m", "md", "mm", "py", "rb", "rs", "sh", "swift", "toml", "ts",
        "tsx", "txt", "xml", "yaml", "yml"
    ]
    private static let imageFileExtensions: Set<String> = [
        "gif", "heic", "heif", "jpeg", "jpg", "png", "webp"
    ]
    private static let extensionlessFileNames: Set<String> = [
        "dockerfile", "gemfile", "makefile", "podfile"
    ]

    // Converts markdown link destinations into local paths the paired Mac can read.
    static func localPath(from url: URL) -> String? {
        if url.isFileURL {
            return normalizedPath(url.path)
        }

        guard url.scheme == nil else {
            return nil
        }

        let rawValue = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        return normalizedPath(rawValue)
    }

    fileprivate static func preferredPreviewKind(for path: String) -> WorkspaceLinkedFilePreviewKind {
        let fileExtension = (path as NSString).pathExtension.lowercased()
        return textFileExtensions.contains(fileExtension) ? .textFirst : .imageFirst
    }

    private static func normalizedPath(_ value: String) -> String? {
        let trimmed = stripLineSuffix(from: stripFragmentAndQuery(from: value))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.contains("\n"),
              !trimmed.contains("\r") else {
            return nil
        }
        guard isLocalPathCandidate(trimmed) else {
            return nil
        }
        return trimmed
    }

    private static func isLocalPathCandidate(_ value: String) -> Bool {
        if value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") {
            return true
        }
        guard !looksLikeSchemeLessWebURL(value) else {
            return false
        }

        let fileName = (value as NSString).lastPathComponent.lowercased()
        let fileExtension = (value as NSString).pathExtension.lowercased()
        return extensionlessFileNames.contains(fileName)
            || textFileExtensions.contains(fileExtension)
            || imageFileExtensions.contains(fileExtension)
    }

    private static func looksLikeSchemeLessWebURL(_ value: String) -> Bool {
        guard value.contains("/") else {
            return false
        }
        guard let firstComponent = value.split(separator: "/", maxSplits: 1).first else {
            return false
        }
        return firstComponent.contains(".")
            && !firstComponent.hasPrefix(".")
            && !firstComponent.hasSuffix(".")
    }

    private static func stripFragmentAndQuery(from value: String) -> String {
        guard let boundary = value.firstIndex(where: { $0 == "#" || $0 == "?" }) else {
            return value
        }
        return String(value[..<boundary])
    }

    private static func stripLineSuffix(from value: String) -> String {
        var normalized = value
        if let range = normalized.range(of: #":\d+(?::\d+)?$"#, options: .regularExpression) {
            normalized.removeSubrange(range)
        }
        return normalized
    }
}

private struct WorkspacePreviewChromeButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.shared.triggerImpactFeedback(style: .light)
            action()
        } label: {
            RemodexIcon.image(systemName: systemName)
                .font(AppFont.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .adaptiveGlass(.regular, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct WorkspacePreviewTitlePill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppFont.subheadline(weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .adaptiveGlass(.regular, in: Capsule())
    }
}

private struct WorkspacePreviewRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Retry", systemImage: "arrow.clockwise")
                .font(AppFont.subheadline(weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .adaptiveGlass(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct AssistantMarkdownImagePreviewButton: View {
    let reference: AssistantMarkdownImageReference
    let currentWorkingDirectory: String?

    @Environment(CodexService.self) private var codex
    @State private var previewRequest: AssistantWorkspaceImagePreviewRequest?
    @State private var loadedPreview: PreviewImagePayload?
    @State private var isAutoLoadingPreview = false
    @State private var didAttemptAutoPreviewLoad = false

    private static let cornerRadius: CGFloat = 18
    private static let maxWidth: CGFloat = 200

    var body: some View {
        Button {
            HapticFeedback.shared.triggerImpactFeedback(style: .light)
            openPreview()
        } label: {
            content
        }
        .buttonStyle(.plain)
        .task(id: autoPreviewLoadKey) {
            await loadPreviewAfterChatSettlesIfNeeded()
        }
        .fullScreenCover(item: $previewRequest) { request in
            AssistantWorkspaceImagePreviewScreen(
                reference: request.reference,
                currentWorkingDirectory: request.currentWorkingDirectory,
                initialPayload: request.initialPayload,
                onDismiss: { previewRequest = nil }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loadedPreview {
            loadedImage(loadedPreview)
        } else {
            metadataCard
        }
    }

    private func loadedImage(_ payload: PreviewImagePayload) -> some View {
        Image(uiImage: payload.image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private var metadataCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                if isAutoLoadingPreview {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.accentColor)
                } else {
                    RemodexIcon.image(systemName: "photo")
                        .font(AppFont.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(reference.fileName.isEmpty ? "Generated image" : reference.fileName)
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.primary)
                Text(reference.path)
                    .font(AppFont.mono(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            RemodexIcon.image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(AppFont.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func openPreview() {
        previewRequest = AssistantWorkspaceImagePreviewRequest(
            reference: reference,
            currentWorkingDirectory: currentWorkingDirectory,
            initialPayload: loadedPreview
        )
    }

    private var autoPreviewLoadKey: String {
        "\(reference.id)|\(codex.connectionPhase)"
    }

    private var canAutoLoadPreview: Bool {
        codex.connectionPhase == .connected
    }

    @MainActor
    private func loadPreviewAfterChatSettlesIfNeeded() async {
        guard canAutoLoadPreview,
              loadedPreview == nil,
              !isAutoLoadingPreview,
              !didAttemptAutoPreviewLoad else {
            return
        }

        do {
            // Give post-connect UI reconciliation a beat before starting image reads.
            try await Task.sleep(nanoseconds: 300_000_000)
            guard canAutoLoadPreview, loadedPreview == nil else { return }
            didAttemptAutoPreviewLoad = true
            isAutoLoadingPreview = true
            defer { isAutoLoadingPreview = false }
            loadedPreview = try await AssistantWorkspaceImagePreviewLoader.load(
                reference: reference,
                currentWorkingDirectory: currentWorkingDirectory,
                codex: codex
            )
        } catch {
            // Inline auto-load stays silent; the fullscreen sheet owns visible errors and retry.
        }
    }
}

private enum WorkspaceLinkedFilePreviewPayload {
    case image(PreviewImagePayload)
    case text(WorkspaceTextFileReadResult)
}

struct WorkspaceLinkedFilePreviewScreen: View {
    let request: WorkspaceFilePreviewRequest
    let onDismiss: () -> Void

    @Environment(CodexService.self) private var codex
    @State private var isLoading = false
    @State private var payload: WorkspaceLinkedFilePreviewPayload?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            switch payload {
            case .image(let imagePayload):
                ZoomableImagePreviewScreen(payload: imagePayload, onDismiss: onDismiss)
            case .text(let file):
                WorkspaceTextFileViewerScreen(file: file, onDismiss: onDismiss, onReload: {
                    Task { await loadPreview(force: true) }
                })
            case nil:
                loadingOrErrorScreen
            }
        }
        .task(id: request.id) {
            await loadPreview()
        }
    }

    private var loadingOrErrorScreen: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer(minLength: 0)

                if isLoading || errorMessage == nil {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading file")
                        .font(AppFont.subheadline(weight: .semibold))
                } else {
                    RemodexIcon.image(systemName: "doc.text")
                        .font(AppFont.system(size: 32, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(fileName)
                        .font(AppFont.subheadline(weight: .semibold))
                        .multilineTextAlignment(.center)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(5)
                    }
                    WorkspacePreviewRetryButton {
                        Task { await loadPreview(force: true) }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)

            previewTopBar
                .padding(.horizontal, 18)
                .padding(.top, 18)
        }
    }

    private var previewTopBar: some View {
        HStack(spacing: 14) {
            WorkspacePreviewChromeButton(systemName: "xmark", accessibilityLabel: "Close file preview") {
                onDismiss()
            }

            WorkspacePreviewTitlePill(title: fileName)

            Spacer(minLength: 0)
        }
    }

    private var fileName: String {
        let basename = (request.path as NSString).lastPathComponent
        return basename.isEmpty ? "File" : basename
    }

    @MainActor
    private func loadPreview(force: Bool = false) async {
        guard !isLoading else { return }
        if payload != nil, !force {
            return
        }

        isLoading = true
        errorMessage = nil
        if force {
            payload = nil
        }
        defer { isLoading = false }

        switch WorkspaceFileLinkResolver.preferredPreviewKind(for: request.path) {
        case .imageFirst:
            await loadImageThenText(force: force)
        case .textFirst:
            await loadTextThenImage(force: force)
        }
    }

    @MainActor
    private func loadImageThenText(force: Bool) async {
        do {
            payload = .image(try await loadImagePayload(force: force))
            return
        } catch {
            let imageError = error
            do {
                payload = .text(try await loadTextPayload())
            } catch {
                errorMessage = combinedPreviewError(primary: imageError, fallback: error)
            }
        }
    }

    @MainActor
    private func loadTextThenImage(force: Bool) async {
        do {
            payload = .text(try await loadTextPayload())
            return
        } catch {
            let textError = error
            do {
                payload = .image(try await loadImagePayload(force: force))
            } catch {
                errorMessage = combinedPreviewError(primary: textError, fallback: error)
            }
        }
    }

    @MainActor
    private func loadImagePayload(force: Bool) async throws -> PreviewImagePayload {
        let imageReference = AssistantMarkdownImageReference(
            path: request.path,
            altText: fileName,
            occurrenceIndex: 0
        )
        return try await AssistantWorkspaceImagePreviewLoader.load(
            reference: imageReference,
            currentWorkingDirectory: request.currentWorkingDirectory,
            codex: codex,
            force: force
        )
    }

    @MainActor
    private func loadTextPayload() async throws -> WorkspaceTextFileReadResult {
        try await codex.readWorkspaceTextFile(
            path: request.path,
            cwd: request.currentWorkingDirectory
        )
    }

    private func combinedPreviewError(primary: Error, fallback: Error) -> String {
        let primaryMessage = primary.localizedDescription
        let fallbackMessage = fallback.localizedDescription
        guard !primaryMessage.isEmpty else { return fallbackMessage }
        guard !fallbackMessage.isEmpty, fallbackMessage != primaryMessage else { return primaryMessage }
        return "\(primaryMessage)\n\(fallbackMessage)"
    }
}

private struct WorkspaceTextFileViewerScreen: View {
    let file: WorkspaceTextFileReadResult
    let onDismiss: () -> Void
    let onReload: () -> Void

    @State private var isShowingCopiedConfirmation = false

    private var content: String {
        file.content ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 12) {
                    fileMetadataHeader
                    Text(content)
                        .font(AppFont.mono(.caption))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle(file.fileName.isEmpty ? "File" : file.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .adaptiveNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        onReload()
                    } label: {
                        RemodexIcon.image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Reload file")

                    Button {
                        UIPasteboard.general.string = content
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingCopiedConfirmation = true
                        }
                    } label: {
                        RemodexIcon.image(systemName: isShowingCopiedConfirmation ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel("Copy file contents")
                }
            }
        }
    }

    private var fileMetadataHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.path)
                .font(AppFont.mono(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Text(metadataSummary)
                .font(AppFont.caption())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var metadataSummary: String {
        var parts = [ByteCountFormatter.string(fromByteCount: Int64(file.byteLength), countStyle: .file)]
        if let lineCount = file.lineCount {
            parts.append("\(lineCount) line\(lineCount == 1 ? "" : "s")")
        }
        parts.append(file.encoding.uppercased())
        return parts.joined(separator: " | ")
    }
}


struct AssistantWorkspaceImagePreviewScreen: View {
    let reference: AssistantMarkdownImageReference
    let currentWorkingDirectory: String?
    let onDismiss: () -> Void

    @Environment(CodexService.self) private var codex
    @State private var isLoading = false
    @State private var payload: PreviewImagePayload?
    @State private var errorMessage: String?

    init(
        reference: AssistantMarkdownImageReference,
        currentWorkingDirectory: String?,
        initialPayload: PreviewImagePayload? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.reference = reference
        self.currentWorkingDirectory = currentWorkingDirectory
        self.onDismiss = onDismiss
        _payload = State(initialValue: initialPayload)
    }

    var body: some View {
        Group {
            if let payload {
                ZoomableImagePreviewScreen(
                    payload: payload,
                    onDismiss: onDismiss
                )
            } else {
                loadingOrErrorScreen
            }
        }
        .task(id: reference.path) {
            await loadPreview()
        }
    }

    private var loadingOrErrorScreen: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(.secondarySystemBackground).opacity(0.7),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 0)

                if isLoading || errorMessage == nil {
                    ProgressView()
                        .controlSize(.large)
                    Text(reference.fileName.isEmpty ? "Loading image" : reference.fileName)
                        .font(AppFont.subheadline(weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                } else {
                    RemodexIcon.image(systemName: "photo")
                        .font(AppFont.system(size: 32, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(reference.fileName.isEmpty ? "Image unavailable" : reference.fileName)
                        .font(AppFont.subheadline(weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                    WorkspacePreviewRetryButton {
                        Task { await loadPreview(force: true) }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)

            topBar
                .padding(.horizontal, 18)
                .padding(.top, 18)
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            WorkspacePreviewChromeButton(systemName: "xmark", accessibilityLabel: "Close image preview") {
                onDismiss()
            }

            if !reference.fileName.isEmpty {
                WorkspacePreviewTitlePill(title: reference.fileName)
            }

            Spacer(minLength: 0)
        }
    }

    @MainActor
    private func loadPreview(force: Bool = false) async {
        guard !isLoading else { return }
        if payload != nil, !force {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            payload = try await AssistantWorkspaceImagePreviewLoader.load(
                reference: reference,
                currentWorkingDirectory: currentWorkingDirectory,
                codex: codex,
                force: force
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum AssistantWorkspaceImagePreviewLoader {
    @MainActor
    static func load(
        reference: AssistantMarkdownImageReference,
        currentWorkingDirectory: String?,
        codex: CodexService,
        force: Bool = false
    ) async throws -> PreviewImagePayload {
        let cachedPreview = await WorkspaceImagePreviewCache.shared.cachedPreview(forPath: reference.path)
        let result = try await codex.readWorkspaceImage(
            path: reference.path,
            cwd: currentWorkingDirectory,
            cachedMetadata: force ? nil : cachedPreview?.metadata
        )
        if result.isNotModified, let cachedPreview {
            return PreviewImagePayload(
                image: cachedPreview.payload.image,
                title: cachedPreview.metadata.fileName.isEmpty ? reference.fileName : cachedPreview.metadata.fileName
            )
        }

        let decodedImage = try await WorkspaceImagePreviewCache.shared.preview(for: result)
        return PreviewImagePayload(
            image: decodedImage.image,
            title: result.fileName.isEmpty ? reference.fileName : result.fileName
        )
    }
}

nonisolated struct CachedWorkspaceImagePreview: Sendable {
    let metadata: WorkspaceImageMetadata
    let payload: CommandImagePreviewPayload
}

nonisolated final class CommandImagePreviewPayload: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }

    var estimatedMemoryCost: Int {
        guard let cgImage = image.cgImage else {
            return 1
        }
        return max(cgImage.bytesPerRow * cgImage.height, 1)
    }
}

actor WorkspaceImagePreviewCache {
    static let shared = WorkspaceImagePreviewCache()

    private let cache = NSCache<NSString, CommandImagePreviewPayload>()
    private var inFlightPreviews: [String: Task<CommandImagePreviewPayload, Error>] = [:]
    private var latestMetadataByPath: [String: WorkspaceImageMetadata] = [:]
    private var latestMetadataAccessOrder: [String] = []

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func cachedPreview(forPath path: String) -> CachedWorkspaceImagePreview? {
        guard let metadata = latestMetadataByPath[path],
              let payload = cache.object(forKey: cacheKey(for: metadata) as NSString) else {
            return nil
        }
        latestMetadataAccessOrder.removeAll { $0 == path }
        latestMetadataAccessOrder.append(path)
        return CachedWorkspaceImagePreview(metadata: metadata, payload: payload)
    }

    func preview(for result: WorkspaceImageReadResult) async throws -> CommandImagePreviewPayload {
        let key = cacheKey(for: result.metadata)
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) {
            return cached
        }
        if let task = inFlightPreviews[key] {
            return try await task.value
        }

        guard let data = result.data else {
            throw CodexServiceError.invalidResponse("Cached image preview was unavailable.")
        }
        let task = Task(priority: .userInitiated) {
            try await CommandImagePreviewDecoder.decode(data)
        }
        inFlightPreviews[key] = task
        defer { inFlightPreviews[key] = nil }

        let decodedImage = try await task.value
        cache.setObject(decodedImage, forKey: nsKey, cost: decodedImage.estimatedMemoryCost)
        rememberMetadata(result.metadata)
        return decodedImage
    }

    private func cacheKey(for metadata: WorkspaceImageMetadata) -> String {
        let mtimeMs = metadata.mtimeMs.map { String($0.bitPattern) } ?? "missing"
        let previewMax = metadata.previewMaxPixelDimension.map(String.init) ?? "original"
        return "\(metadata.path)|\(metadata.byteLength)|\(mtimeMs)|\(previewMax)"
    }

    private func rememberMetadata(_ metadata: WorkspaceImageMetadata) {
        latestMetadataByPath[metadata.path] = metadata
        latestMetadataAccessOrder.removeAll { $0 == metadata.path }
        latestMetadataAccessOrder.append(metadata.path)

        while latestMetadataAccessOrder.count > 64, let evictedPath = latestMetadataAccessOrder.first {
            latestMetadataAccessOrder.removeFirst()
            latestMetadataByPath[evictedPath] = nil
        }
    }
}

nonisolated private enum CommandImagePreviewDecoder {
    private static let maxPreviewPixelDimension = 2_400

    // Downsamples and prepares the preview off the main actor before presenting it.
    static func decode(_ data: Data) async throws -> CommandImagePreviewPayload {
        try await Task.detached(priority: .userInitiated) {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                throw CodexServiceError.invalidResponse("The file is not a readable image.")
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPreviewPixelDimension,
            ] as CFDictionary

            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
                return CommandImagePreviewPayload(image: UIImage(cgImage: cgImage))
            }

            guard let image = UIImage(data: data) else {
                throw CodexServiceError.invalidResponse("The file is not a readable image.")
            }
            return CommandImagePreviewPayload(image: image.preparingForDisplay() ?? image)
        }.value
    }
}
