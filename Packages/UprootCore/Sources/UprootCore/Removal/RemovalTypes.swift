import Foundation

/// What happens to files and folders when they are removed.
public enum RemovalMode: String, Sendable, Codable, CaseIterable {
    /// Move to the Trash, from where they can be put back.
    case trash
    /// Delete at once.
    case permanent
}

/// Why something could not be removed.
public enum RemovalFailure: Sendable, Codable, Hashable {
    /// The system refused even with administrator rights; usually the app lacks Full Disk Access.
    case accessDenied
    /// Administrator rights were needed and there was no way to ask for them.
    case adminUnavailable
    /// The system or a tool gave this explanation.
    case message(String)
}

/// What became of one item.
public struct RemovalOutcome: Sendable, Codable, Identifiable, Hashable {
    public enum Status: Sendable, Codable, Hashable {
        case trashed(location: String?)
        case deleted
        case terminated
        case ejected
        case forgotten
        /// It was not there any more when its turn came.
        case alreadyGone
        case failed(RemovalFailure)
        /// The user dismissed the password prompt.
        case cancelled
        /// It was removed and something put it back within moments.
        case reappeared
    }

    public var id: String
    public var name: String
    public var path: String
    public var kind: ItemKind
    public var status: Status
    public var usedAdmin: Bool
    public var size: Int64?

    public var succeeded: Bool {
        switch status {
        case .trashed, .deleted, .terminated, .ejected, .forgotten, .alreadyGone: true
        case .failed, .cancelled, .reappeared: false
        }
    }
}

public struct RemovalReport: Sendable, Codable {
    public var mode: RemovalMode
    public var date: Date
    public var outcomes: [RemovalOutcome]

    public var succeeded: [RemovalOutcome] { outcomes.filter(\.succeeded) }
    public var problems: [RemovalOutcome] { outcomes.filter { !$0.succeeded } }

    /// Bytes taken off the disk, or moved to the Trash.
    public var bytesRemoved: Int64 {
        succeeded.reduce(0) { $0 + ($1.size ?? 0) }
    }
}

public struct RemovalProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case removing
        /// The password prompt is on screen.
        case waitingForAdministrator
        /// Checking that what was removed stays gone.
        case verifying
    }

    public var phase: Phase
    public var completed: Int
    public var total: Int
    public var currentName: String
}

public enum ElevationError: Error, Sendable {
    /// The user dismissed the password prompt.
    case cancelled
    case failed(String)
}

/// Runs a shell script with administrator rights. The app supplies the real thing; tests supply a stand-in.
public protocol PrivilegeElevator: Sendable {
    /// Runs `script` with /bin/sh as root and returns what it printed.
    func runAsRoot(script: String) async throws -> String
}
