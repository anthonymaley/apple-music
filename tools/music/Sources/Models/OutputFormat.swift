import Foundation

enum OutputMode {
    case human
    case json
}

struct OutputFormat {
    let mode: OutputMode

    func render(_ dict: [String: Any]) -> String {
        switch mode {
        case .human:
            return renderHuman(dict)
        case .json:
            return renderJSON(dict)
        }
    }

    func render(_ items: [[String: Any]], numbered: Bool = true) -> String {
        switch mode {
        case .human:
            return items.enumerated().map { (i, item) in
                let prefix = numbered ? "\(i + 1). " : ""
                return prefix + renderHuman(item)
            }.joined(separator: "\n")
        case .json:
            return renderJSON(items)
        }
    }

    private func renderHuman(_ dict: [String: Any]) -> String {
        // Sorted for deterministic output — Dictionary.values has no stable order.
        let values = dict.sorted { $0.key < $1.key }.map { "\($0.value)" }
        return values.joined(separator: " — ")
    }

    private func renderJSON(_ value: Any) -> String {
        // isValidJSONObject must gate the call: JSONSerialization RAISES an ObjC
        // exception (not a Swift error) on an invalid type like Date, which a
        // `try?` cannot catch — so check first rather than crash.
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return #"{"error": "could not serialize output to JSON"}"#
        }
        return str
    }
}
