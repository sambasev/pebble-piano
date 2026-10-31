import Foundation

/// Any JSON value. Request bodies and JSON schemas are built from these, so they stay
/// `Sendable` and can be compared in tests.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// The value as a Foundation object, for `JSONSerialization`.
    var foundation: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { return Int(n) }
            return n
        case .string(let s): return s
        case .array(let a): return a.map(\.foundation)
        case .object(let o): return o.mapValues(\.foundation)
        }
    }

    /// Encoded as compact JSON with sorted keys, so the same value always gives the same bytes.
    public func data() throws -> Data {
        try JSONSerialization.data(withJSONObject: foundation, options: [.sortedKeys, .fragmentsAllowed])
    }

    public init(parsing data: Data) throws {
        self = JSONValue(foundation: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    init(foundation: Any) {
        switch foundation {
        case is NSNull: self = .null
        case let n as NSNumber:
            // NSNumber hides Bool; check its type before treating it as a number.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map(JSONValue.init(foundation:)))
        case let o as [String: Any]: self = .object(o.mapValues(JSONValue.init(foundation:)))
        default: self = .null
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var intValue: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    public var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}
