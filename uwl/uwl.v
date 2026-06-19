// Idiomatic V binding for the Universal WASM Loader.
//
//   import uwl
//
//   m := uwl.import_module('examples/math_50.wasm')!
//   defer { m.free() }
//   sum := m.call_i32('add', uwl.i32(3), uwl.i32(4))!   // 7
//
// Values cross the boundary through a tiny C shim (uwl_shim.c); a companion
// `.wit` next to the `.wasm` is required for typed calls.
module uwl

#flag -Dstatic_assert=_Static_assert
#flag -I @VMODROOT/uwl
#flag -I @VMODROOT/vendor/wasmtime-v45.0.2-x86_64-mingw-c-api/include
#flag @VMODROOT/uwl/uwl_shim.c
#flag @VMODROOT/vendor/wasmtime-v45.0.2-x86_64-mingw-c-api/lib/libwasmtime.dll.a
#flag -lws2_32 -lbcrypt -luserenv -lntdll -lole32 -lShlwapi -ladvapi32 -lkernel32 -luuid
#include "uwl_shim.h"

// --- C shim FFI surface -----------------------------------------------------
// The declarations below mirror the primitive `uwlv_*` entry points in
// uwl_shim.h. They are the ONLY symbols that cross into C; every `pub` item
// further down is a safe V wrapper over them. (TS analogy: this block is the
// hand-written `declare`/.d.ts for the native addon.)

// Value `kind` discriminants — the tag carried by an `Arg` and by a call result.
// These MUST stay in lockstep with `uwl_kind_t` in universal_wasm_loader.h
// (changing the C enum without updating these silently mis-marshals values).
const k_void = 0 // no value (void export)
const k_i32 = 1 // 32-bit signed integer (WIT s32)
const k_i64 = 2 // 64-bit signed integer (WIT s64)
const k_f32 = 3 // 32-bit float (WIT f32)
const k_f64 = 4 // 64-bit float (WIT f64)
const k_bool = 5 // boolean
const k_str = 6 // UTF-8 string

// C.uwl_module_t is the opaque module handle owned by the C loader.
@[typedef]
pub struct C.uwl_module_t {}

// C.uwlv_arg is the flat, by-value argument record handed to C.uwlv_call.
// Only the field selected by `kind` is read; the others are ignored.
@[typedef]
struct C.uwlv_arg {
mut:
	kind int // one of the k_* discriminants
	i    i64 // payload for i32 / i64 / bool
	d    f64 // payload for f32 / f64
	s    &char = unsafe { nil } // payload for str (NUL-terminated, borrowed)
}

// uwlv_import loads a module; on failure returns nil and sets `err` to a heap
// C string (free it with C.uwlv_free_str).
fn C.uwlv_import(path &char, err &&char) &C.uwl_module_t

// uwlv_free releases a module handle and everything it owns.
fn C.uwlv_free(m &C.uwl_module_t)

// uwlv_free_str frees a heap C string handed back by the shim.
fn C.uwlv_free_str(s &char)

// uwlv_call invokes export `name` with `n` args, writing the result through the
// out-params. Returns 0 on success, non-zero on failure (with `err` set). The
// `out_*` param matching `out_kind` carries the value; `out_s` is a heap string
// the caller must free with C.uwlv_free_str.
fn C.uwlv_call(m &C.uwl_module_t, name &char, args &C.uwlv_arg, n usize, out_kind &int, out_i &i64, out_d &f64, out_s &&char, err &&char) int

// Arg is one native argument to an export call — a tagged union of the
// supported WIT scalar/string types.
//
// Do not construct it directly; use the i32()/i64()/f32()/f64()/boolean()/text()
// builders so the WIT type is explicit at the call site (TS analogy: these are
// the discriminated-union constructors, `kind` being the discriminant). Only the
// payload field selected by `kind` is meaningful.
pub struct Arg {
	kind int    // one of the k_* discriminants
	i    i64    // payload for i32/i64/bool
	d    f64    // payload for f32/f64
	s    string // payload for str
}

// i32 boxes a V `int` as a WIT `s32` argument.
// @param v  the integer value to pass
// @returns  an Arg the call_* functions marshal as `s32`
pub fn i32(v int) Arg {
	return Arg{
		kind: k_i32
		i:    v
	}
}

// i64 boxes a V `i64` as a WIT `s64` argument.
// @param v  the integer value to pass
// @returns  an Arg the call_* functions marshal as `s64`
pub fn i64(v i64) Arg {
	return Arg{
		kind: k_i64
		i:    v
	}
}

// f32 boxes a V `f32` as a WIT `f32` argument.
// @param v  the float value to pass
// @returns  an Arg the call_* functions marshal as `f32`
pub fn f32(v f32) Arg {
	return Arg{
		kind: k_f32
		d:    v
	}
}

// f64 boxes a V `f64` as a WIT `f64` argument.
// @param v  the float value to pass
// @returns  an Arg the call_* functions marshal as `f64`
pub fn f64(v f64) Arg {
	return Arg{
		kind: k_f64
		d:    v
	}
}

// boolean boxes a V `bool` as a WIT `bool` argument.
// @param v  the boolean value to pass
// @returns  an Arg the call_* functions marshal as `bool`
pub fn boolean(v bool) Arg {
	return Arg{
		kind: k_bool
		i:    if v { 1 } else { 0 }
	}
}

// text boxes a V `string` as a WIT `string` argument.
//
// The string is borrowed (not copied) for the duration of the call, so keep the
// source value alive until the call returns.
// @param v  the string value to pass
// @returns  an Arg the call_* functions marshal as `string`
pub fn text(v string) Arg {
	return Arg{
		kind: k_str
		s:    v
	}
}

// Module is a loaded, ABI-translated WASM module. Obtain one from
// import_module() and release it with free(); the single field `handle` is the
// opaque C loader handle and is not meant to be touched directly.
pub struct Module {
	handle &C.uwl_module_t
}

// import_module loads a `.wasm` and ABI-translates it so its exports can be
// called with native V values.
//
// The companion `.wit` (same base name, alongside the `.wasm`) is auto-detected
// and supplies the per-export argument/result types. A `@N` suffix on `path`
// pins the module to version N. Host import callbacks are not exposed here, so
// only pure-compute / library modules are supported.
//
// @param path  filesystem path to the `.wasm` (optionally with a `@N` version suffix)
// @returns     a ready-to-call Module — release it with `m.free()`
// @error       the underlying loader message if the module fails to load/translate
pub fn import_module(path string) !Module {
	err := &char(unsafe { nil })
	h := C.uwlv_import(&char(path.str), &err)
	if h == unsafe { nil } {
		return error(take_err(err, 'import failed'))
	}
	return Module{
		handle: h
	}
}

// free releases the module and every resource it owns.
//
// Call exactly once per module (typically via `defer { m.free() }`); using the
// Module after free() is undefined behavior.
pub fn (m &Module) free() {
	C.uwlv_free(m.handle)
}

// take_err converts a heap C error string into an owned V string and frees the
// C copy, falling back to `fallback` when `err` is nil. (Internal.)
// @param err       the C error string from the shim, or nil
// @param fallback  message to use when `err` is nil
// @returns         an owned V string; the C string (if any) is freed
fn take_err(err &char, fallback string) string {
	if err == unsafe { nil } {
		return fallback
	}
	msg := unsafe { cstring_to_vstring(err) }
	C.uwlv_free_str(err)
	return msg
}

// invoke marshals `args` into the flat C record, calls the export, and returns
// the raw result tuple. Shared core for the typed call_* wrappers. (Internal.)
//
// String results are copied into an owned V string and the C heap copy is freed
// here, so callers never deal with C memory.
//
// @param name  the exported function name
// @param args  the native arguments (already boxed as Arg)
// @returns     (kind, int_val, float_val, str_val) — read the field selected by `kind`
// @error       the loader message if the call fails (bad name, arity/type mismatch, trap)
fn (m &Module) invoke(name string, args []Arg) !(int, i64, f64, string) {
	mut cargs := []C.uwlv_arg{len: args.len}
	for idx, a in args {
		cargs[idx] = C.uwlv_arg{
			kind: a.kind
			i:    a.i
			d:    a.d
			s:    if a.kind == k_str { &char(a.s.str) } else { &char(unsafe { nil }) }
		}
	}

	mut out_kind := 0
	mut out_i := i64(0)
	mut out_d := 0.0
	out_s := &char(unsafe { nil })
	err := &char(unsafe { nil })

	data := unsafe {
		if args.len > 0 { &C.uwlv_arg(cargs.data) } else { &C.uwlv_arg(nil) }
	}
	rc := C.uwlv_call(m.handle, &char(name.str), data, usize(args.len), &out_kind, &out_i,
		&out_d, &out_s, &err)
	if rc != 0 {
		return error(take_err(err, 'call failed'))
	}

	mut s := ''
	if out_kind == k_str && out_s != unsafe { nil } {
		s = unsafe { cstring_to_vstring(out_s) }
		C.uwlv_free_str(out_s)
	}
	return out_kind, out_i, out_d, s
}

// call_i32 invokes export `name` and returns its `s32` result.
// @param name  the exported function name (from the module's `.wit`)
// @param args  call arguments, each built with i32()/i64()/f32()/f64()/boolean()/text()
// @returns     the 32-bit signed integer result
// @error       the loader message if the export is missing, the arity/types mismatch, or it traps
pub fn (m &Module) call_i32(name string, args ...Arg) !int {
	_, i, _, _ := m.invoke(name, args)!
	return int(i)
}

// call_i64 invokes export `name` and returns its `s64` result.
// @param name  the exported function name (from the module's `.wit`)
// @param args  call arguments, each built with i32()/i64()/f32()/f64()/boolean()/text()
// @returns     the 64-bit signed integer result
// @error       the loader message if the export is missing, the arity/types mismatch, or it traps
pub fn (m &Module) call_i64(name string, args ...Arg) !i64 {
	_, i, _, _ := m.invoke(name, args)!
	return i
}

// call_f64 invokes export `name` and returns its floating-point result.
//
// Handles both `f32` and `f64` exports (an `f32` result is widened to `f64`).
// @param name  the exported function name (from the module's `.wit`)
// @param args  call arguments, each built with i32()/i64()/f32()/f64()/boolean()/text()
// @returns     the result as an `f64`
// @error       the loader message if the export is missing, the arity/types mismatch, or it traps
pub fn (m &Module) call_f64(name string, args ...Arg) !f64 {
	_, _, d, _ := m.invoke(name, args)!
	return d
}

// call_bool invokes export `name` and returns its `bool` result.
// @param name  the exported function name (from the module's `.wit`)
// @param args  call arguments, each built with i32()/i64()/f32()/f64()/boolean()/text()
// @returns     the boolean result
// @error       the loader message if the export is missing, the arity/types mismatch, or it traps
pub fn (m &Module) call_bool(name string, args ...Arg) !bool {
	_, i, _, _ := m.invoke(name, args)!
	return i != 0
}

// call_str invokes export `name` and returns its `string` result.
//
// The result is copied into an owned V string (managed by V's GC); no manual
// freeing is required on the V side.
// @param name  the exported function name (from the module's `.wit`)
// @param args  call arguments, each built with i32()/i64()/f32()/f64()/boolean()/text()
// @returns     the string result (owned by the caller)
// @error       the loader message if the export is missing, the arity/types mismatch, or it traps
pub fn (m &Module) call_str(name string, args ...Arg) !string {
	_, _, _, s := m.invoke(name, args)!
	return s
}
