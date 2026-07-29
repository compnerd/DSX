# Register definitions

Each YAML document describes one canonical architecture profile:

```yaml
profile: ARM64
architecture: arm64
layout: fixed
sets:
  - { id: 0, name: gpr, title: General Purpose Registers }
features:
  - id: 0
    name: org.gnu.gdb.aarch64.core
    includes: []
    types: []
registers:
  - id: 0
    name: x0
    alternate: arg1
    role: argument1
    bits: 64
    offset: 0
    set: gpr
    encoding: unsigned
    format: hexadecimal
    numbers: { gdb: 0, lldb: 0, dwarf: 0, ehframe: 0 }
    relations: { containers: [], invalidates: [] }
    feature: org.gnu.gdb.aarch64.core
    type: uint64
```

Every field is required. Nullable values use `null`; collections may be empty.
Numbering domains are independent. The canonical identifier is `id`, not any
protocol or debug-information number.

Feature `types` contain GDB target-description types. A vector has `kind`,
`element`, and `count`; a flag type has `kind`, `bits`, and `fields`. All
non-applicable fields remain present with `null` or an empty collection.

`layout: scalable` is reserved for a future scalable-profile representation.
The generator recognizes the spelling but rejects it until its size and offset
model is implemented.

Anchors, aliases, merge keys, unknown fields, and implicit schema extensions
are rejected. DSXCodeGen also validates identifiers, number domains,
relations, storage overlap, roles, feature references, GDB types, and include
cycles.
