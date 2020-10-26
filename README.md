Collection of scripts that monitor a system or network.

* do-updates:  central script, called once a minute from crontab  
* sda1.sh: symlinkable script (per partition/drive) for disk utilization  
* eth0.sh: symlinkable script (per interface) for network utilization  
* fping.sh:  network latency for a list of hosts (in do-updates)  
* webspeed.sh: determines network speed by pulling a cached copy of your-favorite-remote-website  
* webpage.sh: network latency to webservers listed in do-updates  
* uptime.sh: displays the system uptime  
* speedtest.sh: uses the 'Better(er)SpeedTest' script to provide the best possible network speedtest information- get it from its repo: https://github.com/akhepcat/BettererSpeedTest  
* memory.sh: displays the system memory information  
* load.sh: displays the system CPU utilization  
* sitestats.sh: internal script for rebuilding the web indices  
* dexcom.sh:  Monitors your Dexcom G4/G5/G6 continuous glucose monitor data
* page_load_time.pl:  called from webspeed.sh, used to display the total time to download an entire page with all dependancies  
* sysmon.conf:  placed in /etc/default, defines/overrides the script parameters  
