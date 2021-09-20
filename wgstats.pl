#!/usr/bin/perl -w
# grabs the status of wireguard, for reporting back to the sysmon scripts
use strict;

my ($in_peer, $user, $endpoint, $acl, $seen, $recv, $sent)=("","","","","","","");
my ($onc, $offc, $awayc)=(0,0,0);
my %peer;

$in_peer=0;

open(PIPE, "wg show|");
while (<PIPE>) {
    chomp;

    next unless (m/^peer/i || $in_peer);
    $in_peer=1;
    if (m/peer:(.*)/) {
      $user=$1;
    } elsif (m/endpoint:(.*)/) {
      $endpoint=$1;
    } elsif (m/allowed ips:(.*)/) {
      $acl=$1;
    } elsif (m/handshake:(.*)/) {
      $seen=$1;
    } elsif (m/transfer: (.*) received, (.*) sent/) {
      $recv=$1; $sent=$2;
    }

    if (m/^$/i) {
      my($date,$last);
      my $now=time();
      
      $in_peer=0;
      $seen =~ s/, / /g; $seen =~ s/ago//g;
      if ( $seen ) {
        $date=`date -d "- $seen" "+%s" `;
        chomp($date);
      } else {
        $date=9999999;
      }
      $last=($now - $date);

      $peer{$user}{"user"}=$user;
      $peer{$user}{"endpoint"}=$endpoint;
      $peer{$user}{"acl"}=$acl;
      $peer{$user}{"seen"}=$last;
      $peer{$user}{"status"}=( $last>300?"offline":"online" );
      $peer{$user}{"recv"}=$recv;
      $peer{$user}{"sent"}=$sent;
      
      $user="";
      $endpoint="";
      $acl="";
      $seen="";
      $recv="";
      $sent="";
    }

}

# last
# For online users:

foreach $user (keys %peer) {

  if ( $peer{$user}{"status"} eq "online" ) {
    # online
    $onc ++;    
  
  } elsif ( $peer{$user}{"seen"} <= 86400 ) {
    # away
    $awayc ++;
    
  } else {
    # offline
    $offc ++;
  }
}


print "$onc:$awayc:$offc\n";
