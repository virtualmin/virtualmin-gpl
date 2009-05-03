#!/usr/local/bin/perl
# Check for any virtual server scripts that are out of date, and email
# their domain owners / other people

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';
&foreign_require("mailboxes", "mailboxes-lib.pl");

if ($ARGV[0] eq "-debug" || $ARGV[0] eq "--debug") {
	$debug_mode = 1;
	}

# Find scripts that need updating
@doms = &list_domains();
@updates = &list_script_upgrades(\@doms);
foreach my $u (@updates) {
	$u->{'key'} = join("/", $u->{'dom'}->{'dom'}, $u->{'sinfo'}->{'name'},
			 	$u->{'ver'});
	}

# Filter out notifications that have already been sent, on a per domain, script
# and version basis.
&read_file($script_warnings_file, \%warnsent);
if ($config{'scriptwarn_notify'}) {
	@updates = grep { !$warnsent{$_->{'key'}} } @updates;
	}

# Send out an email for each domain
%email = map { $_, 1 } split(/\s+/, $config{'scriptwarn_email'});
($other) = grep { /\@/ } (keys %email);
if (@updates) {
	if (!$email{'owner'} && !$email{'reseller'}) {
		# Just send one for all domains
		$email = $text{'scriptwarn_header'}."\n\n";
		$fmt = "%-30.30s %-25.25s %-11.11s %-11.11s\n";
		$email .= sprintf $fmt, $text{'scriptwarn_dom'},
					$text{'scriptwarn_script'},
					$text{'scriptwarn_oldver'},
					$text{'scriptwarn_ver'};
		$email .= sprintf $fmt, ("-" x 30), ("-" x 25),
					("-" x 11), ("-" x 11);
		foreach $u (@updates) {
			$email .= sprintf $fmt,
				$u->{'dom'}->{'dom'},
				$u->{'script'}->{'desc'},
				$u->{'sinfo'}->{'version'},
				$u->{'ver'};
			}
		$email .= "\n";
		$url = &get_virtualmin_url($d)."/$module_name/".
		       "edit_newscripts.cgi?mode=upgrade";
		$email .= &text('scriptwarn_where3', $url)."\n\n";
		$email =~ s/\\n/\n/g;
		&send_scriptwarn_email($email, [ $other ]);
		}
	else {
		# Send one per domain with any notifications
		foreach $d (@doms) {
			# Construct the message
			@dupdates = grep { $_->{'dom'} eq $d } @updates;
			next if (!@dupdates);
			$email = &text('scriptwarn_header2', $d->{'dom'}).
				 "\n\n";
			$fmt = "%-48.48s %-15.15s %-15.15s\n";
			$email .= sprintf $fmt, $text{'scriptwarn_script'},
						$text{'scriptwarn_oldver'},
						$text{'scriptwarn_ver'};
			$email .= sprintf $fmt,
					("-" x 48), ("-" x 15), ("-" x 15);
			foreach $u (@dupdates) {
				$email .= sprintf $fmt,
					$u->{'script'}->{'desc'},
					$u->{'sinfo'}->{'version'},
					$u->{'ver'};
				}
			$email .= "\n";
			$email .= &text('scriptwarn_where2',
				&get_virtualmin_url($d)."/$module_name/".
				"list_scripts.cgi?dom=$d->{'id'}")."\n\n";
			$email =~ s/\\n/\n/g;

			# Mail it off
			@emailto = ( );
			if ($email{'owner'}) {
				push(@emailto, $d->{'emailto'});
				}
			if ($email{'reseller'} && $d->{'reseller'}) {
				$resel = &get_reseller($d->{'reseller'});
				if ($resel && $resel->{'acl'}->{'email'}) {
					push(@emailto,
					     $resel->{'acl'}->{'email'});
					}
				}
			if ($other) {
				push(@emailto, $other);
				}
			&send_scriptwarn_email($email, \@emailto, $d);
			}
		}
	}

# Save sent notifications, for filtering
foreach my $u (@updates) {
	$warnsent{$u->{'key'}} ||= time();
	}
&write_file($script_warnings_file, \%warnsent);

sub send_scriptwarn_email
{
local ($text, $emailto, $d) = @_;
local $mail = { 'headers' => [ [ 'From', &get_global_from_address($d) ],
			       [ 'To', join(", ", &unique(@$emailto)) ],
			       [ 'Subject', $text{'scriptwarn_subject'} ],
			       [ 'Content-type', 'text/plain' ] ],
		'body' => $text };
if ($debug_mode) {
	print STDERR "Sending to ",join(", ", @$emailto),"\n";
	print STDERR "Sending from ",&get_global_from_address($d),"\n";
	print STDERR $text,"\n";
	}
else {
	&mailboxes::send_mail($mail);
	}
}

