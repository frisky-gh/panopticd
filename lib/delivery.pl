#!/usr/bin/perl

use strict;
use GDBM_File;
use Time::Local;
use Sys::Hostname;
use FindBin::libs;
use PanopticCommon;

$0 =~ m"^(.*)/[^/]+$";
our $BASEDIR = "$1/..";
our $ENVELOPEDIR = "$BASEDIR/spool/envelope";
our $POSTDIR = "$BASEDIR/spool/post";
our $LOGDIR = "$BASEDIR/log";
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
		print STDERR "$location: needs envelopename clause.\n" and
		return undef unless $lastrule->{'envelopename'};
	}elsif( $lastrule->{'type'} eq 'delivery_by_external_command' ){
		print STDERR "$location: needs commandname clause.\n" and
		return undef unless $lastrule->{'commandname'};
	}elsif( $lastrule->{'type'} eq 'count' ){
		print STDERR "$location: needs group_by clause.\n" and
		return undef unless $lastrule->{'group_by'};
		print STDERR "$location: needs countername clause.\n" and
		return undef unless $lastrule->{'countername'};
	}elsif( $lastrule->{'type'} eq 'record' ){
		print STDERR "$location: needs group_by clause.\n" and
		return undef unless $lastrule->{'group_by'};
		print STDERR "$location: needs recordname clause.\n" and
		return undef unless $lastrule->{'recordname'};
	}elsif( $lastrule->{'type'} eq 'envelope' ){
	}else{
		die $lastrule->{'type'} . ", stopped";
	}
	return 1;
}

sub parse_times_of_day ($$) {
	my ($location, $times_of_day_text) = @_;
	my @times_of_day_text = split m",", lc $times_of_day_text;
	my @times_of_day;
	foreach my $t ( @times_of_day_text ){
		unless( $t =~ m"^(\d{1,2}):(\d{2})(:\d{2})?$" ){
			print STDERR "$location: $t is not a time of the day.\n";
			next;
		}
		push @times_of_day, [$1, $2];
	}
	return @times_of_day;
}

sub parse_days_of_week ($$) {
	my ($location, $days_of_week_text) = @_;
	my @days_of_week_text = split m",", lc $days_of_week_text;
	my %map = (
		'sun' => 1, 'mon' => 2, 'tue' => 3, 'web' => 4,
		'thu' => 5, 'fri' => 6, 'sat' => 7,
		'sunday'   => 1, 'monday' => 2, 'tuesday'  => 3, 'webnesday' => 4,
		'thursday' => 5, 'friday' => 6, 'saturday' => 7,
	);
	my @days_of_week;
	foreach my $d ( @days_of_week_text ){
		my $n = $map{$d};
		unless( $n ){
			print STDERR "$location: $d is not a day of the week.\n";
			next;
		}
		$days_of_week[$n - 1] = 1;
	}
	return @days_of_week;
}

sub parse_word ($$) {
	my ($location, $word) = @_;
	return $word if $word =~ m"^[-_a-zA-Z][-_0-9a-zA-Z]*$";
	print STDERR "$location: needs word.\n" and
	return undef;
}

sub read_delivery_conf {
	open F, '<', "$CONFDIR/delivery.conf" or die;
	my $confname = "delivery.conf";
	my %patternsetmap;
	my @dispatch_rules;
	my @envelope_rules;
	my $context;
	my $last;
	my $rulenum;
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
				'id' => $rulenum,
				'type' => 'delivery_by_mail',
				'if_eventname_matches' => [],
				'if_priority_matches' => [],
				'capture_from_eventname' => [],
				'capture_from_priority' => [],
				'if' => [],
				'envelopename' => undef,
			};
			$context = 'by_mail';
			$rulenum++;
			push @dispatch_rules, $last;
		}elsif( $c[0] eq 'count' ){
			$error_occurred = 1 unless lastrule_is_valid(
				$last, "$confname:$."
			);
			$last = {
				'id' => $rulenum,
				'type' => 'count',
				'if_eventname_matches' => [],
				'if_priority_matches' => [],
				'capture_from_eventname' => [],
				'capture_from_priority' => [],
				'if' => [],
				'countername' => undef,
			};
			$context = 'count';
			$rulenum++;
			push @dispatch_rules, $last;
		}elsif( $c[0] eq 'record' ){
			$error_occurred = 1 unless lastrule_is_valid(
				$last, "$confname:$."
			);
			$last = {
				'id' => $rulenum,
				'type' => 'record',
				'if_eventname_matches' => [],
				'if_priority_matches' => [],
				'capture_from_eventname' => [],
				'capture_from_priority' => [],
				'if' => [],
				'recordname' => undef,
				'group_by' => undef,
			};
			$context = 'record';
			$rulenum++;
			push @dispatch_rules, $last;
		}elsif( $c[0] eq "delivery_by_external_command" ){
			$error_occurred = 1 unless lastrule_is_valid(
				$last, "$confname:$."
			);
			$last = {
				'id' => $rulenum,
				'type' => 'delivery_by_external_command',
				'if_eventname_matches' => [],
				'if_priority_matches' => [],
				'capture_from_eventname' => [],
				'capture_from_priority' => [],
				'if' => [],
				'commandname' => undef,
				'group_by' => undef,
			};
			$context = 'by_command';
			$rulenum++;
			push @dispatch_rules, $last;
		}elsif(	$c[0] eq "if_eventname_matches" ){
			next unless context_is_valid(
				$context, ['by_mail', 'count', 'record', 'by_command'],
				"$confname:$.", $c[0]
			);
			my $re = $c[1];
			push @{$last->{'if_eventname_matches'}}, qr"^$re$";
		}elsif(	$c[0] eq "if_priority_matches" ){
			next unless context_is_valid(
				$context, ['by_mail', 'count', 'record', 'by_command'],
				"$confname:$.", $c[0]
			);
			my $re = $c[1];
			push @{$last->{'if_priority_matches'}}, qr"^$re$";
		}elsif(	$c[0] eq "capture_from_eventname" ){
			next unless context_is_valid(
				$context, ['by_mail', 'count', 'record', 'by_command'],
				"$confname:$.", $c[0]
			);
			my $attrname = $c[1];
			my $re = $c[2];
			push @{$last->{'capture_from_eventname'}}, [$attrname, qr"$re"];
		}elsif(	$c[0] eq "capture_from_priority" ){
			next unless context_is_valid(
				$context, ['by_mail', 'count', 'record', 'by_command'],
				"$confname:$.", $c[0]
			);
			my $attrname = $c[1];
			my $re = $c[2];
			push @{$last->{'capture_from_priority'}}, [$attrname, qr"$re"];
		}elsif(	$c[0] eq "if" ){
			next unless context_is_valid(
				$context, ['by_mail', 'count', 'by_command'],
				"$confname:$.", $c[0]
			);
			my $left = $c[1];
			my $op = $c[2];
			my $right = $c[1];
			push @{$last->{'if'}}, [$left, $op, $right];
		}elsif(	$c[0] eq "envelopename" ){
			next unless context_is_valid(
				$context, ['by_mail'],
				"$confname:$.", $c[0]
			);
			my $envelopename = $c[1];
			$last->{'envelopename'} = $envelopename;
		}elsif(	$c[0] eq "countername" ){
			next unless context_is_valid(
				$context, ['count'],
				"$confname:$.", $c[0]
			);
			my $countername = $c[1];
			$last->{'countername'} = $countername;
		}elsif(	$c[0] eq "recordname" ){
			next unless context_is_valid(
				$context, ['record'],
				"$confname:$.", $c[0]
			);
			my $recordname = $c[1];
			$last->{'recordname'} = $recordname;
		}elsif(	$c[0] eq "commandname" ){
			next unless context_is_valid(
				$context, ['by_command'],
				"$confname:$.", $c[0]
			);
			my $commandname = $c[1];
			$last->{'commandname'} = $commandname;
		}elsif( $c[0] eq "envelope" ){
			$error_occurred = 1 unless lastrule_is_valid(
				$last, "$confname:$."
			);
			$last = {
				'id' => $rulenum,
				'type' => 'envelope',
				'if_envelopename_matches' => [],
				'capture_from_envelopename' => [],
				'set' => [],
				'recipient_address' => [],
				'sender_address' => undef,
				'send_wait_minutes' => undef,
				'resend_wait_minutes' => undef,
				'sending_time_of_day' => undef,
				'sending_day_of_week' => undef,
				'mail_template' => undef,
				'snippet_template' => undef,
				'group_by' => undef,
			};
			$context = 'envelope';
			$rulenum++;
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
			my $name  = $c[2];
			$name = $email if $name eq '';
			push @{$last->{'recipient_address'}}, [$email, $name];
		}elsif(	$c[0] eq 'sender_address' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my $email = $c[1];
			my $name  = $c[2];
			$name = $email if $name eq '';
			$last->{'sender_address'} = [$email, $name];
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
			my @times_of_day = parse_times_of_day "$confname:$.", $c[1];
			next unless @times_of_day;
			$last->{'sending_time_of_day'} = [ @times_of_day ];
		}elsif(	$c[0] eq 'sending_day_of_week' ){
			next unless context_is_valid(
				$context, ['envelope'],
				"$confname:$.", $c[0]
			);
			my @days_of_week = parse_days_of_week "$confname:$.", $c[1];
			next unless @days_of_week;
			$last->{'sending_day_of_week'} = [ @days_of_week ];
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
		}elsif(	$c[0] eq 'group_by' ){
			next unless context_is_valid(
				$context, ['envelope', 'count', 'record'],
				"$confname:$.", $c[0]
			);
			my @group_by = split m",", $c[1];
			$last->{'group_by'} = \@group_by;
		}else{
			print STDERR "$confname:$.:", $c[0], ": syntax error.\n";
			next;
		}
	}
	close F;

	return {
		'dispatch_rules' => \@dispatch_rules,
		'envelope_rules' => \@envelope_rules,
	};
}

####
sub delivery_by_mail ($$) {
	my ($envelope_rules, $update_envelope) = @_;

	# write envelope
	my $now = time;
	my ($sec, $min, $hour, $day, $mon, $year, $week) = localtime $now;
	$year += 1900;
	$mon += 1;
	my $envelope_status = read_envelope_status();
	while( my ($envelopename, $v) = each %$update_envelope ){
		panopticddebug "delivery_by_mail: update_envelope: %s", $envelopename;
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
	my $username = (getpwuid $<)[0];
	my $hostname = hostname;
	my @default_sender = ("$username\@hostname", $username);
	my @post;
	opendir D, $ENVELOPEDIR or die;
	while( my $f = readdir D ){
		next if $f =~ m"^\.";
		next unless $f =~ m"^(.+)\.envelope$";
		next unless -s "$ENVELOPEDIR/$f";
		my $envelopename = $1;

		panopticddebug "delivery_by_mail: envelope=%s", $envelopename;

		my %envelope_attr;
		my %periodic_param;
		my %nonperiodic_param;
		my %template_param;
		my @group_by;
		my @recipient_addr;
		my $sender_addr = [@default_sender];
		OUTSIDE:
		foreach my $rule ( @{$envelope_rules} ){
			foreach my $re ( @{$rule->{'if_envelopename_matches'}} ){
				next OUTSIDE unless $envelopename =~ m"$re";
			}
			panopticddebug "delivery_by_mail:  ruleid=%d", $rule->{'id'};

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
				push @recipient_addr, [
					template( $a->[0], \%envelope_attr ),
					template( $a->[1], \%envelope_attr ),
				];
			}

			if( $rule->{'sender_address'} ){
				my $a = $rule->{'sender_address'};
				$sender_addr = [
					template( $a->[0], \%envelope_attr ),
					template( $a->[1], \%envelope_attr ),
				];
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
			@group_by = @{$rule->{'group_by'}} if $rule->{'group_by'};

		}

		panopticddebug "delivery_by_mail:  envelope=%s", $envelopename;

		# periodic mail timing
		if( $periodic_param{$envelopename} ){
			panopticddebug "delivery_by_mail:  periodic.";
			next unless $periodic_param{$envelopename}->{'sending_day_of_week'}->[$week];

			my $ok;
			foreach my $t ( @{$periodic_param{$envelopename}->{'sending_time_of_day'}} ){
				my $h = $t->[0];
				my $m = $t->[1];
				next unless $hour == $h || $h+1 == $hour;
				next if $hour == $h && $min >= $m || $hour == $h+1 && $min < $m;
				$ok = 1;
				last;
			}
			next unless $ok;

			panopticddebug "delivery_by_mail:  move to post.";

			my $lastsend = $envelope_status->{$envelopename}->{'lastsend'};
			next if $now < $lastsend + 23*60*60;
		# non periodic mail timing
		}else{
			panopticddebug "delivery_by_mail:  non-periodic.";
			my $n = $nonperiodic_param{$envelopename};
			my $send_wait = $n->{'send_wait_minutes'} * 60;
			my $resend_wait = $n->{'send_wait_minutes'} * 60;

			my $create = $envelope_status->{$envelopename}->{'create'};
			my $lastsend = $envelope_status->{$envelopename}->{'lastsend'};

			panopticddebug "delivery_by_mail:  checks create time.";
			next unless $create + $send_wait < $now;
			panopticddebug "delivery_by_mail:  checks last send time.";
			next unless $lastsend + $resend_wait < $now;
			panopticddebug "delivery_by_mail:  posts.";
		}
		
		push @post, [$envelopename, \%envelope_attr, $sender_addr, \@recipient_addr, \%template_param, \@group_by];
	}
	close D;

	my $now = timestamp;
	foreach my $e ( @post ){
		my ($envelopename, $attr, $sender_addr, $recipient_addrs, $template_param, $group_by) = @$e;

		open F, '>>', "$ENVELOPEDIR/$envelopename.envelope" or die;
		print F "envelope_attr\t", hash2ltsv($attr), "\n";
		print F "sender_addr\t", join("\t", $sender_addr->[0], $sender_addr->[1]), "\n";
		foreach my $a ( @$recipient_addrs ){
			print F "recipient_addr\t", join("\t", $a->[0], $a->[1]), "\n";
		}
		print F "template\t", hash2ltsv($template_param), "\n";
		print F "group_by\t", join("\t", @$group_by), "\n";
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

sub delivery_by_external_command ($) {
	my ($exec_command) = @_;
}

sub count ($) {
	my ($update_counter) = @_;
	while( my ($k, $v) = each %$update_counter ){
		my %db;
		unless( tie %db, 'GDBM_File', "$STATUSDIR/counter-$k.gdbm", &GDBM_WRCREAT, 0644 ){
			print STDERR "counter-$k.gdbm: cannot open.\n";
			return undef;
		}
		while( my ($tsv, $count) = each %$v ){
			$db{$tsv} += $count;
		}
	}
}

sub record ($) {
	my ($update_record) = @_;
	my $timestamp = now;
	while( my ($k, $v) = each %$update_record ){
		unless( open F, '>>', "$LOGDIR/record-$k.ltsv" ){
			print STDERR "record-$k.ltsv: cannot open.\n";
			return undef;
		}
		while( my ($ltsv, $count) = each %$v ){
			print F "timestamp:$timestamp	count:$count	$ltsv\n";
		}
		close F;
	}
}

sub dispatch ($) {
	my ($dispatch_rules) = @_;

	my %envelope;
	my %command;
	my %counter;
	my %record;
	my @event_dst;
	while( <STDIN> ){
		chomp;
		if( m"^(\w+)\t"p ){
			@event_dst = ();
			my $event_attr = ltsv2hash( ${^POSTMATCH} );
			my $eventname = $event_attr->{'eventname'};
			my $priority  = $event_attr->{'priority'};
			OUTSIDE:
			foreach my $rule ( @{$dispatch_rules} ){
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
				}elsif( $type eq 'delivery_by_external_command' ){
					my $commandname = template( $rule->{'commandname'}, $event_attr );
					push @event_dst, [$type, $event_attr, $commandname];
				}elsif( $type eq 'count' ){
					my $countername = template( $rule->{'countername'}, $event_attr );
					my @r;
					my $group_by = $event_attr->{'group_by'};
					foreach my $k ( @$group_by ){
						push @r, $event_attr->{$k};
					}
					my $tsv = join("\t", @r);
					push @event_dst, [$type, $tsv, $countername];
				}elsif( $type eq 'record' ){
					my $recordname = template( $rule->{'recordname'}, $event_attr );
					my %r;
					my $group_by = $event_attr->{'group_by'};
					foreach my $k ( @$group_by ){
						$r{$k} = $event_attr->{$k};
					}
					my $ltsv = hash2ltsv( \%r );
					push @event_dst, [$type, $ltsv, $recordname];
				}else{
					die;
				}
			}

			# TODO: 一個も delivery rule に引っかからなかった時

			#
		}elsif( m"^\t"p ){
			my $message = ${^POSTMATCH};
			OUTSIDE:
			foreach my $dst ( @event_dst ){
				my $type = $dst->[0];
				if( $type eq 'delivery_by_mail' ){
					my $attr = $dst->[1];
					my $envelopename = $dst->[2];
					panopticddebug "dispatch: delivery_by_mail: %d -> %s", $., $envelopename;
					push @{$envelope{$envelopename}}, {
						'attr' => $attr,
						'message' => $message
					};
				}elsif( $type eq 'delivery_by_external_command' ){
					my $attr = $dst->[1];
					my $commandname = $dst->[2];
					panopticddebug "dispatch: delivery_by_external_command: %d -> %s", $., $commandname;
					push @{$command{$commandname}}, {
						'attr' => $attr,
						'message' => $message
					};
				}elsif( $type eq 'count' ){
					my $tsv = $dst->[1];
					my $countername = $dst->[3];
					panopticddebug "dispatch: count: %d -> %s", $., $countername;
					$counter{$countername}->{$tsv}++;
				}elsif( $type eq 'record' ){
					my $ltsv = $dst->[1];
					my $recordname = $dst->[2];
					panopticddebug "dispatch: record: %d -> %s", $., $recordname;
					$record{$recordname}->{$ltsv}++;
				}else{
					die;
				}
			}
		}else{
			die;
		}
	}

	return \%envelope, \%command, \%counter, \%record;
}

sub delivery () {
	my $conf = read_delivery_conf();
	my $dispatch_rules = $conf->{'dispatch_rules'};
	my $envelope_rules = $conf->{'envelope_rules'};

	my ($update_envelope, $exec_command, $update_counter, $update_record) = dispatch $dispatch_rules;
	delivery_by_mail $envelope_rules, $update_envelope;
	delivery_by_external_command $exec_command;
	count $update_counter;
	record $update_record;
}


####
if( $ARGV[0] eq '-d' ){
	$PanopticCommon::DEBUG = 1;
}
delivery;


