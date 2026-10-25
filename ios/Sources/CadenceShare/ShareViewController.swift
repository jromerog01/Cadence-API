import CadenceKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Observation

@objc(ShareViewController) final class ShareViewController: UIViewController {
    private let state = ShareState()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareContent(state: state) { [weak self] in
            self?.save()
        })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func save() {
        state.busy = true
        guard let provider = extensionContext?.inputItems
            .compactMap({ $0 as? NSExtensionItem })
            .flatMap({ $0.attachments ?? [] })
            .first(where: { $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }) else {
            state.error = "No se encontró un archivo de audio o video."
            state.busy = false
            return
        }
        let suggestedName = provider.suggestedName
        let model = state.model
        let language = state.language
        let type = provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier)
            ? UTType.audio.identifier : UTType.movie.identifier
        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, error in
            let message: String?
            if let url,
               let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.jesusrg.cadence") {
                do {
                    var filename = suggestedName ?? url.lastPathComponent
                    if URL(fileURLWithPath: filename).pathExtension.isEmpty, !url.pathExtension.isEmpty {
                        filename += "." + url.pathExtension
                    }
                    let inbox = Inbox(root: group.appending(path: "Inbox"))
                    _ = try inbox.enqueue(source: url, filename: filename, model: model,
                                          language: language.isEmpty ? nil : language)
                    message = nil
                } catch { message = error.localizedDescription }
            } else {
                message = error?.localizedDescription ?? "No se pudo abrir el contenedor compartido."
            }
            Task { @MainActor in
                self?.state.error = message
                self?.state.busy = false
                if message == nil { self?.extensionContext?.completeRequest(returningItems: nil) }
            }
        }
    }
}

@MainActor @Observable private final class ShareState {
    var model = "small"
    var language = ""
    var busy = false
    var error: String?
}

private struct ShareContent: View {
    @Bindable var state: ShareState
    let submit: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("Modelo", selection: $state.model) {
                    ForEach(["tiny", "base", "small", "medium", "large-v3-turbo", "large-v3"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                TextField("Idioma (vacío = automático)", text: $state.language)
                Text("El audio se enviará al abrir Cadence.").font(.footnote).foregroundStyle(.secondary)
                if let error = state.error { Text(error).foregroundStyle(.red) }
                Button("Transcribir en servidor", action: submit).disabled(state.busy)
            }
            .navigationTitle("Cadence")
        }
    }
}
