#!/usr/local/bin/perl
# Check the total disk usage for all virtual servers, and email a report to
# the admin for those that are over

package virtual_server;
$main::no_acl_check++;
$no_virtualmin_plugins = 1;
require './virtual-server-lib.pl';

if ($ARGV[0] eq "--debug") {
	$debug_mode = 1;
	}

# For each server, first find its total usage
$homesize = &quota_bsize("home");
$mailsize = &quota_bsize("mail");
$now = time();
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
	$msg = undef;
	if ($usage >= $limit) {
		# Over!
		$msg = [ $d, $usage, $limit, undef, 100 ];
		}
	elsif ($config{'quota_warn'}) {
		# Check if passed some threshold
		@warn = sort { $b <=> $a } split(/\s+/, $config{'quota_warn'});
		foreach $w (@warn) {
			if ($usage > $limit*$w/100) {
				$msg = [ $d, $usage, $limit,
					 int($usage*100/$limit), $w ];
				last;
				}
			}
		}

	# Don't send if we have already sent one for this limit within the
	# configured minimum period
	if ($msg) {
		if ($config{'quota_interval'}) {
			# When as the last time we emailed at this level or
			# higher?
			($lastt, $lastw) = split(/\s+/, $d->{'quota_notify'});
			if ($lastt &&
			    $now - $lastt < $config{'quota_interval'}*60*60 &&
			    $lastw >= $msg->[4]) {
				$msg = undef;
				}
			}
		}
	if ($msg) {
		$d->{'quota_notify'} = $now." ".$msg->[4];
		&save_domain($d);
		push(@msgs, $msg);
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
	if ($debug_mode) {
		print "From: ",&get_global_from_address(),"\n";
		print "To: ",$config{'quota_email'},"\n";
		print $body;
		}
	else {
		&mailboxes::send_mail($mail);
		}
	}

