#!/usr/local/bin/perl

=head1 downgrade-licence.pl

Downgrade Virtualmin Pro system to GPL version

This program downgrades a Virtualmin Pro system to GPL. It also removes Pro-only
plugins like Virtualmin Support and Virtualmin WP Workbench, locks reseller
accounts, switches repositories, and reverts the license to GPL.

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
	$0 = "$pwd/downgrade-licence.pl";
	require './virtual-server-lib.pl';
	require './virtualmin-licence.pl';
	$< == 0 || die "downgrade-licence.pl must be run as root";
	}
&set_all_text_print();
@OLDARGV = @ARGV;

# Track whether the package downgrade failed so we can restore the original
# Pro license and repositories before printing the final summary
my $gpl_downgrading_failed_status;

# Read the current Pro license details once, and reuse them for rollback if
# any later downgrade step fails
my %vserial;
&read_env_file($virtualmin_license_file, \%vserial);
if ($vserial{'SerialNumber'} eq 'GPL' ||
    $vserial{'LicenseKey'} eq 'GPL') {
	&$first_print($text{'downgrade_gpl_already'});
	exit;
	}

# Ask for confirmation and explain what's going to happen
my @lines = (
  "This program downgrades a Virtualmin Pro system to GPL. It also removes ".
  "Pro-only",
  "plugins like Virtualmin Support and Virtualmin WP Workbench, locks reseller",
  "accounts, switches repositories, and reverts the license to GPL."
);
for my $line (@lines) {
	printf "\e[1;30;41m%-80s\e[0m\n", $line;
	}
print "Do you want to continue? (y/N): ";
my $response = <STDIN>;
chomp($response);
if (lc($response) ne 'y' && $response ne '') {
	exit;
	}
print "\n";

# Once the downgrade starts, ignore Ctrl+C and let the explicit failure paths
# handle restoring the original Pro state
$SIG{'INT'} = 'IGNORE';

# Preserve the current repo branch so downgrade and rollback both use the same
# stable, prerelease, or unstable repository family
my $repo_branch = &detect_virtualmin_repo_branch();
$repo_branch ||= 'stable';

# Downgrade Virtualmin license file
&$first_print($text{'downgrade_gpl_license'});
&lock_file($virtualmin_license_file);
my %lfile = ( 'SerialNumber' => "GPL",
	      'LicenseKey' => "GPL" );
&write_env_file($virtualmin_license_file, \%lfile);
&unlock_file($virtualmin_license_file);
&$second_print($text{'setup_done'});

# Set up Virtualmin repositories
&$first_print($text{"licence_updating_repo_${repo_branch}_gpl"});
my ($st, $err, $out) = &setup_virtualmin_repos($repo_branch);
if ($st) {
	# If GPL repo setup fails, immediately restore the original Pro license
	# and repos before exiting
	&$second_print($text{'setup_failed'}." : ".
		     &setup_repos_error($err || $out));
	&revert_virtualmin_license_file(\%vserial, $repo_branch);
	exit(1);
	}
else {
	&$second_print($text{'setup_done'});
	}

# Downgrade Debian/Ubuntu repo and the package
if (&has_command("apt-get")) {
	&$first_print($text{'downgrade_gpl_package'});
	&execute_command("apt-get clean && apt-get update");
	my $out;
	# Capture stdout and stderr together so package manager failures show
	# the real command output instead of only a numeric exit status
	my $rv = &execute_command("apt-get -y install --allow-downgrades ".
				  "--reinstall webmin-virtual-server",
				  undef, \$out, \$out);
	&execute_command("rm -rf $pwd/pro/") if (!$rv && -d "$pwd/pro");
	# Only lock reseller accounts after the main package downgrade succeeds,
	# so failed downgrades do not need to undo reseller state too
	if (!$rv) {
		eval { &lock_all_resellers; };
		}
	&$second_print(!$rv
		? $text{'setup_done'}
		: "$text{'setup_failed'} : ".
		  &execute_command_error($out, $rv));
	$gpl_downgrading_failed_status++ if ($rv);
	&execute_command("apt-get -y purge webmin-virtualmin-support ".
			 "webmin-virtualmin-wp-workbench");
	}

# Downgrade RHEL repo and the package
elsif (&has_command("rpm")) {
	&$first_print($text{'downgrade_gpl_package'});
	&execute_command("yum clean all");
	my $out;
	# Capture stdout and stderr together so package manager failures show
	# the real command output instead of only a numeric exit status
	my $rv = &execute_command("yum -y swap wbm-virtual-server ".
				  "webmin-virtual-server",
				  undef, \$out, \$out);
	if ($rv) {
		$rv = &execute_command("yum -y downgrade webmin-virtual-server",
				       undef, \$out, \$out);
		}
	&execute_command("rm -rf $pwd/pro/") if (!$rv && -d "$pwd/pro");
	# Only lock reseller accounts after the main package downgrade succeeds,
	# so failed downgrades do not need to undo reseller state too
	if (!$rv) {
		eval { &lock_all_resellers; };
		}
	&$second_print(!$rv
		? $text{'setup_done'}
		: "$text{'setup_failed'} : ".
		  &execute_command_error($out, $rv));
	$gpl_downgrading_failed_status++ if ($rv);
	&execute_command("yum -y remove wbm-virtualmin-support ".
			 "wbm-virtualmin-wp-workbench ".
			 "webmin-virtualmin-support ".
			 "webmin-virtualmin-wp-workbench");
	}

# Clear cached license state and run the usual post-actions so Virtualmin
# reflects the new package state before printing the final result
unlink($licence_status);
&clear_links_cache();
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

# Display final message
if ($gpl_downgrading_failed_status) {
	&revert_virtualmin_license_file(\%vserial, $repo_branch);
	&$first_print($text{'downgrade_gpl_some_failed'});
	exit(1);
	}
else {
	&$first_print($text{'downgrade_gpl_all_done'});
	}

# lock_all_resellers()
# Lock all reseller accounts
sub lock_all_resellers
{
my @resels = &list_resellers();
foreach my $resel (@resels) {
	my $oldresel = { %{$resel} };
	$resel->{'pass'} = "!".$resel->{'pass'} if ($resel->{'pass'} !~ /^!/);
	&modify_reseller($resel, $oldresel);
	}
}

# execute_command_error(output, status)
# Convert command output to a readable single-line error
sub execute_command_error
{
my ($out, $status) = @_;
$out ||= "";
$out =~ s/[\r\n]+/ /g;
$out =~ s/\s+/ /g;
$out = &trim($out);
return length($out) ? $out : $status;
}

# revert_virtualmin_license_file(&vserial, repo-branch)
# Restore the previous Pro license and repositories
sub revert_virtualmin_license_file
{
my ($vserial, $repo_branch) = @_;
# Restore the original Pro license file
&$first_print($text{'downgrade_gpl_restore_license'});
&lock_file($virtualmin_license_file);
&write_env_file($virtualmin_license_file, $vserial);
&unlock_file($virtualmin_license_file);
&$second_print($text{'setup_done'});
# Restore the original Pro repositories
&$first_print($text{'downgrade_gpl_restore_repos'});
my ($st, $err, $out) = &setup_virtualmin_repos($repo_branch);
&$second_print(!$st ? $text{'setup_done'}
		    : "$text{'setup_failed'} : ".
		    	&setup_repos_error($err || $out));
}
