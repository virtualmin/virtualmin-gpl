#!/usr/local/bin/perl

=head1 set-global-feature.pl

Turns on or off some Virtualmin feature or plugin globally.

This command is the equivalent of the Features and Plugins page in the
Virtualmin UI, as it can be used to enable or disable features and plugins
globally. To activate a feature, use the C<--enable-feature> flag followed
by a code like C<web> or C<ftp>, as shown by the C<list-features> API command.
To turn off a feature, use the C<--disable-feature> flag. In both cases,
dependencies will be checked before a change is made, to prevent enabling
of features that have missing pre-requisites, or disabling of features that
are currently in use.

To control if a feature or plugin is enabled by default for new domains,
use the C<--default-on> or C<--default-off> flags followed by a feature code.
Features that are not globally enabled cannot be turned on by default.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/set-global-feature.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "set-global-feature.pl must be run as root";
	}
@OLDARGV = @ARGV;

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--enable-feature") {
		push(@enable, shift(@ARGV));
		}
	elsif ($a eq "--disable-feature") {
		push(@disable, shift(@ARGV));
		}
	elsif ($a eq "--default-on") {
		push(@defaulton, shift(@ARGV));
		}
	elsif ($a eq "--default-off") {
		push(@defaultoff, shift(@ARGV));
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@enable || @disable || @defaulton || @defaultoff || &usage("Nothing to do");
%lastconfig = %config;

# Verify inputs
foreach $f (@enable, @disable, @defaulton, @defaultoff) {
	if (&indexof($f, @features) < 0) {
		# Not a feature .. maybe a plugin
		$mdir = &module_root_directory($f);
		if (!&foreign_check($f) || !-r "$mdir/virtual_feature.pl") {
			&usage("$f is neither a core feature or plugin");
			}
		}
	}
foreach $f (@disable) {
	&indexof($f, @vital_features) < 0 ||
		&usage("$f is a vital feature which cannot be disabled");
	}

# Make sure new plugins can be used
foreach $f (@enable) {
	if (&indexof($f, @features) < 0) {
		&foreign_require($f, "virtual_feature.pl");
		$err = &plugin_call($f, "feature_check");
		&usage("Plugin $f cannot be enabled : $err") if ($err);
		}
	}

# Update module config
foreach $f (@enable) {
	if (&indexof($f, @features) >= 0) {
		# A feature being enabled
		next if ($config{$f});
		$config{$f} = 1;
		}
	else {
		# A plugin being enabled
		next if (&indexof($f, @plugins) >= 0);
		push(@plugins, $f);
		}
	}
foreach $f (@disable) {
	if (&indexof($f, @features) >= 0) {
		# A feature being disabled
		$config{$f} = 0;
		}
	else {
		# A plugin being disabled
		@plugins = grep { $_ ne $f } @plugins;
		}
	}

# Update default states
@inactive = split(/\s+/, $config{'plugins_inactive'});
foreach $f (@defaulton) {
	if (&indexof($f, @features) >= 0) {
		# A feature being turned on by default
		$config{$f} = 1 if ($config{$f});
		}
	else {
		# A plugin being turned on by default
		@inactive = grep { $_ ne $f } @inactive;
		}
	}
foreach $f (@defaultoff) {
	if (&indexof($f, @features) >= 0) {
		# A feature being turned off by default
		$config{$f} = 2 if ($config{$f});
		}
	else {
		# A plugin being turned off by default
		@inactive = &unique(@inactive, $f);
		}
	}
$config{'plugins_inactive'} = join(" ", @inactive);

$oldplugins = $config{'plugins'};
$config{'plugins'} = join(" ", @plugins);

# Validate new settings with a config check
&set_all_null_print();
$cerr = &check_virtual_server_config(\%lastconfig);
&usage(&html_tags_to_text($cerr)) if ($cerr);

# Update the procmail setting for default delivery, turn on logging, and 
# create cron job to link up files
if ($config{'spam'}) {
	if (!$config{'no_lookup_domain_daemon'}) {
		&setup_lookup_domain_daemon();
		}
	&setup_default_delivery();
	&enable_procmail_logging();
	&setup_spam_config_job();
	}

# Fix up old procmail scripts that don't call the clam wrapper
if ($config{'virus'}) {
	&copy_clam_wrapper();
	&fix_clam_wrapper();
	}

# Re-generate helper script, for plugins
@plugindirs = map { &module_root_directory($_) } @plugins;
&create_api_helper_command(\@plugindirs);

# Save the config
&lock_file($module_config_file);
if ($config{'last_check'} < time()) {
	$config{'last_check'} = time()+1;
	}
&save_module_config();
&unlock_file($module_config_file);

# Update the miniserv preload list, which includes plugins
if ($oldplugins ne $config{'plugins'}) {
	&update_miniserv_preloads($config{'preload_mode'});
	&restart_miniserv();
	}

print "Enabled ",join(" ", @enable),"\n" if (@enable);
print "Disabled ",join(" ", @disable),"\n" if (@disable);
print "Turned on by default ",join(" ", @defaulton),"\n" if (@defaulton);
print "Turned off by default ",join(" ", @defaultoff),"\n" if (@defaultoff);
&run_post_actions();
&virtualmin_api_log(\@OLDARGV);
exit(0);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Turns on or off some Virtualmin feature or plugin globally.\n";
print "\n";
print "virtualmin set-global-feature --enable-feature name\n";
print "                              --disable-feature name\n";
print "                              --default-on name\n";
print "                              --default-off name\n";
exit(1);
}

