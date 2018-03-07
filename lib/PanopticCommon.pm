#!/usr/bin/perl

package PanopticCommon;
use strict;
use Exporter;
use Encode;
use MIME::EncWords ':all';

our @ISA = ('Exporter');
our @EXPORT = (
	'hash2ltsv', 'ltsv2hash', 'mergehash',
	'timestamp', 'now',
	'timestamp2unixtime', 'unixtime2timestamp',
	'template', 'execcmd', 'sendmail', 'panopticdlog'
);

$0 =~ m"^(.*/)[^/]+$";
our $BASEDIR = "$1/..";
our $RUNDIR = "$BASEDIR/run";
our $LOGDIR = "$BASEDIR/log";
our $SENDMAILEXE = '/usr/lib/sendmail';

####
sub ltsv2hash ($) {
	my ($text) = @_;
	my %hash;
	foreach my $column ( split m"\t", $text ){
		next unless $column =~ m"^(\w+):(.*)$";
		my $k = $1;
		my $v = $2;
		$v =~ s{\\x([0-9a-fA-F]{2})}{ pack('H2', $1); }eg;
		$hash{$k} = $v;
	}
	return \%hash;
}

sub hash2ltsv ($) {
	my ( $hash ) = @_;
	my @r;
	foreach my $k ( sort {$a cmp $b} keys %$hash ){
		my $v = $hash->{$k};
		$v =~ s{([\x00-\x1f\x7e\\])}{ '\x' . unpack('H2', $1); }e;
		push @r, "$k:$v";
	}
	return join "\t", @r;
}

sub mergehash (\%\%) {
	my ( $h1, $h2 ) = @_;
	my %r = %$h2;
	while( my ($k, $v) = each %$h1 ){
		$r{$k} = $v;
	}
	return \%r;
}

sub timestamp () {
	my ($sec, $min, $hour, $day, $mon, $year) = localtime time;
	return sprintf "%04d-%02d-%02d_%02d:%02d", $year+1900, $mon+1, $day, $hour, $min;
}

sub now () {
	my ($sec, $min, $hour, $day, $mon, $year) = localtime;
	return sprintf "%04d-%02d-%02d_%02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec;
}

sub timestamp2unixtime ($) {
	my ( $timestamp ) = @_;
	return 0 unless $timestamp =~ m"^(\d{4})-(\d{2})-(\d{2})_(\d{2}):(\d{2})";
	return timelocal(0, $5, $4, $3, $2-1, $1-1900);
}

sub unixtime2timestamp ($) {
	my ( $unixtime ) = @_;
	my ($sec, $min, $hour, $day, $mon, $year) = localtime $unixtime;
	return sprintf '%04d-%02d-%02d_%02d:%02d', $year+1900, $mon+1, $day, $hour, $min;
}

sub template ($@) {
	my ($string, @params) = @_;
	$string =~ s{%\{(\w+)\}}{
		my $r = undef;
		foreach my $param ( @params ){
			$r = $param->{$1} if defined $param->{$1};
		}
		$r;
	}eg;
	return $string;
}

sub execcmd ($$$) {
	my ($cmd, $infile, $outfile) = @_;
	$infile = "/dev/null" unless defined $infile;
	$outfile = "/dev/null" unless defined $outfile;
	my $errfile = "$RUNDIR/stderr_$$.log";
	my $pid = fork;

	unless( $pid ){
		open STDERR, '>',  $errfile or die;
		open STDOUT, '>>', $outfile or die;
		open STDIN,  '<',  $infile  or die;
		exec @$cmd;
		exit 255;
	}

	my $child_pid = waitpid $pid, 0;
	my $rc = $?;
	my $err;
	if( open F, '<', $errfile ){
		$err = join '', <F>;
		close F;
		unlink $errfile or die;
	}
	return ($rc, $err);
}

sub panopticdlog ($;@) {
	my ($format, @args) = @_;
	unless(fileno LOG){
		open LOG, '>>', "$LOGDIR/panopticd.log" or die;
		LOG->autoflush(1);
	}
	my $timestamp = timestamp;
	my $text = sprintf $format, @args;
	$text =~ s{([\x00-\x1f\x7e\\])}{ '\x' . unpack('H2', $1); }e;
	print LOG "$timestamp panopticd: $text\n";
}

sub sendmail ($$$) {
	my ($mail, $mailfrom, $mailto) = @_;
	my $from_quoted = quotemeta $mailfrom;
	my $to_quoted = quotemeta $_;

	#open E, '|-', "$SENDMAILEXE -f $from_quoted $to_quoted" or die;
	open E, '|-', "cat" or die;
	chomp $mail;
	my @mail = split m"\n", $mail;
	while( $_ = shift @mail ){
		#$_ = decode_utf8( $_ );
		last if $_ eq '';

		my $text = encode_mimewords $_;
		print E encode_utf8($text), "\n";
	}
	print E "MIME-Version: 1.0\n";
	print E "Content-Transfer-Encoding: 8bit\n";
	print E "Content-Type: text/plain; charset=utf-8\n",
		"\n";
	while( $_ = shift @mail ){
		my $text = decode_utf8( $_ );
		print E encode_utf8($text), "\n";
	}
	close E;
}

1;

