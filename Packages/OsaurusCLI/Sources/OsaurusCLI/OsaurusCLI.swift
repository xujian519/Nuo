//
//  OsaurusCLI.swift
//  osaurus
//
//  Main entry point for the Osaurus CLI. Parses command-line arguments and routes to appropriate command handlers.
//

import Foundation
import OsaurusCLICore

@main
struct OsaurusCLI {
    private enum CommandType {
        case status
        case doctor([String])
        case serve([String])
        case stop
        case list
        case show(String)
        case run(String)
        case pull(String)
        case bench([String])
        case mcp([String])
        case ui
        case tools([String])
        case manifest([String])
        case bundle([String])
        case coord([String])
        case config([String])
        case importCmd([String])
        case version
        case help
    }

    private static func parseCommand(_ args: ArraySlice<String>) -> CommandType? {
        guard let command = args.first else { return nil }
        let rest = Array(args.dropFirst())
        switch command {
        case "status": return .status
        case "doctor": return .doctor(rest)
        case "serve": return .serve(rest)
        case "stop": return .stop
        case "list": return .list
        case "show":
            if let modelId = rest.first, !modelId.isEmpty { return .show(modelId) }
            return nil
        case "run":
            if let modelId = rest.first, !modelId.isEmpty { return .run(modelId) }
            return nil
        case "pull":
            if let modelId = rest.first, !modelId.isEmpty { return .pull(modelId) }
            return nil
        case "bench": return .bench(rest)
        case "mcp": return .mcp(rest)
        case "ui": return .ui
        case "tools": return .tools(rest)
        case "manifest": return .manifest(rest)
        case "bundle": return .bundle(rest)
        case "coord": return .coord(rest)
        case "config": return .config(rest)
        case "import": return .importCmd(rest)
        case "version", "--version", "-v": return .version
        case "help", "-h", "--help": return .help
        default: return nil
        }
    }

    static func main() async {
        let arguments = CommandLine.arguments.dropFirst()
        guard let cmd = parseCommand(arguments) else {
            if let first = arguments.first { fputs("Unknown or invalid command: \(first)\n\n", stderr) }
            printUsage()
            exit(EXIT_FAILURE)
        }

        switch cmd {
        case .status:
            await StatusCommand.execute(args: [])
        case .doctor(let args):
            await DoctorCommand.execute(args: args)
        case .serve(let args):
            await ServeCommand.execute(args: args)
        case .stop:
            await StopCommand.execute(args: [])
        case .list:
            await ListCommand.execute(args: [])
        case .show(let modelId):
            await ShowCommand.execute(args: [modelId])
        case .run(let modelId):
            await RunCommand.execute(args: [modelId])
        case .pull(let modelId):
            await PullCommand.execute(args: [modelId])
        case .bench(let args):
            await BenchCommand.execute(args: args)
        case .mcp(let args):
            await MCPCommand.execute(args: args)
        case .ui:
            await UICommand.execute(args: [])
        case .tools(let args):
            await ToolsCommand.execute(args: args)
        case .manifest(let args):
            await ManifestCommand.execute(args: args)
        case .bundle(let args):
            await BundleCommand.execute(args: args)
        case .coord(let args):
            await CoordCommand.execute(args: args)
        case .config(let args):
            await ConfigCommand.execute(args: args)
        case .importCmd(let args):
            await ImportCommand.execute(args: args)
        case .version:
            await VersionCommand.execute(args: [])
        case .help:
            printUsage()
            exit(EXIT_SUCCESS)
        }
    }

    private static func printUsage() {
        let usage = """
            nuo - CLI for Nuo

            Usage:
              nuo serve [--port N] [--expose] [--yes|-y] [--supervise] [--interval N]
                                      Start the server (default: localhost only). If --expose
                                      is set, a warning prompt will appear unless --yes is provided.
                                      With --supervise, run a long-lived keep-alive loop that
                                      relaunches the server whenever it goes down (probe every
                                      --interval seconds, default 15) — intended to run under a
                                      launchd KeepAlive LaunchAgent so the server survives quit.
              nuo stop                Stop the server
              nuo mcp [--access-key KEY]
                                      Run MCP stdio server proxying to local HTTP. When
                                      server network exposure is enabled, provide an
                                      access key here or via OSAURUS_MCP_ACCESS_KEY.
              nuo version             Show version (also: --version or -v)
              nuo status              Check if the Nuo server is running
              nuo doctor [--port N] [--json] [--redact] [--verify-signatures]
                                      Diagnose CLI/app version skew, duplicate app
                                      bundles, server startup, and model storage.
                                      Signature checks are explicit because they can
                                      be slow when many app bundles are installed.
              nuo list                List available model IDs
              nuo show <model_id>     Show metadata for a model
              nuo pull <model_id>     Download a model from Hugging Face
              nuo run <model_id>      Chat with a downloaded model (interactive)
              nuo bench [--model <id>] [--prompt-tokens 1024,8192] [--runs 3] [--json <path>]
                                      Benchmark TTFT / prefill / decode against the
                                      running server; emits JSON tagged with hardware info
              nuo ui                  Show the Nuo menu popover in the menu bar
              nuo tools list          List installed tools
              nuo tools install <plugin_id|url-or-path>
                                      Install a tool from registry or local/URL
              nuo tools search <query>
                                      Search for tools in the registry
              nuo tools outdated      Check for outdated tools
              nuo tools upgrade       Upgrade installed tools
              nuo tools uninstall <tool_name>
                                      Uninstall a tool
              nuo tools verify        Verify dylib integrity of installed tools
              nuo tools create <name> [--language swift|rust]
                                      Scaffold a v2 plugin project
              nuo tools package <plugin_id> <version> [dylib_path]
                                      Package plugin into a zip (includes web/, docs)
              nuo tools reload        Ask the app to rescan tools
              nuo tools rollback <plugin_id>
                                      Roll back a tool to its previous version
              nuo tools dev <plugin_id> [--web-proxy <url>]
                                      Dev mode with hot reload and optional web proxy
              nuo manifest extract <dylib>
                                      Extract manifest JSON from built plugin
              nuo manifest validate <manifest.json>
                                      Validate a plugin manifest's structure (run before packaging)
              nuo bundle load <path.mcpb> [--name "Display Name"]
                                      Load and run an MCP Bundle (.mcpb file)
              nuo coord <subcommand>
                                      Local coordinator orchestration foundation
              nuo config export [-o file.yaml]
                                      Export the current Nuo configuration as YAML
              nuo config plan <file.yaml> [--prune]
                                      Dry-run a declarative YAML document (show the diff)
              nuo config apply <file.yaml> [--prune] [--yes]
                                      Apply a declarative YAML document (--yes confirms
                                      high-risk changes)
              nuo import validate|install|update --from <bundle> [agent|skill|mcp] [name ...]
                                      Install agents, skills and MCP servers from a Nuo
                                      bundle folder (see `nuo import help`)
              nuo import remove --bundle <id> [name ...] / nuo import list
                                      Remove or list what a bundle installed
              nuo help                Show this help

            Bundle author guide: docs/OSAURUS_BUNDLES.md

            """
        print(usage)
    }
}
