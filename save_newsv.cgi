#!/usr/local/bin/perl
# Update spam and virus scanners across all domains

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'sv_err'});
&can_edit_templates() || &error($text{'sv_ecannot'});

# Validate inputs
if ($config{'spam'}) {
	if ($config{'provision_spam_host'}) {
		# Client and host don't change
		($client, $host, $size) = &get_global_spam_client();
		}
	else {
		# Validate spamassassin program and host system
		$client = $in{'client'};
		&has_command($client) ||
			&error(&text('tmpl_espam',"<tt>$client</tt>"));
		if ($in{'host_def'}) {
			$host = undef;
			}
		else {
			&to_ipaddress($in{'host'}) ||
			    defined(&to_ip6address) &&
			    &to_ip6address($in{'host'}) ||
				&error($text{'tmpl_espam_host'});
			$host = $in{'host'};
			}
		}
	# Validate max size
	if ($in{'size_def'}) {
		$size = undef;
		}
	else {
		$in{'size'} =~ /^\d+$/ || &error($text{'tmpl_espam_size'});
		$size = $in{'size'}*$in{'size_units'};
		}
	if ($client eq "spamc" &&
	    (!$host || $host eq "localhost" ||
	     &to_ipaddress($host) eq &to_ipaddress(&get_system_hostname()))) {
		&find_byname("spamd") || &error($text{'tmpl_espamd'});
		}
	}
if ($config{'virus'} && !$config{'provision_virus_host'}) {
	if ($in{'scanner'} == 2) {
		local ($cmd, @args) = &split_quoted_string($in{'scanprog'});
		&has_command($cmd) || &error($text{'spam_escanner'});
		$fullcmd = $in{'scanprog'};
		}
	elsif ($in{'scanner'} == 1) {
		&find_byname("clamd") || &error($text{'spam_eclamdscan'});
		&has_command("clamdscan") || &error($text{'sv_eclamdscan'});
		$fullcmd = "clamdscan";
		}
	elsif ($in{'scanner'} == 0) {
		&has_command("clamscan") || &error($text{'sv_eclamscan'});
		$fullcmd = "clamscan";
		}
	elsif ($in{'scanner'} == 3) {
		&has_command("clamd-stream-client") ||
			&error($text{'sv_estream'});
		$fullcmd = "clamd-stream-client";
		}
	elsif ($in{'scanner'} == 4) {
		&has_command("clamdscan") || &error($text{'sv_eclamdscan'});
		$fullcmd = "clamdscan-remote";
		}
	$in{'vhost_def'} || &to_ipaddress($in{'vhost'}) ||
		&error($text{'sv_evhost'});
	$err = &test_virus_scanner($fullcmd,
				   $in{'vhost_def'} ? undef : $in{'vhost'});
	if ($err) {
		&error(&text('sv_etest', $err));
		}
	}

&obtain_lock_spam_all();

# Update spam scanner
if ($config{'spam'}) {
	&save_global_spam_client($client, $host, $size);
	}

# Update user procmail setting
if ($config{'spam'}) {
	if ($config{'default_procmail'} != $in{'default_procmail'}) {
		$config{'default_procmail'} = $in{'default_procmail'};
		&setup_default_delivery();

		# Save the config
		&lock_file($module_config_file);
		if ($config{'last_check'} < time()) {
			$config{'last_check'} = time()+1;
			}
		&save_module_config();
		&unlock_file($module_config_file);
		}
	}

# Update virus scanner
if ($config{'virus'} && !$config{'provision_virus_host'}) {
	&save_global_virus_scanner($fullcmd,
				   $in{'vhost_def'} ? undef : $in{'vhost'});
	}

# Update bounce behavior
if ($config{'spam'} && defined($in{'exitcode'})) {
	&save_global_quota_exitcode($in{'exitcode'});
	}

&release_lock_spam_all();

&set_all_null_print();
&modify_all_webmin();	# Spam setting may have changed
&run_post_actions();

# All done
&webmin_log("sv");
&redirect("");

