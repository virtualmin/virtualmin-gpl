#!/usr/local/bin/perl
package virtual_server;

use File::Basename;

=head1 configure-all-scripts.pl

Mass-configure web app scripts

This command allows you to modify settings, perform backups, create clones, and
execute other administrative tasks for multiple web app scripts on various local
or remote systems, as long as the app has a dedicated workbench plugin
available and installed.

For detailed usage instructions and specific options, run the command with the
C<--help> flag.

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
	$0 = "$pwd/configure-all-scripts.pl";
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
my $web_app_name;
for (my $i=0; $i<@ARGV; $i++) {
	if ($ARGV[$i] eq '--app' && $i+1 < @ARGV) {
		$web_app_name = $ARGV[$i+1];
		}
	}

# Check for missing --name parameter
if (!$web_app_name) {
	&usage("Missing script type name");
	}

# Locate the usage and CLI handlers for this script type
my $script_usage_func =
	&script_find_kit_func(\@mods, $web_app_name, 'usage_mass');
my $script_cli =
	&script_find_kit_func(\@mods, $web_app_name, 'cli_mass');

# Bail out if there’s no CLI handler
if (!$script_cli) {
	&usage("Script '$web_app_name' does not support mass-configure API");
	}

# Parse common command-line flags
&parse_common_cli_flags(\@ARGV);

# Call the script-specific CLI function
$script_cli->(\@ARGV);

# Expandable usage function
sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Mass-configure web app scripts\n\n";
my $has_script_usage_func = defined(&$script_usage_func);
my $name = 'name';
$name = $web_app_name if ($has_script_usage_func && $web_app_name);
print "virtualmin configure-all-scripts --app $name";
if ($has_script_usage_func) {
	$script_usage_func->($web_app_name);
	}
else {
	print "\n";
	}
exit(1);
}
