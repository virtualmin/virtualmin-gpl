#!/usr/local/bin/perl

=head1 list-rs-containers.pl

Lists all containers owned by a Rackspace account.

This command queries Rackspace's cloud files for the list of all containers
owned by a user. The login and API key for Rackspace must be set using the
C<--user> and C<--key> flags, unless defaults have been set in the Virtualmin
configuration.

By default output is in a human-readable table format, but you can switch to
a more parsable output format with the C<--multiline> flag. Or to just get a
list of filenames, use the C<--name-only> flag.

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
	$0 = "$pwd/list-rs-containers.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-rs-containers.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		}
	elsif ($a eq "--key") {
		$key = shift(@ARGV);
		}
	elsif ($a eq "--container") {
		$container = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$user ||= $config{'rs_user'};
$key ||= $config{'rs_key'};
$user || &usage("Missing --user parameter");
$key || &usage("Missing --key parameter");

# Login and list the containers
$h = &rs_connect($config{'rs_endpoint'}, $user, $key);
if (!ref($h)) {
	print "ERROR: $h\n";
	exit(1);
	}
$files = &rs_list_containers($h);
if (!ref($files)) {
	print "ERROR: $files\n";
	exit(1);
	}

if ($container) {
	@$files = grep { $_ eq $container } @$files;
	}
if ($multi) {
	# Full details
	foreach $f (@$files) {
		print $f,"\n";
		$st = &rs_stat_container($h, $f);
		if (ref($st)) {
			print "    Created: ",
			      &make_date($st->{'X-Timestamp'}),"\n";
			print "    Bytes used: ",
			      $st->{'X-Container-Bytes-Used'},"\n";
			print "    Object count: ",
			      $st->{'X-Container-Object-Count'},"\n";
			}
		else {
			print "    ERROR: $st\n";
			}
		}
	}
elsif ($nameonly) {
	# Container names only
	foreach $f (@$files) {
                print $f,"\n";
		}
	}
else {
	# Summary
	$fmt = "%-30.30s %-30.30s %-15.15s\n";
	printf $fmt, "Container name", "Created", "Size";
	printf $fmt, ("-" x 30), ("-" x 30), ("-" x 15);
	foreach $f (@$files) {
		$st = &rs_stat_container($h, $f);
		printf $fmt, $f, &make_date($st->{'X-Timestamp'}),
			     &nice_size($st->{'X-Container-Bytes-Used'});
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists all containers owned by a Rackspace account.\n";
print "\n";
print "virtualmin list-rs-containers [--multiline | --name-only]\n";
print "                              [--user username]\n";
print "                              [--key api-key]\n";
exit(1);
}
