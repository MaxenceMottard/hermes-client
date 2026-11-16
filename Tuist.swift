import ProjectDescription

/// Tuist server project handle (`account/project`), needed by `tuist share`.
/// Read from `TUIST_SERVER_FULL_HANDLE` so that local development and CI keep
/// working without a Tuist login; only the preview workflow sets it.
let fullHandle: String? = if case let .string(handle) = Environment.serverFullHandle {
    handle
} else {
    nil
}

let tuist = Tuist(
    fullHandle: fullHandle,
    project: .tuist()
)
