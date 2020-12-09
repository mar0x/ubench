package main

import (
    "net/http"
    "strconv"
    "unit.nginx.org/go"
)

type def struct {
    length     int
    length_str string
}

func make_def(l int) *def {
    return &def{l, strconv.Itoa(l)}
}

var body_huge []byte
var body_def map[string]*def
var body_14 *def

func handler(w http.ResponseWriter, r *http.Request) {
    d, found := body_def[r.RequestURI]

    if !found {
        d = body_14
    }

    w.Header().Add("Content-Type", "text/plain")
    w.Header().Add("Content-Length", d.length_str)

    w.Write(body_huge[:d.length])
}

func main() {
    body_huge = make([]byte, 1024 * 1024)
    body := []byte("Hello, world!\n")

    for i := range body_huge {
        body_huge[i] = body[i % len(body)]
    }

    body_14 = make_def(len(body))

    body_def = map[string]*def {
        "/": body_14,
        "/1k": make_def(1024),
        "/4k": make_def(1024 * 4),
        "/16k": make_def(1024 * 16),
        "/64k": make_def(1024 * 64),
        "/1m": make_def(1024 * 1024),
    }

    http.HandleFunc("/", handler)
    unit.ListenAndServe(":8002", nil)
}
