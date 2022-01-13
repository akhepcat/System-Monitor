#!/usr/bin/python3
# SPDX-FileCopyrightText: 2020 by Bryan Siepert, written for Adafruit Industries
#  see:  https://circuitpython.readthedocs.io/projects/scd4x/en/latest/api.html#implementation-notes
# SPDX-License-Identifier: Unlicense
#
# Additional changes by Leif Sawyer for the sysmon suite
#
# warm-up of the sensor takes about 5-6 seconds

import time
import board
import adafruit_scd4x

i2c = board.I2C()
scd4x = adafruit_scd4x.SCD4X(i2c)
scd4x.altitude=220	# integer meters

scd4x.start_periodic_measurement()

# Sleep until ready
while True:
    if scd4x.data_ready:
        break
    time.sleep(1)

# Convert from celcius
ftemp = (scd4x.temperature * 9 / 5) + 32

print("T/H/C: {:0.1f},{:0.1f},{:d}".format(ftemp, scd4x.relative_humidity, scd4x.CO2))
