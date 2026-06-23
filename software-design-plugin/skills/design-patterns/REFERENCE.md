# Design Patterns Reference

Per-pattern intent, structure, and a minimal recipe for the candidates in the
`design-patterns` selector. Loaded on demand — consult the entry for a pattern
the selector surfaced. Grouped by GoF category.

Each entry: **Intent** (the recurring problem it solves) · **Shape** (the
participants) · **Recipe** (the minimal moves) · **Cost / smell-if-misused**.

---

## Creational

### Factory Method
- **Intent**: Defer which concrete class to instantiate to a subclass/seam, so
  callers depend on an abstraction, not a `new ConcreteX()`.
- **Shape**: `Creator.create() -> Product` (abstract); subclasses pick the
  concrete `Product`.
- **Recipe**: Replace a hard-coded constructor call with a call to a `create`
  method; let configuration/subtype decide the concrete type.
- **Cost**: An extra creation seam. Smell if misused: a factory wrapping a single
  concrete type that never varies.

### Abstract Factory
- **Intent**: Create *families* of related objects without binding to their
  concrete classes (e.g. a whole UI toolkit, a whole storage backend).
- **Shape**: `Factory` with several `createX()` methods; concrete factories
  produce a coherent family.
- **Recipe**: Group related Factory Methods behind one interface; select the
  concrete factory once at the composition root.
- **Cost**: Many types. Smell: only one family will ever exist → use Factory
  Method or plain functions.

### Builder
- **Intent**: Construct a complex object through ordered, optional steps instead
  of a telescoping constructor.
- **Shape**: `Builder.withX().withY().build() -> Product`.
- **Recipe**: Move each optional parameter to a fluent setter; `build()`
  validates the assembled invariant.
- **Cost**: A parallel builder type. Smell: 2-3 params that a constructor or
  options object handles fine.

### Singleton
- **Intent**: Exactly one instance with a global access point.
- **Shape**: private constructor + static accessor.
- **Recipe**: Prefer dependency injection of a single instance over a hard
  Singleton — Singletons are hostile to testing and concurrency.
- **Cost**: Hidden global state. Smell: used as a dumping ground for globals.

---

## Structural

### Adapter
- **Intent**: Make an existing interface usable where a different one is
  expected — wrap a third-party/legacy API you can't change.
- **Shape**: `Adapter implements Target { Adaptee inner; }`.
- **Recipe**: Implement the interface your code wants; delegate to the callee you
  have, translating types/errors at the seam.
- **Cost**: A thin translation layer. (This is also the seam `design-legacy-seams`
  introduces to get untestable code under test.)

### Decorator
- **Intent**: Add/remove responsibilities to an instance at runtime, avoiding a
  combinatorial subclass explosion.
- **Shape**: `Decorator implements Component { Component inner; }`; wrappers
  stack.
- **Recipe**: Wrap the component, forward the call, add behaviour before/after.
  Compose wrappers for combinations.
- **Cost**: A wrapper chain that can obscure the base. Smell: one fixed
  decoration → just put it in the class.

### Facade
- **Intent**: Give a complex subsystem one simplified entry point for the common
  case.
- **Shape**: `Facade` calling many subsystem objects.
- **Recipe**: Expose the common workflow as a few methods; leave full subsystem
  access available for the rare case.
- **Cost**: Risk of becoming a god object. A Facade should be *deep* (see
  `design-deep-modules`).

### Proxy
- **Intent**: A stand-in controlling access to another object (lazy load, cache,
  remote, access-control).
- **Shape**: `Proxy implements Subject { Subject real; }`.
- **Recipe**: Implement the subject's interface; add the access concern around a
  delegated call.
- **Cost**: Another indirection; easy to confuse with Decorator (Proxy controls
  *access*, Decorator adds *behaviour*).

---

## Behavioural

### Strategy
- **Intent**: Make an algorithm interchangeable at runtime; replace a type-code
  `switch` over behaviours.
- **Shape**: `Context` holds a `Strategy`; concrete strategies implement it.
- **Recipe**: Extract each `case` body into a strategy object; inject the chosen
  one. Prefer over Template Method (composition over inheritance).
- **Cost**: One interface + N classes. Smell: a single strategy that never varies.

### State
- **Intent**: Let an object alter behaviour as its internal state changes, with
  the *transitions* themselves modelled — not a tangle of mode flags.
- **Shape**: `Context` delegates to a `State`; states return the next state.
- **Recipe**: One class per state; each handles its events and names its
  successor. Choose over Strategy when variants drive transitions between *each
  other*.
- **Cost**: A class per state. Smell: a boolean flag would do.

### Observer
- **Intent**: Notify many dependents when one subject changes, keeping them
  decoupled from it.
- **Shape**: `Subject` holds `Observer` subscribers; `notify()` fans out.
- **Recipe**: Subscribe/unsubscribe API on the subject; push the change (or a
  handle) to each observer. Mind subscription lifecycle/leaks.
- **Cost**: Lifecycle management; ordering is not guaranteed.

### Template Method
- **Intent**: Fix an algorithm's skeleton, let subclasses fill specific steps.
- **Shape**: A base method calling abstract `stepX()` hooks.
- **Recipe**: Put the invariant sequence in the base; subclasses override only
  the varying steps. Use when the skeleton must be *enforced*; otherwise prefer
  Strategy.
- **Cost**: Inheritance coupling.

### Command
- **Intent**: Turn a request into an object — to queue, log, undo, or parameterise
  it.
- **Shape**: `Command.execute()` (and optionally `undo()`).
- **Recipe**: Encapsulate the action + its arguments in an object; the invoker
  holds commands without knowing their concrete work.
- **Cost**: A type per action. Smell: a plain function/closure suffices.

### Iterator
- **Intent**: Traverse a collection without exposing its internal shape.
- **Shape**: `Iterator.next()/hasNext()` over an aggregate.
- **Recipe**: Most languages ship this (generators, `Iterable`); reach for the
  explicit pattern only for a non-trivial structure.
- **Cost**: Low — usually language-native.

### Visitor
- **Intent**: Add operations across a stable type hierarchy without editing each
  type.
- **Shape**: `element.accept(visitor)`; visitor has a `visitX` per type.
- **Recipe**: Double-dispatch each node to the visitor. Use when the *hierarchy*
  is stable but *operations* churn (the inverse of when to subclass).
- **Cost**: Adding a new type touches every visitor — the explicit trade-off.

---

## Choosing between close pairs

| If… | Prefer | Over |
|---|---|---|
| Behaviour varies, skeleton need not be enforced | Strategy (composition) | Template Method (inheritance) |
| Variants drive transitions among themselves | State | Strategy |
| You add *behaviour* around a call | Decorator | Proxy |
| You control *access* to a call | Proxy | Decorator |
| One family will ever exist | Factory Method / functions | Abstract Factory |
| Operations churn, types are stable | Visitor | Editing each type |
| Types churn, operations are stable | Plain methods on each type | Visitor |
