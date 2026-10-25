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
    @State private var showRecorder = false

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
                                        if let local = state.localRecords[job.id] {
                                            Text(local.serverId != nil ? "En este iPhone · sincronizado" : "En este iPhone")
                                        }
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
                    Button("Grabar", systemImage: "mic.fill") { showRecorder = true }
                    Button("Elegir audio", systemImage: "plus") { showImporter = true }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .movie]) { result in
                do { state.receiveAudio(try result.get()) }
                catch { state.errorMessage = error.localizedDescription }
            }
            .sheet(isPresented: $showRecorder) {
                RecorderView(state: state)
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
    @State private var player = AudioPlaybackController()

    private func formatDuration(_ seconds: Double) -> String {
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%d:%02d", min, sec)
    }

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
                        if let local = state.localRecords[id] {
                            Text(local.serverId != nil ? "En este iPhone · sincronizado" : "En este iPhone").foregroundStyle(.secondary)
                            if job.status == "paused" {
                                Button("Continuar transcripción") { Task { await state.resumeLocal(id); await load() } }
                                    .disabled(state.activeLocalID != nil)
                            }
                            if job.status == "done", local.serverId == nil, state.token != nil {
                                Button("Subir texto al servidor") { Task { await state.syncLocal(id); await load() } }
                                    .disabled(state.isBusy)
                            }
                        }
                    }
                    if let audioPath = state.localRecords[id]?.audioPath,
                       FileManager.default.fileExists(atPath: audioPath) {
                        Section("Audio") {
                            HStack(spacing: 16) {
                                Button {
                                    player.togglePlayPause()
                                } label: {
                                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 32))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(formatDuration(player.currentTime))
                                            .font(.caption.monospacedDigit())
                                        Spacer()
                                        Text(formatDuration(player.duration))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: player.duration > 0 ? player.currentTime / player.duration : 0)
                                }
                            }
                            Button("Liberar almacenamiento de audio", role: .destructive) {
                                player.stop()
                                Task { await state.purgeLocalAudio(id); await load() }
                            }
                            .font(.caption)
                        }
                    }
                    Section("Transcripción") {
                        ForEach(job.segments, id: \.idx) { segment in
                            let isCurrent = player.isPlaying && player.currentTime >= segment.startSeconds && player.currentTime < segment.endSeconds
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "%.1f s", segment.startSeconds))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text(segment.text)
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, isCurrent ? 8 : 0)
                            .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if state.localRecords[id]?.audioPath != nil {
                                    player.seek(to: segment.startSeconds)
                                    if !player.isPlaying { player.play() }
                                }
                            }
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
        .task {
            await load()
            if let path = state.localRecords[id]?.audioPath, FileManager.default.fileExists(atPath: path) {
                player.load(url: URL(fileURLWithPath: path))
            }
        }
        .onDisappear {
            player.stop()
        }
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
                Section("Transcripción local") {
                    Toggle("Sincronizar automáticamente", isOn: $state.autoSyncLocal)
                    Button("Descargar modelo de español") {
                        Task { await state.downloadLocalModel(language: "es") }
                    }
                    .disabled(state.isBusy || !state.localEngineAvailable)
                }
                Button("Cerrar sesión", role: .destructive) { state.logout() }
            }
            .navigationTitle("Ajustes")
        }
    }
}

private struct RecorderView: View {
    @Bindable var state: AppState
    @State private var recorder = AudioRecorder()
    @Environment(\.dismiss) private var dismiss

    private var formattedTime: String {
        let minutes = Int(recorder.elapsedTime) / 60
        let seconds = Int(recorder.elapsedTime) % 60
        let tenths = Int((recorder.elapsedTime.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: recorder.isRecording && !recorder.isPaused ? "waveform" : "mic.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                        .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording && !recorder.isPaused)

                    Text(formattedTime)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .monospacedDigit()

                    if recorder.isRecording {
                        ProgressView(value: Double(recorder.audioLevel))
                            .tint(.red)
                            .padding(.horizontal, 48)
                    }
                }

                if let error = recorder.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center).padding()
                }

                Spacer()

                HStack(spacing: 24) {
                    if recorder.isRecording {
                        Button {
                            if recorder.isPaused { recorder.resume() }
                            else { recorder.pause() }
                        } label: {
                            Label(recorder.isPaused ? "Continuar" : "Pausar",
                                  systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                                .frame(minWidth: 100)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            if let url = recorder.stop() {
                                dismiss()
                                state.importedAudio = url
                            }
                        } label: {
                            Label("Listo", systemImage: "checkmark.circle.fill")
                                .frame(minWidth: 100)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button {
                            Task { await recorder.start() }
                        } label: {
                            Label("Grabar", systemImage: "circle.fill")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Grabar audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
        }
    }
}
