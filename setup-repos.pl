#!/usr/local/bin/perl

=head1 setup-repos.pl

Setup Virtualmin repositories.

This program can be used to set up Virtualmin and Webmin repositories.

The C<--branch> parameter can be used to set the repository branch to one of
C<stable>, C<prerelease>, or C<unstable>. If the branch isn't specified, the
currently configured branch will be used, or C<stable> if none is configured.

You can force an update to the license serial and key used in repositories by
passing C<--serial> and C<--key> parameters. If not set, existing keys found
in /etc/virtualmin-license will be used. GPL users should not use C<--serial>
and C<--key> parameters unless they want to configure Virtualmin Pro
repositories.

If C<--serial> and C<--key> parameters are set and the license is not actually
valid, an error will be returned, unless the C<--no-check> parameter is given.

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
	$0 = "$pwd/setup-repos.pl";
	require './virtual-server-lib.pl';
	require './virtualmin-licence.pl';
	$< == 0 || die "setup-repos.pl must be run as root";
	}

# Parse command-line args
&set_all_text_print();
@OLDARGV = @ARGV;

# Parse args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--branch") {
		$branch = shift(@ARGV);
		&usage("Invalid branch '$branch', must be one of ".
		       "stable, prerelease, or unstable")
			if ($branch !~ /^(stable|prerelease|unstable)$/);
		}
	elsif ($a eq "--serial") {
		$serial = shift(@ARGV);
		}
	elsif ($a eq "--key") {
		$key = shift(@ARGV);
		}
	elsif ($a eq "--no-check") {
		$nocheck = "--no-check ";
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
	}
}

# Change license if serial and key given
if ($serial && $key) {
	my ($err, $msg) = &change_licence($serial, $key, $nocheck, 1, 1);
	if ($err && $msg) {
		&usage("Error changing licence : $msg");
		}
	}

# Set up Virtualmin repositories
my $repo_branch;
$repo_branch = &detect_virtualmin_repo_branch() if (!$branch);
$repo_branch ||= $branch;
&$first_print("Setting up Virtualmin $repo_branch repositories ..");
my ($st, $err, $out) = &setup_virtualmin_repos($repo_branch);
if ($st) {
	&$first_print(".. error : @{[setup_repos_error($err || $out)]}");
	}
else {
	&$first_print(".. done");
	}

&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Setup Virtualmin repositories.\n";
print "\n";
print "virtualmin setup-repos [--branch <stable|prerelease|unstable>]\n";
print "                       [--serial number] [--key id] [--no-check]\n";
exit(1);
}
