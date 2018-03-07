#!/usr/bin/perl

use strict;
use Time::Local;
use FindBin::libs;
use PanopticCommon;

$0 =~ m"^(.*)/[^/]+$";
our $BASEDIR = "$1/..";
our $ENVELOPEDIR = "$BASEDIR/spool/envelope";
our $POSTDIR = "$BASEDIR/spool/post";
our $STATUSDIR = "$BASEDIR/status";
our $CONFDIR = "$BASEDIR/conf";

####
sub read_envelope_status () {
	my %laststatus;
	if( open F, '<', "$STATUSDIR/envelopestatus" ){
		while( <F> ){
			chomp;
			my ($envelopename, $lastsend_timestamp, $create_timestamp) = split m"\t";
			$laststatus{$envelopename} = {
				'lastsend' => timestamp2unixtime $lastsend_timestamp,
				'create' => timestamp2unixtime $create_timestamp,
			};
		}
		close F;
	}
	return \%laststatus;
}

sub write_envelope_status ($) {
	my ( $status ) = @_;
	open F, '>', "$STATUSDIR/envelopestatus" or die;
	foreach my $envelopename ( sort {$a cmp $b} keys %$status ){
		my $s = $status->{$envelopename};
		print F join("\t",
			$envelopename,
			unixtime2timestamp $s->{'lastsend'},
			unixtime2timestamp $s->{'create'}
		), "\n";
	}
	close F;
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

sub lastrule_is_valid ($$) {
	my ($lastrule, $location) = @_;
	return 1 unless defined $lastrule;
	if( $lastrule->{'type'} eq 'delivery_by_mail' ){
		print STDERR "$location: need envelopename clause.\n" and
		return undef unless $lastrule->{'envelopename'};
	}elsif( $lastrule->{'type'} eq 'envelope' ){
	}else{
		die $lastrule->{'type'} . ", stopped";
	}
	return 1;
}

sub read_delivery_conf {
	open F, '<', "$CONFDIR/delivery.conf" or die;
	my $confname = "delivery.conf";
	my %patternsetmap;
	my @delivery_rules;
	my @envelope_rules;
	my $context;
	my $last;
	my $error_occurred;
	while( <F> ){
		chomp;
		s{^\s*}{};
		next if m"^$";
		next if m"^#";
		my @c = split m"\s+";
		if( $c[0] eq "delivery_by_mail" ){
			$error_occurred = 1 unless lastrule_is_valid(
				$last, "$confname:$."
			);
			$last = {
				'type' => 'delivery_by_mail',
				'if_eventname_matches' => [],
				'if_priority_matches' => [],
				'capture_from_eventname' => [],
				'capture_from_priority' => [],
				'if' => [],
			};
			$context = 'delivery';
			push @delivery_rules, $last;
		}elsif(	$c[0] eq "if_eventname_matches" ){
			next unless context_is_valid(
				$context, ['delivery'],
				"$confname:$.", $c[0]
			);
			my $re = $c[1];
			push @{$last->{'if_eventname_matches'}}, qr"^$re$";
		}elsif(	$c[0] eq "if_priority_matches" ){
			next unless context_is_valid(
				$context, ['delivery'],
				"$confname:$.", $c[0]
			);
			my $re = $c[1];
			push @{$last->{'if_priority_matches'}}, qr"^$re$";
		}elsif(	$c[0] eq "capture_from_eventname" ){
			next unless context_is_valid(
				$context, ['delivery'],
				"$confname:$.", $c[0]
			);
			my $attrname = $c[1];
			my $re = $c[2];
			push @{$last->{'capture_from_eventname'}}, [$attrname, qr"$re"];
		}elsif(	$c[0] eq "capture_from_priority" ){
			next unless context_is_valid(
				$context, ['delivery'],
				"$confname:$.", $c[0]
			);
			my $attrname = $c[1];
			my $re = $c[2];
			push @{$last->{'capture_from_priority'}}, [$attrname, qr"$re"];
		}elsif(	$c[0] eq "if" ){
			next unless context_is_valid(
				$context, ['delivery'],
				"$confname:$.", $c[0]
			);
			my $left = $c[1];
			my $op = $c[2];
			my $right = $c[1];
			push @{$last->{'if'}}, [$left, $op, $right];
		}elsif(	$c[0] eq "envelopename" ){
			next unless context_is_valid(
				$context, ['delivery'],
				"$confname:$.", $c[0]
			);
			my $envelopename = $c[1];
			$last->{'envelopename'} = $envelopename;
		}elsif( $c[0] eq "envelope" ){
			$error_occurred = 1 unless lastrule_is_valid(
				$last, "$confname:$."
			);
			$last = {
				'type' => 'envelope',
				'if_envelopename_matches' => [],
				'capture_from_envelopename' => [],
				'set' => [],
				'recipient_address' => [],
				'send_wait_minutes' => undef,
				'resend_wait_minutes' => undef,
				'sending_time_of_day' => undef,
				'sending_day_of_week' => undef,
				'mail_template' => undef,
				'snippet_template' => undef,
				'concatenate_messages_by' => undef,
			};
			$context = 'envelope';
			push @envelope_rules, $last;
		}elsif(	$c[0] eq "if_envelopename_matches" ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $re = $c[1];
			push @{$last->{'if_envelopename_matches'}}, qr"^$re$";
		}elsif(	$c[0] eq "capture_from_envelopename" ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $attrname = $c[1];
			my $re = $c[2];
			push @{$last->{'capture_from_envelopename'}}, [$attrname, qr"$re"];
		}elsif(	$c[0] eq "set" ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $attrname = $c[1];
			my $attrvalue = $c[2];
			push @{$last->{'set'}}, [$attrname, $attrvalue];
		}elsif(	$c[0] eq 'recipient_address' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $email = $c[1];
			# TODO: configure recipient name
			# TODO: configure sender addr and name
			push @{$last->{'recipient_address'}}, $email;
		}elsif(	$c[0] eq 'send_wait_minutes' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $min = $c[1];
			$last->{'send_wait_minutes'} = $min;
		}elsif(	$c[0] eq 'resend_wait_minutes' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $min = $c[1];
			$last->{'resend_wait_minutes'} = $min;
		}elsif(	$c[0] eq 'sending_time_of_day' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $time_of_day = $c[1];
			$last->{'sending_time_of_day'} = $time_of_day;
		}elsif(	$c[0] eq 'sending_day_of_week' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $day_of_week = $c[1];
			$last->{'sending_day_of_week'} = $day_of_week;
		}elsif(	$c[0] eq 'mail_template' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $templatename = $c[1];
			$last->{'mail_template'} = $templatename;
		}elsif(	$c[0] eq 'snippet_template' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $templatename = $c[1];
			$last->{'snippet_template'} = $templatename;
		}elsif(	$c[0] eq 'concatenate_messages_by' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $attrs = $c[1];
			$last->{'concatenate_messages_by'} = $attrs;
		}else{
			print STDERR "$confname:$.:", $c[0], ": syntax error.\n";
			next;
		}
	}
	close F;

	return {
		'delivery_rules' => \@delivery_rules,
		'envelope_rules' => \@envelope_rules,
	};
}

####
sub delivery {
	my $conf = read_delivery_conf();
	my $delivery_rules = $conf->{'delivery_rules'};
	my $envelope_rules = $conf->{'envelope_rules'};
	my @event_dst;
	my %envelope;

	while( <STDIN> ){
		chomp;
		if( m"^(\w+)\t"p ){
			@event_dst = ();
			my $event_attr = ltsv2hash( ${^POSTMATCH} );
			my $eventname = $event_attr->{'eventname'};
			my $priority  = $event_attr->{'priority'};
			OUTSIDE:
			foreach my $rule ( @{$delivery_rules} ){
				foreach my $re ( @{$rule->{'if_eventname_matches'}} ){
					next OUTSIDE unless $eventname =~ m"$re";
				}
				foreach my $re ( @{$rule->{'if_priority_matches'}} ){
					next OUTSIDE unless $priority =~ m"$re";
				}
				my $type = $rule->{'type'};

				foreach my $capture ( @{ $rule->{'capture_from_eventname'} } ){
					my ($attrname, $re) = @{$capture};
					if( $eventname =~ m"$re" ){
						$event_attr->{$attrname} = $1;
					}else{
						$event_attr->{$attrname} = undef;
					}
				}
				foreach my $capture ( @{ $rule->{'capture_from_priority'} } ){
					my ($attrname, $re) = @{$capture};
					if( $priority =~ m"$re" ){
						$event_attr->{$attrname} = $1;
					}else{
						$event_attr->{$attrname} = undef;
					}
				}

				if( $type eq 'delivery_by_mail' ){
					my $envelopename = template( $rule->{'envelopename'}, $event_attr );
					push @event_dst, [$type, $event_attr, $envelopename];
				}
			}

			# TODO: 一個も delivery rule に引っかからなかった時

			#
		}elsif( m"^\t"p ){
			my $message = ${^POSTMATCH};
			OUTSIDE:
			foreach my $dst ( @event_dst ){
#print STDERR "DEBUG1: $dst\n";
				my $type = $dst->[0];
				my $attr = $dst->[1];
				if( $type eq 'delivery_by_mail' ){
					my $envelopename = $dst->[2];
					push @{$envelope{$envelopename}}, {
						'attr' => $attr,
						'message' => $message
					};
				}
			}
		}else{
			die;
		}
	}

	# write envelope
	my $now = time;
	my ($sec, $min, $hour, $day, $mon, $year, $week) = localtime $now;
	$year += 1900;
	$mon += 1;
	my $envelope_status = read_envelope_status();
	while( my ($envelopename, $v) = each %envelope ){
		unless( $envelope_status->{$envelopename} ){
			$envelope_status->{$envelopename} = {
				'create' => 0,
				'lastsend' => 0,
			};
		}

		unless( -f "$ENVELOPEDIR/$envelopename.envelope" ){
			$envelope_status->{$envelopename}->{'create'} = $now;
		}

		open F, '>>', "$ENVELOPEDIR/$envelopename.envelope" or die;
		foreach my $event ( @{$v} ){
			my $attr = $event->{'attr'};
			my $message = $event->{'message'};
			print F "attr\t", hash2ltsv($attr), "\n";
			print F "\t", $message, "\n";
		}
		close F;

	}

	# send mail
	my @post;
	opendir D, $ENVELOPEDIR or die;
	while( my $f = readdir D ){
		next if $f =~ m"^\.";
		next unless $f =~ m"^(.+)\.envelope$";
		my $envelopename = $1;

		my %envelope_attr;
		my %periodic_param;
		my %nonperiodic_param;
		my %template_param;
		my @concat_messages;
		my @recipient_addr;
		OUTSIDE:
		foreach my $rule ( @{$envelope_rules} ){
			foreach my $re ( @{$rule->{'if_envelopename_matches'}} ){
				next OUTSIDE unless $envelopename =~ m"$re";
			}
			my $type = $rule->{'type'};

			foreach my $capture ( @{ $rule->{'capture_from_envelopename'} } ){
				my ($attrname, $re) = @{$capture};
				if( $envelopename =~ m"$re" ){
					$envelope_attr{$attrname} = $1;
				}else{
					$envelope_attr{$attrname} = undef;
				}
			}

			foreach my $set ( @{ $rule->{'set'} } ){
				my ($attrname, $attrvalue) = @{$set};
				$envelope_attr{$attrname} = $attrvalue;
			}

			foreach my $a ( @{ $rule->{'recipient_address'} } ){
				push @recipient_addr, template( $a, \%envelope_attr );
			}

			if( $rule->{'sending_day_of_week'} or $rule->{'sending_time_of_day'} ){
				$periodic_param{$envelopename} = {
					'sending_day_of_week' => $rule->{'sending_day_of_week'},
					'sending_time_of_day' => $rule->{'sending_time_of_day'},
				};
			}
			if( $rule->{'sending_time_of_day'} or $rule->{'resend_wait_minutes'} ){
 				$nonperiodic_param{$envelopename} = {
					'send_wait_minutes' => $rule->{'send_wait_minutes'},
					'resend_wait_minutes' => $rule->{'resend_wait_minutes'},
				};
			}

			$template_param{'mail'} = $rule->{'mail_template'};
			$template_param{'snippet'} = $rule->{'snippet_template'};
			@concat_messages = split m",", $rule->{'concatenate_messages_by'};

		}

		# periodic mail timing
		if( $periodic_param{$envelopename} ){
print STDERR "DEBUG1 $envelopename\n";
			my @weekdays_text = split m",", lc $periodic_param{$envelopename}->{'sending_day_of_week'};
			my %map = (
				'sun' => 0, 'mon' => 1, 'tue' => 2, 'web' => 3,
				'thu' => 4, 'fri' => 5, 'sat' => 6,
				'sunday' => 0, 'monday' => 1, 'tuesday' => 2, 'webnesday' => 3,
				'thursday' => 4, 'friday' => 5, 'saturday' => 6,
			);
			my @weekdays;
			foreach my $w ( @weekdays_text ){
				$weekdays[$map{$w}] = 1;
			}
			next unless $weekdays[$week];
print STDERR "DEBUG1-1\n";

			my $now_text = sprintf "%02d:%02d", $hour, $min;
			my $time_begin = $periodic_param{$envelopename}->{'sending_time_of_day'};
			$time_begin =~ m"^(\d{2}):(\d{2})" or die;
			my $time_end = sprintf "%02d:%02d", ($1 + 1) % 24, $2;
			if    ( $time_begin lt $time_end ){
				next unless $time_begin le $now_text && $now_text le $time_end;
			}else{
				next unless $time_begin le $now_text || $now_text le $time_end;
			}
print STDERR "DEBUG1-2\n";

			my $lastsend = $envelope_status->{$envelopename}->{'lastsend'};
			next if $now < $lastsend + 23*60*60;
		# non periodic mail timing
		}else{
print STDERR "DEBUG2 $envelopename check create time\n";
			my $n = $nonperiodic_param{$envelopename};
			my $send_wait = $n->{'send_wait_minutes'} * 60;
			my $resend_wait = $n->{'send_wait_minutes'} * 60;

			my $create = $envelope_status->{$envelopename}->{'create'};
			my $lastsend = $envelope_status->{$envelopename}->{'lastsend'};

			next unless $create + $send_wait < $now;
print STDERR "DEBUG2-1 check last send time\n";
			next unless $lastsend + $resend_wait < $now;
print STDERR "DEBUG2-2\n";
		}
		
		push @post, [$envelopename, \%envelope_attr, \@recipient_addr, \%template_param, \@concat_messages];
	}
	close D;

	my $now = timestamp();
	foreach my $e ( @post ){
		my ($envelopename, $attr, $addr, $template_param, $concat_messages) = @$e;

		open F, '>>', "$ENVELOPEDIR/$envelopename.envelope" or die;
		print F "envelope_attr\t", hash2ltsv($attr), "\n";
		print F "recipient_addr\t", join("\t", @$addr), "\n";
		print F "template\t", hash2ltsv($template_param), "\n";
		print F "concat_messages\t", join("\t", @$concat_messages), "\n";
		close F;

		unless( rename	"$ENVELOPEDIR/$envelopename.envelope",
				"$POSTDIR/${envelopename}_$now.envelope" ){
			print STDERR "$envelopename.envelope: cannot move.\n";
			next;
		}
		$envelope_status->{$envelopename}->{'create'} = undef;
		$envelope_status->{$envelopename}->{'lastsend'} = time;
	}

	write_envelope_status( $envelope_status );
}

####
delivery();


