#!/usr/local/bin/perl
# Check the total disk usage for all virtual servers, and email a report to
# the admin for those that are over

package virtual_server;
$main::no_acl_check++;
$no_virtualmin_plugins = 1;
require './virtual-server-lib.pl';

# For each server, first find its total usage
$homesize = &quota_bsize("home");
$mailsize = &quota_bsize("mail");
foreach $d (&list_domains()) {
	next if ($d->{'parent'} || $d->{'alias'});
	next if (!$d->{'quota'});

	# Get usage for this server and all sub-servers
	($homequota, $mailquota, $dbquota) = &get_domain_quota($d, 1);
	$usage = $homequota*$homesize +
		 $mailquota*$mailsize +
		 $dbquota;

	# Compare to server's limit
	$limit = $d->{'quota'}*$homesize;
	if ($usage >= $limit) {
		# Over!
		push(@msgs, [ $d, $usage, $limit ]);
		}
	elsif ($config{'quota_warn'} &&
	       $usage > $limit*$config{'quota_warn'}/100) {
		# Passed warning level
		push(@msgs, [ $d, $usage, $limit, int($usage*100/$limit) ]);
		}
	}

if (@msgs) {
	# Construct an email
	$fmt = "%-20.20s %-15.15s %-15.15s %-20.20s\n";
	$body = "The following Virtualmin servers have reached or are approaching\ntheir disk quota limits:\n\n";
	$body .= sprintf($fmt, "Server", "Quota", "Usage", "Status");
	$body .= sprintf($fmt, "-" x 20, "-" x 15, "-" x 15, "-" x 20);
	foreach $m (@msgs) {
		$msg = $m->[3] ? "Reached $m->[3] %" : "Over quota";
		$body .= sprintf($fmt, $m->[0]->{'dom'},
				       &nice_size($m->[2]),
				       &nice_size($m->[1]),
				       $msg);
		}

	# Send the email
	&foreign_require("mailboxes", "mailboxes-lib.pl");
	$mail = { 'headers' => [ [ 'From' => &get_global_from_address() ],
				 [ 'To' => $config{'quota_email'} ],
				 [ 'Subject' => 'Disk Quota Monitoring' ],
				 [ 'Content-type', 'text/plain' ] ],
		  'body' => $body };
	&mailboxes::send_mail($mail);
	}

