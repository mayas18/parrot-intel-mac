import Foundation

/// Intel backend. whisper.cpp runs locally; neither audio nor transcript is uploaded.
/// Transcript output stays in memory and the temporary WAV is removed after decoding.
actor WhisperCppTranscriber: Transcriber {
    nonisolated let modelID: String
    private let model: TranscriptionModel
    private let tuning: WhisperTuning
    private var retired = false

    init(model: TranscriptionModel, tuning: WhisperTuning) {
        self.modelID = model.id
        self.model = model
        self.tuning = tuning
    }

    static func variant(for model: TranscriptionModel) -> String {
        String(model.id.dropFirst("whisper-".count))
    }

    static func modelURL(for model: TranscriptionModel) -> URL {
        if let path = ProcessInfo.processInfo.environment["PARROT_GGML_MODEL"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return Paths.appSupport.appendingPathComponent("models/whisper-cpp/ggml-\(variant(for: model)).bin")
    }

    static func executableURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["PARROT_WHISPER_CLI"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/whisper-cli")
    }

    static func isCached(_ model: TranscriptionModel) -> Bool {
        guard let values = try? modelURL(for: model).resourceValues(forKeys: [.fileSizeKey]) else { return false }
        return (values.fileSize ?? 0) > 1_000_000
    }

    func warmUp(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard !retired else { return }
        guard FileManager.default.isExecutableFile(atPath: Self.executableURL().path) else {
            throw failure("Intel transcription needs the bundled whisper-cli. Rebuild Parrot.app or set PARROT_WHISPER_CLI to its executable.")
        }
        if Self.isCached(model) { return }
        if ProcessInfo.processInfo.environment["PARROT_GGML_MODEL"] != nil {
            throw failure("PARROT_GGML_MODEL must point to an existing GGML model.")
        }
        let destination = Self.modelURL(for: model)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(Self.variant(for: model)).bin")!
        Log.info("downloading \(model.id) for Intel...")
        progress?(0)
        let (temporary, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw failure("Could not download the Intel model: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        let handle = try FileHandle(forReadingFrom: temporary)
        let magic = try handle.read(upToCount: 4)
        try handle.close()
        guard magic == Data([0x6c, 0x6d, 0x67, 0x67]) else { throw failure("Downloaded file is not a GGML Whisper model.") }
        try Task.checkCancellation()
        // Another transcriber may have completed the same download while this actor suspended.
        if !Self.isCached(model) {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        progress?(1)
        Log.info("✓ \(model.id) ready (whisper.cpp, Intel CPU)")
    }

    func unload() { retired = true }

    func transcribe(_ audio: [Float], context: TranscriptionContext) async throws -> Transcript {
        try await warmUp()
        guard !retired else { throw failure("This transcription model has been unloaded.") }
        try Task.checkCancellation()
        let started = Date()
        let input = tuning.prepare(audio)
        guard !input.isEmpty else { return Transcript(text: "", timings: .zero) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("parrot-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = folder.appendingPathComponent("audio.wav")
        try Self.wavData(input).write(to: wav, options: .atomic)
        let preprocessing = Date().timeIntervalSince(started)
        let language = DictionaryContext.knownLanguage(of: model) ?? context.language
        let prompt = context.prompt ?? language.flatMap { context.examples[$0] }
        var arguments = ["-m", Self.modelURL(for: model).path, "-f", wav.path, "-nt", "-np", "-ng", "-l", language ?? "auto"]
        if let prompt, !prompt.isEmpty { arguments += ["--prompt", prompt] }
        let process = Process()
        process.executableURL = Self.executableURL()
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(120, Double(input.count) / 16_000 * 20), execute: deadline)
        defer { deadline.cancel() }
        let data = await withTaskCancellationHandler {
            await Task.detached {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return data
            }.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw failure("whisper.cpp failed (status \(process.terminationStatus)).")
        }
        let total = Date().timeIntervalSince(started)
        var timings = TranscriberTimings.zero
        timings.audioSeconds = Double(input.count) / 16_000
        timings.preprocessing = preprocessing
        // The CLI loads its model for each invocation; report the complete backend
        // time together rather than inventing separate Core ML stage measurements.
        timings.backend = total - preprocessing
        timings.total = total
        timings.language = language
        timings.windows = Int(ceil(timings.audioSeconds / 30))
        return Transcript(text: WhisperKitTranscriber.sanitize(String(decoding: data, as: UTF8.self)), timings: timings)
    }

    /// PCM16 WAV at the Transcriber protocol's 16 kHz mono sample rate.
    static func wavData(_ audio: [Float]) -> Data {
        var result = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { result.append(contentsOf: $0) }
        }
        let bytes = UInt32(audio.count * 2)
        result.append(contentsOf: "RIFF".utf8); append(bytes + 36)
        result.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(16_000))
        append(UInt32(32_000)); append(UInt16(2)); append(UInt16(16))
        result.append(contentsOf: "data".utf8); append(bytes)
        for sample in audio {
            let value = sample.isFinite ? max(-1, min(1, sample)) : 0
            append(Int16((value * Float(Int16.max)).rounded()))
        }
        return result
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Parrot.WhisperCpp", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
