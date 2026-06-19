// Example: a WASM-backed adder that looks like ordinary V.
// Run from the repo root:  v run examples/adder.v
module main

import uwl

// adder is a native-looking V wrapper over the module's WASM `add` export — it
// hides the uwl.i32(...) boxing behind a plain (int, int) -> int signature.
// @param m  a loaded module exporting `add: func(s32, s32) -> s32`
// @param a  first addend
// @param b  second addend
// @returns  a + b, computed inside the WASM module
// @error    propagates any call failure from the loader
fn adder(m &uwl.Module, a int, b int) !int {
	return m.call_i32('add', uwl.i32(a), uwl.i32(b))
}

fn main() {
	m := uwl.import_module('examples/math_50.wasm') or {
		eprintln('load failed: ${err}')
		return
	}
	defer {
		m.free()
	}

	println('adder(3, 4) = ${adder(m, 3, 4)!}')
	println('multiply(2.5, 4.0) = ${m.call_f64('multiply', uwl.f64(2.5), uwl.f64(4.0))!}')
	println('square(5) = ${m.call_i32('square', uwl.i32(5))!}')
}
