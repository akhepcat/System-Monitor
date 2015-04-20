Collection of scripts that monitor a system or network for the plugbox service.

do-updates:  central script, called once a minute from crontab
sda1.sh: symlinkable script (per partition/drive) for disk utilization
eth0.sh: symlinkable script (per interface) for network utilization
fping.sh:  network latency for a list of hosts (in do-updates)
webspeed.sh: determines network speed by pulling a cached copy of the CNN home-page
webpage.sh: network latency to webservers listed in do-updates
uptime.sh: displays the system uptime
speedtest.sh: uses the 'BetterSpeedTest' subscribe to provide the best possible network speedtest information
memory.sh: displays the system memory information
load.sh: displays the system CPU utilization
sitestats.sh: internal script for rebuilding the web indices
