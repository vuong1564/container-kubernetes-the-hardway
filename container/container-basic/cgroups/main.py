#!/usr/bin/env python3
import time
f = open("/dev/zero", "rb")
data = b""

i=0
while True:
    data += f.read(10000000) # 10mb
    i += 1
    print("%dmb" % (i*10,))
    time.sleep(1)
