#!/usr/bin/env python3

# vim:ts=4:sts=4:sw=4:et

import math
import re
import subprocess
import sys
from statistics import mean, stdev, variance
from datetime import datetime

concurrency = 64
nreq = 10000

detailed = open("detailed.log", 'a')
result = open("result.txt", 'a')

def log(f, *args):
    t = datetime.now().strftime("%H:%M:%S")
    a = [ str(i) for i in args ]
    print(t + ' ' + ' '.join(a))
    print(t + ' ' + ' '.join(a), file=f)
    f.flush()

def ab(n, c, url):
    p = subprocess.Popen(['ab', '-k', '-q', '-n', str(n), '-c', str(c), '-w', url],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    o, e = p.communicate()

    rc = p.returncode

    if rc != 0:
        return None

    res = dict()

    for l in o.split(b'\n'):
        nr = re.search(b'<th[^>]*>([^<]+)<', l)
        nv = re.search(b'<td[^>]*>([^<]+)<', l)
        if nr and nv:
            v = nv[1].split(b' ')[0]
            try:
                res[nr[1]] = float(v)
            except ValueError:
                res[nr[1]] = v

    return res

def filtered_ab(n, c, url, min_time=1.0, max_dev=0.01):
    rps_history = []
    var_mean = {}

    i = 0

    while i < 20:
        r = ab(n, c, url)

        if r is None:
            break

        rps = r[b'Requests per second:']
        time = r[b'Time taken for tests:']
        failed = r[b'Failed requests:']

        rps_history.append(rps)

        if len(rps_history) > 5:
            rps_history.pop(0)

        m = mean(rps_history)

        if len(rps_history) == 5:
            dev = stdev(rps_history) / m
        else:
            dev = None

        log(detailed, c, n, time, rps, m, dev)

        if time < min_time:
            rps_history.pop()
            k = max(2.0, min_time / time)
            n = int(n * k)

        if dev and dev <= max_dev:
            return m, dev

        if dev:
            var_mean[dev] = m

        i += 1

    dev = min(var_mean.keys())

    return var_mean[dev], dev


if __name__ == '__main__':

    if len(sys.argv) > 1:
        url = sys.argv[1]
    else:
        url = 'http://127.0.0.1:8400/'

    c = 1

    while c < 129:
        rps, dev = filtered_ab(nreq, c, url)

        log(result, url, c, rps, dev)

        c *= 2
