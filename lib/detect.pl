#!/usr/bin/perl

use strict;
use FindBin::libs;
use PanopticCommon;

$0 =~ m"^(.*)/[^/]+$";
our $BASEDIR = "$1/..";

our $CONFDIR = "$BASEDIR/conf";
our $PATTERNDIR = "$BASEDIR/conf/pattern";

####
sub read_patternset {
	my ( $patternsetname ) = @_;
	my %patternset = (
		're' => undef,
		'attr' => {},
		'source' => {},
	);
	my $f = "$patternsetname.patternset";
	my $type;
	open F, '<', "$PATTERNDIR/$f" or die "$f: cannot open, stopped";
	while( <F> ){
		chomp;
		unless( m"^(\w+)\t"p ){
			print STDERR "$f:$.: syntax error.\n";
			next;
		}
		my $paramname = $1;
		if    ( $paramname eq 'type' ){
			$type = ${^POSTMATCH};
			$patternset{'type'} = $type;
		}elsif( $paramname eq 're' ){
			$patternset{'re'} =  ${^POSTMATCH};
		}elsif( $paramname eq 'attr' ){
			$patternset{'attr'} = ltsv2hash( ${^POSTMATCH} );
		}elsif( $paramname eq 'subpatternset_attrs' ){
			unless( m"^(\w+)\t(\d+)\t"p ){
				print STDERR "$f:$.: syntax error.\n";
				next;
			}
			my $index = $2;
			$patternset{'attrs'}->[$index] = ltsv2hash( ${^POSTMATCH} );
		}elsif( $paramname eq 'include_patternfiles' ){
			$patternset{'include_patternfiles'} = [ split m"\t", ${^POSTMATCH} ];
		}elsif( $paramname eq 'subpatternset_names' ){
			die;
		}else{
			die;
		}
	}
	close F;
	return \%patternset;
}

####
sub context_is_valid ($$$$) {
	my ($context, $available_context, $location, $arg) = @_;
	foreach my $a (@{$available_context}){
		return 1 if $context eq $a;
	}
	print STDERR "$location:$arg: not allowed by context.\n";
	return undef;
}

sub lastdetect_is_valid ($$) {
	my ($lastdetect, $location) = @_;
	return 1 unless defined $lastdetect;
	if( $lastdetect->{'action'} eq 'detect' ){
		print STDERR "$location: need patternset clause.\n" and
		return undef unless $lastdetect->{'patternset'};
		print STDERR "$location: need eventname clause.\n" and
		return undef unless $lastdetect->{'eventname_set'};
		print STDERR "$location: need priority clause.\n" and
		return undef unless $lastdetect->{'priority_set'};
	}elsif( $lastdetect->{'action'} eq 'ignore' ){
		print STDERR "$location: need patternset clause.\n" and
		return undef unless $lastdetect->{'patternset'};
	}elsif( $lastdetect->{'action'} eq 'default' ){
		print STDERR "$location: need eventname clause.\n" and
		return undef unless $lastdetect->{'eventname_set'};
		print STDERR "$location: need priority clause.\n" and
		return undef unless $lastdetect->{'priority_set'};
	}else{
		die $lastdetect->{'action'} . ", stopped";
	}
	return 1;
}

sub lastdetection_is_valid ($$$) {
	my ($lastdetection, $lastdetect, $location) = @_;
	return 1 unless defined $lastdetection;
	print STDERR "$location: need least one detect clause.\n" and
	return undef unless @{$lastdetection->{'detect'}};
	return lastdetect_is_valid( $lastdetect, $location);
}

sub read_detect_conf {
	open F, '<', "$CONFDIR/detect.conf" or die;
	my $confname = "detect.conf";

	my $error;
	my @rules;
	my $context;
	my $lastdetection;
	my $lastdetect;
	while( <F> ){
		chomp;
		s{^\s*}{};
		next if m"^$";
		next if m"^#";
		my @c = split m"\s+";
		if( $c[0] eq "detection" ){
			$error = 1 unless lastdetection_is_valid(
				$lastdetect, $lastdetection, "$confname:$.",
			);
			$lastdetection = {
				'if_logname_matches' => [],
				'capture_from_logname' => [],
				'if_message_matches' => [],
				'capture_from_message' => [],
				'if' => [],
				'detect' => [],
			};
			$context = 'detection';
			push @rules, $lastdetection;
		}elsif(	$c[0] eq "if_logname_matches" ){
			next unless context_is_valid(
				$context, ['detection'],
				"$confname:$.", $c[0],
			);
			my $re = $c[1];
			push @{$lastdetection->{'if_logname_matches'}}, qr"^$re$";
		}elsif(	$c[0] eq "capture_from_logname" ){
			next unless context_is_valid(
				$context, ['detection'],
				"$confname:$.", $c[0],
			);
			my $attrname = $c[1];
			my $re = $c[2];
			push @{$lastdetection->{'capture_from_logname'}}, [$attrname, qr"$re"];
		}elsif(	$c[0] eq "if_message_matches" ){
			next unless context_is_valid(
				$context, ['detection'],
				"$confname:$.", $c[0],
			);
			my $re = $c[1];
			push @{$lastdetection->{'if_message_matches'}}, qr"^$re$";
		}elsif(	$c[0] eq "capture_from_message" ){
			next unless context_is_valid(
				$context, ['detection'],
				"$confname:$.", $c[0],
			);
			my $attrname = $c[1];
			my $re = $c[2];
			push @{$lastdetection->{'capture_from_message'}}, [$attrname, qr"$re"];
		}elsif(	$c[0] eq "if" ){
			next unless context_is_valid(
				$context, ['detection'],
				"$confname:$.", $c[0],
			);
			my $left = $c[1];
			my $op = $c[2];
			my $right = $c[3];
			push @{$lastdetection->{'if'}}, [$left, $op, $right];
		}elsif(	$c[0] eq "detect" ){
			$error = 1 unless lastdetect_is_valid(
				$lastdetect, "$confname:$.",
			);
			next unless context_is_valid(
				$context, ['detection', 'detect', 'ignore'],
				"$confname:$.", $c[0],
			);
			my $eventname = $c[1];
			$lastdetect = {
				'action' => 'detect',
				'patternset' => undef,
				'exclude_patternset' => undef,
				'set' => [
					['eventname' => $eventname],
				],
				'eventname_set' => undef,
				'priority' => undef,
			};
			$context = 'detect';
			push @{$lastdetection->{'detect'}}, $lastdetect;
		}elsif(	$c[0] eq "patternset" ){
			next unless context_is_valid(
				$context, ['detect', 'ignore'],
				"$confname:$.", $c[0],
			);
			my $patternsetname = $c[1];
			$lastdetect->{'patternset'} = $patternsetname;
		}elsif(	$c[0] eq "exclude_pattrnset" ){
			next unless context_is_valid(
				$context, ['detect', 'ignore'],
				"$confname:$.", $c[0],
			);
			my $patternsetname = $c[1];
			$lastdetect->{'exclude_patternset'} = $patternsetname;
		}elsif(	$c[0] eq "set" ){
			next unless context_is_valid(
				$context, ['detect', 'default'],
				"$confname:$.", $c[0],
			);
			my $name = $c[1];
			my $value = $c[2];
			push @{$lastdetect->{'set'}}, [$name => $value];
		}elsif(	$c[0] eq "eventname" ){
			next unless context_is_valid(
				$context, ['detect', 'default'],
				"$confname:$.", $c[0],
			);
			my $value = $c[1];
			push @{$lastdetect->{'set'}}, ['eventname' => $value];
			$lastdetect->{'eventname_set'} = 1;
		}elsif(	$c[0] eq "priority" ){
			next unless context_is_valid(
				$context, ['detect', 'default'],
				"$confname:$.", $c[0],
			);
			my $value = $c[1];
			$lastdetect->{'priority_set'} = 1;
		}elsif(	$c[0] eq "ignore" ){
			$error = 1 unless lastdetect_is_valid(
				$lastdetect, "$confname:$.",
			);
			next unless context_is_valid(
				$context, ['detection', 'detect'],
				"$confname:$.", $c[0],
			);
			$lastdetect = {
				'action' => 'ignore',
				'patternset' => undef,
				'exclude_patternset' => undef,
			};
			$context = 'ignore';
			push @{ $lastdetection->{'detect'} }, $lastdetect;
		}elsif(	$c[0] eq "default" ){
			$error = 1 unless lastdetect_is_valid(
				$lastdetect, "$confname:$.",
			);
			next unless context_is_valid(
				$context, ['detection', 'detect', 'ignore'],
				"$confname:$.", $c[0],
			);
			$lastdetect = {
				'action' => 'default',
				'patternset' => undef,
				'exclude_patternset' => undef,
				'set' => [
					['eventname' => 'default'],
				],
				'eventname_set' => undef,
				'priority' => undef,
			};
			$context = 'default';
			push @{ $lastdetection->{'detect'} }, $lastdetect;
		}else{
			print STDERR "$confname:$.", $c[0], ": syntax error.\n";
			next;
		}
	}
	close F;

	return {
		'rules' => \@rules,
		'patternsetmap' => {},
	};
}

####
sub detect_patternset ($$$$) {
	my ($patternsetmap, $patternsetname, $runtime_attr, $message) = @_;
	my $pn = template( $patternsetname, $runtime_attr );
	return () if $pn eq '';

	my $p = $patternsetmap->{$patternsetname};
	unless( defined $p ){
		$p = read_patternset( $patternsetname );
		$patternsetmap->{$patternsetname} = $p;
	}

	my @r;
	my $type = $p->{'type'};
	my $re = $p->{'re'};
	if    ( $type eq 'simple' ){
#print STDERR "DEBUG1: $message =~ $re\n";
		return () unless $message =~ m"$re";
#print STDERR "DEBUG1: HIT: $message\n";
		my $patternset_attr = $p->{'attr'};
		push @r, {
			'type' => 'event',
			'message' => $message,
			'attr' => mergehash(%$runtime_attr, %$patternset_attr),
		};
	}elsif( $type eq 'single_matchable' ){
		my @m;
		$message =~ m"$re";
		return () unless @m;
		my $subpatternset_attrs = $p->{'subpatternset_attrs'};
		my $subpatternset_attr = $subpatternset_attrs->[ $m[0] ];
		push @r, {
			'attr' => mergehash(%$runtime_attr, %$subpatternset_attr),
		};
	}elsif( $type eq 'multi_matchable' ){
		my @m;
		$message =~ m"$re";
		return () unless @m;
		my $subpatternset_attrs = $p->{'subpatternset_attrs'};
		foreach my $m ( @m ){
			my $subpatternset_attr = $subpatternset_attrs->[ $m ];
			push @r, {
				'type' => 'event',
				'message' => $message,
				'attr' => mergehash(%$runtime_attr, %$subpatternset_attr),
			};
		}
	}else{
		die;
	}
	return @r;
}

sub detect_internal ($$$) {
	my ($detector, $patternsetmap, $message) = @_;

	my ($rule, $runtime_attr) = @$detector;
	foreach my $re ( @{$rule->{'if_message_matches'}} ){
		return () unless $message =~ m"$re";
	}
	foreach my $capture ( @{ $rule->{'capture_from_message'} } ){
		my ($attrname, $re) = @$capture;
		if( $message =~ m"$re" ){
			$runtime_attr->{$attrname} = $1;
		}else{
			$runtime_attr->{$attrname} = undef;
		}
	}

#print STDERR "DEBUG3: $message\n";
	my @result;
	foreach my $detect ( @{$rule->{'detect'}} ){
		my $action = $detect->{'action'};
#print STDERR "DEBUG4: $action\n";
		if    ( $action eq 'detect' ){
			my @detect_result = detect_patternset(
				$patternsetmap, $detect->{'patternset'},
				$runtime_attr, $message
			);
			next unless @detect_result;
			my @detect_exclude_result = detect_patternset(
				$patternsetmap, $detect->{'exclude_patternset'},
				$runtime_attr, $message
			);
			next if @detect_exclude_result;

			# override event-attributes by detect-attributes
			my $set = $detect->{'set'};
			foreach my $event ( @detect_result ){
				my $event_attr = $event->{'attr'};
				foreach my $e ( @{$set} ){
					$event_attr->{$e->[0]} = template( $e->[1], $event_attr );
				}
				push @result, $event;
			}
			last;
		}elsif( $action eq 'ignore' ){
			my @detect_result = detect_patternset(
				$patternsetmap, $detect->{'patternset'},
				$runtime_attr, $message
			);
			next unless @detect_result;
			my @detect_exclude_result = detect_patternset(
				$patternsetmap, $detect->{'exclude_patternset'},
				$runtime_attr, $message
			);
			next if @detect_exclude_result;
			last;
		}elsif( $action eq 'default' ){
			# create event
			my $event_attr = { %$runtime_attr };
			my $set = $detect->{'set'};
			foreach my $e ( @{$set} ){
				$event_attr->{$e->[0]} = template( $e->[1], $event_attr );
			}
			push @result, {
				'type' => 'event',
				'message' => $message,
				'attr' => $event_attr,
			};
			last;
		}else{
			die;
		}
	}
	return @result;
}

####
sub detect {
	my $conf = read_detect_conf();
	my $patternsetmap = $conf->{'patternsetmap'};
	my $detection_rules = $conf->{'rules'};

	my @runtime_detector;
	my @event;
	while( <STDIN> ){
		chomp;
		if( m"^\t"p ){
			my $message = ${^POSTMATCH};
			OUTSIDE:
			foreach my $detector ( @runtime_detector ){
				push @event, detect_internal($detector, $patternsetmap, $message);
				$detector->[1]->{'nr'}++;
			}

#print STDERR "DEBUG5: ", $log_attr->{"nr"}, "\n";
		}else{
			@runtime_detector = ();
#print STDERR "DEBUG2: $logname=================================================\n";
			my $log_attr = ltsv2hash( $_ );
			my $logname = $log_attr->{'logname'};
			OUTSIDE:
			foreach my $rule ( @{$detection_rules} ){
				foreach my $re ( @{$conf->{'if_logname_matches'}} ){
					next OUTSIDE unless $logname =~ m"$re";
				}

				my %runtime_attr = (
					'logname' => $logname,
					%$log_attr,
				);
#print STDERR "DEBUG5: ", join(' ', %runtime_attr), "\n";
				foreach my $capture ( @{ $conf->{'capture_from_logname'} } ){
					my ($attrname, $re) = @{$capture};
					if( $logname =~ m"$re" ){
						$runtime_attr{$attrname} = $1;
					}else{
						$runtime_attr{$attrname} = undef;
					}
				}
				push @runtime_detector, [$rule, \%runtime_attr];
			}

			# TODO: 一個も runtime_detector がない時

			#
		}
	}

	foreach my $event ( @event ){
		my $attr = hash2ltsv( $event->{'attr'} );
		my $message = $event->{'message'};
		print "attr\t$attr\n";
		print "\t$message\n";
	}
	#my ($out, $in);
	#open2($out, $in, "$dir E, '-|$TARGETDIR or die;
	#while( <D> ){
}


####
detect();
