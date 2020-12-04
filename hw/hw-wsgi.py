body_huge = b'Hello, world!\n' * 74899
body_14 = (body_huge[:14], b'14')

body_def = {
    '/':    body_14,
    '/1k':  (body_huge[:1024], b'1024'),
    '/4k':  (body_huge[:1024 * 4], b'4096'),
    '/16k': (body_huge[:1024 * 16], b'16384'),
    '/64k': (body_huge[:1024 * 64], b'65536'),
    '/1m':  (body_huge[:1024 * 1024], b'1048576'),
}

def application(environ, start_response):
    body = body_def.get(environ['REQUEST_URI'], body_14)

    start_response('200 OK', [
        (b'Content-Type', b'text/plain'),
        (b'Content-Length', body[1]),
    ])
    return body[0]
