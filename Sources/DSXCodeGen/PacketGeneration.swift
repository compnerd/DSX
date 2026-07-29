// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

import Yams

internal struct PacketDefinition: Decodable {
  internal let pattern: String
  internal let leaf: String
  internal let exact: Bool
  internal let availability: PacketAvailability
  internal let scope: PacketScope
  internal let request: PacketEncoding
  internal let response: PacketEncoding

  internal init(from decoder: Decoder) throws {
    let keys: Set<String> = [
      "pattern", "leaf", "exact", "feature", "compatibility", "scope",
      "request", "response",
    ]
    let values = try container(decoder, keys: keys)
    pattern = try values.decode(String.self, forKey: SchemaKey("pattern"))
    leaf = try values.decode(String.self, forKey: SchemaKey("leaf"))
    exact = try values.decodeIfPresent(Bool.self,
                                       forKey: SchemaKey("exact")) ?? true
    let feature =
        try values.decodeIfPresent(String.self, forKey: SchemaKey("feature"))
    let compatibility =
        try values.decodeIfPresent(String.self,
                                   forKey: SchemaKey("compatibility"))
    availability = try PacketAvailability(feature: feature,
                                          compatibility: compatibility)
    scope =
        try values.decodeIfPresent(PacketScope.self,
                                   forKey: SchemaKey("scope")) ?? .mode
    request =
        try values.decodeIfPresent(PacketEncoding.self,
                                   forKey: SchemaKey("request")) ?? .text
    response =
        try values.decodeIfPresent(PacketEncoding.self,
                                   forKey: SchemaKey("response")) ?? .text
  }
}

internal enum PacketScope: String, Decodable {
  case mode
  case remote
  case session
}

internal enum PacketEncoding: String, Decodable {
  case binary
  case text
}

internal enum PacketAvailability: UInt8 {
  case always
  case gdb
  case lldb
  case stopthreads
  case threadsuffix

  internal init(feature: String?, compatibility: String?)
      throws(DSXCodeGenError) {
    switch (feature, compatibility) {
    case (.some, .some):
      throw .schema("packet feature and compatibility cannot be combined")
    case (.some("stopthreads"), .none): self = .stopthreads
    case (.some("threadsuffix"), .none): self = .threadsuffix
    case (.some(let feature), .none):
      throw .schema("unsupported packet feature '\(feature)'")
    case (.none, .some("gdb")): self = .gdb
    case (.none, .some("lldb")): self = .lldb
    case (.none, .some(let mode)):
      throw .schema("unsupported compatibility mode '\(mode)'")
    case (.none, .none): self = .always
    }
  }
}

private final class PacketNode {
  fileprivate var packet: PacketDefinition?
  fileprivate var children = Dictionary<UInt8, PacketNode>()
}

internal func packets(_ source: String) throws(DSXCodeGenError) -> String {
  let definitions: Array<PacketDefinition>
  do {
    definitions = try YAMLDecoder().decode(Array<PacketDefinition>.self,
                                           from: source)
  } catch let error as DSXCodeGenError {
    throw error
  } catch {
    throw .schema(String(describing: error))
  }
  guard !definitions.isEmpty else {
    throw .schema("at least one packet is required")
  }
  let root = PacketNode()
  for definition in definitions {
    guard !definition.pattern.isEmpty else {
      throw .schema("packet patterns cannot be empty")
    }
    var node = root
    for byte in definition.pattern.utf8 {
      if let child = node.children[byte] {
        node = child
      } else {
        let child = PacketNode()
        node.children[byte] = child
        node = child
      }
    }
    guard case .none = node.packet else {
      throw .schema("duplicate packet pattern '\(definition.pattern)'")
    }
    node.packet = definition
  }
  return try PacketGenerator(definitions: definitions, root: root).generate()
}

private struct PacketGenerator {
  private let names: Array<String>
  private let ordinals: Dictionary<String, UInt8>
  private let root: PacketNode

  fileprivate init(definitions: Array<PacketDefinition>, root: PacketNode)
      throws(DSXCodeGenError) {
    var names = Array<String>()
    var ordinals = Dictionary<String, UInt8>()
    for definition in definitions where ordinals[definition.leaf] == nil {
      guard names.count < Int(UInt8.max) else {
        throw .schema("packet classifier has too many leaves")
      }
      names.append(definition.leaf)
      ordinals[definition.leaf] = UInt8(names.count)
    }
    self.names = names
    self.ordinals = ordinals
    self.root = root
  }

  fileprivate func generate() throws(DSXCodeGenError) -> String {
    var source = header()
    source.append("")
    source += leaves()
    source.append("")
    source.append("internal enum GDBPacketRoute: UInt8, Sendable {")
    source.append("  case unsupported")
    source.append("  case mode")
    source.append("  case remote")
    source.append("  case session")
    source.append("}")
    source.append("")
    source.append("internal typealias GDBPacketMatch =")
    source.append("    (route: GDBPacketRoute, leaf: GDBPacketLeaf,")
    source.append("     availability: UInt8, payload: Int,")
    source.append("     request: GDBPacketEncoding,")
    source.append("     response: GDBPacketEncoding)")
    source.append("")
    source += try classifier()
    source.append("")
    return source.joined(separator: "\n")
  }

  private func leaves() -> Array<String> {
    var source = ["internal enum GDBPacketLeaf: Equatable, Sendable {"]
    source.append("  case unsupported")
    var transfer = false
    for leaf in names {
      if leaf.hasPrefix("transfer.") {
        transfer = true
      } else {
        source.append("  case \(leaf)")
      }
    }
    if transfer {
      source.append("  case transfer(GDBTransferObject)")
    }
    source.append("")
    source.append("  fileprivate init?(_ ordinal: UInt8) {")
    source.append("    switch ordinal {")
    source.append("    case 0: self = .unsupported")
    for (index, leaf) in names.enumerated() {
      source.append("    case \(index + 1): self = \(expression(leaf))")
    }
    source.append("    default: return nil")
    source.append("    }")
    source.append("  }")
    source.append("}")
    return source
  }

  private func expression(_ leaf: String) -> String {
    guard leaf.hasPrefix("transfer.") else {
      return ".\(leaf)"
    }
    let start = leaf.index(leaf.startIndex, offsetBy: "transfer.".count)
    return ".transfer(.\(leaf[start...]))"
  }

  private func classifier() throws(DSXCodeGenError) -> Array<String> {
    let root = compact(root)
    var nodes = Array<PacketCompactNode>()
    flatten(root, into: &nodes)
    var offsets = Dictionary<ObjectIdentifier, Int>()
    var offset = 0
    for node in nodes {
      offsets[ObjectIdentifier(node)] = offset
      offset += node.size
    }
    guard offset <= Int(UInt16.max) else {
      throw .schema("packet classifier is too large")
    }
    var bytes = Array<UInt8>()
    bytes.reserveCapacity(offset)
    for node in nodes {
      let result = metadata(node.packet)
      guard node.edges.count <= Int(UInt8.max) else {
        throw .schema("packet node has too many edges")
      }
      bytes.append(result.flags)
      bytes.append(result.leaf)
      bytes.append(UInt8(node.edges.count))
      for edge in node.edges {
        guard edge.bytes.count <= Int(UInt8.max) else {
          throw .schema("packet pattern segment is too long")
        }
        guard let target = offsets[ObjectIdentifier(edge.target)] else {
          preconditionFailure("missing packet node")
        }
        bytes.append(UInt8(edge.bytes.count))
        bytes.append(UInt8(truncatingIfNeeded: target))
        bytes.append(UInt8(truncatingIfNeeded: target >> 8))
        bytes.append(contentsOf: edge.bytes)
      }
    }

    var source = Array<String>()
    source.append("internal enum GDBPacketClassifier {")
    source.append("  private static let kTrie: InlineArray<_, UInt8> = [")
    for start in stride(from: 0, to: bytes.count, by: 10) {
      let end = min(start + 10, bytes.count)
      let values = bytes[start ..< end].map(hex).joined(separator: ", ")
      source.append("    \(values),")
    }
    source.append("  ]")
    source.append("")
    source += interpreter()
    source.append("}")
    return source
  }

  private func metadata(_ packet: PacketDefinition?)
      -> (flags: UInt8, leaf: UInt8) {
    guard let packet else {
      return (0, 0)
    }
    let prefix: UInt8 = packet.exact ? 0 : 0x04
    let request: UInt8 = packet.request == .binary ? 0x40 : 0
    let response: UInt8 = packet.response == .binary ? 0x80 : 0
    let encoding = request | response
    let support = packet.availability.rawValue << 3
    let flags = scope(packet.scope) | prefix | support | encoding
    guard let leaf = ordinals[packet.leaf] else {
      preconditionFailure("missing packet leaf")
    }
    return (flags, leaf)
  }

  private func compact(_ source: PacketNode) -> PacketCompactNode {
    let node = PacketCompactNode(packet: source.packet)
    for byte in source.children.keys.sorted() {
      guard var child = source.children[byte] else {
        continue
      }
      var bytes = [byte]
      while child.packet == nil, child.children.count == 1 {
        guard let byte = child.children.keys.first,
            let next = child.children[byte] else {
          break
        }
        bytes.append(byte)
        child = next
      }
      node.edges.append(PacketCompactEdge(bytes: bytes, target: compact(child)))
    }
    return node
  }

  private func flatten(_ node: PacketCompactNode,
                       into nodes: inout Array<PacketCompactNode>) {
    nodes.append(node)
    for edge in node.edges {
      flatten(edge.target, into: &nodes)
    }
  }

  private func scope(_ scope: PacketScope) -> UInt8 {
    switch scope {
    case .mode: 1
    case .remote: 2
    case .session: 3
    }
  }

  private func hex(_ byte: UInt8) -> String {
    let value = String(byte, radix: 16)
    return value.count == 1 ? "0x0\(value)" : "0x\(value)"
  }

  private func interpreter() -> Array<String> {
    [
      "  private static var unsupported: GDBPacketMatch {",
      "    (route: .unsupported, leaf: .unsupported, availability: 0,",
      "     payload: 0, request: .text, response: .text)",
      "  }",
      "",
      "  internal static func allows(_ match: GDBPacketMatch,",
      "                              _ state: borrowing GDBRemoteSessionState)",
      "      -> Bool {",
      "    return switch match.availability {",
      "    case 0: true",
      "    case 1: state.compatibility == .gdb",
      "    case 2: state.compatibility == .lldb",
      "    case 3: state.negotiation.supported.contains(.stopthreads)",
      "    case 4: state.negotiation.supported.contains(.threadsuffix)",
      "    default: false",
      "    }",
      "  }",
      "",
      "  internal static func classify(_ packet: borrowing Span<UInt8>)",
      "      -> GDBPacketMatch {",
      "    var node = 0",
      "    var index = 0",
      "    while true {",
      "      let flags = kTrie[node]",
      "      if index == packet.count {",
      "        guard flags & 0x03 > 0 else {",
      "          return unsupported",
      "        }",
      "        return match(node, flags: flags, payload: index)",
      "      }",
      "      let count = Int(kTrie[node + 2])",
      "      var edge = node + 3",
      "      var found = false",
      "      for _ in 0 ..< count {",
      "        let length = Int(kTrie[edge])",
      "        let start = edge + 3",
      "        if matches(packet, from: index, bytes: start, count: length) {",
      "          node = offset(edge + 1)",
      "          index += length",
      "          found = true",
      "          break",
      "        }",
      "        edge = start + length",
      "      }",
      "      guard found else {",
      "        guard flags & 0x04 > 0 else {",
      "          return unsupported",
      "        }",
      "        return match(node, flags: flags, payload: index)",
      "      }",
      "    }",
      "  }",
      "",
      "  private static func matches(_ packet: borrowing Span<UInt8>,",
      "                              from: Int, bytes: Int, count: Int)",
      "      -> Bool {",
      "    guard count <= packet.count - from else {",
      "      return false",
      "    }",
      "    for index in 0 ..< count {",
      "      guard packet[from + index] == kTrie[bytes + index] else {",
      "        return false",
      "      }",
      "    }",
      "    return true",
      "  }",
      "",
      "  private static func offset(_ index: Int) -> Int {",
      "    Int(kTrie[index]) | Int(kTrie[index + 1]) << 8",
      "  }",
      "",
      "  private static func match(_ node: Int, flags: UInt8, payload: Int)",
      "      -> GDBPacketMatch {",
      "    guard let leaf = GDBPacketLeaf(kTrie[node + 1]) else {",
      "      preconditionFailure(\"invalid packet leaf\")",
      "    }",
      "    guard let route = GDBPacketRoute(rawValue: flags & 0x03) else {",
      "      preconditionFailure(\"invalid packet scope\")",
      "    }",
      "    let request: GDBPacketEncoding =",
      "        flags & 0x40 > 0 ? .binary : .text",
      "    let response: GDBPacketEncoding =",
      "        flags & 0x80 > 0 ? .binary : .text",
      "    return (route: route, leaf: leaf,",
      "            availability: flags >> 3 & 0x07, payload: payload,",
      "            request: request, response: response)",
      "  }",
    ]
  }
}

private final class PacketCompactNode {
  fileprivate let packet: PacketDefinition?
  fileprivate var edges = Array<PacketCompactEdge>()

  fileprivate init(packet: PacketDefinition?) {
    self.packet = packet
  }

  fileprivate var size: Int {
    3 + edges.reduce(0) { size, edge in size + 3 + edge.bytes.count }
  }
}

private struct PacketCompactEdge {
  fileprivate let bytes: Array<UInt8>
  fileprivate let target: PacketCompactNode
}
