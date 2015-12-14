#!/usr/local/bin/perl
# Update the configured dynamic DNS service

package virtual_server;
$main::no_acl_check++;
$no_virtualmin_plugins = 1;
require './virtual-server-lib.pl';
&foreign_require("mailboxes");

exit(1) if (!$config{'dynip_service'});

$h = &get_system_hostname();
($svc) = grep { $_->{'name'} eq $config{'dynip_service'} }
	      &list_dynip_services();
$from = &get_global_from_address();

# Check if we need to update
($oldip, $oldwhen) = &get_last_dynip_update($config{'dynip_service'});
$newip = $config{'dynip_auto'} ? &get_external_ip_address()
			       : &get_default_ip();
if (!$newip) {
	# Failed to get current IP address .. so do nothing
	print STDERR "Failed to get current IP address\n";
	exit(0);
	}
if ($oldip ne $newip || $oldwhen < time()-28*24*60*60) {
	# Talk to the dynamic IP service, as our IP has changed or we
	# haven't reported in for a month
	($ip, $err) = &update_dynip_service();
	if ($err) {
		# Failed .. tell the user
		if ($config{'dynip_email'}) {
			&mailboxes::send_text_mail(
				$from,
				$config{'dynip_email'},
				undef,
				"Virtualmin dynamic IP update FAILED",
				join("\n", &mailboxes::wrap_lines(
					"An attempt to update the dynamic IP ".
					"for $h to $newip with ".
					"$svc->{'desc'} failed: $err\n", 75)).
				"Sent by Virtualmin at: ".
					&get_virtualmin_url()."\n"
				);
			}
		exit(1);
		}
	}

# Save and tell the user
if ($ip) {
	&set_last_dynip_update($config{'dynip_service'}, $ip);
	}
if ($ip && $ip ne $oldip) {
	# Fix up any virtual servers using the old IP
	if ($oldip) {
		&set_all_null_print();
		$dc = &update_all_domain_ip_addresses($ip, $oldip);
		&run_post_actions();

		# Also change shared IP
		@shared = &list_shared_ips();
		$idx = &indexof($oldip, @shared);
		if ($idx >= 0) {
			$shared[$idx] = $ip;
			&save_shared_ips(@shared);
			}
		}

	if ($config{'dynip_email'}) {
		# Email the user
		$dc ||= "No";
		&mailboxes::send_text_mail(
			$from,
			$config{'dynip_email'},
			undef,
			"Virtualmin dynamic IP update",
			join("\n", &mailboxes::wrap_lines(
				"The IP address of $h has been successfully ".
				"updated to $ip with $svc->{'desc'}. $dc ".
				"virtual servers have been configured to use ".
				"the new IP address\n", 75))."\n".
			"Sent by Virtualmin at: ".&get_virtualmin_url()."\n"
			);
		}
	}

