#!/usr/bin/perl

use strict;
use FindBin::libs;
use PanopticCommon;

$0 =~ m"^(.*)/[^/]+$";
our $BASEDIR = "$1/..";
our $LOGDIR = "$BASEDIR/spool/targetlog";
our $STATUSDIR = "$BASEDIR/status";
our $CONFDIR = "$BASEDIR/conf";

our $LOGPATTERN = qr"^(syslog|\w+\.log)_....-..-..$";

####
my %currstate;
opendir D, $LOGDIR or die;
while( my $d = readdir D ){
	next if $d =~ m"^\.";
	next unless -f "$LOGDIR/$d";
	next unless $d =~ m"$LOGPATTERN";
	my ($dev, $inode, $mode, $nlink, $uid, $gid, $rdev, $size) = stat "$LOGDIR/$d";
	$currstate{"$d"} = {"size" => $size};
}
close D;

my %laststate;
if( open F, '<', "$STATUSDIR/logstatus" ){
	while( <F> ){
		chomp;
		my ($file, $size, $nr) = split m"\t";
		$laststate{$file} = {"size" => $size, 'nr' => $nr};
	}
	close F;
}

my %logdiff;
while( my ($file, $state) = each %currstate ){
	my $laststate = $laststate{$file};
	unless( $laststate ){
		$laststate = {'size' => 0, 'nr' => 0};
	}
	my $size = $state->{"size"};
	my $lastsize = $laststate->{"size"};
	next if $size == $lastsize;
	my $length;
	my $offset;
	if( $size > $lastsize ){
		$offset = $lastsize;
		$length = $size - $lastsize;
	} else {
		$offset = 0;
		$length = $size;
	}
	open F, '<', "$LOGDIR/$file" or die "$file: cannot open, stopped";
	seek F, $offset, 0;
	read F, $logdiff{$file}, $length;
	close F;
	my @r = split m"\n", $logdiff{$file};
	$state->{'nr'} = $laststate->{'nr'} + @r - 1;
	print hash2ltsv( {
		'logdir'  => $LOGDIR,
		'logname' => $file,
		'offset'  => $offset,
		'length'  => $length,
		'nr'      => $laststate->{'nr'} + 0,
	} ), "\n";
	foreach my $r ( @r ){
		print "\t$r\n";
	}
}

open F, '>', "$STATUSDIR/.logstatus" or die;
foreach my $file ( sort {$a cmp $b} keys %currstate ){
	my $state = $currstate{$file};
	print F join("\t", $file, $state->{'size'}, $state->{'nr'}), "\n";
}
close F;

rename "$STATUSDIR/.logstatus", "$STATUSDIR/logstatus" or die;
exit 0;

