/*
 * uwl_shim.h — V-facing C surface over the Universal WASM Loader.
 *
 * Self-contained: it does NOT include universal_wasm_loader.h (nor wasm.h), so
 * V can parse it into its own translation unit without the wasmtime headers.
 * Every entry point V needs is a `uwlv_*` wrapper declared here; the real
 * implementation (uwl_shim.c) includes the loader for the definitions.
 *
 * Why a shim at all: the loader's value constructors/accessors are `static
 * inline` (not linkable) and `uwl_val_t` is awkward to pass by value across V's
 * FFI. The shim hides both behind a primitive `uwlv_arg` array + out-params.
 */
#ifndef UWL_SHIM_H
#define UWL_SHIM_H

#include <stddef.h>

/* Opaque module handle; the full definition lives in the loader. */
typedef struct uwl_module uwl_module_t;

/* One call argument. Only the field matching `kind` is read. */
typedef struct {
    int          kind; /* uwl_kind_t: 1=i32 2=i64 3=f32 4=f64 5=bool 6=str */
    long long    i;    /* i32 / i64 / bool */
    double       d;    /* f32 / f64 */
    const char  *s;    /* string */
} uwlv_arg;

/* Load a module (host imports not supported from V yet). Returns NULL with
 * *err set (heap; free with uwlv_free_str) on failure. */
uwl_module_t *uwlv_import(const char *path, char **err);
void          uwlv_free(uwl_module_t *m);
void          uwlv_free_str(char *s);

/*
 * Call an export. Returns 0 on success, -1 on failure (with *err set to a heap
 * string — free with uwlv_free_str). On success *out_kind holds the result
 * kind; the matching out-param carries the value. For a string result *out_s is
 * a heap string the caller frees with uwlv_free_str.
 */
int uwlv_call(uwl_module_t *m, const char *name,
              const uwlv_arg *args, size_t n,
              int *out_kind, long long *out_i, double *out_d, char **out_s,
              char **err);

#endif /* UWL_SHIM_H */
