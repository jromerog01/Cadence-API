import CadenceKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import QuickLook

struct ContentView: View {
    @State private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if state.user == nil && !state.localOnly {
                LoginView(state: state)
            } else {
                TabView {
                    LibraryView(state: state)
                        .tabItem { Label("Biblioteca", systemImage: "text.book.closed") }
                    SettingsView(state: state)
                        .tabItem { Label("Ajustes", systemImage: "gearshape") }
                }
            }
        }
        .task { await state.restore(); state.checkInbox() }
        .onOpenURL { state.receiveAudio($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, state.token != nil {
                state.checkInbox()
                Task { await state.refresh() }
            }
            else { state.stopWatching() }
        }
        .alert("Cadence", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("Aceptar") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

private struct LoginView: View {
    @Bindable var state: AppState
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Servidor") {
                    TextField("https://cadence.ejemplo.com", text: $state.server)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                Section("Cuenta") {
                    TextField("Correo", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Contraseña", text: $password)
                }
                Button("Iniciar sesión") {
                    Task { await state.login(email: email, password: password) }
                }
                .disabled(state.isBusy || email.isEmpty || password.isEmpty || state.server.isEmpty)
                if state.localEngineAvailable {
                    Button("Usar solo en este iPhone") { Task { await state.useLocalMode() } }
                }
            }
            .navigationTitle("Cadence")
            .overlay { if state.isBusy { ProgressView() } }
        }
    }
}

private struct LibraryView: View {
    @Bindable var state: AppState
    @State private var search = ""
    @State private var showImporter = false

    private var filtered: [Job] {
        search.isEmpty ? state.jobs : state.jobs.filter {
            $0.originalFilename.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.jobs.isEmpty {
                    ContentUnavailableView("Sin transcripciones", systemImage: "waveform", description: Text("Tus trabajos aparecerán aquí."))
                } else {
                    List {
                        ForEach(filtered) { job in
                            NavigationLink(value: job.id) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(job.originalFilename).font(.headline)
                                    HStack {
                                        Text(job.status == "done" ? "Lista" : job.status == "error" ? "Error" : "En proceso")
                                        Text(job.createdAt, style: .date)
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                    if job.status == "processing" || job.status == "queued" {
                                        ProgressView(value: state.liveProgress[job.id] ?? job.progress)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { filtered[$0].id }
                            for id in ids { Task { await state.delete(id) } }
                        }
                    }
                }
            }
            .navigationTitle("Biblioteca")
            .navigationDestination(for: String.self) { JobDetailView(state: state, id: $0) }
            .searchable(text: $search)
            .refreshable { await state.refresh() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Actualizar", systemImage: "arrow.clockwise") { Task { await state.refresh() } }
                    Button("Elegir audio", systemImage: "plus") { showImporter = true }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .movie]) { result in
                do { state.receiveAudio(try result.get()) }
                catch { state.errorMessage = error.localizedDescription }
            }
            .sheet(isPresented: Binding(
                get: { state.importedAudio != nil },
                set: { if !$0 { state.importedAudio = nil } }
            )) {
                if let file = state.importedAudio { NewJobView(state: state, file: file) }
            }
        }
    }
}

private struct NewJobView: View {
    @Bindable var state: AppState
    let file: URL
    @State private var model = "small"
    @State private var language = ""
    @State private var engine = "server"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio") { Text(state.pendingInboxItem?.filename ?? file.lastPathComponent) }
                Section("Transcripción") {
                    if state.localEngineAvailable {
                        Picker("Motor", selection: $engine) {
                            if !state.localOnly { Text("Servidor").tag("server") }
                            Text("En este iPhone").tag("device")
                        }
                    }
                    if engine == "server" { Picker("Modelo", selection: $model) {
                        ForEach(state.models, id: \.name) { item in
                            Text(item.name).tag(item.name)
                        }
                    } }
                    TextField(engine == "device" ? "Idioma obligatorio (es, en…)" : "Idioma (vacío = automático)", text: $language)
                        .textInputAutocapitalization(.never)
                    if engine == "device" {
                        Text("El audio permanece en este iPhone. La primera vez debes descargar el modelo del idioma.").font(.footnote)
                        Button("Descargar modelo del idioma") { Task { await state.downloadLocalModel(language: language) } }
                            .disabled(language.isEmpty || state.isBusy)
                        if state.isBusy { ProgressView("Descargando modelo…") }
                    }
                }
                if let progress = state.uploadProgress {
                    Section("Subiendo") { ProgressView(value: progress) }
                }
                Button(engine == "device" ? "Transcribir en este iPhone" : "Transcribir en servidor") {
                    Task {
                        if engine == "device" {
                            let filename = state.pendingInboxItem?.filename ?? file.lastPathComponent
                            state.importedAudio = nil
                            dismiss()
                            await state.startLocal(file: file, filename: filename, language: language)
                            return
                        }
                        await state.upload(file: file, filename: state.pendingInboxItem?.filename, model: model, language: language)
                        if state.uploadProgress == nil && state.errorMessage == nil {
                            state.importedAudio = nil
                            dismiss()
                        }
                    }
                }
                .disabled(state.uploadProgress != nil || state.isBusy || (engine == "device" && (language.isEmpty || state.activeLocalID != nil)))
            }
            .navigationTitle("Nuevo trabajo")
            .toolbar { Button("Cancelar") { state.importedAudio = nil; dismiss() } }
            .task {
                if state.localOnly { engine = "device"; language = "es" }
                else { await state.loadModels() }
                if let pending = state.pendingInboxItem {
                    model = pending.model
                    language = pending.language ?? ""
                }
                if !state.models.contains(where: { $0.name == model }) { model = state.models.first?.name ?? model }
            }
        }
    }
}

private struct JobDetailView: View {
    @Bindable var state: AppState
    let id: String
    @State private var job: Job?
    @State private var exportedFile: URL?
    @State private var previewFile: URL?

    var body: some View {
        Group {
            if let job {
                List {
                    Section {
                        LabeledContent("Estado", value: job.status)
                        LabeledContent("Modelo", value: job.model)
                        if let language = job.detectedLanguage ?? job.language {
                            LabeledContent("Idioma", value: language)
                        }
                        if job.status != "done" { ProgressView(value: state.liveProgress[job.id] ?? job.progress) }
                        if let error = job.errorMessage { Text(error).foregroundStyle(.red) }
                        if state.localRecords[id] != nil {
                            Text("En este iPhone").foregroundStyle(.secondary)
                            if job.status == "paused" {
                                Button("Continuar transcripción") { Task { await state.resumeLocal(id); await load() } }
                                    .disabled(state.activeLocalID != nil)
                            }
                        }
                    }
                    Section("Transcripción") {
                        ForEach(job.segments, id: \.idx) { segment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "%.1f s", segment.startSeconds))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text(segment.text).textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } else { ProgressView() }
        }
        .navigationTitle(job?.originalFilename ?? "Trabajo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let job, job.status == "done" {
                Menu("Compartir", systemImage: "square.and.arrow.up") {
                    ForEach(["txt", "md", "json", "srt", "vtt", "pdf"], id: \.self) { format in
                        Button(format.uppercased()) { Task { await export(format) } }
                    }
                    Button("Copiar texto") {
                        UIPasteboard.general.string = job.segments.map(\.text).joined(separator: "\n\n")
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { exportedFile != nil },
            set: { if !$0 { exportedFile = nil } }
        )) {
            if let file = exportedFile {
                NavigationStack {
                    VStack(spacing: 20) {
                        Text(file.lastPathComponent)
                        ShareLink(item: file) { Label("Compartir archivo", systemImage: "square.and.arrow.up") }
                        if file.pathExtension == "pdf" {
                            Button("Vista previa") { previewFile = file }
                        }
                    }
                    .padding()
                    .navigationTitle("Exportación")
                    .toolbar { Button("Cerrar") { exportedFile = nil } }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { previewFile != nil },
            set: { if !$0 { previewFile = nil } }
        )) {
            if let file = previewFile { PDFPreview(file: file) }
        }
        .task { await load() }
        .onChange(of: state.localRecords[id]?.job) { _, value in if let value { job = value } }
        .refreshable { await load() }
    }

    private func load() async {
        do { job = try await state.job(id) }
        catch { state.errorMessage = error.localizedDescription }
    }

    private func export(_ format: String) async {
        do { exportedFile = try await state.export(jobID: id, format: format) }
        catch { state.errorMessage = error.localizedDescription }
    }
}

private struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("Cuenta") {
                    if let user = state.user {
                        LabeledContent("Usuario", value: user.displayName)
                        LabeledContent("Correo", value: user.email)
                    }
                    LabeledContent("Servidor", value: state.server)
                }
                Button("Cerrar sesión", role: .destructive) { state.logout() }
            }
            .navigationTitle("Ajustes")
        }
    }
}
