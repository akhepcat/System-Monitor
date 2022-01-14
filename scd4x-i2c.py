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
scd4x.temperature_offset = 7	# float celcius
# scd4x.self_calibration_enabled = False	# for CO2 calibrations, refer to manual
scd4x.persist_settings()

scd4x.start_periodic_measurement()
loop = 0
ntemp = 0
otemp = 0

# Sleep until ready
while True:
    if scd4x.data_ready:
        loop = loop + 1

        scd4x._read_data()
        ntemp = scd4x.temperature

        # Discard all but the lowest reported value over
        if ( ntemp < otemp or otemp == 0) :
            otemp = ntemp

        if loop >= 6:
            break
    time.sleep(1)

print("T/H/C: {:0.1f},{:0.1f},{:d}".format( ((otemp / 5 * 9)+32), scd4x.relative_humidity, scd4x.CO2))
