#!/usr/bin/perl
# Save provisioning settings

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'provision_ecannot'});
&error_setup($text{'provision_err'});
&ReadParse();
%oldconfig = %config;

# Validate and store inputs
foreach $f (&list_provision_features()) {
	push(@oldpfeatures, $f) if ($config{'provision_'.$f});
	push(@pfeatures, $f) if ($in{'provision_'.$f});
	}
if ($in{'provision_cloudmin'}) {
	# Use Virtualmin's provisioning service
	$in{'provision_server'} = $cloudmin_provisioning_server;
	$in{'provision_port'} = $cloudmin_provisioning_port;
	$in{'provision_ssl'} = $cloudmin_provisioning_ssl;
	}
if (@pfeatures) {
	&to_ipaddress($in{'provision_server'}) ||
	  defined(&to_ip6address) && &to_ip6address($in{'provision_server'}) ||
	     &error($text{'provision_eserver'});
	$in{'provision_port'} =~ /^[1-9][0-9]*$/ ||
	     &error($text{'provision_eport'});
	$in{'provision_user'} =~ /^[a-zA-Z0-9\.\-\_\@]+$/ ||
	     &error($text{'provision_euser'});
	$in{'provision_pass'} =~ /:/ &&
	     &error($text{'provision_epass'});
	}
$config{'provision_server'} = $in{'provision_server'};
$config{'provision_port'} = $in{'provision_port'};
$config{'provision_ssl'} = $in{'provision_ssl'} || 0;
$config{'provision_user'} = $in{'provision_user'};
$config{'provision_pass'} = $in{'provision_pass'};
foreach $f (&list_provision_features()) {
	$config{'provision_'.$f} = $in{'provision_'.$f} || 0;
	}

&ui_print_header(undef, $text{'provision_title'}, "");

# Check that provisioning works for the server and login
&$first_print(&text('provision_checking', "<tt>$in{'provision_server'}</tt>"));
$err = &check_provision_login();
if ($err) {
	&$second_print(&text('provision_echeck', $err));
	goto FAILED;
	}
else {
	&$second_print($text{'setup_done'});
	}

# If virus provisioning is enabled, force use of clamdscan remote for
# all domains
if ($in{'provision_virus'} && !$config{'provision_virus_host'}) {
	&$first_print($text{'provision_virussetup'});
	($ok, $msg) = &provision_api_call("provision-virus", { }, 0);
	if (!$ok || $msg !~ /ip=\S+/ || $msg !~ /port=\d+/ ||
	    $msg !~ /host=\S+/) {
		&$second_print(&text('provision_evirussetup', $msg));
		}
	else {
		$msg =~ /ip=(\S+)/;
		$clamhost = $1;
		$msg =~ /port=(\S+)/;
		$clamhost .= ":$1" if ($1 != 3310);
		$err = &test_virus_scanner("clamdscan-remote", $clamhost);
		if ($err) {
			&$second_print(&text('provision_evirustest',
					     $clamhost, $err));
			}
		else {
			&save_global_virus_scanner("clamdscan-remote",
						   $clamhost);
			$msg =~ /host=(\S+)/;
			$config{'provision_virus_host'} = $1;
			&save_module_config();
			&$second_print(&text('provision_virusgot', $clamhost));
			if (&check_clamd_status() == 1) {
				# Can now disable clamd
				&disable_clamd();
				}
			}
		}
	}
elsif (!$in{'provision_virus'} && $config{'provision_virus_host'}) {
	# Un-provision virus access
	&$first_print($text{'provision_virusunsetup'});
	$clamhost = $config{'provision_virus_host'};
	$clamhost =~ s/:\d+$//;
	($ok, $msg) = &provision_api_call("unprovision-virus",
					  { 'host' => $clamhost }, 0);
	if (!$ok) {
		&$second_print(&text('provision_evirusunsetup', $msg));
		}
	else {
		# Done .. switch back to clamscan
		&save_global_virus_scanner("clamscan");
		&$second_print($text{'setup_done'});
		}
	delete($config{'provision_virus_host'});
	&save_module_config();
	}

# If spam provisioning is enabled, force use of spamc for
# all domains
if ($in{'provision_spam'} && !$config{'provision_spam_host'}) {
	&$first_print($text{'provision_spamsetup'});
	($ok, $msg) = &provision_api_call("provision-spam", { }, 0);
	if (!$ok || $msg !~ /ip=\S+/ || $msg !~ /port=\d+/ ||
	    $msg !~ /host=\S+/) {
		&$second_print(&text('provision_espamsetup', $msg));
		}
	else {
		$msg =~ /ip=(\S+)/;
		$spamhost = $1;
		$msg =~ /port=(\S+)/;
		$spamhost .= ":$1" if ($1 != 783);
		&save_global_spam_client("spamc", $spamhost);
		$msg =~ /host=(\S+)/;
		$config{'provision_spam_host'} = $1;
		&save_module_config();
		&$second_print(&text('provision_spamgot', $spamhost));
		if (&check_spamd_status() == 1) {
			# Can now disable spamd
			&disable_spamd();
			}
		}
	}
elsif (!$in{'provision_spam'} && $config{'provision_spam_host'}) {
	# Un-provision spam filtering
	&$first_print($text{'provision_spamunsetup'});
	$spamhost = $config{'provision_spam_host'};
	$spamhost =~ s/:\d+$//;
	($ok, $msg) = &provision_api_call("unprovision-spam",
					  { 'host' => $spamhost }, 0);
	if (!$ok) {
		&$second_print(&text('provision_espamunsetup', $msg));
		}
	else {
		# Done .. switch back to spamassassin
		&save_global_spam_client("spamassassin");
		&$second_print($text{'setup_done'});
		}
	delete($config{'provision_spam_host'});
	&save_module_config();
	}



# Get limits from the server and display
&$first_print(&text('provision_limits'));
($ok, $feats) = &provision_api_call("list-provision-features", {}, 1);
foreach $f (@$feats) {
	$v = $f->{'values'};
	push(@lmsgs, &text('provision_limit',
			   $v->{'limit'} ? $v->{'limit'}->[0]
					 : $text{'provision_nolimit'},
			   $v->{'description'}->[0]).
		     ($v->{'usage'}->[0] ? " ".&text('provision_used',
						     $v->{'usage'}->[0]) : ""));
	}
&$second_print(&text('provision_limitsgot', join(', ', @lmsgs)));

# Save config and tell the user
&$first_print($text{'provision_saving'});
&save_module_config();
&$second_print($text{'setup_done'});

FAILED:
&ui_print_footer("", $text{'index_return'});

