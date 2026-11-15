import Foundation
import UprootCore

// A read-only command-line front end to the scanner, for checking what a search finds
// without opening the app. It never deletes anything.
//
//   uproot-scan Terrain "Terrain FX" --vendor "Waves Crate" [--exclude word] [--inside-bundles] [--all]
//   uproot-scan --files invoice

var products: [String] = []
var vendors: [String] = []
var excludes: [String] = []
var options = ScanOptions()
var showLow = false
var target = SearchTarget.program

var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--vendor", "-v": if !arguments.isEmpty { vendors.append(arguments.removeFirst()) }
    case "--exclude", "-x": if !arguments.isEmpty { excludes.append(arguments.removeFirst()) }
    case "--inside-bundles": options.searchInsideBundles = true
    case "--external": options.includeExternalVolumes = true
    case "--all": showLow = true
    case "--files": target = .files
    case "--help", "-h":
        print("usage: uproot-scan <name>... [--vendor <company>]... [--exclude <text>]... [--files] [--inside-bundles] [--external] [--all]")
        exit(0)
    default: products.append(argument)
    }
}

let query = SearchQuery(target: target, products: products, vendors: vendors, excludes: excludes, options: options)
guard query.hasSearchableTerms else {
    FileHandle.standardError.write(Data("uproot-scan: give at least one name of two or more characters\n".utf8))
    exit(2)
}

let result = await Scanner().scan(query)
let formatter = ByteCountFormatter()
formatter.countStyle = .file

func mark(_ relevance: Relevance) -> String {
    switch relevance {
    case .high: "[x]"
    case .medium: "[ ]"
    case .low: " ? "
    }
}

var category: ItemCategory?
for item in result.items where showLow || item.relevance > .low {
    if item.category != category {
        category = item.category
        print("\n== \(item.category.rawValue)")
    }
    let indent = item.parentID == nil ? "" : "    "
    let admin = item.needsAdmin ? " (admin)" : ""
    let extra = item.unrelatedChildCount > 0 ? " (+\(item.unrelatedChildCount) unrelated inside)" : ""
    print("\(indent)\(mark(item.relevance)) \(item.path)\(admin)\(extra)")
    print("\(indent)      \(item.reasons.map { String(describing: $0) }.joined(separator: "; "))")
}

let low = result.items.filter { $0.relevance == .low }.count
print("\n\(result.items.count - low) items, \(low) doubtful\(showLow ? "" : " (hidden; pass --all)")")
print("scanned \(result.entriesScanned) entries in \(String(format: "%.2f", result.duration)) s")
if !result.identifiers.isEmpty { print("bundle identifiers: \(result.identifiers.joined(separator: ", "))") }
if result.unreadableCount > 0 { print("could not read \(result.unreadableCount) folders, e.g. \(result.unreadableSample.prefix(3).joined(separator: ", "))") }
