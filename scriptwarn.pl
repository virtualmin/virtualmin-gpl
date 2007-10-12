#!/usr/local/bin/perl
# Check for any virtual server scripts that are out of date, and email
# their domain owners / other people

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';
&foreign_require("mailboxes", "mailboxes-lib.pl");

# Find scripts that need updating
@doms = &list_domains();
@updates = &list_script_upgrades(\@doms);

# Find the Webmin protocol and port
&get_miniserv_config(\%miniserv);
$proto = $miniserv{'ssl'} ? 'https' : 'http';
$port = $miniserv{'port'};

# Send out an email for each domain
%email = map { $_, 1 } split(/\s+/, $config{'scriptwarn_email'});
($other) = grep { /\@/ } (keys %email);
if (@updates) {
	if (!$email{'owner'} && !$email{'reseller'}) {
		# Just send one for all domains
		$email = $text{'scriptwarn_header'}."\n\n";
		$fmt = "%-30.30s %-30.30s %-15.15s\n";
		$email .= sprintf $fmt, $text{'scriptwarn_dom'},
					$text{'scriptwarn_script'},
					$text{'scriptwarn_ver'};
		$email .= sprintf $fmt, ("-" x 30), ("-" x 30), ("-" x 15);
		foreach $u (@updates) {
			$email .= sprintf $fmt,
				$u->{'dom'}->{'dom'},
				$u->{'script'}->{'desc'}, $u->{'ver'};
			}
		$email .= "\n";
		$email .= $text{'scriptwarn_where'}."\n\n";
		$email =~ s/\\n/\n/g;
		&send_scriptwarn_email($email, [ $other ]);
		}
	else {
		# Send one per domain with any
		foreach $d (@doms) {
			# Construct the message
			@dupdates = grep { $_->{'dom'} eq $d } @updates;
			next if (!@dupdates);
			$email = &text('scriptwarn_header2', $d->{'dom'}).
				 "\n\n";
			$fmt = "%-60.60s %-15.15s\n";
			$email .= sprintf $fmt, $text{'scriptwarn_script'},
						$text{'scriptwarn_ver'};
			$email .= sprintf $fmt, ("-" x 60), ("-" x 15);
			foreach $u (@dupdates) {
				$email .= sprintf $fmt,
					$u->{'script'}->{'desc'}, $u->{'ver'};
				}
			$email .= "\n";
			$email .= &text('scriptwarn_where2',
				&get_webmin_url($d)."/$module_name/".
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
			&send_scriptwarn_email($email, \@emailto);
			}
		}
	}

sub send_scriptwarn_email
{
local ($text, $emailto) = @_;
local $mail = { 'headers' => [ [ 'From', $config{'from_addr'} ||
					 &mailboxes::get_from_address() ],
			       [ 'To', join(", ", @$emailto) ],
			       [ 'Subject', $text{'scriptwarn_subject'} ],
			       [ 'Content-type', 'text/plain' ] ],
		'body' => $text };
&mailboxes::send_mail($mail);
}

sub get_webmin_url
{
local ($d) = @_;
if ($config{'scriptwarn_url'}) {
	$d ||= { 'dom' => &get_system_hostname() };
	return &substitute_domain_template($config{'scriptwarn_url'}, $d);
	}
else {
	return $proto."://$d->{'dom'}:$port";
	}
}

