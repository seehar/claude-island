---
type: "agent_requested"
description: "Modern Swift 6.3.x Coding Guidelines"
---

# Swift 6.3 Authoritative Reference for Greenfield Projects

**Swift 6.3 shipped March 24, 2026.** This document captures every major language feature, idiomatic pattern, and best practice an AI coding agent needs to scaffold or contribute to a new Swift project. Each section provides prescriptive directives, short code examples, and explicit callouts for anything deprecated or superseded relative to Swift 5.x or earlier 6.x releases.

---

## 1. Strict concurrency model (complete)

Swift 6 enforces data-race safety at compile time. Swift 6.2 introduced "Approachable Concurrency" (SE-0461, SE-0466) that dramatically simplifies the model. Swift 6.3 adds module selectors (SE-0491) to resolve naming conflicts with concurrency types.

### Sendable conformance

Use **value types** (structs, enums) as the default — they receive automatic `Sendable` inference when all stored properties are `Sendable`. Use `final class` with only immutable `let` stored `Sendable` properties for the few cases requiring reference semantics. Prefer `Mutex<T>` from the `Synchronization` framework over `@unchecked Sendable` when wrapping mutable state in a class.

```swift
import Synchronization

final class ThreadSafeCache: Sendable {
    private let store = Mutex<[String: Int]>([:])
    func get(_ key: String) -> Int? { store.withLock { $0[key] } }
    func set(_ key: String, _ val: Int) { store.withLock { $0[key] = val } }
}
```

Reserve `@unchecked Sendable` for types whose thread safety is guaranteed by external mechanisms (OS locks, dispatch queues) that the compiler cannot verify. Use `nonisolated(unsafe)` as a targeted escape hatch for individual stored properties rather than marking an entire type `@unchecked Sendable`. With **region-based isolation** (SE-0414) and `sending` (SE-0430), many types no longer need explicit `Sendable` conformance at all — the compiler proves safety at each use site.

### Actor isolation rules

Use `actor` to protect shared mutable state with a dedicated serial executor. Use **`@MainActor`** to isolate UI-related code; in Swift 6.2+ greenfield projects, set `@MainActor` as the default isolation for app targets so all code is implicitly main-actor-isolated. Use `nonisolated` to opt individual declarations out of inherited isolation. Use `@concurrent` (SE-0461) to explicitly request background execution for CPU-heavy async work.

```swift
// Swift 6.2+ greenfield app target
class ViewModel { // implicitly @MainActor
    var items: [Item] = []
    func refresh() async { items = await fetchItems() }
    nonisolated func pureHash(_ s: String) -> Int { s.hashValue }
    @concurrent func compress(_ data: Data) async -> Data { /* background */ }
}
```

**`nonisolated(nonsending)`** is now the default for nonisolated async functions (SE-0461) — they run on the **caller's** actor instead of hopping to the global concurrent executor. Use `@concurrent` when you genuinely need background execution. Use `@preconcurrency` on imports or protocol conformances to suppress concurrency diagnostics from pre-Swift-6 dependencies; the compiler inserts runtime isolation assertions.

### Region-based isolation (SE-0414)

The compiler performs flow-sensitive data-flow analysis, grouping values into "isolation regions." When a non-`Sendable` value crosses an isolation boundary, the compiler verifies its entire region is **disconnected** — no other live references exist. This eliminates the vast majority of false-positive Sendable warnings that plagued Swift 5.10.

```swift
@MainActor func setup() async {
    let config = NonSendableConfig()   // freshly created, disconnected
    await backgroundProcessor(config)  // ✅ compiler proves safety
    // config cannot be used here — consumed by the transfer
}
```

### `sending` parameters and results (SE-0430)

Use `sending` on a function parameter to require the caller to prove the argument is disconnected. Use `sending` on a return value to guarantee the callee returns a disconnected value. Many concurrency APIs (including `Task.init`) now use `sending` closures, which is why non-`Sendable` captures work in `Task { }` blocks in Swift 6.

```swift
func transfer(_ value: sending NonSendableType) async { /* can cross isolation */ }
func produce() -> sending NonSendableType { NonSendableType() }
```

### Task groups — idiomatic patterns

Use `TaskGroup` / `ThrowingTaskGroup` when child task results must be collected. Use **`DiscardingTaskGroup` / `ThrowingDiscardingTaskGroup`** (SE-0381) for fire-and-forget child tasks — they prevent unbounded memory growth from accumulated results, making them ideal for servers and event loops.

```swift
try await withThrowingDiscardingTaskGroup { group in
    for conn in try await server.accept() {
        group.addTask { try await handle(conn) }
    }
}
```

Limit concurrency by seeding a fixed number of tasks upfront and adding new tasks as each completes via `group.next()`.

### Structured vs. unstructured concurrency

Prefer **`async let`** for a known number of parallel operations. Prefer **`TaskGroup`** for a dynamic number. Use unstructured `Task { }` only to bridge synchronous → asynchronous contexts (e.g., SwiftUI `.task`, `viewDidLoad`). It inherits actor isolation, priority, and task-local values. Use `Task.detached` only when you must avoid inheriting the current actor — this is rare.

### AsyncSequence and AsyncStream

Use the **primary associated type** syntax (SE-0421) for opaque return types: `some AsyncSequence<Element, Never>`. Use `AsyncStream.makeStream()` factory for cleaner producer/consumer separation.

```swift
func events() -> some AsyncSequence<Event, Never> {
    let (stream, cont) = AsyncStream<Event>.makeStream()
    monitor.onEvent { cont.yield($0) }
    monitor.onDone { cont.finish() }
    return stream
}
```

### Concurrency configuration for greenfield projects

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "MyApp",
    targets: [
        .executableTarget(
            name: "MyApp",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),            // SE-0466
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .target(name: "Networking") // library: no default isolation
    ]
)
```

For **app targets**, use `MainActor` default isolation. For **library targets**, omit `.defaultIsolation` to keep the nonisolated default.

### Module selectors for concurrency disambiguation (SE-0491)

Use `Swift::Task` to disambiguate when a dependency or your own code shadows the standard library `Task`:

```swift
import MyModule // also defines a "Task" type
let swiftTask = Swift::Task { await work() }
let myTask = MyModule::Task(name: "custom")
```

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 5.x: Sendable checking opt-in; actors experimental. No region-based analysis.
> - Swift 6.0: Strict concurrency enforced as errors. Region-based isolation (SE-0414) and `sending` (SE-0430) dramatically reduce false positives. `DiscardingTaskGroup` available.
> - Swift 6.2: `nonisolated(nonsending)` default (SE-0461). Default `@MainActor` isolation per target (SE-0466). `@concurrent` attribute introduced.
> - Swift 6.3: Module selectors (`::`) for naming conflicts (SE-0491). Async calls now permitted in `defer` bodies (SE-0493).

---

## 2. Ownership, borrowing, and noncopyable types

### Declaring `~Copyable` types

Suppress the implicit `Copyable` conformance with `~Copyable`. Use `consuming` on methods that end the value's lifetime, `borrowing` for read-only access, and `mutating` for in-place changes. The compiler enforces that consumed values are never used afterward.

```swift
struct FileHandle: ~Copyable {
    private let fd: CInt
    init(path: String) throws { fd = open(path, O_RDONLY) }
    borrowing func read(_ n: Int) -> Data { /* read without ownership transfer */ }
    consuming func close() { Darwin.close(fd) }
    deinit { Darwin.close(fd) }
}
```

### `~Escapable` types and lifetime dependencies

`~Escapable` types (SE-0446) cannot be stored or returned beyond their immediate context, enabling safe non-owning views. **`Span<T>`** (SE-0447, SE-0456) is the canonical `~Escapable` type — a bounds-checked, non-owning view into contiguous memory. Use `.span` properties instead of `withUnsafeBufferPointer` closures. The `@lifetime` attribute is available as a supported experimental feature in Swift 6.2+ for defining custom lifetime dependencies on returned non-escapable values.

### Noncopyable generics (SE-0427)

Suppress `Copyable` on generic parameters with `~Copyable`. Provide conditional `Copyable` conformance when the wrapped type is `Copyable`:

```swift
struct Box<T: ~Copyable>: ~Copyable {
    var value: T
    consuming func take() -> T { value }
}
extension Box: Copyable where T: Copyable {}
```

`Optional` and `Result` are already generalized for `~Copyable` wrapped types (SE-0437, SE-0465).

### SE-0499: Noncopyable standard library protocol support

**`Equatable`, `Hashable`, `Comparable`, `CustomStringConvertible`, `CustomDebugStringConvertible`, and `Error`** now accept `~Copyable` and `~Escapable` conforming types. This unblocks noncopyable numeric types, unique resources, and containers like `InlineArray` and `Span` for conditional `Hashable` conformance. Operator requirements use `borrowing` parameters:

```swift
struct UniqueToken: ~Copyable, Hashable {
    let id: UInt64
    static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
```

String interpolation now works with `~Copyable` types conforming to `CustomStringConvertible`.

### Practical patterns

Use noncopyable types for **unique file handles**, **database transactions** (`consuming func commit()` / `consuming func rollback()` ensures exactly-once semantics), **state machines** (consuming transitions prevent invalid reuse), and **exclusive resources** (locks, atomics). Prefer noncopyable types over actors when you need compile-time uniqueness enforcement rather than runtime isolation. Prefer noncopyable types over reference types when you want to eliminate reference counting overhead entirely.

### Current limitations

Classes and actors cannot be `~Copyable`. Standard `Array<~Copyable>` is not yet available. `Codable` has not been generalized for `~Copyable`. Adding `~Copyable` to an existing generic parameter is generally ABI-breaking.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 5.9: Basic `~Copyable` structs/enums; no generics, no protocol conformances.
> - Swift 6.0: Noncopyable generics (SE-0427), pattern matching (SE-0432), Optional/Result support (SE-0437).
> - Swift 6.2: `Span<T>` and `~Escapable` types; experimental `@lifetime`.
> - Swift 6.3 (SE-0499): `Equatable`, `Hashable`, `Comparable`, string protocols now support `~Copyable` and `~Escapable`.

---

## 3. Typed throws and error handling

### `throws(ErrorType)` syntax (SE-0413)

Use typed throws for **module-internal code** requiring exhaustive error handling, **generic pass-through functions** that propagate but never originate errors, and **constrained environments** (Embedded Swift). Prefer untyped `throws` for public library APIs to preserve evolution flexibility.

```swift
enum ParseError: Error { case badFormat, overflow }

func parse(_ s: String) throws(ParseError) -> Int {
    guard let n = Int(s) else { throw .badFormat }
    guard n < 1_000_000 else { throw .overflow }
    return n
}
// Exhaustive catch — no catch-all needed:
do { let n = try parse(input) }
catch .badFormat { /* handle */ }
catch .overflow { /* handle */ }
```

`throws(any Error)` is equivalent to plain `throws`. `throws(Never)` is equivalent to a non-throwing function. Only one concrete error type is permitted per `throws` clause.

### Typed throws subsumes `rethrows`

Typed throws with a generic error parameter is the modern replacement for `rethrows`:

```swift
func map<U, E>(_ transform: (Wrapped) throws(E) -> U) throws(E) -> U?
```

When `E` is inferred as `Never`, the function becomes non-throwing — strictly more expressive than `rethrows`, which cannot handle stored closures.

### Decision tree: typed throws vs. untyped throws vs. Result

Use **untyped `throws`** as the default for most code — it is more flexible and easier to evolve. Use **`throws(ConcreteError)`** in internal code, generic wrappers, and Embedded Swift. Use **`Result<Success, Failure>`** primarily at API boundaries where callers need to store or pass errors as values, or when bridging callback-based APIs; typed throws largely supersedes `Result` for new code.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 5.x: All throws untyped. Exhaustive catching impossible. `rethrows` was the only error-propagation mechanism for higher-order functions.
> - Swift 6.0 (SE-0413): `throws(ErrorType)` syntax. Dot-syntax in throw expressions. Generic error propagation.

---

## 4. Type system and generics

### Parameter packs (variadic generics)

Use `each T` to declare a type parameter pack and `repeat each T` for expansion (SE-0393, SE-0398, SE-0399). Pack iteration via `for-in` over `repeat each` is available since Swift 5.9.

```swift
func allEqual<each T: Equatable>(_ a: repeat each T, _ b: repeat each T) -> Bool {
    for pair in repeat (each a, each b) {
        guard pair.0 == pair.1 else { return false }
    }
    return true
}
```

Parameter packs eliminated SwiftUI's 10-view limit and hundreds of standard library overloads. Current limitation: stored properties cannot contain bare pack expansions (only inside tuple or function types).

### `some` vs. `any` decision tree

| Situation | Use |
|---|---|
| Single concrete type, hidden from caller | `some Protocol` or `<T: Protocol>` |
| Heterogeneous collection | `[any Protocol]` |
| Protocol with associated types in collection | `any Protocol<ConcreteAssoc>` |
| Performance-critical hot path | Prefer `some` / generics (static dispatch) |

Swift 6 **requires** the `any` keyword for existential types (SE-0335). Bare protocol names as types produce errors.

### Primary associated types and constrained existentials

Use `any Collection<Int>` or `some Sequence<String>` to constrain protocols with primary associated types (SE-0346, SE-0353). Standard library examples: `Sequence<Element>`, `Collection<Element>`, `Identifiable<ID>`.

### `@retroactive` conformances (SE-0364)

When conforming a foreign type to a foreign protocol in your module, annotate with `@retroactive` to silence the warning:

```swift
extension Date: @retroactive Identifiable {
    public var id: Date { self }
}
```

### Synthesized conformance rules

**`Equatable`, `Hashable`**: Auto-synthesized for structs/enums when all stored properties/associated values conform. **`Codable`**: Auto-synthesized when all stored properties conform. **`BitwiseCopyable`** (SE-0426): Auto-inferred for non-public types with all-BitwiseCopyable stored properties; public types require explicit declaration or `@frozen`.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 5.6: `any` keyword introduced as optional. Swift 6.0: `any` required (SE-0335).
> - Swift 5.9: Parameter packs introduced. Swift 6.0: Pack iteration.
> - Swift 6.0: `BitwiseCopyable` marker protocol. `@retroactive` annotation.

---

## 5. Macros

### Macro categories

**Freestanding** (prefixed with `#`): `@freestanding(expression)` produces a value; `@freestanding(declaration)` produces declarations. **Attached** (prefixed with `@`): `@attached(peer)`, `@attached(member)`, `@attached(accessor)`, `@attached(memberAttribute)`, `@attached(extension)`, `@attached(body)` (SE-0415 — at most one body macro per function). A single macro can inhabit multiple attached roles.

### Built-in macros

Use **`@Observable`** for data-model classes with fine-grained property tracking. Use **`#Preview`** for Xcode canvas previews. Use **`#Predicate`** for type-safe filtering predicates (Foundation). Use **`@Test`** and **`#expect`** for Swift Testing assertions.

### When to write a custom macro

Use macros to **eliminate boilerplate across types** — generating conformances, members, accessors, or performing compile-time validation. Use **property wrappers** for per-property runtime behavior (clamping, lazy init, UserDefaults bridging). Use **protocol conformance with synthesized implementations** when a shared interface with minimal generated code suffices. Macros are the highest-complexity option; reach for them only when simpler mechanisms fall short.

### Macro testing with `assertMacroExpansion`

```swift
import SwiftSyntaxMacrosTestSupport

let testMacros: [String: Macro.Type] = ["URL": URLMacro.self]
assertMacroExpansion(
    "#URL(\"https://swift.org\")",
    expandedSource: "URL(string: \"https://swift.org\")!",
    macros: testMacros
)
```

Point-Free's `swift-macro-testing` package provides a more ergonomic alternative that auto-records expected output on first run and works with both XCTest and Swift Testing.

### Prebuilt swift-syntax for shared macro libraries (new in 6.3)

SwiftPM 6.3 extends prebuilt swift-syntax support to **shared libraries used only by macro targets**. Factor out common macro implementation code into a library; SwiftPM downloads pre-compiled swift-syntax binaries instead of building from source, reducing clean builds from 30–60 seconds to seconds. SwiftPM auto-detects when such a library is used by non-macro targets and disables prebuilts to avoid link-time conflicts.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 5.9: Macro system introduced (SE-0382, SE-0389, SE-0394, SE-0397).
> - Swift 6.0: `@attached(body)` macros (SE-0415).
> - Swift 6.2: Prebuilt swift-syntax binary support.
> - Swift 6.3: Prebuilt support extended to shared macro libraries.

---

## 6. Data flow and observation (SwiftUI context)

### `@Observable` as the default

Use **`@Observable`** (SE-0395, Observation framework) for all new data-model classes targeting iOS 17+ / macOS 14+. It replaces the entire `ObservableObject` / `@Published` / `@ObservedObject` stack. The key advantage is **fine-grained reactivity**: SwiftUI tracks which specific properties `body` reads and only re-renders when those change — unlike `ObservableObject`, which re-renders on any `@Published` change.

```swift
@Observable class CounterModel {
    var count = 0
    @ObservationIgnored var cache: [String] = [] // not tracked
}

struct CounterView: View {
    @State private var model = CounterModel()
    var body: some View {
        Button("Count: \(model.count)") { model.count += 1 }
    }
}
```

### Property wrapper mapping

| Scenario | Observation (iOS 17+) | Legacy (iOS 13+) |
|---|---|---|
| View owns model | `@State` | `@StateObject` |
| View receives model (read) | plain `let` / `var` | `@ObservedObject` |
| View needs binding | `@Bindable` | `@ObservedObject` + `$` |
| Environment sharing | `.environment(model)` + `@Environment(Type.self)` | `.environmentObject` + `@EnvironmentObject` |

### When `@ObservationTracked` / `@ObservationIgnored` matter

`@ObservationTracked` is auto-applied by the `@Observable` macro — never write it manually. Use **`@ObservationIgnored`** on stored properties that should not trigger view updates: caches, Combine cancellables, injected dependencies. Computed properties derive tracking from the stored properties they access.

### SwiftData model patterns

`@Model` implicitly includes `@Observable` behavior. Use `@Query` for fetching and `@Bindable` for editing:

```swift
@Model class Movie {
    var title: String
    var year: Int
    init(title: String, year: Int) { self.title = title; self.year = year }
}

struct EditView: View {
    @Bindable var movie: Movie
    var body: some View { TextField("Title", text: $movie.title) }
}
```

> **Changed from Swift 5.x / earlier 6.x:**
> - `ObservableObject`/`@Published` (Combine-based): Still works but deprecated in spirit for iOS 17+ targets.
> - `@Observable` (SE-0395): Macro-based, fine-grained tracking, no Combine dependency.
> - `@StateObject` → `@State`; `@ObservedObject` → plain property or `@Bindable`; `.environmentObject` → `.environment`.
> - Property wrapper isolation inference removed (SE-0401) — `@StateObject` no longer infers `@MainActor`.

---

## 7. Swift Testing framework

### `import Testing` vs. legacy XCTest

Use **`import Testing`** for all new test targets. It ships with the Swift 6 toolchain — no package dependency needed. It supports macOS, Linux, Windows, and Android. Reserve XCTest for **UI automation tests**, **performance tests** (`XCTMetric`), and incremental migration of existing test suites. The two frameworks coexist in the same target but their assertions must not be mixed.

### Core patterns

Use `@Test` on free functions or struct methods. Use `@Suite` on structs for grouping (structs preferred over classes — each test gets a fresh instance). Use `#expect` for soft assertions and `try #require` for hard assertions that stop the test on failure.

```swift
@Suite("Authentication")
struct AuthTests {
    @Test("Valid credentials succeed", .tags(.smoke))
    func validLogin() async throws {
        let result = try await Auth.login(user: "admin", pass: "secret")
        #expect(result.isAuthenticated)
    }

    @Test(arguments: ["", " ", "x"])
    func invalidPassword(_ pass: String) async throws {
        #expect(throws: AuthError.self) { try await Auth.login(user: "admin", pass: pass) }
    }
}
```

### Traits

Use `.disabled("reason")` to skip, `.enabled(if: condition)` for conditional execution, `.tags(.name)` for categorization, `.bug("URL", "title")` to link to issue trackers, `.timeLimit(.minutes(1))` for time bounds, and `.serialized` to force sequential execution within a suite.

### Parameterized tests

Pass up to two argument collections via `@Test(arguments:)`. Use `zip()` to pair arguments instead of the default Cartesian product. Arguments must be `Sendable`.

### Confirmation-based async testing

Use `confirmation(expectedCount:)` as the replacement for XCTest expectations:

```swift
await confirmation(expectedCount: 1) { confirm in
    sut.onComplete { confirm() }
    sut.start()
}
```

### New in Swift 6.3

**Warning issues (ST-0013):** Record non-failing warnings with `Issue.record("msg", severity: .warning)`. **Test cancellation (ST-0016):** Cancel mid-test with `try Test.cancel()` (entire test) or `try Test.Case.cancel()` (single parameterized argument). **Exit test value capturing (ST-0012):** Exit test closures can now capture `Codable` values from the enclosing context. **Image attachments (ST-0014, ST-0015, ST-0017):** Attach `CGImage`, `UIImage`, `NSImage`, and Windows-native image types via cross-import overlays. **SourceLocation filePath (ST-0020):** `SourceLocation` now exposes `filePath` (full filesystem path) alongside `fileID`, critical for snapshot testing tools.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 6.0: Swift Testing introduced (`@Test`, `#expect`, `@Suite`).
> - Swift 6.1: `confirmation(expectedCount:)` ranges (ST-0005), error return from `#expect(throws:)` (ST-0006), test scoping traits (ST-0007).
> - Swift 6.2: Exit tests (ST-0008), attachments (ST-0009).
> - Swift 6.3: Warning severity, test cancellation, image attachments, exit test value capturing, SourceLocation filePath.

---

## 8. Package and module structure

### Package.swift conventions (tools-version 6.0+)

Use `swiftLanguageModes: [.v6]` (SE-0441) at the package level or `.swiftLanguageMode(.v6)` per target. Enable upcoming features incrementally via `.enableUpcomingFeature("FeatureName")`. Key upcoming features: `InternalImportsByDefault`, `ExistentialAny`, `BareSlashRegexLiterals`, `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`.

### Access control defaults in 6.x

In Swift 6 language mode, **imports default to `internal`** (SE-0409, `InternalImportsByDefault`). This prevents accidental leaking of dependency types through your public API. Use `public import` explicitly when re-exporting. The **`package`** access level (SE-0386) provides cross-target visibility within the same Swift package — prefer it over `public` for inter-target APIs.

### When to split into multiple modules

Split when: build parallelism matters (independent modules compile concurrently), you need `package` access boundaries, or distinct areas have different concurrency isolation needs (e.g., a `Networking` module without `@MainActor` default vs. an app module with it). Keep modules coarse enough to avoid excessive import overhead.

### New in Swift 6.3

**SwiftBuild preview:** A unified build engine integrated into SwiftPM, activated via `--build-system swiftbuild`. It replaces the native build system with a consistent cross-platform experience based on llbuild. The native build system remains the default in 6.3. Packages that build with the native system should work without changes.

```bash
swift build --build-system swiftbuild
swift test --build-system swiftbuild
```

**Discoverable package traits:** `swift package show-traits` lists traits a package supports. **Flexible inherited documentation:** Command plugins generating symbol graphs now control whether inherited documentation is included. **C interop build plugins (experimental):** SwiftPM supports generating C source files, module maps, and headers from build tool plugins into C targets. Enable via `// swift-tools-version: 6.3;(experimentalCGen)`.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 5.x: Imports default to `public`. No `package` access level.
> - Swift 6.0: `InternalImportsByDefault`, `package` access level, access-level imports (SE-0409).
> - Swift 6.1: Package traits.
> - Swift 6.3: SwiftBuild preview, C-source plugin generation, prebuilt swift-syntax for macro libraries, `show-traits` command.

---

## 9. C/C++ interoperability and the `@c` attribute

### SE-0495: `@c` attribute

Use `@c` to expose Swift global functions and enums to C code. Use `@c(SymbolName)` for custom C symbol naming. The declaration appears in the generated C compatibility header requested via `-emit-clang-header-path`.

```swift
@c(MyLib_init)
func initialize(config: CInt) -> Bool { /* ... */ true }
// Generated header: bool MyLib_init(int config);

@c enum Status: CInt { case ok, error, timeout }
// Generated C names: StatusOk, StatusError, StatusTimeout
```

### `@c` + `@implementation`

Provide a Swift body for a function already declared in a C header. The compiler validates that the Swift signature matches the C declaration:

```swift
// C header: int process_buffer(const void *buf, size_t len);
@c @implementation
func process_buffer(_ buf: UnsafeRawPointer, _ len: Int) -> CInt { /* ... */ }
```

### Migration from `@_cdecl`

`@_cdecl` is effectively superseded by `@c`. Replace `@_cdecl("name")` with `@c(name)` for stricter C-only type checking, or `@objc(name)` for Objective-C-compatible behavior. Note: `@_cdecl` emits two symbols; switching to `@c` is technically ABI-breaking.

### `@objc` vs. `@c`

Use `@objc` for Objective-C interop (classes, methods, protocols, message dispatch). Use `@c` for pure C interop (global functions, enums, C calling convention). `@c` is the correct choice for non-Objective-C C codebases and Embedded Swift.

### Span and safe buffer access

Prefer **`Span<T>`** (SE-0447) over `UnsafeBufferPointer` for new code. Access via `.span` properties on `Array`, `ContiguousArray`, `InlineArray`, and `Data`. C/C++ headers with bounds annotations (`__counted_by`, `__sized_by`) automatically bridge to `Span<T>` / `RawSpan`. The `@safe` attribute marks C APIs as safe when they have been audited.

> **Changed from Swift 5.x / earlier 6.x:**
> - `@_cdecl`: Underscore-prefixed, unofficial. Now superseded by `@c` (SE-0495) in Swift 6.3.
> - `@_alwaysEmitIntoClient`: Superseded by `@export(implementation)` (SE-0497).
> - `UnsafeBufferPointer` → `Span`: Safe, bounds-checked, non-escapable replacement introduced in Swift 6.2.
> - Swift 6.3: `@c` attribute formalized. Improved tolerance for C signature mismatches.

---

## 10. Module selectors (SE-0491)

### `ModuleName::symbol` syntax

Use `::` to prefix any declaration reference with its source module name. This resolves ambiguities that the dot-based syntax (`Module.Type`) cannot handle, particularly when a module contains a type with the same name as the module itself.

```swift
import XCTest  // module "XCTest" contains class "XCTest"
let testCase: XCTest::XCTestCase = MyTests()
```

### When required vs. optional

Module selectors are **required** when the compiler cannot otherwise resolve ambiguity — two imported modules export identically named top-level declarations. They are **optional** in all other cases; prefer clean, unqualified names when no ambiguity exists. Avoid API designs that force clients to use module selectors; rename conflicting declarations instead.

### Accessing Swift standard library types

Use `Swift::Task`, `Swift::Duration`, or `Swift::String` to unambiguously reference standard library types when imports shadow them:

```swift
import MyFramework  // defines its own Duration type
let timeout: Swift::Duration = .seconds(30)
```

### Relationship to fully qualified names

Module selectors (`A::foo`) skip all enclosing scopes and begin lookup at the module's top level. The older dot syntax (`A.foo`) first checks if `A` is a local scope or type before falling back to module lookup. Prefer module selectors when disambiguation is the explicit intent.

> **Changed from Swift 5.x / earlier 6.x:**
> - Entirely new in Swift 6.3. Previously, name collisions could only be resolved via dot-qualified names, which failed for module-type name conflicts.

---

## 11. Naming, style, and idiom

### API Design Guidelines

The official swift.org API Design Guidelines remain current and unchanged in substance. Core principle: **clarity at the point of use**. Name by role not type. Use mutating/nonmutating pairs (verb: `sort()`/`sorted()`; noun: `union()`/`formUnion()`). Booleans read as assertions (`isEmpty`, `canDecode`). Types and protocols use `UpperCamelCase`; everything else uses `lowerCamelCase`.

### `if`/`switch` expressions (SE-0380)

Prefer `if`/`switch` expressions over ternary operators for multi-line or complex conditions. Each branch must be a single expression; `else` is required for `if` expressions:

```swift
let label = switch state {
    case .loading: "Loading…"
    case .loaded(let n): "\(n) items"
    case .error: "Failed"
}
```

### `guard` vs. `if let` vs. `Optional.map`

Use **`guard let`** for early exits at function entry — unwrapped values stay in scope. Use **`if let`** for conditional branching where both paths do meaningful work. Use **`Optional.map`** / `.flatMap` for concise functional transforms: `url.map { URLRequest(url: $0) }`. Use the Swift 5.7 shorthand (`guard let value` instead of `guard let value = value`).

### `consume` keyword usage

For `~Copyable` types, `consume` is implicit when passing to `consuming` parameters but can be written explicitly for clarity. For copyable types, `consuming` / `borrowing` annotations are performance hints for library authors — most app code should not need them.

### File and type naming conventions

Name files after their primary type (`NetworkManager.swift`). Name extensions with the pattern `Type+Protocol.swift` or `Type+Feature.swift`. Actors, global actors, noncopyable types, and macros follow the same `UpperCamelCase` convention as other types — no special prefix or suffix is needed.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 5.7: `if let value` shorthand (SE-0345). Swift 5.9: `if`/`switch` expressions (SE-0380).
> - Swift 6.0: `any` required for existential types, changing how protocol-as-type names appear in code.

---

## 12. Performance annotations and tuning

### `@specialized` (SE-0460)

Provide pre-specialized implementations of generic APIs for common concrete types. Use `@specialized(where ...)` to generate dispatch stubs that reroute to specialized code at runtime:

```swift
extension Sequence where Element: BinaryInteger {
    @specialized(where Self == [Int])
    @specialized(where Self == [UInt32])
    func sum() -> Double { reduce(0) { $0 + Double($1) } }
}
```

All generic parameters must be fully bound in the `where` clause. Adding or removing `@specialized` has **no ABI impact** — it is purely a performance optimization. Use it in library code where callers pass existentials or cross ABI-stable boundaries that prevent the optimizer from specializing.

### `@inline(always)` (SE-0496)

Guarantee inlining for direct calls. Produces **compile-time errors** if inlining is definitively impossible (stronger than the unofficial `@inline(__always)` which was a mere hint). For `public` / `package` functions, `@inline(always)` implies `@inlinable`. Use only when the code-size trade-off is worthwhile — typically tiny hot-path functions:

```swift
@inline(always)
func fastClamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
```

### `@export` (SE-0497)

**`@export(implementation)`** makes a function's body available to client modules for specialization, inlining, and analysis. It formalizes and subsumes `@_alwaysEmitIntoClient`. The function body becomes part of the module interface. **`@export(interface)`** ensures only a callable symbol is emitted — the implementation remains hidden. This is critical for Embedded Swift's linkage model, where definitions are otherwise always visible to clients.

### `@inlinable`, `@usableFromInline`, `@frozen`

Use **`@inlinable`** on public hot-path functions when the body can be frozen. Use **`@usableFromInline`** to expose internal helpers to `@inlinable` code without making them public. Use **`@frozen`** on structs/enums whose stored property layout will never change. For source-only SPM packages, these annotations are safe to use liberally since clients always recompile. For ABI-stable frameworks, each is a permanent commitment.

### `borrowing` / `consuming` guidance for library authors

For copyable types, the compiler defaults are optimal in most cases. Add ownership annotations only in performance-critical paths where you need guaranteed ARC elimination. For `~Copyable` types, ownership modifiers are mandatory and dictate the calling convention.

### Access level and optimization

Start with the most restrictive access level that works. `private` / `fileprivate` enable inlining within the file. `internal` enables whole-module optimization. **`package`** enables cross-target optimization within a package. `public` without `@inlinable` requires dynamic dispatch in resilient/ABI-stable contexts.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 6.3: `@specialized` (SE-0460), `@inline(always)` (SE-0496), and `@export` (SE-0497) all formalized.
> - `@inline(__always)` → `@inline(always)`: Stronger guarantees, compile-time errors, implies `@inlinable` for public functions.
> - `@_alwaysEmitIntoClient` → `@export(implementation)`: Official, supported replacement.

---

## 13. Embedded Swift

### Section placement control (SE-0492)

Use `@section("name")` to place global variables into named linker sections and `@used` to prevent dead-stripping. Use `#if objectFormat(ELF)` / `objectFormat(MachO)` / `objectFormat(COFF)` / `objectFormat(Wasm)` to conditionalize section names:

```swift
#if objectFormat(MachO)
@section("__DATA,vectors") @used
#elseif objectFormat(ELF)
@section(".vectors") @used
#endif
let vectorTable: UInt32 = 0x2000_0000
```

This enables placing vector tables, boot2 sections, and hardware-required data structures at specific addresses — previously requiring C.

### Pure-Swift floating-point printing

`description` and `debugDescription` for `Float` and `Double` are now available in Embedded Swift via a new all-Swift implementation with no C library dependency.

### `@c` in embedded contexts

Use `@c` (SE-0495) to define C-compatible function exports in Embedded Swift. Combined with `@section` and `@used`, this enables fully-Swift bare-metal firmware with zero lines of C.

### Swift MMIO and svd2swift

**Swift MMIO 0.1.x** provides type-safe memory-mapped I/O. The **svd2swift** tool generates Swift MMIO interfaces from CMSIS SVD files, available as a CLI or SwiftPM build plugin. The **SVD2LLDB** plugin enables register-level debugging by name rather than raw address.

### LLDB debugging improvements

Swift 6.3 adds better value printing for Embedded Swift types, `memory read -t TypeName` for rendering addresses as Swift types, core dump inspection of `Dictionary`/`Array` without a live process, native `InlineArray` support, and ARMv7m exception frame unwinding for complete backtraces.

### `EmbeddedRestrictions` diagnostic group

Opt-in warnings that diagnose language constructs unavailable in Embedded Swift (untyped throws, existential generics). Enabled by default in Embedded Swift builds; enable in regular builds for forward compatibility:

```swift
swiftSettings: [.treatWarning("EmbeddedRestrictions", as: .warning)]
```

### Linkage model progress

`@export(interface)` (SE-0497) enables hiding implementations even in Embedded Swift's compilation model. Weak symbol definitions fix duplicate symbol errors in diamond dependency graphs.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 6.3: `@section`/`@used` (SE-0492), `@c` (SE-0495), `@export` (SE-0497), floating-point printing, `EmbeddedRestrictions` diagnostics, enhanced LLDB support, Swift MMIO 0.1.x.

---

## 14. Platform and ecosystem context

### Cross-platform status

**macOS, iOS, tvOS, watchOS, visionOS:** Full support via Xcode. **Linux:** Fully supported; Amazon Linux 2023 AMIs include the Swift toolchain. **Windows:** Maturing support with VS Code extension and LLDB improvements. **Android:** First official Swift SDK for Android shipped with Swift 6.3 — a major milestone enabling native Android programs in Swift and Kotlin/Java integration via Swift Java. **FreeBSD:** Preview support for FreeBSD 14.3+ (x86_64 only). **WebAssembly:** Official Wasm SDK distributed from swift.org since Swift 6.2, with both full and Embedded variants.

### Runtime module: `demangle` (SE-0498)

Use `import Runtime` to access the official `demangle` function for converting mangled Swift symbols to human-readable names:

```swift
import Runtime
if let name = demangle("$sSiN") { print(name) } // "Swift.Int"
```

A buffer-based variant throws `DemanglingError.truncated(requiredBufferSize:)` when the output buffer is too small. C++ demangling is not supported.

### `isTriviallyIdentical(to:)` (SE-0494)

Use this **O(1)** method on copy-on-write types (`Array`, `Dictionary`, `String`, `Set`, `Span`, `RawSpan`) to check whether two values share the same backing storage. It returns `true` only when identity is trivially provable; `false` does not mean the values are unequal. Use as a performance gate before expensive equality checks:

```swift
if !oldData.isTriviallyIdentical(to: newData) && oldData != newData {
    updateUI(newData)
}
```

### Minimum deployment targets

Most Swift 6.3 language features (ownership, typed throws, macros, performance attributes) work across all deployment targets since they are compile-time. Features requiring runtime support include: `Span` and `~Escapable` types (require Swift 6.0+ stdlib), `AsyncSequence` primary associated types (require Swift 6.0+ stdlib), `@Observable` (iOS 17+ / macOS 14+), and `Mutex` (requires Synchronization framework, iOS 18+ / macOS 15+). `@c`, `@section`, `@specialized`, `@inline(always)`, `@export`, and module selectors have **no new runtime requirements** and can be back-deployed.

> **Changed from Swift 5.x / earlier 6.x:**
> - Swift 6.2: Official Wasm SDK, Span types, Swiftly 1.0 toolchain manager.
> - Swift 6.3: First official Android SDK, FreeBSD preview, Swift Build engine preview, `demangle` API (SE-0498), `isTriviallyIdentical(to:)` (SE-0494).

---

## Reference list

### Swift Evolution proposals

| Proposal | Title | Version |
|----------|-------|---------|
| SE-0193 | Cross-module inlining and specialization | 4.2 |
| SE-0279 | Multiple trailing closures | 5.3 |
| SE-0298 | Async/Await: AsyncSequence | 5.5 |
| SE-0302 | Sendable and @Sendable closures | 5.5 |
| SE-0304 | Structured concurrency | 5.5 |
| SE-0306 | Actors | 5.5 |
| SE-0313 | Improved control over actor isolation | 5.5 |
| SE-0314 | AsyncStream and AsyncThrowingStream | 5.5 |
| SE-0335 | Introduce existential `any` | 5.6 |
| SE-0345 | `if let` shorthand for shadowing existing optional | 5.7 |
| SE-0346 | Lightweight same-type requirements for primary associated types | 5.7 |
| SE-0353 | Constrained existential types | 5.7 |
| SE-0362 | Piecemeal adoption of upcoming language improvements | 5.8 |
| SE-0364 | Warning for retroactive conformances | 5.7 |
| SE-0366 | `consume` operator to end lifetime of a variable binding | 5.9 |
| SE-0377 | `borrowing` and `consuming` parameter ownership modifiers | 5.9 |
| SE-0380 | `if` and `switch` expressions | 5.9 |
| SE-0381 | DiscardingTaskGroup | 5.9 |
| SE-0382 | Expression macros | 5.9 |
| SE-0386 | New access modifier: `package` | 5.9 |
| SE-0389 | Attached macros | 5.9 |
| SE-0390 | Noncopyable structs and enums | 5.9 |
| SE-0393 | Value and type parameter packs | 5.9 |
| SE-0394 | Package Manager support for custom macros | 5.9 |
| SE-0395 | Observation | 5.9 |
| SE-0397 | Freestanding declaration macros | 5.9 |
| SE-0398 | Allow generic types to abstract over packs | 5.9 |
| SE-0399 | Tuple of value pack expansion | 5.9 |
| SE-0401 | Remove actor isolation inference from property wrappers | 6.0 |
| SE-0409 | Access-level modifiers on import declarations | 6.0 |
| SE-0413 | Typed throws | 6.0 |
| SE-0414 | Region-based isolation | 6.0 |
| SE-0415 | Function body macros | 6.0 |
| SE-0418 | Inferring Sendable for methods and key path literals | 6.0 |
| SE-0420 | Inheritance of actor isolation | 6.0 |
| SE-0421 | Generalize effect polymorphism for AsyncSequence and AsyncIteratorProtocol | 6.0 |
| SE-0423 | Dynamic actor isolation enforcement | 6.0 |
| SE-0426 | BitwiseCopyable | 6.0 |
| SE-0427 | Noncopyable generics | 6.0 |
| SE-0429 | Partial consumption of noncopyable values | 6.0 |
| SE-0430 | `sending` parameter and result values | 6.0 |
| SE-0432 | Borrowing and consuming pattern matching for noncopyable types | 6.0 |
| SE-0435 | Swift language version per target | 6.0 |
| SE-0436 | `@implementation` attribute for Objective-C categories | 6.0 |
| SE-0437 | Noncopyable standard library primitives | 6.0 |
| SE-0441 | `swiftLanguageModes` Package.swift setting | 6.0 |
| SE-0446 | Non-escapable types | 6.0 |
| SE-0447 | Span: Safe access to contiguous storage | 6.2 |
| SE-0456 | Span-providing properties | 6.2 |
| SE-0460 | Explicit specialization (`@specialized`) | 6.3 |
| SE-0461 | Isolating nonisolated async functions (`@concurrent`, `nonisolated(nonsending)`) | 6.2 |
| SE-0465 | Non-escapable stdlib primitives | 6.2 |
| SE-0466 | Default actor isolation (MainActor default) | 6.2 |
| SE-0470 | Global-actor isolated conformances | 6.2 |
| SE-0491 | Module selectors for name disambiguation | 6.3 |
| SE-0492 | Section placement control (`@section`, `@used`) | 6.3 |
| SE-0493 | Async calls in `defer` bodies | 6.3 |
| SE-0494 | `isTriviallyIdentical(to:)` methods | 6.3 |
| SE-0495 | C-compatible functions and enums (`@c`) | 6.3 |
| SE-0496 | `@inline(always)` attribute | 6.3 |
| SE-0497 | Controlling function definition visibility (`@export`) | 6.3 |
| SE-0498 | Expose `demangle` function in Runtime module | 6.3 |
| SE-0499 | `~Copyable` and `~Escapable` in standard library protocols | 6.3 |

### Swift Testing proposals

| Proposal | Title | Version |
|----------|-------|---------|
| ST-0005 | Ranged confirmations | 6.1 |
| ST-0006 | Return errors from `#expect(throws:)` | 6.1 |
| ST-0007 | Test scoping traits | 6.1 |
| ST-0008 | Exit tests | 6.2 |
| ST-0009 | Attachments | 6.2 |
| ST-0010 | `evaluate()` in `ConditionTrait` | 6.2 |
| ST-0011 | Issue handling traits | 6.2 |
| ST-0012 | Exit test value capturing | 6.3 |
| ST-0013 | Issue severity (warning) | 6.3 |
| ST-0014 | Image attachments (Apple platforms) | 6.3 |
| ST-0015 | Image attachments (Windows) | 6.3 |
| ST-0016 | Test cancellation | 6.3 |
| ST-0017 | Image attachment consolidation | 6.3 |
| ST-0020 | SourceLocation `filePath` property | 6.3 |
