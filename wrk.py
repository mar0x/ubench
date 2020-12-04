#!/usr/bin/env python3

# vim:ts=4:sts=4:sw=4:et

import math
import os
import re
import resource
import subprocess
import sys
from statistics import mean, stdev, variance
from datetime import datetime

nreq = 10000
mydir = os.path.dirname(sys.argv[0])
wrk_bin = os.path.join(mydir, 'wrk', 'wrk')
max_threads = 8

detailed = open("detailed.log", 'a')
result = open("result.txt", 'a')

def log(f, *args):
    t = datetime.now().strftime("%H:%M:%S")
    a = [ str(i) for i in args ]
    print(t + ' ' + ' '.join(a))
    print(t + ' ' + ' '.join(a), file=f)
    f.flush()

def wrk(n, c, url):
    t = min(max_threads, c)
    p = subprocess.Popen([wrk_bin, '-d', '10', '-c', str(c), '-t', str(t), url],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    o, e = p.communicate()

    rc = p.returncode

    if rc != 0:
        print(str(o) + '\n' + str(e))
        return None

    res = dict()

    for l in o.split(b'\n'):
        r = re.search(b'^([^/]+/sec):\s+(.+)$', l)
        if r:
            v = r[2]
            try:
                res[r[1]] = float(v)
            except ValueError:
                res[r[1]] = v
            continue

        r = re.search(b'^\s*([0-9]+)\s+requests in\s+([0-9.]+)', l)
        if r:
            res[b'time'] = float(r[2])
            res[b'requests'] = int(r[1])

    return res

def filtered_wrk(n, c, url, min_time=1.0, max_dev=0.01):
    rps_history = []
    var_mean = {}

    i = 0
    if n < c:
        n = c

    while i < 10:
        r = wrk(n, c, url)

        if r is None:
            break

        rps = r[b'Requests/sec']
        time = r[b'time']
        total = r[b'requests']

        rps_history.append(rps)

        m = mean(rps_history[-5:])

        if len(rps_history) >= 5:
            dev = stdev(rps_history[-5:]) / m
        else:
            dev = None

        log(detailed, c, total, time, rps, m, dev)

        if dev and dev <= max_dev:
            return m, dev, min(rps_history), max(rps_history)

        if dev:
            var_mean[dev] = m

        i += 1

    dev = min(var_mean.keys())

    return var_mean[dev], dev, min(rps_history), max(rps_history)

if __name__ == '__main__':

    url = 'http://127.0.0.1:8400/'
    c = 1

    if len(sys.argv) > 1:
        url = sys.argv[1]

    if len(sys.argv) > 2:
        c = int(sys.argv[2])

    resource.setrlimit(resource.RLIMIT_NOFILE, (65536, 65536))

    while c <= 16384:
        rps, dev, min_rps, max_rps = filtered_wrk(nreq, c, url)

        log(result, url, c, rps, dev, min_rps, max_rps)

        if c < 1024:
            c *= 2
        else:
            c += 1024
