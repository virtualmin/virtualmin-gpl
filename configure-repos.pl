#!/usr/local/bin/perl

=head1 configure-repos.pl

Configure Virtualmin repositories.

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
	$0 = "$pwd/configure-repos.pl";
	require './virtual-server-lib.pl';
	require './virtualmin-licence.pl';
	$< == 0 || die "configure-repos.pl must be run as root";
	}

# Parse command-line args
&set_all_text_print();
@OLDARGV = @ARGV;

# Parse args
while(@ARGV > 0) {
	my $a = shift(@ARGV);
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
	# Keep license and repository progress single-spaced.
	local $second_print = $first_print;
	my ($err, $msg) = &change_licence($serial, $key, $nocheck, 1, 1);
	if ($err) {
		# Validation may have already printed the error without returning a message.
		&usage("Error changing licence : $msg") if ($msg);
		exit(1);
		}
	}

# Set up Virtualmin repositories
my $repo_branch;
$repo_branch = &detect_virtualmin_repo_branch() if (!$branch);
$repo_branch ||= $branch;
$repo_branch ||= 'stable';
my %vserial;
&read_env_file($virtualmin_license_file, \%vserial);
my $repo_type = 'gpl';
if ($vserial{'SerialNumber'} ne 'GPL' && $vserial{'LicenseKey'} ne 'GPL') {
	$repo_type = 'pro';
	}
local $| = 1;
my $configuring = 0;
&$first_print("Fetching latest repository setup script ..");
my ($st, $err, $out) = &setup_virtualmin_repos($repo_branch, sub {
	$configuring = 1;
	&$first_print(".. done");
	&$first_print($text{"licence_updating_repo_${repo_branch}_$repo_type"});
	});
if ($st) {
	my $error = &setup_repos_error($err || $out);
	# Keep sentence-style installer errors compact in CLI output.
	$error =~ s/\.\s+Exiting\.\z/, exiting/;
	$error =~ s/(?<!\.)\.\s*$//;
	# Point at the setup log only once configuring has started, so download
	# failures cannot name a previous run's log, and never repeat the path
	# when the installer's own error already gives it.
	my $log = "$module_var_directory/configure-repos.log";
	$error .= "; see $log for more details"
		if ($configuring && -s $log && index($error, $log) < 0);
	&$first_print(".. error : ".lcfirst($error));
	}
else {
	&$first_print(".. done");
	}

&virtualmin_api_log(\@OLDARGV);
# Preserve failures for callers such as the GPL-to-Pro upgrade command.
exit($st ? 1 : 0);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Configure Virtualmin repositories.\n";
print "\n";
print "virtualmin configure-repos [--branch <stable|prerelease|unstable>]\n";
print "                           [--serial number] [--key id] [--no-check]\n";
exit(1);
}
