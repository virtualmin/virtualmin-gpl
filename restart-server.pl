#!/usr/local/bin/perl

=head1 restart-server.pl

Restarts one of the servers managed by Virtualmin.

This command stops and re-starts one of the servers managed by Virtualmin,
such as Apache or BIND. The server to restart must be set using the
C<--server> flag, followed by a feature name like C<web> or C<dns>.

For server types that have multiple versions such as FPM, you can select
the version to restart with the C<--version> flag. Or use C<--domain> to find
automatically select the correct version for the given domain.

By default the server will be completely stopped and re-started, but for some
server types you can request a configuration reload instead with the 
C<--reload> flag.

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
	$0 = "$pwd/restart-server.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "restart-server.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--version") {
		$ver = shift(@ARGV);
		}
	elsif ($a eq "--server") {
		$sname = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--quiet") {
		$quiet = 1;
		}
	elsif ($a eq "--reload") {
		$reload = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate server name
$sname || &usage("Missing name of server to restart");
@slist = ( );
foreach my $f (@startstop_features) {
	my $sfunc = "startstop_".$f;
	if ($config{$f} && defined(&$sfunc)) {
		foreach my $s (&$sfunc()) {
			my $sf = $s->{'feature'} || $f;
			if ($sf eq $sname) {
				$found = 1;
				}
			push(@slist, $sf);
			}
		}
	}
foreach my $f (&list_startstop_plugins()) {
	if ($f eq $sname) {
		$found = 2;
		}
	push(@slist, $f);
	}
@slist = &unique(@slist);
$found || &usage("Server $sname does not exist. Valid servers are : ".join(" ", @slist));

# Get the FPM version from the domain
if ($sname eq "fpm" && !$ver) {
	$dname || &usage("When restarting the FPM server, either the --version or --domain flag must be given");
	$d = &get_domain($dname) || &get_domain_by("dom", $dname);
	$d || &usage("Virtual server $dname does not exist");
	my $conf = &get_php_fpm_config($d);
	$conf || &usage("No FPM config found for $dname");
	$ver = $conf->{'version'};
	}

# Restart the server
if (!$quiet) {
	if ($reload) {
		&$first_print("Reloading server $sname".($ver ? " version $ver" : "")." ...");
		}
	else {
		&$first_print("Restarting server $sname".($ver ? " version $ver" : "")." ...");
		}
	}
if ($found == 1) {
	# Core server
	my $startfunc = "start_service_".$sname;
	my $stopfunc = "stop_service_".$sname;
	my $reloadfunc = "reload_service_".$sname;
	if ($reload && defined(&$reloadfunc)) {
		# Call reload function
		$err = &$reloadfunc($ver);
		}
	else {
		# Just call start and stop
		$err = &$stopfunc($ver);
		if (!$err) {
			$err = &$startfunc($ver);
			}
		}
	}
else {
	# Plugin server
	if ($reload && &plugin_defined($sname, "feature_reload_service")) {
		# Call reload function
		$err = &plugin_call($sname, "feature_reload_service", $ver);
		}
	else {
		# Just call start and stop
		$err = &plugin_call($sname, "feature_stop_service", $ver);
		if (!$err) {
			$err = &plugin_call($sname, "feature_start_service", $ver);
			}
		}
	}
if (!$quiet) {
	if ($err) {
		&$second_print(".. failed : $err");
		}
	else {
		&$second_print(".. done");
		}
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);
exit($err ? 1 : 0);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Restarts one of the servers managed by Virtualmin.\n";
print "\n";
print "virtualmin restart-server --server name\n";
print "                         [--domain name | --version number]\n";
print "                         [--quiet]\n";
print "                         [--reload]\n";
exit(1);
}

