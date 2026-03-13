---
type: "agent_requested"
description: "Modern Swift 6.2.x Coding Guidelines"
---

# Swift 6.2.x Authoritative Reference for Swift Projects

**Swift 6.2** (shipped September 2025 with Xcode 17, latest patch 6.2.4) represents a mature language with **complete data-race safety**, an "Approachable Concurrency" paradigm, safe systems programming primitives (`Span`, `InlineArray`), and first-class cross-platform support including WebAssembly and Android. This document provides prescriptive, directive-style guidance for every major language feature area. All SE proposals cited are accepted and implemented unless noted otherwise.

---

## 1. Strict Concurrency Model (complete)

Swift 6 makes data-race safety a **compile-time guarantee**. Concurrency violations that were warnings in Swift 5 are errors in Swift 6 language mode. Swift 6.2's "Approachable Concurrency" pivot (SE-0461, SE-0466) dramatically simplifies adoption by making nonisolated async functions run on the caller's actor by default and offering **`MainActor` default isolation** for app targets.

### Sendable conformance

Use `Sendable` on value types whose stored properties are all Sendable — the compiler synthesizes conformance implicitly for internal types. Explicitly declare `Sendable` on `public` types. Use `Sendable` on `final class` types only when all stored properties are immutable `let` constants that are themselves `Sendable`. Prefer `Mutex<T>` (from the `Synchronization` framework, Swift 6+) to protect mutable class state, which lets the class conform to `Sendable` without `@unchecked`:

```swift
import Synchronization
final class ThreadSafeCache: Sendable {
    private let store = Mutex<[String: Data]>([:])
    func get(_ key: String) -> Data? { store.withLock { $0[key] } }
    func set(_ key: String, _ val: Data) { store.withLock { $0[key] = val } }
}
```

Use `@unchecked Sendable` only for legacy types using locks or dispatch queues the compiler cannot verify. Treat it as a temporary migration tool. Avoid marking types `Sendable` when **region-based isolation** (SE-0414) proves safety automatically — many non-Sendable values can safely cross isolation boundaries without conformance.

### Actor isolation rules

Declare `actor` for types with mutable state accessed from multiple isolation domains. All instance members are actor-isolated by default; cross-actor access requires `await`. Use `@MainActor` to isolate code to the main thread — mandatory for UI mutations. Use custom global actors (`@globalActor`) sparingly for domain-specific serialization (e.g., `@DatabaseActor`).

Mark members `nonisolated` to opt out of the enclosing actor's isolation. Use `nonisolated(unsafe)` (SE-0412) only as a **temporary escape hatch** for global/static storage where you accept full responsibility for thread safety. Use `@preconcurrency import` to suppress Sendable diagnostics from legacy modules, and `@preconcurrency` on declarations to maintain backward compatibility with Swift 5 callers.

**Swift 6.2 changes** — `nonisolated(nonsending)` (SE-0461): nonisolated `async` functions now run on the **caller's actor** by default instead of hopping to the global concurrent executor. Use `@concurrent` to explicitly opt a function into background execution:

```swift
// Runs on caller's actor (Swift 6.2 default)
nonisolated func fetchData() async -> Data { ... }
// Explicitly runs off-actor
@concurrent func heavyComputation() async -> Result { ... }
```

**Default actor isolation** (SE-0466): set `MainActor` as the default for an entire target via `.defaultIsolation(MainActor.self)` in `Package.swift` or the Xcode "Default Actor Isolation" build setting. Use this for **app targets**; keep `nonisolated` default for libraries.

### Region-based isolation and transfer analysis

SE-0414 (Swift 6.0) introduced **region-based isolation**: the compiler performs data-flow analysis tracking "isolation regions" — groups of values that may alias each other. When a non-Sendable value is sent across an isolation boundary, the compiler verifies the value and everything in its region is **never used afterward** in the original domain. This eliminates thousands of false-positive Sendable requirements compared to Swift 5.10's conservative analysis.

```swift
func example() async {
    let value = NonSendableObject()
    await useOnMainActor(value) // ✅ value created here, transferred, never reused
    // value.doSomething()      // ❌ ERROR: use after transfer
}
```

### `sending` parameter and result annotations

SE-0430 introduced `sending` — a value-level annotation (unlike `Sendable` which is type-level) requiring the value be "disconnected" at the function boundary. Use `sending` when your API accepts non-Sendable values that will be transferred to another isolation domain. `Task.init`'s closure changed from `@Sendable` to `sending` in Swift 6.

```swift
actor Storage {
    var item: NonSendable?
    func store(_ obj: sending NonSendable) { item = obj }
}
```

**Rule of thumb**: `Sendable` = every instance is forever safe across boundaries. `sending` = this *specific* value is safe because ownership is transferred.

### Task groups

Use `withTaskGroup(of:returning:body:)` to collect results from parallel child tasks. Use `withThrowingTaskGroup` when child tasks can throw. Use **`withDiscardingTaskGroup`** (SE-0381) for long-running fire-and-forget workloads (servers, event loops) — child task results are automatically discarded, preventing memory leaks:

```swift
try await withThrowingDiscardingTaskGroup { group in
    while let conn = try await server.accept() {
        group.addTask { try await handle(conn) }
    }
}
```

Limit concurrency by seeding a fixed number of initial tasks and adding new ones as existing tasks complete via `group.next()`.

### Structured vs. unstructured concurrency

**Default to structured concurrency** (`async let`, task groups) — it provides automatic cancellation propagation, priority inheritance, and guaranteed child completion. Use `Task { }` only to bridge synchronous → async contexts (e.g., SwiftUI button handlers); it inherits actor isolation and priority. Use `Task.detached` only when you must shed all inherited context — prefer a `nonisolated` function with a regular `Task` instead.

### AsyncSequence, AsyncStream, and primary associated types

SE-0421 (Swift 6.0) added a `Failure` associated type and primary associated types to `AsyncSequence`, enabling `some AsyncSequence<Int, Never>` syntax. Use `AsyncStream.makeStream()` (SE-0388) as the preferred factory — it cleanly separates producer and consumer:

```swift
let (stream, continuation) = AsyncStream<Event>.makeStream()
continuation.yield(.loaded(data))
continuation.finish()
for await event in stream { handle(event) }
```

Always set `onTermination` on continuations to clean up resources.

### Concurrency migration for greenfield projects

For **app targets** (Swift 6.2 / Xcode 17): enable `MainActor` default isolation plus the Approachable Concurrency suite of flags. For **library/SPM packages**: keep `nonisolated` default. Always set Swift 6 language mode:

```swift
// swift-tools-version: 6.2
.target(name: "MyApp", swiftSettings: [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
])
```

> **Changed from Swift 5.x**: Concurrency checking escalated from opt-in warnings to mandatory errors. Region-based isolation (SE-0414) and `sending` (SE-0430) are new in Swift 6.0. Swift 6.2's Approachable Concurrency (SE-0461, SE-0466) inverts the default — async functions now stay on the caller's actor unless explicitly marked `@concurrent`, and app targets can default to `@MainActor`. `Task.init` closures changed from `@Sendable` to `sending`.

---

## 2. Ownership, Borrowing & Noncopyable Types

### ~Copyable types

Suppress the implicit `Copyable` conformance with `~Copyable`. Noncopyable structs and enums get value-type semantics with unique ownership and **`deinit`** support — previously class-only. Assignment is a move; the original variable becomes invalid.

```swift
struct FileHandle: ~Copyable {
    private let fd: Int32
    init(path: String) throws { fd = open(path, O_RDONLY); guard fd >= 0 else { throw Err.open } }
    borrowing func read(_ n: Int) -> Data { /* ... */ }
    consuming func close() { Darwin.close(fd); discard self }
    deinit { Darwin.close(fd) }
}
```

Use `borrowing` for read-only access, `consuming` when taking ownership (invalidates caller's copy), and `mutating` for exclusive mutable access. Use `discard self` in consuming methods to suppress `deinit` when cleanup was done explicitly. SE-0427 (Swift 6.0) extended noncopyable types into the generics system, enabling `Optional<T: ~Copyable>`.

### ~Escapable types and lifetime dependencies

SE-0446 (Swift 6.2) introduced `~Escapable` types — values that cannot outlive their scope, generalizing non-escaping closure semantics to all types. `Span<T>` is the canonical `~Escapable` type. Lifetime dependency annotations (`@lifetime(borrow self)`, `@lifetime(copy self)`) specify which parent object's lifetime a `~Escapable` value depends on. **Note**: `@lifetime` is available as an experimental feature in Swift 6.2 (`-enable-experimental-feature LifetimeDependence`) — the formal SE proposal is still in progress.

### Extracting values from noncopyable containers

SE-0437 (Swift 6.0) generalized `Optional`, `Result`, and `UnsafePointer` for noncopyable wrapped types. Use a `take()` pattern with `consume self` to forward ownership of the payload while writing `nil` back:

```swift
extension Optional where Wrapped: ~Copyable {
    mutating func take() -> Wrapped? {
        switch consume self {
        case .some(let val): self = nil; return val
        case .none: self = nil; return nil
        }
    }
}
```

### Practical patterns

Use `~Copyable` structs for **unique file handles, database connections, and tokens** — single-owner semantics with automatic `deinit` cleanup. Use `~Copyable` enums with `consume self` in `mutating` methods for **compile-time state machines** — the compiler forces `self` reassignment on every path, catching missing transitions.

### Decision tree

Use `~Copyable struct` for unique resources with exclusive ownership. Use `actor` for shared mutable state across concurrent contexts. Use regular `class` when you need shared identity with inheritance. Use `~Copyable enum` for typestate patterns. Use `~Escapable struct` for borrowed views into another container's memory.

> **Changed from Swift 5.x**: `~Copyable` introduced in Swift 5.9 (SE-0390). Swift 6.0 added noncopyable generics (SE-0427), noncopyable stdlib primitives (SE-0437), and pattern matching (SE-0432). Swift 6.2 added `~Escapable` (SE-0446). Classes and actors cannot be `~Copyable`.

---

## 3. Typed Throws & Error Handling

### `throws(ErrorType)` syntax

SE-0413 (Swift 6.0) allows functions to declare a concrete error type. Only instances of that type can be thrown, and `catch` blocks receive the concrete type — no more type-erased `any Error`:

```swift
enum ParseError: Error { case invalidFormat, missingField(String) }
func parse(_ data: Data) throws(ParseError) -> Config {
    guard isValid(data) else { throw .invalidFormat }
    return Config(data)
}
```

`throws(any Error)` is equivalent to plain `throws`; `throws(Never)` is equivalent to non-throwing. Only **one** error type per function. In `do` blocks, if all `try` calls throw the same typed error, exhaustive pattern matching eliminates the need for a general `catch`.

### Interaction with rethrows, Result, and Task

Typed throws with a generic error parameter **subsumes `rethrows`** — when `E` is inferred as `Never` (non-throwing closure), the outer function becomes non-throwing automatically:

```swift
func count<E>(where pred: (Element) throws(E) -> Bool) throws(E) -> Int
```

`Result { try typedThrowingFunction() }` preserves the concrete error type. `Task<Success, Failure>` already has typed `Failure`, bridging naturally with typed throws.

### Guidelines

**Default to plain `throws`** — it is better for most scenarios per the proposal authors. Use `throws(MyError)` only when the error domain is closed and exhaustive handling is valuable. Use `throws(E)` generics for higher-order functions replacing `rethrows`. Use `Result<T, E>` for storing results or callback-based APIs.

> **Changed from Swift 5.x**: Typed throws is entirely new in Swift 6.0. Previously all thrown errors were type-erased to `any Error`. `rethrows` still works but typed throws generics are the modern replacement.

---

## 4. Type System & Generics

### Parameter packs

SE-0393 (Swift 5.9) introduced variadic generics. Declare type parameter packs with `each T` and expand with `repeat each`. SE-0408 (Swift 6.0) added pack iteration via `for-in`:

```swift
func allSatisfy<each T: Equatable>(_ value: repeat each T, _ other: repeat each T) -> Bool {
    for pair in repeat (each value, each other) {
        guard pair.0 == pair.1 else { return false }
    }
    return true
}
```

**Limitations**: no head/tail destructuring, cannot enforce minimum element count, stored properties cannot directly be pack expansion types (nest in tuples).

### Opaque return types (`some`) vs. boxed existentials (`any`)

**Require `any`** when using a protocol as an existential type in Swift 6 language mode — bare protocol names are errors. Decision tree: use `some Protocol` (or explicit generics `<T: Protocol>`) when a single concrete type suffices — it gives **static dispatch** and preserves type identity. Use `any Protocol` only when you need **runtime heterogeneity** (e.g., `[any Shape]` holding mixed types). Start concrete → move to `some` → resort to `any` only when necessary.

### Primary associated types and constrained existentials

SE-0346 (Swift 5.7) allows protocols to declare primary associated types in angle brackets, enabling `any Collection<Int>` and `some Collection<String>` syntax:

```swift
var items: any Collection<Int> = [1, 2, 3]
func process(_ c: some Collection<String>) { /* ... */ }
```

Standard library protocols adopted this: `Sequence<Element>`, `Collection<Element>`, `Identifiable<ID>`, etc. (SE-0358). Limit to **one** primary associated type per protocol in most cases.

### `@retroactive` conformances

SE-0364 warns when both type and protocol come from external modules. Use `@retroactive` to acknowledge the risk:

```swift
extension ExternalType: @retroactive ExternalProtocol { ... }
```

Prefer wrapper types or upstream contributions over retroactive conformances.

### Synthesized conformances and BitwiseCopyable

**Equatable/Hashable** (SE-0185): auto-synthesized for structs with all-conforming stored properties and enums with all-conforming associated values. **Codable** (SE-0166, SE-0295): auto-synthesized including enums with associated values (Swift 5.5+). **BitwiseCopyable** (SE-0426, Swift 6.0): marker protocol for types copyable via `memcpy`. Auto-inferred for internal structs/enums; must be explicit for `public` types. Enables more efficient code generation for low-level and generic operations.

> **Changed from Swift 5.x**: Parameter packs (SE-0393) new in 5.9, pack iteration (SE-0408) in 6.0. `any` keyword required in Swift 6 (SE-0335 enforcement). `@retroactive` required for cross-module conformances. `BitwiseCopyable` new in Swift 6.0. Note: `ExistentialAny` was **deferred to Swift 7** — it remains an upcoming feature flag, not mandatory in Swift 6.

---

## 5. Macros

### Macro roles

Swift macros span **8 roles** across two categories:

- **Freestanding**: `@freestanding(expression)` (SE-0382) produces a value; `@freestanding(declaration)` (SE-0397) produces declarations. At most one freestanding role per macro.
- **Attached**: `@attached(peer)`, `@attached(accessor)`, `@attached(member)`, `@attached(memberAttribute)` (all SE-0389); `@attached(extension)` (SE-0402, replaced `@attached(conformance)`); `@attached(body)` (SE-0415, Swift 6.0) synthesizes/replaces function bodies. Attached roles can be freely composed on a single macro.

SE-0407 extended `@attached(member)` with a `conformances:` parameter for protocol-aware member generation.

### Built-in macros

`#Predicate` (Foundation, iOS 17+): type-safe compile-time predicate builder replacing `NSPredicate`. `#Expression` (iOS 18+): generalized `#Predicate` returning any type. `#Preview`: replaces `PreviewProvider` protocol for Xcode previews. `@Observable` (SE-0395): multi-role macro transforming classes into observable types with per-property tracking. `@ObservationTracked` is auto-applied to stored properties; `@ObservationIgnored` opts properties out.

### Custom macros vs. alternatives

Prefer macros when generating multiple declarations, enforcing compile-time validation, or transforming type structure across properties. Prefer property wrappers for single-property runtime behavior (clamping, lazy init). Prefer protocol conformance when the standard library already provides synthesis. **Macros expand visibly in Xcode** — transparency is a design advantage over opaque runtime abstractions.

### Macro testing

Use `assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport` for string-comparison expansion tests. For improved ergonomics, Point-Free's `swift-macro-testing` library provides snapshot-based testing with inline diagnostic rendering, compatible with Swift Testing:

```swift
import MacroTesting
@Suite(.macros([StringifyMacro.self]))
struct Tests {
    @Test func expansion() {
        assertMacro { "#stringify(a + b)" }
        expansion: { "(a + b, \"a + b\")" }
    }
}
```

> **Changed from Swift 5.x**: Macros are entirely new in Swift 5.9. `@attached(conformance)` was replaced by `@attached(extension)` (SE-0402). `@attached(body)` added in Swift 6.0 (SE-0415). No macro system existed prior to Swift 5.9.

---

## 6. Data Flow & Observation (SwiftUI Context)

### @Observable as the default

SE-0395's `@Observable` macro (Swift 5.9 / iOS 17+) replaces the `ObservableObject` / `@Published` stack. Key advantages: **per-property tracking** (only views reading changed properties re-render), automatic observation of computed properties, no manual `@Published` annotations, and internal thread safety via `Mutex`-backed registrar.

```swift
@Observable final class UserModel {
    var name = ""       // automatically tracked
    var score = 0       // automatically tracked
    @ObservationIgnored var id = UUID()  // opted out
}
```

### Property wrappers in the Observation world

The wrapper landscape simplifies dramatically. Pass `@Observable` objects as plain properties for read-only access — SwiftUI auto-tracks. Use `@State` when the view **owns** the object's lifetime (replaces `@StateObject`). Use `@Bindable` for `$` bindings to `@Observable` properties (replaces `@ObservedObject`). Use `@Environment` for injection through the view hierarchy (replaces `@EnvironmentObject`):

```swift
struct EditorView: View {
    @Bindable var settings: Settings  // for $bindings
    var body: some View {
        Slider(value: $settings.fontSize, in: 8...32)
    }
}
```

### When @ObservationTracked / @ObservationIgnored matter

`@ObservationTracked` is applied automatically by `@Observable` — you never write it manually. Use `@ObservationIgnored` for: properties that should not trigger UI updates (IDs, caches), properties using custom property wrappers (since `@Observable` converts stored properties to computed), and high-frequency properties where observation overhead matters.

### SwiftData model patterns

`@Model` automatically includes `Observable` conformance — **do not also add `@Observable`**. Use `@Query` for declarative fetching and `#Predicate` for type-safe filtering:

```swift
@Model final class Book {
    var title: String
    var author: String
    init(title: String, author: String) { self.title = title; self.author = author }
}
struct LibraryView: View {
    @Query(sort: \Book.title) var books: [Book]
    var body: some View { List(books) { book in Text(book.title) } }
}
```

> **Changed from Swift 5.x**: `@Observable` replaces `ObservableObject`/`@Published`. `@State` replaces `@StateObject`, `@Bindable` replaces `@ObservedObject`, `@Environment` replaces `@EnvironmentObject`. Observation is per-property (not whole-object). SwiftData replaces Core Data's `NSManagedObject` + `.xcdatamodeld` with pure Swift `@Model` classes.

---

## 7. Swift Testing Framework

### import Testing vs. legacy XCTest

Use `import Testing` for **all new unit tests** in Swift 6.x. It uses `@Test` functions (can be struct methods or global functions), `#expect`/`#require` macros, and runs tests in **parallel by default**. Use `XCTest` only for UI testing and performance testing (Swift Testing has no support for these). Both frameworks coexist in the same target but assertions cannot cross frameworks.

```swift
import Testing
struct MathTests {
    @Test("Addition is commutative")
    func commutativity() { #expect(2 + 3 == 3 + 2) }
}
```

### @Test, @Suite, and traits

Mark any function with `@Test`. Group tests with `@Suite` on structs (preferred), classes, or actors. Traits propagate from suites to contained tests:

- `.disabled("reason")` — skip with explanation
- `.enabled(if: condition)` — conditional execution
- `.tags(.networking)` — categorization for filtering (define as `extension Tag { @Tag static var networking: Self }`)
- `.bug(id: "FB12345")` — link to bug tracker
- `.timeLimit(.minutes(1))` — per-test timeout
- `.serialized` — run suite tests sequentially

### Parameterized tests

Use `@Test(arguments:)` to run a single test function with multiple inputs, each as an independent parallel test case:

```swift
@Test("Even values", arguments: [2, 8, 50])
func even(value: Int) { #expect(value.isMultiple(of: 2)) }

@Test(arguments: zip([18, 30], [77.0, 73.0]))
func heartRate(age: Int, bpm: Double) { #expect(bpm < 100) }
```

Use arrays/ranges/`.allCases` for arguments. Argument types must be `Sendable`. For cross-product of multiple arguments, pass separate collections.

### #expect, #require, withKnownIssue, confirmation

`#expect` records failure but continues (soft assertion). `#require` throws on failure, halting the test — use `try` (hard assertion, also unwraps optionals). `withKnownIssue` suppresses expected failures and notifies when fixed. `confirmation` replaces `XCTestExpectation` for event-counting:

```swift
@Test func eventFires() async {
    await confirmation("callback", expectedCount: 1) { confirm in
        sut.onComplete = { confirm() }
        await sut.run()
    }
}
```

### Organization

Prefer structs over classes for suites (value semantics, no shared state). Use `init` for setup. Group by feature in suites; use tags for cross-cutting concerns. Name files descriptively: `UserServiceTests.swift`. Custom traits (Swift 6.1+) via `TestTrait` + `TestScoping` provide reusable setup/teardown.

> **Changed from Swift 5.x**: Swift Testing is entirely new (Swift 6.0 / Xcode 16). Replaces `XCTestCase` subclassing, `test` method prefix convention, 40+ `XCTAssert*` functions, and `XCTestExpectation`. Tests run in parallel by default. Exit testing and attachments added in Swift 6.2.

---

## 8. Package & Module Structure

### Package.swift conventions (tools-version 6.0+)

`swift-tools-version: 6.0` enables **Swift 6 language mode for all targets by default** — concurrency violations are errors. Override per-target with `.swiftLanguageMode(.v5)` for incremental migration. The old `swiftLanguageVersions` is renamed to `swiftLanguageModes`.

```swift
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "MyApp",
    targets: [
        .target(name: "Core"),  // Swift 6 mode
        .target(name: "Legacy", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
```

### Upcoming feature flags

Enable future-mode behavior incrementally with `.enableUpcomingFeature()`. Key flags not yet mandatory in Swift 6 (targeting Swift 7):

- `ExistentialAny` (SE-0335) — require `any` for all existentials
- `InternalImportsByDefault` (SE-0409) — imports default to `internal` visibility
- `MemberImportVisibility` (SE-0444) — members only visible from directly imported modules
- `InferIsolatedConformances` (SE-0470) — infer isolated conformances
- `NonisolatedNonsendingByDefault` (SE-0461) — nonisolated async functions are nonsending

Use `#if hasFeature(ExistentialAny)` for conditional compilation when supporting multiple language modes.

### Access control: `package` access level and internal imports

SE-0386 (Swift 5.9) introduced `package` — visible to all modules within the same SwiftPM package but invisible externally. Use `package` instead of `public` for intra-package APIs. SE-0409 adds access-level modifiers to imports: `public import Foundation` exposes Foundation to downstream clients; plain `import` becomes `internal` when `InternalImportsByDefault` is enabled. This reduces transitive dependency leakage.

### Module splitting

Split into multiple modules when: build time suffers (only changed modules recompile), teams need independent workstreams, or code is shared across app targets (widgets, extensions). Prefer a **wide, shallow** dependency graph. Start with 3–5 modules and split as needed — over-modularization creates overhead. Use interface/implementation splits for maximum build parallelism.

### SwiftPM plugins

**Build tool plugins** (SE-0303) run automatically during builds for code generation (protobuf, SwiftGen, OpenAPI). **Command plugins** (SE-0332) are invoked manually via `swift package <verb>` for formatting, linting, and documentation. Popular examples: SwiftLint, swift-docc-plugin, swift-openapi-generator.

> **Changed from Swift 5.x**: `swift-tools-version: 6.0` defaults to Swift 6 language mode (errors, not warnings). `package` access level new in 5.9. `InternalImportsByDefault` and `MemberImportVisibility` target Swift 7 as mandatory. Per-target warning control added in Swift 6.2 (SE-0480).

---

## 9. Memory Safety & Pointer Guidelines

### Temporary pointer lifetimes

Pointers from `withUnsafeBufferPointer`, `withUnsafeBytes`, or implicit pointer conversions are **valid only for the closure's duration**. Never store, return, or escape them. Keep unsafe pointer usage within the smallest possible scope.

```swift
// ✅ Correct: use within closure
let sum = array.withUnsafeBufferPointer { buf in buf.reduce(0, +) }
// ❌ Never escape
var saved: UnsafeBufferPointer<Int>?
array.withUnsafeBufferPointer { saved = $0 } // Undefined behavior
```

### Span and RawSpan migration

`Span<T>` (SE-0447, Swift 6.2) is a **non-owning, non-escapable, bounds-checked** view into contiguous memory — Swift's safe replacement for `UnsafeBufferPointer`. `RawSpan` provides the untyped equivalent for binary parsing. SE-0456 added `.span` computed properties to `Array`, `String`, `Data`, and other stdlib types:

```swift
let array = [1, 2, 3, 4, 5]
let s: Span<Int> = array.span  // safe, bounds-checked, lifetime-dependent
print(s[0])
```

`MutableSpan` (SE-0467) delegates safe mutations. **Caveat**: full use in user-defined APIs requires `@lifetime` annotations, which remain an **experimental feature** in Swift 6.2. Prefer `Span` over `UnsafeBufferPointer` for all new read-only contiguous access.

### C/C++ interoperability

C++ interop (enabled via `.interoperabilityMode(.Cxx)`) is stable since Swift 5.9. Swift 6.2 adds a **safe interop mode**: annotate C++ view types with `SWIFT_NONESCAPABLE` (imports as `~Escapable`), annotate functions with `__lifetimebound` for lifetime tracking, and `std::span<const T>` automatically bridges to Swift `Span<T>`. C APIs with `__counted_by(N)` annotations get safe `Span` overloads. Never let C++ exceptions propagate into Swift frames.

> **Changed from Swift 5.x**: `Span`/`RawSpan` entirely new in Swift 6.2. C++ interop introduced in 5.9, safe interop mode new in 6.2 with `SWIFT_NONESCAPABLE`/`__lifetimebound` annotations. Opt-in strict memory safety mode available in 6.2 for security-critical projects.

---

## 10. Naming, Style & Idiom

### API Design Guidelines

The official swift.org API Design Guidelines remain unchanged since Swift 3 (SE-0023). **Clarity at the point of use** is the primary goal. Types and protocols use UpperCamelCase; everything else uses lowerCamelCase. Boolean properties read as assertions (`isEmpty`, `isValid`). Mutating/nonmutating pairs follow `sort()`/`sorted()` convention.

### Trailing closure disambiguation

SE-0286 (Swift 6.0) changed trailing closure matching from backward-scan to **forward-scan**. Design APIs assuming the first trailing closure label is dropped. Use labeled trailing closures for all subsequent closure parameters. Avoid trailing closure syntax in `guard` conditions.

### if/switch expressions

SE-0380 (Swift 5.9) allows `if` and `switch` as value-producing expressions. Prefer these over ternary for multi-line or complex conditions:

```swift
let label = if score > 500 { "Pass" } else { "Fail" }
let tier = switch level {
    case .free: "Basic"
    case .pro: "Professional"
    case .enterprise: "Enterprise"
}
```

Both `else` and `default` are required for exhaustiveness. Each branch is type-checked independently (no cross-branch coercion like ternary).

### guard vs. if let vs. Optional.map

Use `guard let` at function tops for precondition validation with early exit — the unwrapped value stays in scope. Use `if let` when both nil and non-nil branches need handling. Use `Optional.map` for concise functional transformations: `username.map { "@\($0)" } ?? "Anonymous"`. Use shorthand `guard let name else { return }` (SE-0345, Swift 5.7).

### consume keyword style

`consume` (SE-0366, Swift 5.9) ends a variable's lifetime early. Use it in performance-critical paths, noncopyable type APIs, and to document ownership transfer intent. Do not sprinkle it everywhere — the optimizer handles most cases.

### Naming conventions for new constructs

**Actors**: UpperCamelCase nouns (`ImageLoader`). **Global actors**: UpperCamelCase used as `@Attribute` (`@DatabaseActor`). **Macros**: attached macros use UpperCamelCase (`@Observable`); freestanding expression macros use `#PascalCase` (`#Predicate`) or `#lowerCamelCase` (`#stringify`). **Noncopyable types**: same naming as regular structs/enums; `~Copyable` is a constraint, not part of the name. One primary type per file: `ImageLoader.swift`; extensions: `ImageLoader+Caching.swift`.

> **Changed from Swift 5.x**: Forward-scan trailing closures (SE-0286) is a source-breaking change in Swift 6. `if`/`switch` expressions new in Swift 5.9. `guard let x` shorthand new in Swift 5.7. `consume` keyword new in Swift 5.9.

---

## 11. Performance Annotations & Tuning

### @inlinable, @usableFromInline, @frozen, package

`@inlinable` exports a function body into the module interface for cross-module inlining — the body becomes **ABI-permanent**. `@usableFromInline` makes `internal` declarations available to `@inlinable` code. `@frozen` publishes struct layout / enum cases — enables direct field access but prevents adding/removing/reordering stored properties. `package` (SE-0386) provides intra-package visibility without ABI commitments.

**Directive for library authors**: only mark functions `@inlinable` if they are stable, small (<10 lines), and on hot paths with benchmark evidence. Only `@frozen` types whose layout is truly permanent. Without library evolution mode, these annotations carry no ABI constraints. Use `package` instead of `public` for multi-module package APIs.

### Copy-on-write and noncopyable types

Standard CoW types (`Array`, `Dictionary`, `String`) copy storage on mutation. Noncopyable types **eliminate CoW overhead entirely** — single owner, no reference counting. For large value types representing unique resources, `~Copyable` is often more efficient than CoW. For large value types shared widely, implement manual CoW with `isKnownUniquelyReferenced`.

### borrowing/consuming guidance for library authors

For **copyable types**: ownership annotations (SE-0377) are optional and strictly for optimization. Don't annotate unless benchmarks show measurable improvement. For **noncopyable types**: ownership annotations are **mandatory** — the compiler cannot insert copies. Changing between `consuming` and `borrowing` is **ABI-breaking** for library-evolution builds.

> **Changed from Swift 5.x**: `@frozen` was introduced in Swift 5.1. `borrowing`/`consuming` new in Swift 5.9. `package` access level new in Swift 5.9. `@abi` attribute (SE-0476) new in Swift 6.2, decoupling ABI name from source name for library evolution.

---

## 12. Platform & Ecosystem Context

### Compiler-level features (back-deploy to any OS)

These features have **no OS runtime dependency**: `if`/`switch` expressions, macros, parameter packs, `consume` / `borrowing` / `consuming`, noncopyable types, `package` access level, strict concurrency checking, `InlineArray`, `Span`, Swift Testing, trailing closure forward scan, typed throws, `BitwiseCopyable`.

### Runtime-dependent features (require minimum OS)

**Concurrency (async/await, actors)**: iOS 13+/macOS 10.15+ via back-deployment library; natively iOS 15+/macOS 12+. **Observation (`@Observable`)**: **iOS 17+ / macOS 14+**. **SwiftData**: **iOS 17+ / macOS 14+**. **`#Predicate`**: iOS 17+. **`#Expression`**: iOS 18+.

### Cross-platform and ecosystem status

**Server-side Swift** is production-mature — Apple's Password Monitoring Service migrated Java → Swift with **40% performance improvement** and 85% code reduction. Vapor, gRPC Swift 2, and a unified Foundation implementation across Linux and Apple platforms are stable. **Linux** has first-class support with Foundation parity. **Windows** is maturing with official VS Code extension support. **Android** has an official Swift SDK (early preview, daily snapshot builds). **WebAssembly** gained first-class support in Swift 6.2. **Embedded Swift** targets Swift 6.3 for major maturation.

Swift 6.2's Approachable Concurrency significantly lowers the adoption barrier. NSA/CISA recommend Swift alongside Rust as a **memory-safe language**. Xcode 17's default project template enables MainActor isolation and the full Approachable Concurrency suite.

> **Changed from Swift 5.x**: WebAssembly and Android are new platform targets. Server-side Swift moved from experimental to production-proven. Observation framework requires iOS 17+ (no back-deployment). Swift 6.2's compile-time features (concurrency defaults, Span, InlineArray) back-deploy freely.

---

## Reference List

### Swift Evolution Proposals

| Proposal | Title |
|----------|-------|
| SE-0185 | Synthesizing Equatable and Hashable conformance |
| SE-0244 | Opaque Result Types |
| SE-0274 | Concise Magic File Names |
| SE-0279 | Multiple Trailing Closures |
| SE-0286 | Forward-scan Matching for Trailing Closures |
| SE-0295 | Codable Synthesis for Enums with Associated Values |
| SE-0298 | Async/Await Sequences |
| SE-0302 | Sendable and @Sendable Closures |
| SE-0303 | Package Manager Build Tool Plugins |
| SE-0304 | Structured Concurrency |
| SE-0306 | Actors |
| SE-0313 | Improved Control over Actor Isolation |
| SE-0314 | AsyncStream and AsyncThrowingStream |
| SE-0316 | Global Actors |
| SE-0325 | Additional Package Plugin APIs |
| SE-0332 | Package Manager Command Plugins |
| SE-0335 | Introduce Existential `any` |
| SE-0337 | Incremental Migration to Concurrency Checking |
| SE-0341 | Opaque Parameter Declarations |
| SE-0345 | `if let` Shorthand for Shadowing an Existing Optional Variable |
| SE-0346 | Lightweight Same-type Requirements for Primary Associated Types |
| SE-0352 | Implicitly Opened Existentials |
| SE-0354 | Regex Literals |
| SE-0358 | Primary Associated Types in the Standard Library |
| SE-0362 | Piecemeal Adoption of Upcoming Language Improvements |
| SE-0364 | Warning for Retroactive Conformances of External Types |
| SE-0366 | `consume` Operator to End the Lifetime of a Variable Binding |
| SE-0376 | Function Back Deployment |
| SE-0377 | `borrowing` and `consuming` Parameter Ownership Modifiers |
| SE-0380 | `if` and `switch` Expressions |
| SE-0381 | DiscardingTaskGroups |
| SE-0382 | Expression Macros |
| SE-0383 | Deprecate @UIApplicationMain and @NSApplicationMain |
| SE-0386 | New Access Modifier: `package` |
| SE-0388 | Convenience Async[Throwing]Stream.makeStream Methods |
| SE-0389 | Attached Macros |
| SE-0390 | Noncopyable Structs and Enums |
| SE-0393 | Value and Type Parameter Packs |
| SE-0395 | Observation |
| SE-0397 | Freestanding Declaration Macros |
| SE-0398 | Allow Generic Types to Abstract Over Packs |
| SE-0399 | Tuple of Value Pack Expansion |
| SE-0401 | Remove Actor Isolation Inference Caused by Property Wrappers |
| SE-0402 | Extension Macros |
| SE-0407 | Member Macro Conformances |
| SE-0408 | Pack Iteration |
| SE-0409 | Access-level Modifiers on Import Declarations |
| SE-0411 | Isolated Default Value Expressions |
| SE-0412 | Strict Concurrency for Global Variables |
| SE-0413 | Typed Throws |
| SE-0414 | Region Based Isolation |
| SE-0415 | Function Body Macros |
| SE-0418 | Inferring Sendable for Methods and Key Path Literals |
| SE-0421 | Generalize Effect Polymorphism for AsyncSequence and AsyncIteratorProtocol |
| SE-0423 | Dynamic Actor Isolation Enforcement from Non-strict-concurrency Contexts |
| SE-0426 | BitwiseCopyable |
| SE-0427 | Noncopyable Generics |
| SE-0430 | `sending` Parameter and Result Values |
| SE-0431 | `@isolated(any)` Function Types |
| SE-0432 | Borrowing and Consuming Pattern Matching for Noncopyable Types |
| SE-0434 | Usability of Global-Actor-Isolated Types |
| SE-0437 | Noncopyable Standard Library Primitives |
| SE-0441 | Swift Language Version Naming |
| SE-0443 | Fine-Grained Diagnostic Control |
| SE-0444 | Member Import Visibility |
| SE-0446 | Nonescapable Types |
| SE-0447 | Span: Safe Access to Contiguous Storage |
| SE-0449 | Allow Nonisolated to Prevent Global Actor Inference |
| SE-0450 | Package Traits |
| SE-0452 | Integer Generic Parameters |
| SE-0456 | Span-Providing Properties on Standard Library Types |
| SE-0461 | Nonisolated Nonsending By Default |
| SE-0465 | Nonescapable Standard Library Primitives |
| SE-0466 | Default Actor Isolation |
| SE-0467 | MutableSpan and MutableRawSpan |
| SE-0470 | Infer Isolated Conformances |
| SE-0474 | Yielding Accessors |
| SE-0476 | `@abi` Attribute |
| SE-0480 | Per-Target Warning Control in SwiftPM |

### WWDC Sessions

| Session | Year | Title |
|---------|------|-------|
| WWDC24 | 2024 | What's New in Swift |
| WWDC24 | 2024 | Migrate Your App to Swift 6 |
| WWDC24 | 2024 | A Swift Tour: Explore Swift's Features and Design |
| WWDC24 | 2024 | Meet Swift Testing |
| WWDC25 | 2025 | What's New in Swift (Session 245) |
| WWDC25 | 2025 | Embracing Swift Concurrency |

### Key URLs

| Resource | URL |
|----------|-----|
| Swift Blog | https://www.swift.org/blog/ |
| Swift 6.0 Announcement | https://www.swift.org/blog/announcing-swift-6/ |
| Swift 6.1 Release | https://www.swift.org/blog/swift-6.1-released/ |
| Swift 6.2 Release | https://www.swift.org/blog/swift-6.2-released/ |
| Swift Evolution Dashboard | https://www.swift.org/swift-evolution/ |
| Swift Migration Guide | https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/ |
| API Design Guidelines | https://www.swift.org/documentation/api-design-guidelines/ |
| Apple: Adopting Swift 6 | https://developer.apple.com/documentation/swift/adoptingswift6 |
| Apple: What's New in Swift | https://developer.apple.com/swift/whats-new/ |
| Swift Evolution GitHub | https://github.com/swiftlang/swift-evolution |
| Upcoming Feature Flags Cheatsheet | https://github.com/treastrain/swift-upcomingfeatureflags-cheatsheet |
