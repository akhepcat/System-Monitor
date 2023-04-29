#!/usr/bin/perl

use HTTP::Tiny;

my $sysconf="/etc/default/sysmon.conf";

my $count;
my $ver;
my $res;
my $DEBUG=0;

my $ua  = HTTP::Tiny->new( 'verify_SSL' => '1' );
my %conf;

open(CONF, "<$sysconf") || die "Can't read from $sysconf,";
while(<CONF>) {
    chomp;
    
    if (m/^[[:space:]]*([[:alpha:]]+)="?(.*)"?/) {
        my $var=$1; $_=$2;
        s/\s+#.*//; s/"//; # remove comments and floating quotes
        $conf{"$var"}=$_;  # set the variables
        print "DBG: setting var ($var = $_))\n" if $DEBUG;
    }            

}
close(CONF);
my $cmd=$conf{"OOKLACMD"};
my $sthosts=$conf{"OOKLASVRS"};


# check to make sure the sthosts variable is set, otherwise add one to the loop
if (length($sthosts)<1) {
	$sthosts="1";
}
print "speedtest hosts is: $sthosts\n" if $DEBUG;

my @svrs = split(' ', $sthosts);
my $SVR;
my $xcmd;

if(!grep(/{SVR}/,$cmd)) {
	@svrs=(1);
}

foreach $SVR (@svrs) {
	my $content;
	$xcmd = $cmd;
	
	if(grep(/{SVR}/,$xcmd)) {
		print "DBG: cmd has server variable: ($xcmd)\n" if $DEBUG;

		$xcmd =~ s/\{SVR\}/$SVR/;

		print "DBG: piping from cmd: ($xcmd)\n" if $DEBUG;
	} else {
		print "DBG: unmodified cmd: ($xcmd)\n" if $DEBUG;
	}

	open (CSV, "$xcmd 2>/dev/null|") || die "can't execute speedtest ($xcmd) for data import";
	while(<CSV>) {
		chomp;

		print "DBG: speedtest results ($_)\n" if $DEBUG;
		s/^"//; s/"$//;	#remove leading and trailing quotes, we don't need 'em
		s|N/A|0|g;
	
		# "Example Speedtest Server","12345","8.505","2.851","N/A","248501521","9274691","2072280746","48526824","https://www.speedtest.net/result/c/98765432-1111-2222-3333-abcdef123456"
		# header: "server name","server id","latency","jitter","packet loss","download","upload","download bytes","upload bytes","share url"
		#  index:    0              1          2        3         4             5           6          7                8             9
	
		@data = split(/\",\"/, $_);

	}
	close(CSV);

	$count=scalar(@down);

	# uses the following format:
		# measurement,tag=tval,tag=tval data=val
	$content= "speedtest,host=".$conf{"SERVERNAME"}.",serverid=".$data[1]." download=". ($data[5] * 8) .
		"\nspeedtest,host=".$conf{"SERVERNAME"}.",serverid=".$data[1]." upload=". ($data[6] * 8) .
		"\nspeedtest,host=".$conf{"SERVERNAME"}.",serverid=".$data[1]." jitter=".  $data[3] .
		"\nspeedtest,host=".$conf{"SERVERNAME"}.",serverid=".$data[1]." loss=". $data[4] .
		"\nspeedtest,host=".$conf{"SERVERNAME"}.",serverid=".$data[1]." latency=". $data[2];

	print $content . "\n" if $DEBUG;

    if($DEBUG<=2) {
	if (length($conf{"INFLUXURL"})) {
	        print "DBG: pinging influxdb\n" if $DEBUG;
		my $purl = $conf{"INFLUXURL"};
		$purl =~ s/write.*//;
		$res = $ua->request(
		    'HEAD' => $purl . "/ping",
		    {
		        headers => {
		            'User-Agent' => 'curl/7.55.1',
		            'Accept'     => '*/*'
		        },
		    },
		);
		$ver=$res->{'headers'}->{'x-influxdb-version'};

		if (length($conf{"INFLUXURL"}) && length($ver)) {
		        print "DBG: ok: setting up call to influxdb\n" if $DEBUG;

			$res = $ua->request(
			    'POST' => $conf{"INFLUXURL"} ,
			    {
			        headers => {
			            'Content-Type'   => 'application/x-www-form-urlencoded',
			            'Accept'         => '*/*',
			            'User-Agent'     => 'pcurl/1.0',
			            'Content-Length' => length($content)
			        },
				content => $content
			    },
			);

		        print "DBG: result is " . $res->{'success'} . "\n" if $DEBUG;
			if ($res->{'success'} eq 1) {
				print "update successful\n" if $DEBUG;
			} else {
				print "error updating influxdb!\n";
			}
		} else {
			print "influxdb not available\n";
		}

	} else {
		print "influxdb not configured\n";
	}

    }

    sleep(60) if (scalar(@svrs) > 1);
}
