#!/usr/local/bin/perl
# Update spam and virus scanners across all domains

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'sv_err'});
&can_edit_templates() || &error($text{'sv_ecannot'});

# Validate inputs
if ($config{'spam'}) {
	$client = $in{'client'};
	&has_command($client) || &error(&text('tmpl_espam',"<tt>$client</tt>"));
	if ($in{'host_def'}) {
		$host = undef;
		}
	else {
		gethostbyname($in{'host'}) || &error($text{'tmpl_espam_host'});
		$host = $in{'host'};
		}
	if ($in{'size_def'}) {
		$size = undef;
		}
	else {
		$in{'size'} =~ /^\d+$/ || &error($text{'tmpl_espam_size'});
		$size = $in{'size'};
		}
	if ($client eq "spamc" &&
	    (!$host || $host eq "localhost" ||
	     &to_ipaddress($host) eq &to_ipaddress(&get_system_hostname()))) {
		&find_byname("spamd") || &error($text{'tmpl_espamd'});
		}
	}
if ($config{'virus'}) {
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
	$err = &test_virus_scanner($fullcmd);
	if ($err) {
		&error(&text('sv_etest', $err));
		}
	}

# Update spam scanner
if ($config{'spam'}) {
	&save_global_spam_client($client, $host, $size);
	}

# Update virus scanner
if ($config{'virus'}) {
	&save_global_virus_scanner(
		$in{'scanner'} == 0 ? "clamscan" :
		$in{'scanner'} == 1 ? "clamdscan" : $in{'scanprog'});
	}

&set_all_null_print();
&run_post_actions();

# All done
&webmin_log("sv");
&redirect("");

