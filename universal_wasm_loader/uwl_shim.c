/* Compiles the loader implementation + the V-facing shim. */
#define UWL_IMPLEMENTATION
#include "universal_wasm_loader.h"
#include "uwl_shim.h"

#include <stdlib.h>

uwl_module_t *uwlv_import(const char *path, char **err) {
    return uwl_import(path, NULL, 0, err);
}

void uwlv_free(uwl_module_t *m) { uwl_free(m); }

void uwlv_free_str(char *s) { uwl_string_free(s); }

int uwlv_call(uwl_module_t *m, const char *name,
              const uwlv_arg *args, size_t n,
              int *out_kind, long long *out_i, double *out_d, char **out_s,
              char **err) {
    uwl_val_t *vals = n ? (uwl_val_t *)malloc(n * sizeof(uwl_val_t)) : NULL;
    for (size_t i = 0; i < n; i++) {
        switch (args[i].kind) {
            case UWL_I32:  vals[i] = uwl_i32((int32_t)args[i].i); break;
            case UWL_I64:  vals[i] = uwl_i64((int64_t)args[i].i); break;
            case UWL_F32:  vals[i] = uwl_f32((float)args[i].d); break;
            case UWL_F64:  vals[i] = uwl_f64(args[i].d); break;
            case UWL_BOOL: vals[i] = uwl_bool((int)args[i].i); break;
            case UWL_STR:  vals[i] = uwl_str(args[i].s ? args[i].s : ""); break;
            default:       vals[i] = uwl_void(); break;
        }
    }

    uwl_val_t out;
    int rc = uwl_call(m, name, vals, n, &out, err);

    for (size_t i = 0; i < n; i++)
        if (vals[i].kind == UWL_STR) uwl_val_free(&vals[i]);
    free(vals);

    if (rc != 0) { *out_kind = UWL_VOID; return -1; }

    *out_kind = (int)out.kind;
    *out_i = 0; *out_d = 0; *out_s = NULL;
    switch (out.kind) {
        case UWL_I32:  *out_i = uwl_as_i32(out); break;
        case UWL_I64:  *out_i = uwl_as_i64(out); break;
        case UWL_F32:  *out_d = uwl_as_f32(out); break;
        case UWL_F64:  *out_d = uwl_as_f64(out); break;
        case UWL_BOOL: *out_i = uwl_as_bool(out); break;
        case UWL_STR:  *out_s = out.str; out.str = NULL; break; /* transfer ownership */
        default: break;
    }
    uwl_val_free(&out); /* str ownership already transferred when applicable */
    return 0;
}
