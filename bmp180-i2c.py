#!/usr/bin/python
# Copyright (c) 2014 Adafruit Industries
# Author: Tony DiCola
# see original MIT license at https://github.com/adafruit/Adafruit_Python_BMP
#
# Additional changes by Leif Sawyer for the sysmon suite
#

# Can enable debug output by uncommenting:
#import logging
#logging.basicConfig(level=logging.DEBUG)

import Adafruit_BMP.BMP085 as BMP085

# use the correct bus (this needs to be programmable later
sensor = BMP085.BMP085(busnum=4)

otemp=sensor.read_temperature()		# C, convert to F
press=sensor.read_pressure()		# Pascals, convert to milibarts
# alt=sensor.read_altitude()		# Meters, convert to feet  ## we don't use this right now

print("T/P: {:0.1f},{:0.1f}".format( ((otemp / 5 * 9)+32), (press / 100) ))
