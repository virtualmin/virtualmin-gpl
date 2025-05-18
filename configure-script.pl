#!/usr/local/bin/perl
package virtual_server;

use File::Basename;

=head1 configure-script.pl

Configure or mass-configure web app scripts

This command enables you to modify settings, perform backups, create clones, and
execute other administrative tasks for one or more web app scripts, provided the
supported applications have a dedicated workbench plugin. Use the C<--mass> flag
to leverage the API for executing actions on multiple local and remote web apps
at once.

For detailed usage instructions and specific options for each script type and
mode, run the command with the C<--help> flag.

=cut

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
	$0 = "$pwd/configure-script.pl";
	require './virtual-server-lib.pl';
	}

# Load all modules that can configure web app scripts
my @mods;
foreach my $p (@plugins) {
	my %mod = &get_module_info($p);
	if ($mod{'config_script'}) {
		push(@mods, \%mod);
		&load_plugin_libraries($mod{'dir'});
		}
	}

# Pre-process args to get web app name
my ($web_app_name, $massapi);
for (my $i=0; $i<@ARGV; $i++) {
	if ($ARGV[$i] eq '--script-type' && $i+1 < @ARGV) {
		$web_app_name = $ARGV[$i+1];
		}
	elsif ($ARGV[$i] eq '--mass') {
		# boolean flag—no argument expected
		$massapi = 1;
		}
	}

# Check for missing --name parameter
if (!$web_app_name) {
	&usage("Missing script type name");
	}

# Locate the usage and CLI handlers for this script type
my $tapi_desc = 'Configure web app script';
my ($uapi, $capi, $tapi) = ('usage', 'cli', 'configure');
if ($massapi) {
	$tapi_desc = 'Mass-configure web app scripts';
	$uapi = 'usage_mass', $capi = 'cli_mass', $tapi = 'mass-configure';
	}
my $script_usage_func = &script_find_kit_func(\@mods, $web_app_name, $uapi);
my $script_cli        = &script_find_kit_func(\@mods, $web_app_name, $capi);

# Bail out if there’s no CLI handler
if (!$script_cli) {
	&usage("Script '$web_app_name' does not support $tapi API");
	}

# Parse common command-line flags
&parse_common_cli_flags(\@ARGV);

# Call the script-specific CLI function
$script_cli->(\@ARGV);

# Expandable usage function
sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "$tapi_desc\n\n";
print "virtualmin configure-script --script-type name";
if (defined(&$script_usage_func)) {
	$script_usage_func->($web_app_name);
	}
else {
	print "\n";
	}
exit(1);
}
