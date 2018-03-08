#!/usr/bin/perl

use strict;
use FindBin::libs;
use PanopticCommon;

$0 =~ m"^(.*)/[^/]+$";
our $BASEDIR = "$1/..";
our $MAILTEMPLATEDIR = "$BASEDIR/conf/mail";
our $POSTDIR = "$BASEDIR/spool/post";
our $STATUSDIR = "$BASEDIR/status";
our $CONFDIR = "$BASEDIR/conf";

our $SENDMAILEXE = '/usr/lib/sendmail';

####
sub read_mail_template ($) {
	my ($templatename) = @_;
	my $template;
	open F, '<', "$MAILTEMPLATEDIR/$templatename.template" or die "$templatename.template: not found, stopped";
	while( <F> ){
		$template .= $_;
	}
	close F;
	return $template;
}

####
sub post {
	my @concat_attr = ('logname', 'eventname');

	my $envelope_attr;
	my $event_attr;
	my $sender_addr;
	my @recipient_addr;
	my $template_param;
	my @concat_messages;
	my @event;
	while( <STDIN> ){
		chomp;
		if( m"^(\w+)\t"p ){
			if( $1 eq 'attr' ){
				$event_attr = ltsv2hash( ${^POSTMATCH} );
			}elsif( $1 eq 'envelope_attr' ){
				$envelope_attr = ltsv2hash( ${^POSTMATCH} );
			}elsif( $1 eq 'sender_addr' ){
				$sender_addr = [split m"\t", ${^POSTMATCH}];
			}elsif( $1 eq 'recipient_addr' ){
				push @recipient_addr, [split m"\t", ${^POSTMATCH}];
			}elsif( $1 eq 'template' ){
				$template_param = ltsv2hash( ${^POSTMATCH} );
			}elsif( $1 eq 'concat_messages' ){
				@concat_messages = split m"\t", ${^POSTMATCH};
			}
		}elsif( m"^\t"p ){
			# TODO: auto-detect charset and transcode
			my $message = ${^POSTMATCH};
			push @event, [$event_attr, $message];
		}else{
			die;
		}
	}

	# TODO: configure following parameters.
	$template_param->{'max_messages_in_snippet'} = 50;
	$template_param->{'max_snippets_in_mail'} = 50;

	# concatenate snippet which has same attributes
	my %snippet;
	foreach my $e ( @event ){
		my $attr = $e->[0];
		my $message = $e->[1];
		my @snippet_name;
		foreach my $concat_attr ( @concat_messages ){
			push @snippet_name, $attr->{$concat_attr};
		}
		my $snippet_name = join "\t", @snippet_name;
		push @{$snippet{$snippet_name}}, $message;
	}

	# make snippet from template
	my $snippet_template = read_mail_template( $template_param->{'snippet'} );
	my @snippets;
	while( my ($snippet_name, $messages) = each %snippet ){
		my @snippet_name = split m"\t", $snippet_name;
		my %snippet_attr;
		for( my $i = 0; $i <= $#snippet_name; $i++ ){
			$snippet_attr{ $concat_messages[$i] } = $snippet_name[$i];
		}
		if( @$messages > $template_param->{'max_messages_in_snippet'} ){
			splice @$messages, $template_param->{'max_messages_in_snippet'};
			push @$messages, '(... snipped.)';
		}
		$snippet_attr{'messages'} = join "\n", @$messages;
		push @snippets, template($snippet_template, \%snippet_attr, $envelope_attr);
	}

	# make mail from template
	my $mail_template = read_mail_template( $template_param->{'mail'} );
	if( @snippets > $template_param->{'max_snippets_in_mail'} ){
		splice @snippets, $template_param->{'max_snippets_in_mail'};
		push @snippets, '(... snipped.)';
	}
	my $snippets = join('', @snippets);

	foreach my $a ( @recipient_addr ){
		my %mail_attr = (
			'snippets' => $snippets,
			'sender_address'    => $sender_addr->[0],
			'sender_name'       => $sender_addr->[1],
			'recipient_address' => $a->[0],
			'recipient_name'    => $a->[1],
		);
		my $mail = template($mail_template, \%mail_attr, $envelope_attr);
		# TODO: censor function. (email addr => xxx@xxx.xxx, and so on)

		sendmail $mail, $sender_addr->[0], $a->[0];
	}
}

####
post();






