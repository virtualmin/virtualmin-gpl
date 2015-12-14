#!/usr/local/bin/perl
# Check the total disk usage for all virtual servers, and email a report to
# the admin for those that are over.

package virtual_server;
$main::no_acl_check++;
$no_virtualmin_plugins = 1;
require './virtual-server-lib.pl';
&foreign_require("mailboxes");

if ($ARGV[0] eq "--debug") {
	$debug_mode = 1;
	}

# For each server, first find its total usage
$homesize = &quota_bsize("home");
$mailsize = &quota_bsize("mail");
$now = time();
&read_file($user_quota_warnings_file, \%userwarnings);
foreach $d (&list_domains()) {
	next if ($d->{'alias'});
	next if ($d->{'disabled'});

	if ($d->{'quota'} && !$d->{'parent'}) {
		# Get usage for this server and all sub-servers
		($homequota, $mailquota, $dbquota) = &get_domain_quota($d, 1);
		$usage = $homequota*$homesize +
			 $mailquota*$mailsize +
			 $dbquota;

		# Compare to server's limit
		$msg = &check_quota_threshold($d, $usage,
					      $d->{'quota'}*$homesize);

		# Don't send if we have already sent one for this limit within
		# the configured minimum period
		if ($msg && !&check_quota_interval($msg,
				split(/\s+/, $d->{'quota_notify'}))) {
			$msg = undef;
			}

		# Record that we have notified this domain
		if ($msg) {
			$d->{'quota_notify'} = $now." ".$msg->[4];
			&save_domain($d);
			push(@msgs, $msg);
			}
		}
	
	# Check all users in the domain, if enabled
	@users = ( );
	if ($config{'quota_mailbox'}) {
		@users = &list_domain_users($d, 1, 0, 0, 1);
		}
	foreach $u (@users) {
		next if ($u->{'webowner'});
		local $msg;

		# Check if over home quota
		if ($u->{'quota'}) {
			$usage = $u->{'uquota'}*$homesize;
			$msg = &check_quota_threshold(
				$d, $usage, $u->{'quota'}*$homesize, $u);
			}

		# Check if over mail quota
		if ($u->{'mquota'} && !$msg) {
			$usage = $u->{'umquota'}*$mailsize;
			$msg = &check_quota_threshold(
				$d, $usage, $u->{'mquota'}*$homesize, $u);
			}

		# Don't send if we have already sent one for this limit within
		# the configured minimum period
		if ($msg && !&check_quota_interval($msg,
				split(/\s+/, $userwarnings{$u->{'user'}}))) {
			$msg = undef;
			}

		if ($msg) {
			# Record that we have notified this user
			$userwarnings{$u->{'user'}} = $now." ".$msg->[4];
			push(@umsgs, $msg);
			}
		}
	}
&write_file($user_quota_warnings_file, \%userwarnings);

# Send email to domain owners separately for both their domains and users
if ($config{'quota_users'}) {
	@emails = &unique(map { $_->[0]->{'emailto'} } (@msgs, @umsgs));
	foreach $email (@emails) {
		@emsgs = grep { $_->[0]->{'emailto'} eq $email } @msgs;
		if (@emsgs) {
			&send_domain_quota_email(\@emsgs, $email);
			}
		@eumsgs = grep { $_->[0]->{'emailto'} eq $email } @umsgs;
		if (@eumsgs) {
			&send_user_quota_email(\@eumsgs, $email);
			}
		}
	}

# Send email to mailbox users separately
if ($config{'quota_mailbox_send'}) {
	foreach $msg (@umsgs) {
		&send_single_user_quota_email($msg);
		}
	}

# Send email to master admin for both domains and users over quota
if ($config{'quota_email'}) {
	if (@msgs) {
		&send_domain_quota_email(\@msgs, $config{'quota_email'});
		}
	if (@umsgs) {
		&send_user_quota_email(\@umsgs, $config{'quota_email'});
		}
	}

# send_domain_quota_email(&message, address)
# Converts a list of domain over-quota notifications into a message, and send it
sub send_domain_quota_email
{
local ($msgs, $email) = @_;

local $fmt = "%-20.20s %-15.15s %-15.15s %-20.20s\n";
local $body = "$text{'quotawarn_body'}\n\n";
local $body .= sprintf($fmt, $text{'quotawarn_server'},
			     $text{'quotawarn_quota'},
			     $text{'quotawarn_usage'},
			     $text{'quotawarn_status'});
$body .= sprintf($fmt, "-" x 20, "-" x 15, "-" x 15, "-" x 20);
local $emaild = undef;
foreach my $m (@$msgs) {
	local $msg = $m->[3] ? &text('quotawarn_reached', $m->[3])
			     : $text{'quotawarn_over'};
	$emaild ||= $m->[0];
	$body .= sprintf($fmt, $m->[0]->{'dom'},
			       &nice_size($m->[2]),
			       &nice_size($m->[1]),
			       $msg);
	}
$body .= "\n";
$body .= &text('quotawarn_suffixdom', &get_virtualmin_url($emaild))."\n";

# Send the email
if ($debug_mode) {
	print "From: ",&get_global_from_address($emailid),"\n";
	print "To: ",$email,"\n";
	print $body;
	print "-\n";
	}
else {
	&mailboxes::send_text_mail(&get_global_from_address($emailid),
				   $email,
				   undef,
				   'Virtualmin Disk Quota Monitoring',
				   $body);
	}
}

# send_user_quota_email(&message, address)
# Converts a list of user over-quota notifications into a message, and send it
sub send_user_quota_email
{
local ($msgs, $email) = @_;

local $fmt = "%-30.30s %-15.15s %-15.15s %-15.15s\n";
local $body = "$text{'quotawarn_body2'}\n\n";
local $body .= sprintf($fmt, $text{'quotawarn_email'},
                             $text{'quotawarn_quota'},
                             $text{'quotawarn_usage'},
                             $text{'quotawarn_status'});
$body .= sprintf($fmt, "-" x 35, "-" x 15, "-" x 15, "-" x 15);
local $emaild = undef;
foreach my $m (@$msgs) {
	local $msg = $m->[3] ? &text('quotawarn_reached', $m->[3])
                             : $text{'quotawarn_over'};
	$emaild ||= $m->[0];
	$body .= sprintf($fmt, $m->[5]->{'email'} ||
				$m->[5]->{'user'},
			       &nice_size($m->[2]),
			       &nice_size($m->[1]),
			       $msg);
	}
$body .= "\n";
$body .= &text('quotawarn_suffixuser', &get_virtualmin_url($emaild))."\n";

# Send the email
if ($debug_mode) {
	print "From: ",&get_global_from_address($emailid),"\n";
	print "To: ",$email,"\n";
	print $body;
	print "-\n";
	}
else {
	&mailboxes::send_text_mail(&get_global_from_address($emailid),
				   $email,
				   undef,
				   $text{'quotawarn_subject'},
				   $body);
	}
}

# send_single_user_quota_email(&message)
# Send email to one user who is close to or over quota
sub send_single_user_quota_email
{
local ($msg) = @_;
$email = $msg->[5]->{'email'} ||
	  $msg->[5]->{'user'}.'@'.&get_system_hostname();
local $tmpl = &get_quotas_message();
local %hash = %{$msg->[5]};
$hash{'quota_limit'} = &nice_size($msg->[2]);
$hash{'quota_used'} = &nice_size($msg->[1]);
$hash{'quota_percent'} = $msg->[3] || '';
local $body = &substitute_domain_template($tmpl, $msg->[0], \%hash);

# Send the email
if ($debug_mode) {
	print "From: ",$msg->[0]->{'emailto'},"\n";
	print "To: ",$email,"\n";
	print $body;
	print "-\n";
	}
else {
	&mailboxes::send_text_mail($msg->[0]->{'emailto'},
				   $email,
				   undef,
				   $text{'quotawarn_subject'},
				   $body);
	}
}

# check_quota_threshold(&domain, usage, limit, [&user])
# If some user or domain is over it's limit or over a warning level, return
# a message hash ref with the details.
sub check_quota_threshold
{
local ($d, $usage, $limit, $user) = @_;
if ($usage >= $limit) {
	# Over!
	return [ $d, $usage, $limit, undef, 100, $user ];
	}
elsif ($config{'quota_warn'}) {
	# Check if passed some threshold
	local @warn = sort { $b <=> $a } split(/\s+/, $config{'quota_warn'});
	foreach my $w (@warn) {
		if ($usage > $limit*$w/100) {
			return [ $d, $usage, $limit,
				 int($usage*100/$limit), $w, $user ];
			}
		}
	}
return undef;
}

# check_quota_interval(&message, last-time, last-level)
# Returns 0 if the user or domain should not be notified, 1 if so
sub check_quota_interval
{
local ($msg, $lastt, $lastw) = @_;
if ($config{'quota_interval'}) {
	# When as the last time we emailed at this level or
	# higher?
	if ($lastt &&
	    $now - $lastt < $config{'quota_interval'}*60*60 &&
	    $lastw >= $msg->[4]) {
		return 0;
		}
	}
return 1;
}

