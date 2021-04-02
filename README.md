# System Monitor

A loosely bound collection of scripts that monitor a system or network.

# Contents

* do-updates:  central script, called once a minute from crontab  
* sda1.sh: symlinkable script (per partition/drive) for disk utilization  
* eth0.sh: symlinkable script (per interface) for network utilization  
* fping.sh:  network latency for a list of hosts (in do-updates)  
* response.sh:  creates/updates a single-page index for all fping graphs
* webspeed.sh: determines network speed by pulling a cached copy of your-favorite-remote-website  
* webpage.sh: network latency to webservers listed in do-updates  
* uptime.sh: displays the system uptime  
* speedtest.sh: uses the 'Better(er)SpeedTest' script to provide the best possible network speedtest information- get it from its repo: https://github.com/akhepcat/BettererSpeedTest  
* memory.sh: displays the system memory information  
* load.sh: displays the system CPU utilization  
* sitestats.sh: internal script for rebuilding the web indices  
* dexcom.sh:  Monitors your Dexcom G4/G5/G6 continuous glucose monitor data
* bmp180.sh:  Monitors the temperature and humidity on a Raspberry Pi using a BMP180 or compatible sensor
* resolvers.sh: Monitors the response time for DNS resolvers
* page_load_time.pl:  called from webspeed.sh, used to display the total time to download an entire page with all dependancies  
* sysmon.conf:  placed in /etc/default, defines/overrides the script parameters  


# Supported datastores

* rrdtool - the default datastore, supported by all scripts 
* InfluxDB - a work in progress, supported by very few of the scripts

# Usage

Read the source, Luke! and the config file.  It's pretty simple!

# Bugs

It's probably got some.   

