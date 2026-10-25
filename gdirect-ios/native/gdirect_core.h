#ifndef GDIRECT_CORE_H
#define GDIRECT_CORE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Callback is synchronous on the worker thread. Return nonzero to cancel.
typedef int (*gd_progress_fn)(int64_t completed, int64_t total, int speed, int connections, void *context);
// JSON response is allocated by Rust. Exactly one gd_free call per non-null result.
char *gd_execute(const char *request_json, gd_progress_fn progress, void *context);
void gd_free(char *response);
#ifdef __cplusplus
}
#endif
#endif
