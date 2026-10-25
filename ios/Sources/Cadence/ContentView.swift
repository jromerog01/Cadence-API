import CadenceKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if state.user == nil {
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
        .task { await state.restore() }
        .onOpenURL { state.receiveAudio($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, state.token != nil { Task { await state.refresh() } }
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
                            for index in offsets { Task { await state.delete(filtered[index].id) } }
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio") { Text(file.lastPathComponent) }
                Section("Transcripción") {
                    Picker("Modelo", selection: $model) {
                        ForEach(state.models, id: \.name) { item in
                            Text(item.name).tag(item.name)
                        }
                    }
                    TextField("Idioma (vacío = automático)", text: $language)
                        .textInputAutocapitalization(.never)
                }
                if let progress = state.uploadProgress {
                    Section("Subiendo") { ProgressView(value: progress) }
                }
                Button("Transcribir en servidor") {
                    Task {
                        await state.upload(file: file, model: model, language: language)
                        if state.uploadProgress == nil && state.errorMessage == nil {
                            state.importedAudio = nil
                            dismiss()
                        }
                    }
                }
                .disabled(state.uploadProgress != nil)
            }
            .navigationTitle("Nuevo trabajo")
            .toolbar { Button("Cancelar") { state.importedAudio = nil; dismiss() } }
            .task {
                await state.loadModels()
                if !state.models.contains(where: { $0.name == model }) { model = state.models.first?.name ?? model }
            }
        }
    }
}

private struct JobDetailView: View {
    @Bindable var state: AppState
    let id: String
    @State private var job: Job?

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
                    }
                    Section("Transcripción") {
                        ForEach(job.segments, id: \.idx) { segment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(segment.startSeconds.formatted(.number.precision(.fractionLength(1))) + " s")
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
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { job = try await state.job(id) }
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
