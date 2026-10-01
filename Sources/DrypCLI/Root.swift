import ArgumentParser
import DrypCore
import Foundation

public struct Dryp: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "dryp",
        abstract: "Keep your Mac awake: caf (screen and everything on) and nosleep (lid can close).",
        version: DrypVersion.current,
        subcommands: [Caf.self, Nosleep.self, Off.self, Status.self, AppCommand.self, Update.self, Uninstall.self],
        // -h means hours, so help is long-form only (inherited by every subcommand).
        helpNames: [.long])

    public init() {}
}

/// Parses and runs; maps ArgumentParser's usage exit (64) to the spec's 2.
public enum DrypMain {
    public static func run(_ arguments: [String]) -> Int32 {
        do {
            var command = try Dryp.parseAsRoot(arguments)
            try command.run()
            return 0
        } catch {
            let code = Dryp.exitCode(for: error)
            let message = Dryp.fullMessage(for: error)
            if code == .success {
                if !message.isEmpty { CLIEnvironment.current.out(message) }
                return 0
            }
            if !message.isEmpty { CLIEnvironment.current.err(message) }
            return code == .validationFailure ? 2 : code.rawValue
        }
    }
}

enum ModeCommand {
    static func validate(_ value: String?, hours: Bool) throws {
        guard let value else {
            if hours { throw ValidationError("-h needs a number of hours") }
            return
        }
        if value == "off" {
            if hours { throw ValidationError("'off' doesn't take -h") }
            return
        }
        do { _ = try DurationParser.parse(value, hours: hours) } catch { throw ValidationError("\(error)") }
    }

    static func run(_ mode: Mode, value: String?, hours: Bool) throws {
        let env = CLIEnvironment.current
        let code: Int32
        if value == "off" {
            code = Requests.stop([mode], env: env)
        } else {
            code = Requests.start(mode, seconds: try value.map { try DurationParser.parse($0, hours: hours) }, env: env)
        }
        if code != 0 { throw ExitCode(code) }
    }
}

struct Caf: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Keep the screen and everything on (like caffeinate -dimsu). No number = no limit.")

    @Argument(help: "Minutes (hours with -h), or 'off'.") var value: String?
    @Flag(name: [.customShort("h"), .customLong("hours")], help: "Read the number as hours.") var hours = false

    func validate() throws { try ModeCommand.validate(value, hours: hours) }
    func run() throws { try ModeCommand.run(.caf, value: value, hours: hours) }
}

struct Nosleep: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Disable sleep so the lid can close and agents keep running. No number = no limit.")

    @Argument(help: "Minutes (hours with -h), or 'off'.") var value: String?
    @Flag(name: [.customShort("h"), .customLong("hours")], help: "Read the number as hours.") var hours = false

    func validate() throws { try ModeCommand.validate(value, hours: hours) }
    func run() throws { try ModeCommand.run(.nosleep, value: value, hours: hours) }
}

struct Off: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop both caf and nosleep.")

    func run() throws {
        let code = Requests.stop([.caf, .nosleep], env: CLIEnvironment.current)
        if code != 0 { throw ExitCode(code) }
    }
}
