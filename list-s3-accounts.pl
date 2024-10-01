#!/usr/local/bin/perl

=head1 list-s3-accounts.pl

Lists all S3 Virtualmin accounts.

This command lists all S3 accounts registered with Virtualmin.

By default output is in a human-readable table format, but you can switch to
a more parsable output format with the C<--multiline> flag. Or to just get a
list of access keys, use the C<--name-only> flag.

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
	$0 = "$pwd/list-s3-accounts.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-s3-accounts.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
&parse_common_cli_flags(\@ARGV);
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	&usage("Unknown parameter $a");
	}
@s3s = &list_s3_accounts();

if ($multiline) {
	# Full details
	my @scheds = &list_scheduled_backups();
	foreach $s (@s3s) {
		print $s->{'id'},"\n";
		if ($s->{'iam'}) {
			print "    IAM credentials: Yes\n";
			}
		else {
			print "    Access key: $s->{'access'}\n";
			print "    Secret key: $s->{'secret'}\n";
			print "    IAM credentials: No\n";
			}
		if ($s->{'desc'}) {
			print "    Description: $s->{'desc'}\n";
			}
		if ($s->{'endpoint'}) {
			print "    Endpoint: $s->{'endpoint'}\n";
			}
		if ($s->{'location'}) {
			print "    Default location: $s->{'location'}\n";
			}
		my @users = grep { &backup_uses_s3_account($_, $s) } @scheds;
		foreach my $b (@users) {
			print "    Used by backup ID: ",$b->{'id'},"\n";
			}
		}
	}
elsif ($nameonly) {
	# Access keys only
	foreach $s (@s3s) {
                print ($s->{'access'} || "None"),"\n";
		}
	}
else {
	# Summary
	$fmt = "%-45.45s %-30.30s\n";
	printf $fmt, "Access Key", "Description";
	printf $fmt, ("-" x 45), ("-" x 30);
	foreach $s (@s3s) {
		printf $fmt, $s->{'access'} || "None", $s->{'desc'};
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists all S3 Virtualmin accounts.\n";
print "\n";
print "virtualmin list-s3-accounts [--multiline | --json | --xml | --name-only]\n";
exit(1);
}
