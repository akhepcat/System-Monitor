#!/usr/bin/perl -w
use Time::HiRes qw( sleep gettimeofday tv_interval );
$WGET = "/usr/bin/wget";
$TMPD=`/usr/bin/mktemp -d`;
chomp($TMPD);

$SITE = $ARGV[0];
chomp($SITE);

$check = "$WGET -T 30 -o $TMPD/tmp.log -p --no-cache -nd -P $TMPD/ $SITE";

$t0 = [gettimeofday];
`$check`;
$elapsed = tv_interval ( $t0, [gettimeofday]);


`rm -rf $TMPD` if (-d $TMPD);

print "$elapsed\n";
