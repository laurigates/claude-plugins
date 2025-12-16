# Rust Development Reference

Comprehensive reference documentation for advanced Rust development patterns, async programming, unsafe code, WebAssembly, and embedded development.

## Async Patterns & Tokio

### Tokio Runtime Configuration

**Basic Runtime Setup**
```rust
use tokio::runtime::Runtime;

// Multi-threaded runtime (default)
let rt = Runtime::new().unwrap();
rt.block_on(async {
    // async code
});

// Current thread runtime (for simple cases)
use tokio::runtime::Builder;
let rt = Builder::new_current_thread()
    .enable_all()
    .build()
    .unwrap();
```

**Tokio Main Attribute**
```rust
#[tokio::main]
async fn main() {
    // Async code runs on multi-threaded runtime
}

// Equivalent to:
fn main() {
    tokio::runtime::Runtime::new()
        .unwrap()
        .block_on(async {
            // code
        })
}
```

### Async Patterns

**Concurrent Execution**
```rust
use tokio::join;

async fn fetch_user(id: u64) -> User { /* ... */ }
async fn fetch_posts(user_id: u64) -> Vec<Post> { /* ... */ }

// Run concurrently, wait for both
let (user, posts) = join!(
    fetch_user(123),
    fetch_posts(123)
);

// Using try_join for Result types
use tokio::try_join;
let (user, posts) = try_join!(
    fetch_user(123),
    fetch_posts(123)
)?;
```

**Spawning Tasks**
```rust
use tokio::task;

// Spawn task on runtime
let handle = task::spawn(async {
    // Runs on tokio thread pool
    expensive_computation().await
});

// Wait for task completion
let result = handle.await.unwrap();

// Spawn blocking task (for CPU-bound work)
let result = task::spawn_blocking(|| {
    // Runs on blocking thread pool
    cpu_intensive_work()
}).await.unwrap();
```

**Select Pattern**
```rust
use tokio::select;

async fn race_requests() {
    let result = select! {
        res1 = fetch_from_primary() => res1,
        res2 = fetch_from_backup() => res2,
        _ = tokio::time::sleep(Duration::from_secs(5)) => {
            return Err("Timeout");
        }
    };
}
```

**Channels for Communication**
```rust
use tokio::sync::{mpsc, oneshot};

// Multi-producer, single-consumer
let (tx, mut rx) = mpsc::channel(32);

tokio::spawn(async move {
    tx.send("message").await.unwrap();
});

while let Some(msg) = rx.recv().await {
    println!("Received: {}", msg);
}

// One-shot channel (single value)
let (tx, rx) = oneshot::channel();
tokio::spawn(async move {
    tx.send(42).unwrap();
});
let value = rx.await.unwrap();
```

### Stream Processing

**Using Streams**
```rust
use tokio_stream::{self as stream, StreamExt};

let mut stream = stream::iter(vec![1, 2, 3, 4, 5]);

while let Some(value) = stream.next().await {
    println!("Got: {}", value);
}

// Stream combinators
let doubled = stream::iter(vec![1, 2, 3])
    .map(|x| x * 2)
    .filter(|x| x % 2 == 0)
    .collect::<Vec<_>>()
    .await;
```

**Interval and Timeout**
```rust
use tokio::time::{interval, timeout, Duration};

// Periodic execution
let mut interval = interval(Duration::from_secs(1));
loop {
    interval.tick().await;
    println!("Tick!");
}

// Timeout on async operations
let result = timeout(
    Duration::from_secs(5),
    long_running_operation()
).await;

match result {
    Ok(value) => println!("Got: {:?}", value),
    Err(_) => println!("Timeout!"),
}
```

## Unsafe Code Guidelines

### When to Use Unsafe

**Valid Use Cases**:
- Implementing low-level abstractions (collections, smart pointers)
- FFI (Foreign Function Interface) bindings
- Performance-critical code with proven safety invariants
- Platform-specific operations (inline assembly, intrinsics)

**Safety Requirements**:
1. Document all safety invariants in comments
2. Minimize unsafe blocks (smallest possible scope)
3. Provide safe public APIs wrapping unsafe code
4. Test thoroughly with Miri for undefined behavior

### Unsafe Operations

**Raw Pointers**
```rust
unsafe fn deref_raw_pointer(ptr: *const i32) -> i32 {
    // SAFETY: Caller must ensure:
    // - ptr is non-null
    // - ptr is properly aligned
    // - ptr points to valid i32
    // - no mutable aliases exist
    *ptr
}

// Safe wrapper
fn safe_deref(value: &i32) -> i32 {
    unsafe { deref_raw_pointer(value as *const i32) }
}
```

**Implementing Send/Sync**
```rust
use std::marker::PhantomData;

struct MyType {
    ptr: *mut u8,
    _phantom: PhantomData<u8>,
}

// SAFETY: MyType maintains exclusive ownership of ptr
// and ensures proper synchronization
unsafe impl Send for MyType {}
unsafe impl Sync for MyType {}
```

**Inline Assembly**
```rust
use std::arch::asm;

unsafe fn rdtsc() -> u64 {
    let lo: u32;
    let hi: u32;
    asm!(
        "rdtsc",
        out("eax") lo,
        out("edx") hi,
        options(nomem, nostack)
    );
    ((hi as u64) << 32) | (lo as u64)
}
```

### Memory Safety Patterns

**RAII for Unsafe Resources**
```rust
struct FileDescriptor {
    fd: i32,
}

impl FileDescriptor {
    fn new(path: &str) -> std::io::Result<Self> {
        let fd = unsafe {
            // SAFETY: path is valid C string
            libc::open(path.as_ptr() as *const i8, libc::O_RDONLY)
        };
        if fd < 0 {
            Err(std::io::Error::last_os_error())
        } else {
            Ok(Self { fd })
        }
    }
}

impl Drop for FileDescriptor {
    fn drop(&mut self) {
        unsafe {
            // SAFETY: fd is valid and owned by this instance
            libc::close(self.fd);
        }
    }
}
```

## WebAssembly Compilation

### Setup and Build

**Install wasm32 Target**
```bash
rustup target add wasm32-unknown-unknown
rustup target add wasm32-wasi  # For WASI support
```

**Build for WebAssembly**
```bash
# Bare WASM
cargo build --target wasm32-unknown-unknown --release

# With WASI (filesystem, env access)
cargo build --target wasm32-wasi --release

# Optimize size with wasm-opt
wasm-opt -Oz -o output.wasm target/wasm32-unknown-unknown/release/app.wasm
```

### wasm-bindgen Integration

**Cargo.toml**
```toml
[dependencies]
wasm-bindgen = "0.2"

[lib]
crate-type = ["cdylib"]

[profile.release]
opt-level = "z"     # Optimize for size
lto = true
codegen-units = 1
panic = 'abort'
```

**Basic JavaScript Interop**
```rust
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn greet(name: &str) -> String {
    format!("Hello, {}!", name)
}

#[wasm_bindgen]
extern "C" {
    // Import JavaScript functions
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);

    fn alert(s: &str);
}

#[wasm_bindgen(start)]
pub fn main() {
    log("WASM module loaded");
}
```

**Working with JavaScript Objects**
```rust
use wasm_bindgen::prelude::*;
use web_sys::{Document, Element, Window};

#[wasm_bindgen]
pub fn create_element() -> Result<(), JsValue> {
    let window = web_sys::window().expect("no global window");
    let document = window.document().expect("no document");

    let div = document.create_element("div")?;
    div.set_inner_html("Created from Rust!");

    document.body()
        .expect("no body")
        .append_child(&div)?;

    Ok(())
}
```

## Embedded Development

### no_std Environment

**Basic no_std Setup**
```rust
#![no_std]
#![no_main]

use panic_halt as _;  // Panic handler

#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Entry point
    loop {}
}
```

**Custom Allocator**
```rust
#![no_std]
#![feature(alloc_error_handler)]

extern crate alloc;

use alloc::vec::Vec;
use embedded_alloc::Heap;

#[global_allocator]
static HEAP: Heap = Heap::empty();

#[alloc_error_handler]
fn alloc_error(_: core::alloc::Layout) -> ! {
    loop {}
}

fn init_heap() {
    const HEAP_SIZE: usize = 1024;
    static mut HEAP_MEM: [u8; HEAP_SIZE] = [0; HEAP_SIZE];

    unsafe {
        HEAP.init(HEAP_MEM.as_ptr() as usize, HEAP_SIZE);
    }
}
```

### HAL Patterns

**Peripheral Abstraction**
```rust
pub trait GpioPin {
    fn set_high(&mut self);
    fn set_low(&mut self);
    fn is_high(&self) -> bool;
}

pub struct Led<P: GpioPin> {
    pin: P,
}

impl<P: GpioPin> Led<P> {
    pub fn new(pin: P) -> Self {
        Self { pin }
    }

    pub fn on(&mut self) {
        self.pin.set_high();
    }

    pub fn off(&mut self) {
        self.pin.set_low();
    }
}
```

**Embedded HAL Traits**
```rust
use embedded_hal::digital::v2::OutputPin;
use embedded_hal::blocking::delay::DelayMs;

fn blink<P, D>(led: &mut P, delay: &mut D)
where
    P: OutputPin,
    D: DelayMs<u16>,
{
    loop {
        led.set_high().ok();
        delay.delay_ms(500);
        led.set_low().ok();
        delay.delay_ms(500);
    }
}
```

## Advanced Debugging

### Debugging Tools

**Cargo Expand (Macro Expansion)**
```bash
cargo install cargo-expand
cargo expand              # Expand all
cargo expand module::item # Expand specific item
```

**Miri (Undefined Behavior Detection)**
```bash
rustup component add miri
cargo miri test           # Run tests with miri
cargo miri run            # Run binary with miri
```

**Flamegraph Profiling**
```bash
cargo install flamegraph
cargo flamegraph          # Generate flamegraph
cargo flamegraph --bench benchmark_name
```

### Advanced Debugging Patterns

**Custom Debug Formatting**
```rust
use std::fmt;

struct Point { x: i32, y: i32 }

impl fmt::Debug for Point {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Point")
            .field("x", &self.x)
            .field("y", &self.y)
            .finish()
    }
}

// Or use derive with custom attributes
#[derive(Debug)]
struct Complex {
    #[debug("{:#x}", self.value)]  // Hex formatting
    value: u32,
}
```

**Conditional Compilation for Debug**
```rust
#[cfg(debug_assertions)]
macro_rules! debug_println {
    ($($arg:tt)*) => {
        println!($($arg)*);
    };
}

#[cfg(not(debug_assertions))]
macro_rules! debug_println {
    ($($arg:tt)*) => {};
}
```

**Performance Profiling with Criterion**
```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn fibonacci(n: u64) -> u64 {
    match n {
        0 => 1,
        1 => 1,
        n => fibonacci(n - 1) + fibonacci(n - 2),
    }
}

fn criterion_benchmark(c: &mut Criterion) {
    c.bench_function("fib 20", |b| {
        b.iter(|| fibonacci(black_box(20)))
    });
}

criterion_group!(benches, criterion_benchmark);
criterion_main!(benches);
```

## Performance Optimization

### Zero-Cost Abstractions

**Inline Optimization**
```rust
#[inline(always)]
fn hot_function() {
    // Always inlined
}

#[inline(never)]
fn cold_function() {
    // Never inlined (for debugging)
}

#[inline]  // Hint to compiler
fn normal_function() {
    // May be inlined
}
```

**SIMD Optimization**
```rust
#[cfg(target_arch = "x86_64")]
use std::arch::x86_64::*;

#[target_feature(enable = "avx2")]
unsafe fn simd_sum(data: &[f32; 8]) -> f32 {
    let v = _mm256_loadu_ps(data.as_ptr());
    let sum = _mm256_hadd_ps(v, v);
    let sum = _mm256_hadd_ps(sum, sum);
    _mm256_cvtss_f32(sum)
}
```

### Memory Layout Optimization

**Struct Field Ordering**
```rust
// Bad: 16 bytes (with padding)
struct Unoptimized {
    a: u8,   // 1 byte + 3 padding
    b: u32,  // 4 bytes
    c: u8,   // 1 byte + 7 padding
}

// Good: 8 bytes
struct Optimized {
    b: u32,  // 4 bytes
    a: u8,   // 1 byte
    c: u8,   // 1 byte + 2 padding
}

// Explicit packing
#[repr(C, packed)]
struct Packed {
    a: u8,
    b: u32,
    c: u8,
}  // 6 bytes, no padding (use carefully!)
```

## Testing Patterns

### Property-Based Testing

**Using quickcheck**
```rust
#[cfg(test)]
mod tests {
    use quickcheck::quickcheck;

    quickcheck! {
        fn prop_reverse_reverse(xs: Vec<i32>) -> bool {
            let reversed: Vec<_> = xs.iter().cloned().rev().collect();
            let double_reversed: Vec<_> = reversed.iter().cloned().rev().collect();
            xs == double_reversed
        }
    }
}
```

### Fuzzing

**cargo-fuzz Setup**
```bash
cargo install cargo-fuzz
cargo fuzz init
cargo fuzz add target_name

# Run fuzzer
cargo fuzz run target_name
```

**Fuzz Target**
```rust
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        // Fuzz your parser/decoder
        let _ = my_parser::parse(s);
    }
});
```

## Error Handling Patterns

### Advanced Error Types

**Using thiserror**
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum DataStoreError {
    #[error("data store disconnected")]
    Disconnect(#[from] io::Error),

    #[error("the data for key `{0}` is not available")]
    Redaction(String),

    #[error("invalid header (expected {expected:?}, found {found:?})")]
    InvalidHeader {
        expected: String,
        found: String,
    },

    #[error(transparent)]
    Other(#[from] anyhow::Error),
}
```

**Context with anyhow**
```rust
use anyhow::{Context, Result};

fn read_config() -> Result<Config> {
    let content = std::fs::read_to_string("config.toml")
        .context("Failed to read config file")?;

    toml::from_str(&content)
        .context("Failed to parse config")?
}
```

This reference provides comprehensive patterns for advanced Rust development. For basic setup and common operations, see SKILL.md.
