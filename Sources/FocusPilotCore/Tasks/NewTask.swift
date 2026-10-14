import Foundation

/// What the owner typed in the capture sheet, ready to save.
///
/// Text fields are trimmed, and empty optional fields become nil, so "no
/// project" is never stored as a blank project.
public struct NewTask: Equatable, Sendable {
    public enum Invalid: Error, Equatable {
        case missingTitle
    }

    public var title: String
    public var projectName: String?
    public var deadline: Deadline?
    public var nextAction: String?

    public init(title: String, projectName: String? = nil, deadline: Deadline? = nil, nextAction: String? = nil) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectName = Self.nonBlank(projectName)
        self.deadline = deadline
        self.nextAction = Self.nonBlank(nextAction)
    }

    public var isValid: Bool { !title.isEmpty }

    private static func nonBlank(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
