#!/usr/local/bin/perl
# Update access control and usage limits for this domain's user

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_limits($d) || &error($text{'edit_ecannot'});

# Validate and store inputs
&error_setup($text{'limits_err'});
$in{'mailboxlimit_def'} || $in{'mailboxlimit'} =~ /^\d+$/ ||
	&error($text{'setup_emailboxlimit'});
$d->{'mailboxlimit'} = $in{'mailboxlimit_def'} ? undef : $in{'mailboxlimit'};
$in{'aliaslimit_def'} || $in{'aliaslimit'} =~ /^\d+$/ ||
	&error($text{'setup_ealiaslimit'});
$d->{'aliaslimit'} = $in{'aliaslimit_def'} ? undef : $in{'aliaslimit'};
$in{'dbslimit_def'} || $in{'dbslimit'} =~ /^\d+$/ ||
	&error($text{'setup_edbslimit'});
$d->{'dbslimit'} = $in{'dbslimit_def'} ? undef : $in{'dbslimit'};
$in{'domslimit_def'} || $in{'domslimit'} =~ /^\d+$/ ||
	&error($text{'limits_edomslimit'});
$d->{'domslimit'} = $in{'domslimit_def'} == 1 ? undef :
		    $in{'domslimit_def'} == 2 ? "*" : $in{'domslimit'};
$in{'aliasdomslimit_def'} || $in{'aliasdomslimit'} =~ /^\d+$/ ||
	&error($text{'limits_ealiasdomslimit'});
$d->{'aliasdomslimit'} = $in{'aliasdomslimit_def'} == 1 ? undef
		   					: $in{'aliasdomslimit'};
$in{'realdomslimit_def'} || $in{'realdomslimit'} =~ /^\d+$/ ||
	&error($text{'limits_erealdomslimit'});
$d->{'realdomslimit'} = $in{'realdomslimit_def'} == 1 ? undef
		   				      : $in{'realdomslimit'};
$d->{'nodbname'} = $in{'nodbname'};
$d->{'norename'} = $in{'norename'};
$d->{'migrate'} = $in{'migrate'};
$d->{'forceunder'} = $in{'forceunder'};
$d->{'safeunder'} = $in{'safeunder'};
$d->{'ipfollow'} = $in{'ipfollow'};
if ($virtualmin_pro) {
	$in{'mongrels_def'} || $in{'mongrels'} =~ /^[1-9][0-9]*$/ ||
		&error($text{'limits_emongrels'});
	$d->{'mongrelslimit'} = $in{'mongrels_def'} ? undef : $in{'mongrels'};
	}
$d->{'demo'} = $in{'demo'};
%sel_features = map { $_, 1 } split(/\0/, $in{'features'});
foreach $f (@opt_features, "virt", &list_feature_plugins()) {
	next if (!&can_use_feature($f));
	next if ($config{$f} == 3);
	$d->{"limit_".$f} = $sel_features{$f};
	}
$d->{'webmin_nocat_modules'} = $in{'nocatwebmin'};
if (&can_webmin_modules()) {
	$d->{'webmin_modules'} = $in{'modules'};
	}

# Save edit options
%sel_edits = map { $_, 1 } split(/\0/, $in{'edit'});
foreach $ed (@edit_limits) {
	$d->{"edit_".$ed} = $sel_edits{$ed};
	}

# Save plugin inputs
foreach $f (&list_feature_plugins()) {
	$err = &plugin_call($f, "feature_limits_parse", $d, \%in);
	&error($err) if ($err);
	}

# Save allowed scripts
if (defined(&list_scripts)) {
	if ($in{'scripts_def'}) {
		$d->{'allowedscripts'} = undef;
		}
	else {
		$d->{'allowedscripts'} =
			join(' ', split(/\r?\n/, $in{'scripts'}));
		}
	}

# Update files
&set_all_null_print();
&save_domain($d);
if (defined($in{'shell'})) {
	# Update shell
	&change_domain_shell($d, $in{'shell'});
	}
&refresh_webmin_user($d);

# Update jail
if (!&check_jailkit_support()) {
	my $oldjail = &get_domain_jailkit($d);
	if ($in{'jail'}) {
		# Setup or re-sync jail for this user
		$err = &enable_domain_jailkit($d);
		&error(&text('limits_ejailon', $err)) if ($err);
		$d->{'jail'} = 1 if (!$err);
		}
	elsif ($oldjail && !$in{'jail'}) {
		# Tear down jail for this user
		$err = &disable_domain_jailkit($d);
		&error(&text('limits_ejailoff', $err)) if ($err);
		$d->{'jail'} = 0 if (!$err);
		}
	&save_domain($d);
	}

&run_post_actions();
&clear_links_cache($d);
&webmin_log("limits", "domain", $d->{'dom'}, $d);

&domain_redirect($d);


