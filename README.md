# System Monitor

A loosely bound collection of scripts that monitor a system or network.

# Contents

* do-updates:  central script, called once a minute from crontab  
* sda1.sh: symlinkable script (per partition/drive) for disk utilization  
* eth0.sh: symlinkable script (per interface) for network utilization  
* netifs.sh: auto-discovering script for network utilization, returns all active i/f's, can exclude lo in the config file
* fping.sh:  network latency for a list of hosts (in do-updates)  
* response.sh:  creates/updates a single-page index for all fping graphs
* webspeed.sh: determines network speed by pulling a cached copy of your-favorite-remote-website  
* webpage.sh: network latency to webservers listed in do-updates  
* uptime.sh: displays the system uptime  
* speedtest.sh: uses the 'Better(er)SpeedTest' script to provide the best possible network speedtest information- get it from its repo: https://github.com/akhepcat/BettererSpeedTest  
* ookla.pl:  uses the ookla official cli command.  MaxMind GeoIP issues may restrict what servers you can see
* memory.sh: displays the system memory information  
* load.sh: displays the system CPU utilization  
* sitestats.sh: internal script for rebuilding the web indices  
* dexcom.sh:  Monitors your Dexcom G4/G5/G6 continuous glucose monitor data
* bmp180.sh:  Monitors the temperature and air pressure on a Raspberry Pi using a BMP180 or compatible sensor
* scd4x.sh:   Monitors the temperature, humidity, and CO2 levels on a Raspberry Pi using an SCD40/SCD41 sensor (adafruit!)
* scd4x-i2c.py: Polls data from the SCD4x sensor over i2c - use "pip3 install adafruit-circuitpython-scd4x" for dependencies
* resolvers.sh: Monitors the response time for DNS resolvers
* page_load_time.pl:  called from webspeed.sh, used to display the total time to download an entire page with all dependancies  
* sysmon.conf:  placed in /etc/default, defines/overrides the script parameters  


# Supported datastores

* rrdtool - the default datastore, supported by all scripts 
* InfluxDB - a work in progress, supported by very few of the scripts

# Usage

Read the source, Luke! and the config file.  It's pretty simple!

tl;dr -  assuming you're running as root
1) copy the sysmon.conf  into  /etc/default
2) determine which modules (scripts) you want to run by default, and edit that line in the config file
3) run the 'do-updates' script in 'debug' mode, verify that polls are working, correct all errors
4) run the 'do-updates' in 'create' mode, to generate all the required databases
5) call the 'do-updates' script from cron every minute, and it'll do the rest

# Bugs

It's probably got some.   

