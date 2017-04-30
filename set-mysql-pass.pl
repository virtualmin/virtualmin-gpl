#!/usr/local/bin/perl

=head1 set-mysql-pass.pl

Change the root MySQL password, even if the current password is unknown.

This command can be used for forcibly change the MySQL password (typically
for the root user), even when the password is unknown. Be careful using it
though, as it will shut down the MySQL server for up to 30 seconds during
the password change process.

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
	$0 = "$pwd/set-mysql-pass.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "set-mysql-pass.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
&require_mysql();
$user = $mysql::config{'login'};
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$pass || &usage("Missing --pass flag");
$user || &usage("Missing --user flag, and current MySQL user is unknown");
%lastconfig = %config;

# Force the change
my $err = &force_set_mysql_password($user, $pass);
if ($err) {
	print "ERROR: $err\n";
	exit(1);
	}

# Update the local config
if ($user eq $mysql::config{'login'}) {
	$mysql::config{'pass'} = $pass;
	$mysql::mysql_pass = $pass;
	&mysql::save_module_config(\%mysql::config, "mysql");
	$mysql::authstr = &mysql::make_authstr();
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);
print "OK\n";
exit(0);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Change the root MySQL password, even if the current password is unknown.\n";
print "\n";
print "virtualmin set-mysql-pass --pass password\n";
print "                         [--user username]\n";
exit(1);
}

