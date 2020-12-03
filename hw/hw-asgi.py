body_huge = b'Hello, world!\n' * 74899
body_14 = (body_huge[:14], b'14')

body_def = {
    '/':   body_14,
    '/1k': (body_huge[:1024], b'1024'),
    '/4k': (body_huge[:1024 * 4], b'4096'),
    '/1m': (body_huge[:1024 * 1024], b'1048576'),
}

async def application(scope, receive, send):
    if scope['type'] != 'http':
        return

    await receive()

    body = body_def.get(scope['path'], body_14)

    await send({
        'type': 'http.response.start',
        'status': 200,
        'headers': [
            (b'content-type', b'text.plain'),
            (b'content-length', body[1]),
        ]
    })

    await send({
        'type': 'http.response.body',
        'body': body[0],
    })
