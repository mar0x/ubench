package main

import (
    "net/http"
    "unit.nginx.org/go"
)

var body []byte

func handler(w http.ResponseWriter, r *http.Request) {
    w.Header().Add("Content-Type", "text/plain")
    w.Header().Add("Content-Length", "14")

    w.Write(body)
}

func main() {
    body = []byte("Hello, world!\n")

    http.HandleFunc("/", handler)
    unit.ListenAndServe(":8000", nil)
}
