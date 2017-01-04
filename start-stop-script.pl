#!/usr/local/bin/perl

=head1 start-stop-script.pl

Stops, starts or restarts the server process for some script.

This command can be used to start, stop or restart the server process behind
some script, such as one using Node.JS or Ruby on Rails. It
takes the usual C<--domain> parameter to identify the server, and either
C<--id> followed by the install ID, or C<--type> followed by the script's short
name. The latter option is more convenient, but only works if there is only
one instance of the script in the virtual server. If multiple different versions
are installed, you can also use C<--version> to select a specific one to manage.

The action to take on the chosen script must be specified with exactly one of
the C<--start> , C<--stop> or C<--restart> flags.

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
	$0 = "$pwd/delete-script.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "start-stop-script.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
&set_all_text_print();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--type") {
		$sname = shift(@ARGV);
		}
	elsif ($a eq "--version") {
		$ver = shift(@ARGV);
		}
	elsif ($a eq "--path") {
		$path = shift(@ARGV);
		}
	elsif ($a eq "--id") {
		$id = shift(@ARGV);
		}
	elsif ($a =~ /^--(start|stop|restart)$/) {
		$mode = $1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate args
$domain || &usage("No domain specified");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$mode || &usage("Missing one of --start, --stop or --restart");

# Find the script
$id || $sname || usage("Either the --id or --type parameters must be given");
@scripts = &list_domain_scripts($d);
if ($id) {
	($sinfo) = grep { $_->{'id'} eq $id } @scripts;
	$sinfo || &usage("No script install with ID $id was found for this virtual server");
	}
else {
	@matches = grep { $_->{'name'} eq $sname } @scripts;
	if ($ver) {
		@matches = grep { $_->{'version'} eq $ver } @matches;
		}
	if ($path) {
		@matches = grep { $_->{'opts'}->{'path'} eq $path } @matches;
		}
	@matches || &usage("No script install for $sname was found for this virtual server");
	@matches == 1 || &usage("More than one script install for $sname was found for this virtual server. Use the --id option to specify the exact install, or --version to select a version");
	$sinfo = $matches[0];
	}

# Do the action
$script = &get_script($sinfo->{'name'});
$sfunc = $script->{'status_server_func'};
defined(&$sfunc) ||
	&usage("Script does not have a server that can be stopped or started");

if ($mode eq "start") {
	&$first_print("Starting server for $script->{'desc'} ..");
	$err = &{$script->{'start_server_func'}}($d, $sinfo->{'opts'});
	}
elsif ($mode eq "stop") {
	&$first_print("Stopping server for $script->{'desc'} ..");
	$err = &{$script->{'stop_server_func'}}($d, $sinfo->{'opts'});
	}
elsif ($mode eq "restart") {
	&$first_print("Restarting server for $script->{'desc'} ..");
	&{$script->{'stop_server_func'}}($d, $sinfo->{'opts'});
	sleep(1);	# Give it time to shut down
	$err = &{$script->{'start_server_func'}}($d, $sinfo->{'opts'});
	}
if ($err) {
	&$second_print(".. failed : $err");
	exit(1);
	}
else {
	&$second_print(".. done");
	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Stops, starts or restarts the server process for some script.\n";
print "\n";
print "virtualmin start-stop-script --domain domain.name\n";
print "                            [--type name --version number] |\n";
print "                            [--id number]\n";
print "                             --start | --stop | --restart\n";
exit(1);
}

