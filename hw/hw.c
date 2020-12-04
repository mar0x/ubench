
/*
 * Copyright (C) NGINX, Inc.
 */

#include <nxt_unit.h>
#include <nxt_unit_request.h>
#include <nxt_clang.h>
#include <pthread.h>
#include <string.h>
#include <stdlib.h>


#define CONTENT_TYPE    "Content-Type"
#define CONTENT_LENGTH  "Content-Length"
#define TEXT_PLAIN      "text/plain"
#define HELLO_WORLD     "Hello, world!\n"


static int hw_ready_handler(nxt_unit_ctx_t *ctx);
static void *hw_worker(void *main_ctx);
static void hw_request_handler(nxt_unit_request_info_t *req);


static int        thread_count;
static pthread_t  *threads;

typedef struct {
    uint32_t    size;
    uint32_t    size_str_len;
    const char  *size_str;
    const char  *path;
    char        *body;
} body_def_t;

#define BODY_DEF(n, p) \
    { n, nxt_length(#n), #n, p, NULL }

static body_def_t  body_def[] = {
    BODY_DEF(14,      "/"),
    BODY_DEF(1024,    "/1k"),
    BODY_DEF(4096,    "/4k"),
    BODY_DEF(16384,   "/16k"),
    BODY_DEF(65536,   "/64k"),
    BODY_DEF(1048576, "/1m")
};

enum {
    BODY_14,
    BODY_1K,
    BODY_4K,
    BODY_16K,
    BODY_64K,
    BODY_1M,
    BODY_MAX,
};

int
main(int argc, char **argv)
{
    int              i, err;
    uint32_t         o;
    body_def_t       *bd;
    nxt_unit_ctx_t   *ctx;
    nxt_unit_init_t  init;

    static const char      hw[] = HELLO_WORLD;
    static const uint32_t  hw_size = nxt_length(HELLO_WORLD);

    if (argc == 3 && strcmp(argv[1], "-t") == 0) {
        thread_count = atoi(argv[2]);
    }

    memset(&init, 0, sizeof(nxt_unit_init_t));

    init.callbacks.request_handler = hw_request_handler;
    init.callbacks.ready_handler = hw_ready_handler;

    ctx = nxt_unit_init(&init);
    if (ctx == NULL) {
        return 1;
    }

    for (i = 0; i < BODY_MAX; i++) {
        bd = &body_def[i];
        bd->body = malloc(bd->size);

        for (o = 0; o < bd->size; o++) {
            bd->body[o] = hw[o % hw_size];
        }
    }

    err = nxt_unit_run(ctx);

    nxt_unit_debug(ctx, "main worker finished with %d code", err);

    if (thread_count > 1) {
        for (i = 0; i < thread_count - 1; i++) {
            err = pthread_join(threads[i], NULL);

            if (nxt_fast_path(err == 0)) {
                nxt_unit_debug(ctx, "join thread #%d", i);

            } else {
                nxt_unit_alert(ctx, "pthread_join(#%d) failed: %s (%d)",
                                    i, strerror(err), err);
            }
        }

        nxt_unit_free(ctx, threads);
    }

    nxt_unit_done(ctx);

    nxt_unit_debug(NULL, "main worker done");

    return 0;
}


static int
hw_ready_handler(nxt_unit_ctx_t *ctx)
{
    int  i, err;

    nxt_unit_debug(ctx, "ready");

    if (!nxt_unit_is_main_ctx(ctx) || thread_count <= 1) {
        return NXT_UNIT_OK;
    }

    threads = nxt_unit_malloc(ctx, sizeof(pthread_t) * (thread_count - 1));
    if (threads == NULL) {
        return NXT_UNIT_ERROR;
    }

    for (i = 0; i < thread_count - 1; i++) {
        err = pthread_create(&threads[i], NULL, hw_worker, ctx);
        if (err != 0) {
            return NXT_UNIT_ERROR;
        }
    }

    return NXT_UNIT_OK;
}


static void *
hw_worker(void *main_ctx)
{
    int             rc;
    nxt_unit_ctx_t  *ctx;

    ctx = nxt_unit_ctx_alloc(main_ctx, NULL);
    if (ctx == NULL) {
        return NULL;
    }

    nxt_unit_debug(ctx, "start worker");

    rc = nxt_unit_run(ctx);

    nxt_unit_debug(ctx, "worker finished with %d code", rc);

    nxt_unit_done(ctx);

    return (void *) (intptr_t) rc;
}


static void
hw_request_handler(nxt_unit_request_info_t *req)
{
    int                 rc, clen = nxt_length(HELLO_WORLD);
    const char          *path;
    const body_def_t    *bd;
    nxt_unit_request_t  *r;

    r = req->request;
    bd = &body_def[BODY_14];

    switch (r->path_length) {
    case 1: break;
    case 3:
        path = nxt_unit_sptr_get(&r->path);

        switch (path[1] + path[2]) {
        case '1' + 'k': bd = &body_def[BODY_1K]; break;
        case '4' + 'k': bd = &body_def[BODY_4K]; break;
        case '1' + 'm': bd = &body_def[BODY_1M]; break;
        }

        break;

    case 4:
        path = nxt_unit_sptr_get(&r->path);

        switch (path[1] + path[2]) {
        case '1' + '6': bd = &body_def[BODY_16K]; break;
        case '6' + '4': bd = &body_def[BODY_64K]; break;
        }

        break;
    }

    rc = nxt_unit_response_init(req, 200 /* Status code. */,
                                2 /* Number of response headers. */,
                                nxt_length(CONTENT_TYPE)
                                + nxt_length(TEXT_PLAIN)
                                + nxt_length(CONTENT_LENGTH)
                                + bd->size_str_len
                                + nxt_length(HELLO_WORLD));
    if (nxt_slow_path(rc != NXT_UNIT_OK)) {
        goto fail;
    }

    rc = nxt_unit_response_add_field(req,
                                     CONTENT_TYPE, nxt_length(CONTENT_TYPE),
                                     TEXT_PLAIN, nxt_length(TEXT_PLAIN));
    if (nxt_slow_path(rc != NXT_UNIT_OK)) {
        goto fail;
    }

    rc = nxt_unit_response_add_field(req,
                                     CONTENT_LENGTH, nxt_length(CONTENT_LENGTH),
                                     bd->size_str, bd->size_str_len);
    if (nxt_slow_path(rc != NXT_UNIT_OK)) {
        goto fail;
    }

    rc = nxt_unit_response_write(req, bd->body, bd->size);

fail:

    nxt_unit_request_done(req, rc);
}
