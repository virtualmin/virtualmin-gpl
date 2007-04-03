#!/usr/local/bin/perl
# Save the defaults for new users in this virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&error_setup($text{'defaults_err'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&can_edit_users() || &error($text{'users_ecannot'});
$user = &create_initial_user($d, 1);

# Save disk quotas
if (&has_home_quotas()) {
	if ($in{'quota_def'} == 1) {
		delete($user->{'quota'});
		}
	elsif ($in{'quota_def'} == 2) {
		$user->{'quota'} = "none";
		}
	else {
		$in{'quota'} =~ /^[0-9\.]+$/ ||
			&error($text{'defaults_equota'});
		$user->{'quota'} = &quota_parse("quota", "home");
		}
	}
if (&has_mail_quotas()) {
	if ($in{'mquota_def'} == 1) {
		delete($user->{'mquota'});
		}
	elsif ($in{'mquota_def'} == 2) {
		$user->{'mquota'} = "none";
		}
	else {
		$in{'mquota'} =~ /^[0-9\.]+$/ ||
			&error($text{'defaults_emquota'});
		$user->{'mquota'} = &quota_parse("mquota", "mail");
		}
	}

# Save mail server quota
if (&has_server_quotas()) {
	if ($in{'qquota_def'} == 1) {
		$user->{'qquota'} = "none";
		}
	else {
		$in{'qquota'} =~ /^\d+$/ || &error($text{'defaults_eqquota'});
		$user->{'qquota'} = $in{'qquota'};
		}
	}

# Save FTP login
if (&can_mailbox_ftp()) {
	$user->{'shell'} = $in{'ftp'} == 1 ? $config{'ftp_shell'} :
			 $in{'ftp'} == 3 ? $config{'jail_shell'} : $in{'shell'};
	}

# Save mail forwarding
if ($in{'aliases_def'}) {
	delete($user->{'to'});
	}
else {
	@values = &parse_alias(undef, "NEWUSER", [ ], "user", $d);
	$user->{'to'} = \@values;
	}

# Save databases
foreach $db (split(/\0/, $in{'dbs'})) {
	local ($type, $name) = split(/_/, $db, 2);
	push(@dbs, { 'type' => $type, 'name' => $name });
	}
$user->{'dbs'} = \@dbs;

# Save secondary groups
%cangroups = map { $_, 1 } (&allowed_secondary_groups($d),
			    @{$user->{'secs'}});
@secs = split(/\0/, $in{'groups'});
foreach my $g (@secs) {
	$cangroups{$g} || &error(&text('user_egroup', $g));
	}
$user->{'secs'} = [ @secs ];

# Primary address is not done yet
delete($user->{'email'});

# Save plugin defaults
foreach $f (@mail_plugins) {
	&plugin_call($f, "mailbox_defaults_parse", $user, $d, \%in);
	}

&save_initial_user($user, $d);
&webmin_log("initial", "domain", $d->{'dom'});
&redirect("list_users.cgi?dom=$in{'dom'}");
