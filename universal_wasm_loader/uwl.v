// Idiomatic V binding for the Universal WASM Loader.
//
//   import universal_wasm_loader as uwl
//
//   m := uwl.import_module('examples/math_50.wasm')!
//   defer { m.free() }
//   sum := m.call_i32('add', uwl.i32(3), uwl.i32(4))!   // 7
//
// Values cross the boundary through a tiny C shim (uwl_shim.c); a companion
// `.wit` next to the `.wasm` is required for typed calls.
module universal_wasm_loader

#flag -Dstatic_assert=_Static_assert
#flag -I @VMODROOT/universal_wasm_loader
#flag -I @VMODROOT/vendor/wasmtime-v45.0.2-x86_64-mingw-c-api/include
#flag @VMODROOT/universal_wasm_loader/uwl_shim.c
#flag @VMODROOT/vendor/wasmtime-v45.0.2-x86_64-mingw-c-api/lib/libwasmtime.dll.a
#flag -lws2_32 -lbcrypt -luserenv -lntdll -lole32 -lShlwapi -ladvapi32 -lkernel32 -luuid
#include "uwl_shim.h"

// uwl_kind_t discriminants (must match universal_wasm_loader.h).
const k_void = 0
const k_i32 = 1
const k_i64 = 2
const k_f32 = 3
const k_f64 = 4
const k_bool = 5
const k_str = 6

@[typedef]
pub struct C.uwl_module_t {}

@[typedef]
struct C.uwlv_arg {
mut:
	kind int
	i    i64
	d    f64
	s    &char = unsafe { nil }
}

fn C.uwlv_import(path &char, err &&char) &C.uwl_module_t
fn C.uwlv_free(m &C.uwl_module_t)
fn C.uwlv_free_str(s &char)
fn C.uwlv_call(m &C.uwl_module_t, name &char, args &C.uwlv_arg, n usize, out_kind &int, out_i &i64, out_d &f64, out_s &&char, err &&char) int

// Arg is one native argument to an export call. Build with i32()/i64()/f32()/
// f64()/boolean()/text() so the WIT type is unambiguous.
pub struct Arg {
	kind int
	i    i64
	d    f64
	s    string
}

pub fn i32(v int) Arg {
	return Arg{
		kind: k_i32
		i:    v
	}
}

pub fn i64(v i64) Arg {
	return Arg{
		kind: k_i64
		i:    v
	}
}

pub fn f32(v f32) Arg {
	return Arg{
		kind: k_f32
		d:    v
	}
}

pub fn f64(v f64) Arg {
	return Arg{
		kind: k_f64
		d:    v
	}
}

pub fn boolean(v bool) Arg {
	return Arg{
		kind: k_bool
		i:    if v { 1 } else { 0 }
	}
}

pub fn text(v string) Arg {
	return Arg{
		kind: k_str
		s:    v
	}
}

// Module is a loaded, ABI-translated WASM module.
pub struct Module {
	handle &C.uwl_module_t
}

// import_module loads a `.wasm` (its companion `.wit` is auto-detected). A `@N`
// suffix on the path pins the module version.
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

// free releases the module and all resources it owns.
pub fn (m &Module) free() {
	C.uwlv_free(m.handle)
}

fn take_err(err &char, fallback string) string {
	if err == unsafe { nil } {
		return fallback
	}
	msg := unsafe { cstring_to_vstring(err) }
	C.uwlv_free_str(err)
	return msg
}

// Internal: marshal args, invoke, and return the raw result tuple.
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
	rc := C.uwlv_call(m.handle, &char(name.str), data, usize(args.len), &out_kind,
		&out_i, &out_d, &out_s, &err)
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

// call_i32 calls an export returning s32.
pub fn (m &Module) call_i32(name string, args ...Arg) !int {
	_, i, _, _ := m.invoke(name, args)!
	return int(i)
}

// call_i64 calls an export returning s64.
pub fn (m &Module) call_i64(name string, args ...Arg) !i64 {
	_, i, _, _ := m.invoke(name, args)!
	return i
}

// call_f64 calls an export returning f32 or f64.
pub fn (m &Module) call_f64(name string, args ...Arg) !f64 {
	_, _, d, _ := m.invoke(name, args)!
	return d
}

// call_bool calls an export returning bool.
pub fn (m &Module) call_bool(name string, args ...Arg) !bool {
	_, i, _, _ := m.invoke(name, args)!
	return i != 0
}

// call_str calls an export returning string.
pub fn (m &Module) call_str(name string, args ...Arg) !string {
	_, _, _, s := m.invoke(name, args)!
	return s
}
