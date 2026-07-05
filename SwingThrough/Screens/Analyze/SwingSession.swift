// Main-actor adapter between SwiftUI/SwiftData and the cancellable analysis actor.
// Source video ownership is transferred to durable job storage before Vision starts.
import Foundation
import Observation
import os
import SwiftData
import SwingKit

@Observable
@MainActor
final class SwingSession {
    private static let performanceLog = OSLog(
        subsystem: "com.swingthrough.SwingThrough",
        category: "Analysis"
    )

    enum Phase {
        case idle
        case running(AnalysisProgress, isCancelling: Bool)
        case failed(jobID: UUID?, message: String)
    }

    var phase: Phase = .idle

    @ObservationIgnored private let coordinator: AnalysisJobCoordinator
    @ObservationIgnored private let fileStore: AnalysisFileStore
    @ObservationIgnored private var workflowTask: Task<UUID?, Never>?
    @ObservationIgnored private var workflowID: UUID?
    @ObservationIgnored private weak var activeJob: AnalysisJobRecord?
    @ObservationIgnored private weak var activeContext: ModelContext?
    @ObservationIgnored private var activePersistenceFailure: Error?
    private var activeJobID: UUID?
    private var activeExecutionID: UUID?

    init(coordinator: AnalysisJobCoordinator = AnalysisJobCoordinator(),
         fileStore: AnalysisFileStore = AnalysisFileStore()) {
        self.coordinator = coordinator
        self.fileStore = fileStore
    }

    /// Stage and analyze a new source. The returned record is safe for NavigationPath
    /// because all SwiftData access remains on this actor.
    func run(selection: SwingSetupSelection,
             context: ModelContext, history: [SwingRecord]) async -> SwingRecord? {
        guard workflowTask == nil else {
            if let activeJobID {
                phase = .failed(
                    jobID: activeJobID,
                    message: AnalysisJobCoordinatorError.jobAlreadyActive(activeJobID)
                        .localizedDescription
                )
            }
            return nil
        }

        let jobID = UUID()
        let executionID = UUID()
        let workflowID = UUID()
        self.workflowID = workflowID
        activeJobID = jobID
        activeExecutionID = executionID
        phase = .running(
            AnalysisProgress(
                jobID: jobID, executionID: executionID,
                stage: .queued, fraction: 0, message: "Saving video"
            ),
            isCancelling: false
        )
        let task = Task { @MainActor [weak self] in
            guard let self else { return nil as UUID? }
            return await self.prepareAndExecute(
                jobID: jobID, executionID: executionID,
                selection: selection,
                context: context, history: history
            )
        }
        workflowTask = task
        let completedID = await task.value
        if self.workflowID == workflowID {
            workflowTask = nil
            self.workflowID = nil
        }
        return completedID.flatMap { fetchSwing(id: $0, context: context) }
    }

    func retry(jobID: UUID, context: ModelContext,
               history: [SwingRecord]) async -> SwingRecord? {
        guard workflowTask == nil else { return nil }
        guard let job = fetchJob(id: jobID, context: context) else {
            phase = .failed(jobID: nil, message: "That saved analysis could not be found.")
            return nil
        }

        let workflowID = UUID()
        let executionID = UUID()
        self.workflowID = workflowID
        activeJobID = jobID
        activeExecutionID = executionID
        phase = .running(
            AnalysisProgress(
                jobID: jobID, executionID: executionID,
                stage: .queued, fraction: 0, message: "Preparing retry"
            ),
            isCancelling: false
        )
        let task = Task { @MainActor [weak self] in
            guard let self else { return nil as UUID? }
            return await self.execute(
                job: job, executionID: executionID,
                context: context, history: history
            )
        }
        workflowTask = task
        let completedID = await task.value
        if self.workflowID == workflowID {
            workflowTask = nil
            self.workflowID = nil
        }
        return completedID.flatMap { fetchSwing(id: $0, context: context) }
    }

    func cancel() {
        guard let jobID = activeJobID, let executionID = activeExecutionID else { return }
        if case .running(let progress, _) = phase {
            var cancelling = progress
            cancelling.message = "Canceling analysis"
            phase = .running(cancelling, isCancelling: true)
        }
        workflowTask?.cancel()
        Task { await coordinator.cancel(jobID: jobID, executionID: executionID) }
    }

    func dismissFailure() {
        guard workflowTask == nil else { return }
        phase = .idle
    }

    func discard(jobID: UUID, context: ModelContext) async {
        guard jobID != activeJobID, let job = fetchJob(id: jobID, context: context) else { return }
        do {
            try await fileStore.discard(jobID: jobID)
            context.delete(job)
            try context.save()
            if case .failed(let failedID, _) = phase, failedID == jobID {
                phase = .idle
            }
        } catch {
            phase = .failed(
                jobID: jobID,
                message: "The saved video could not be discarded. Try again."
            )
        }
    }

    // MARK: - Workflow

    private func prepareAndExecute(jobID: UUID, executionID: UUID,
                                   selection: SwingSetupSelection,
                                   context: ModelContext,
                                   history: [SwingRecord]) async -> UUID? {
        var stagedJob: AnalysisJobRecord?
        do {
            let fileName = try await fileStore.stageVideo(
                at: selection.videoURL,
                jobID: jobID,
                view: selection.view,
                club: selection.club,
                handednessPreference: selection.handedness,
                trimStart: selection.trimStart,
                trimEnd: selection.trimEnd,
                sourceMetadata: selection.metadata
            )
            let job = AnalysisJobRecord(
                id: jobID,
                stage: .queued,
                message: "Waiting",
                videoFileName: fileName,
                originalFileName: selection.videoURL.lastPathComponent,
                view: selection.view,
                club: selection.club,
                handednessPreference: selection.handedness,
                trimStart: selection.trimStart,
                trimEnd: selection.trimEnd,
                sourceMetadata: selection.metadata
            )
            stagedJob = job
            context.insert(job)
            do {
                try context.save()
            } catch {
                context.rollback()
                // The manifest intentionally remains so launch reconciliation can
                // recover a process interruption between file and database writes.
                throw error
            }
            try Task.checkCancellation()
            return await execute(
                job: job, executionID: executionID,
                context: context, history: history
            )
        } catch is CancellationError {
            if stagedJob != nil {
                markCancelled(jobID: jobID, context: context)
            }
            clearActive(jobID: jobID, executionID: executionID)
            phase = .idle
            return nil
        } catch {
            try? AnalysisJobRecovery.reconcile(context: context)
            if let recovered = fetchJob(id: jobID, context: context) {
                markFailed(
                    job: recovered,
                    category: AnalysisDiagnostics.safeFailureCategory(error),
                    message: "The video was retained, but its analysis state could not be saved.",
                    context: context
                )
            }
            clearActive(jobID: jobID, executionID: executionID)
            if fetchJob(id: jobID, context: context) == nil {
                phase = .failed(
                    jobID: nil,
                    message: "The video could not be saved for analysis. Check free storage and try again."
                )
            }
            return nil
        }
    }

    private func execute(job: AnalysisJobRecord, executionID: UUID,
                         context: ModelContext,
                         history: [SwingRecord]) async -> UUID? {
        guard await fileStore.videoExists(named: job.videoFileName) else {
            markFailed(job: job, category: "missingInput",
                       message: "The retained video is unavailable.", context: context)
            clearActive(jobID: job.id, executionID: executionID)
            return nil
        }

        activeJob = job
        activeContext = context
        activePersistenceFailure = nil
        activeJobID = job.id
        activeExecutionID = executionID
        DiagnosticsStore.shared.begin(jobID: job.id)

        job.attemptCount += 1
        job.lastErrorCategory = nil
        transition(
            job: job,
            to: .preparing,
            fraction: 0,
            message: "Preparing video",
            context: context,
            force: true
        )
        if let persistenceError = activePersistenceFailure {
            markFailed(
                job: job,
                category: AnalysisDiagnostics.safeFailureCategory(persistenceError),
                message: "Analysis state could not be saved. Your video is retained for retry.",
                context: context
            )
            clearActive(jobID: job.id, executionID: executionID)
            return nil
        }

        let request: AnalysisJobRequest
        do {
            request = AnalysisJobRequest(
                jobID: job.id,
                executionID: executionID,
                videoURL: try await fileStore.videoURL(named: job.videoFileName),
                view: job.view,
                sourceWindow: job.sourceWindow,
                handednessOverride: job.handednessPreference.resolved
            )
        } catch {
            markFailed(job: job, category: "missingInput",
                       message: "The retained video is unavailable.", context: context)
            clearActive(jobID: job.id, executionID: executionID)
            return nil
        }

        var latestDiagnostics: AnalysisDiagnostics?
        var persistenceSignpost: OSSignpostID?
        var reportFileName: String?

        do {
            let result = try await coordinator.run(
                request: request,
                progress: { [weak self] fraction in
                    Task { @MainActor in
                        self?.receiveProgress(
                            jobID: request.jobID,
                            executionID: request.executionID,
                            fraction: fraction
                        )
                    }
                },
                diagnostics: { [weak self] snapshot in
                    Task { @MainActor in
                        self?.receiveDiagnostics(
                            snapshot,
                            executionID: request.executionID
                        )
                    }
                }
            )
            try Task.checkCancellation()
            guard isActive(jobID: job.id, executionID: executionID) else {
                throw CancellationError()
            }

            latestDiagnostics = result.diagnostics
            var finished = result.report
            finished.id = job.id
            finished.club = job.club
            finished.videoFileName = job.videoFileName
            if let handedness = job.handednessPreference.resolved {
                finished.handedness = handedness
            }
            transition(
                job: job, to: .resultsReady, fraction: 1,
                message: "Measurements ready", context: context
            )

            transition(
                job: job, to: .resultsReady, fraction: 1,
                message: "Preparing local guidance", context: context
            )
            try Task.checkCancellation()
            let recentTitles = history.prefix(3)
                .compactMap { SwingStore.loadReport(named: $0.reportFileName)?.coaching }
                .flatMap { $0.goals.map(\.title) }
            let coachingStart = Date()
            let coaching = try await CoachingService(apiKeyProvider: AppAPIKeyProvider())
                .localCoach(
                    finished,
                    context: CoachingContext(club: job.club, recentGoalTitles: recentTitles)
                )
            try Task.checkCancellation()
            var diagnostics = result.diagnostics
            diagnostics.recordStage(
                "localCoaching",
                duration: Date().timeIntervalSince(coachingStart)
            )
            latestDiagnostics = diagnostics
            DiagnosticsStore.shared.update(diagnostics)
            finished.coaching = coaching

            transition(
                job: job, to: .saving, fraction: 1,
                message: "Saving swing", context: context
            )
            try Task.checkCancellation()
            let signpost = OSSignpostID(log: Self.performanceLog)
            persistenceSignpost = signpost
            os_signpost(.begin, log: Self.performanceLog, name: "Persistence",
                        signpostID: signpost, "job=%{public}s", job.id.uuidString)
            let started = Date()

            let savedReportName = try await fileStore.saveReport(finished)
            reportFileName = savedReportName
            let record = SwingRecord(
                id: finished.id,
                date: finished.date,
                club: finished.club,
                score: finished.score.isAvailable ? finished.score.total : -1,
                viewRaw: finished.view.rawValue,
                reportFileName: savedReportName,
                videoFileName: job.videoFileName
            )
            job.completedSwingID = record.id
            context.insert(record)
            context.delete(job)
            do {
                try context.save()
            } catch {
                context.rollback()
                try? await fileStore.removeReport(named: savedReportName)
                reportFileName = nil
                throw error
            }
            try? await fileStore.markCompleted(jobID: job.id)

            diagnostics.recordStage("persistence", duration: Date().timeIntervalSince(started))
            diagnostics.finish()
            DiagnosticsStore.shared.update(diagnostics)
            os_signpost(.end, log: Self.performanceLog, name: "Persistence",
                        signpostID: signpost,
                        "job=%{public}s result=success", job.id.uuidString)
            persistenceSignpost = nil
            clearActive(jobID: job.id, executionID: executionID)
            phase = .idle
            return record.id
        } catch is CancellationError {
            if let persistenceSignpost {
                endPersistence(signpost: persistenceSignpost, jobID: job.id, result: "cancelled")
            }
            if let reportFileName { try? await fileStore.removeReport(named: reportFileName) }
            if let persistenceError = activePersistenceFailure {
                markFailed(
                    jobID: job.id,
                    category: AnalysisDiagnostics.safeFailureCategory(persistenceError),
                    message: "Analysis state could not be saved. Your video is retained for retry.",
                    context: context
                )
            } else {
                markCancelled(jobID: job.id, context: context)
            }
            clearActive(jobID: job.id, executionID: executionID)
            phase = .idle
            return nil
        } catch {
            if let persistenceSignpost {
                endPersistence(signpost: persistenceSignpost, jobID: job.id, result: "failure")
            }
            if let reportFileName { try? await fileStore.removeReport(named: reportFileName) }
            if let failure = error as? SwingAnalysisFailure {
                latestDiagnostics = failure.diagnostics
                DiagnosticsStore.shared.update(failure.diagnostics)
                if failure.diagnostics.failureCategory == "cancelled" {
                    markCancelled(jobID: job.id, context: context)
                    clearActive(jobID: job.id, executionID: executionID)
                    phase = .idle
                    return nil
                }
            }
            let category = latestDiagnostics?.failureCategory
                ?? AnalysisDiagnostics.safeFailureCategory(error)
            markFailed(
                jobID: job.id,
                category: category,
                message: userMessage(for: error),
                context: context
            )
            clearActive(jobID: job.id, executionID: executionID)
            return nil
        }
    }

    // MARK: - State application

    private func receiveProgress(jobID: UUID, executionID: UUID, fraction: Double) {
        guard isActive(jobID: jobID, executionID: executionID),
              let job = activeJob,
              let context = activeContext,
              !job.stage.isTerminal
        else { return }

        let (stage, label): (AnalysisStage, String) = switch fraction {
        case ..<0.25: (.tracking2D, "Reading motion")
        case ..<0.75: (.tracking3D, "Tracking your body in 3D")
        default: (.measuring, "Measuring plane and sequence")
        }
        transition(
            job: job, to: stage, fraction: fraction,
            message: label, context: context
        )
    }

    private func receiveDiagnostics(_ diagnostics: AnalysisDiagnostics, executionID: UUID) {
        guard isActive(jobID: diagnostics.jobID, executionID: executionID),
              let job = activeJob,
              let context = activeContext
        else { return }

        DiagnosticsStore.shared.update(diagnostics)
        job.sourceDuration = diagnostics.sourceDuration > 0 ? diagnostics.sourceDuration : nil
        job.sourceFPS = diagnostics.sourceFPS > 0 ? diagnostics.sourceFPS : nil
        job.sourceWidth = diagnostics.sourceWidth > 0 ? diagnostics.sourceWidth : nil
        job.sourceHeight = diagnostics.sourceHeight > 0 ? diagnostics.sourceHeight : nil

        let stage: AnalysisStage
        let label: String
        if diagnostics.stageDurations["metrics"] != nil {
            stage = .resultsReady; label = "Measurements ready"
        } else if diagnostics.stageDurations["detailedPose"] != nil {
            stage = .measuring; label = "Measuring plane and sequence"
        } else if diagnostics.stageDurations["detectSwing"] != nil {
            stage = .tracking3D; label = "Tracking your body in 3D"
        } else if diagnostics.stageDurations["coarsePose"] != nil {
            stage = .detectingSwing; label = "Finding the swing"
        } else if diagnostics.stageDurations["preflight"] != nil {
            stage = .tracking2D; label = "Reading motion"
        } else {
            stage = .preparing; label = "Preparing video"
        }
        transition(
            job: job, to: stage, fraction: job.progress,
            message: label, context: context
        )
    }

    private func transition(job: AnalysisJobRecord, to stage: AnalysisStage,
                            fraction: Double, message: String,
                            context: ModelContext, force: Bool = false) {
        guard force || (!job.stage.isTerminal && stage.rank >= job.stage.rank) else { return }
        let stageChanged = stage != job.stage
        job.stage = stage
        job.progress = min(1, max(job.progress, fraction))
        job.message = message
        if stageChanged || force {
            job.updatedAt = Date()
            do {
                try context.save()
            } catch {
                activePersistenceFailure = error
                workflowTask?.cancel()
                if let jobID = activeJobID, let executionID = activeExecutionID {
                    Task { await coordinator.cancel(jobID: jobID, executionID: executionID) }
                }
            }
        }
        if isActive(jobID: job.id, executionID: activeExecutionID) {
            phase = .running(
                AnalysisProgress(
                    jobID: job.id,
                    executionID: activeExecutionID ?? UUID(),
                    stage: stage,
                    fraction: job.progress,
                    message: message
                ),
                isCancelling: false
            )
        }
    }

    private func markCancelled(jobID: UUID, context: ModelContext) {
        guard let job = fetchJob(id: jobID, context: context) else { return }
        job.stage = .cancelled
        job.message = "Canceled — ready to retry"
        job.lastErrorCategory = "cancelled"
        job.updatedAt = Date()
        try? context.save()
    }

    private func markFailed(job: AnalysisJobRecord, category: String,
                            message: String, context: ModelContext) {
        markFailed(jobID: job.id, category: category, message: message, context: context)
    }

    private func markFailed(jobID: UUID, category: String,
                            message: String, context: ModelContext) {
        guard let job = fetchJob(id: jobID, context: context) else {
            phase = .failed(jobID: nil, message: message)
            return
        }
        job.stage = .failed
        job.message = message
        job.lastErrorCategory = category
        job.updatedAt = Date()
        do {
            try context.save()
        } catch {
            context.rollback()
        }
        phase = .failed(jobID: jobID, message: message)
    }

    private func fetchJob(id: UUID, context: ModelContext) -> AnalysisJobRecord? {
        let jobs = try? context.fetch(FetchDescriptor<AnalysisJobRecord>())
        return jobs?.first { $0.id == id }
    }

    private func fetchSwing(id: UUID, context: ModelContext) -> SwingRecord? {
        let records = try? context.fetch(FetchDescriptor<SwingRecord>())
        return records?.first { $0.id == id }
    }

    private func isActive(jobID: UUID, executionID: UUID?) -> Bool {
        activeJobID == jobID && activeExecutionID == executionID
    }

    private func clearActive(jobID: UUID, executionID: UUID) {
        guard isActive(jobID: jobID, executionID: executionID) else { return }
        activeJob = nil
        activeContext = nil
        activePersistenceFailure = nil
        activeJobID = nil
        activeExecutionID = nil
    }

    private func endPersistence(signpost: OSSignpostID, jobID: UUID, result: StaticString) {
        os_signpost(.end, log: Self.performanceLog, name: "Persistence",
                    signpostID: signpost, "job=%{public}s result=%{public}s",
                    jobID.uuidString, String(describing: result))
    }

    private func userMessage(for error: Error) -> String {
        if let failure = error as? SwingAnalysisFailure,
           let description = failure.errorDescription, !description.isEmpty {
            return description
        }
        if error is AnalysisJobCoordinatorError { return error.localizedDescription }
        return "Analysis stopped unexpectedly. Your video is saved and ready to retry."
    }
}
