#!/usr/local/bin/perl
# Blacklist email in spamtrap files, and whitelist mail in hamtraps, for all
# domains with spam emailed.

package virtual_server;
$main::no_acl_check++;
$no_virtualmin_plugins = 1;
require './virtual-server-lib.pl';
&foreign_require("mailboxes", "mailboxes-lib.pl");
&foreign_require("spam", "spam-lib.pl");

# Find the sa-learn command
$salearn = &has_command($spam::config{'sa_learn'} || "sa-learn");

if ($ARGV[0] eq "-debug" || $ARGV[0] eq "--debug") {
	$debug_mode = 1;
	}

# For each domain with spam enabled and with the aliases, process the files
foreach $d (&list_domains()) {
	# Is this domain suitable
	if (!$d->{'spam'}) {
		print STDERR "$d->{'dom'}: spam filtering is not enabled\n"
			if ($debug);
		next;
		}
	$st = &get_spamtrap_aliases($d);
	if ($st != 1) {
		print STDERR "$d->{'dom'}: missing spamtrap aliases\n"
			if ($debug);
		next;
		}

	if (!$salearn) {
		print STDERR "The sa-learn command was not found ",
			     "on your system\n";
		exit(1);
		}

	# Get users in the domain
	@users = &list_domain_users($d, 0, 0, 1, 1);

	# Find and read the spam folder and ham folder
	print STDERR "$d->{'dom'}: processing spam file\n" if ($debug);
	$spamf = { 'file' => &spam_alias_file($d),
		   'type' => 0 };
	@spammails = &mailboxes::mailbox_list_mails(undef, undef, $spamf);
	print STDERR "$d->{'dom'}: ",scalar(@spammails)," messages in ",
		     $spamf->{'file'},"\n" if ($debug);
	foreach $m (@spammails) {
		$m->{'spamtrap'} = 1;
		}
	@mails = @spammails;
	print STDERR "$d->{'dom'}: processing ham file\n" if ($debug);
	$hamf = { 'file' => &ham_alias_file($d),
		  'type' => 0 };
	@hammails = &mailboxes::mailbox_list_mails(undef, undef, $spamf);
	print STDERR "$d->{'dom'}: ",scalar(@hammails)," messages in ",
		     $hamf->{'file'},"\n" if ($debug);
	push(@mails, @hammails);

	foreach $m (@mails) {
		# Find the Virtualmin user for the sender or recipient
		print STDERR "$d->{'dom'}: subject ",
			     "$m->{'header'}->{'subject'}\n" if ($debug);
		$user = undef;
		foreach $h ('from', 'to', 'cc') {
			@sp = &mailboxes::split_addresses($m->{'header'}->{$h});
			foreach $e (map { $_->[0] } @sp) {
				$user ||= &find_user_by_email($e, $users);
				last if ($user);
				}
			if ($user) {
				$what = $h eq 'from' ? 'from' : 'to';
				last;
				}
			}
		print STDERR "$d->{'dom'}: user=",
		    ($user ? $user->{'user'} : "")," what=$what\n" if ($debug);
		next if (!$user);

		# For each message, find the attached mail if there is one and
		# if this email was forwarded by a Virtualmin user.
		&mailboxes::parse_mail($m, undef, 1);
		if ($what eq 'from' && @{$m->{'attach'}} >= 1) {
			$a = $m->{'attach'}->[0];
			if ($a->{'type'} eq 'message/rfc822') {
				$m = &mailboxes::extract_mail($a->{'data'});
				}
			}

		# Feed to sa-learn --spam or --ham, run as the sender
		local $cmd = $m->{'spamtrap'} ? "$salearn --spam"
					      : "$salearn --ham";
		$cmd = &command_as_user($cmd, 0, $cmd);
		$temp = &transname();
		&mailboxes::send_mail($m, $temp);
		&set_ownership_permissions($user->{'uid'}, $user->{'gid'},
					   0700, $temp);
		$out = &backquote_command("$cmd <$temp 2>&1");
		$ex = $?;
		&unlink_file($temp);
		# XXX check output

		# XXX global blacklist??
		}

	# Delete both folders
	# XXX
	}

# find_user_by_email(email, &users)
sub find_user_by_email
{
local ($e, $users) = @_;
foreach my $u (@$users) {
	if ($u->{'email'} eq $e) {
		return $u;
		}
	foreach my $ee (@{$u->{'extraemail'}}) {
		if ($ee eq $e) {
			return $u;
			}
		}
	}
return undef;
}

