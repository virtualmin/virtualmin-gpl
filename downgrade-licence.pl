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

my $gpl_repos_warning = "GPL version is already installed!";
my $gpl_downgrading_package = "Downgrading packages ..";
my $gpl_downgrading_all_done = "Your system has been successfully downgraded to Virtualmin GPL!";
my $gpl_downgrading_some_failed = "Downgrading to Virtualmin GPL finished with errors!";
my $gpl_downgrading_done = ".. done";
my $gpl_downgrading_failed = ".. failed";
my $gpl_downgrading_failed_status;

my %vserial;
&read_env_file($virtualmin_license_file, \%vserial);
if ($vserial{'SerialNumber'} eq 'GPL' ||
    $vserial{'LicenseKey'} eq 'GPL') {
	&$first_print($gpl_repos_warning);
	exit;
	}

# Ask for confirmation and explain what's going to happen
my @lines = (
  "This program downgrades a Virtualmin Pro system to GPL. It also removes Pro-only",
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

# Downgrade Virtualmin license file
&lock_file($virtualmin_license_file);
my %lfile = ( 'SerialNumber' => "GPL",
	      'LicenseKey' => "GPL" );
&write_env_file($virtualmin_license_file, \%lfile);
&unlock_file($virtualmin_license_file);

# Set up Virtualmin repositories
my $repo_branch = &detect_virtualmin_repo_branch();
$repo_branch ||= 'stable';
&$first_print($text{"licence_updating_repo_${repo_branch}_gpl"});
my ($st, $err, $out) = &setup_virtualmin_repos($repo_branch);
if ($st) {
	&$second_print(&text('setup_postfailure',
		     &setup_repos_error($err || $out)));
	# Revert license file back to Pro version on failure
	&lock_file($virtualmin_license_file);
	&write_env_file($virtualmin_license_file, \%vserial);
	&unlock_file($virtualmin_license_file);
	exit(1);
	}
else {
	&$second_print($text{'setup_done'});
	}

# Downgrade Debian/Ubuntu repo and the package
if (&has_command("apt-get")) {
	eval { &lock_all_resellers; };
	&$first_print($gpl_downgrading_package);
	&execute_command("apt-get clean && apt-get update");
	my $rv = &execute_command("apt-get -y install --allow-downgrades --reinstall webmin-virtual-server");
	&$second_print(!$rv ? $gpl_downgrading_done : "$gpl_downgrading_failed : $rv");
	$gpl_downgrading_failed_status++ if ($rv);
	&execute_command("apt-get -y purge webmin-virtualmin-support webmin-virtualmin-wp-workbench");
	}

# Downgrade RHEL repo and the package
elsif (&has_command("rpm")) {
	eval { &lock_all_resellers; };
	&$first_print($gpl_downgrading_package);
	&execute_command("yum clean all");
	my $rv = &execute_command("yum -y downgrade webmin-virtual-server wbm-virtual-server");
	&$second_print(!$rv ? $gpl_downgrading_done : "$gpl_downgrading_failed : $rv");
	$gpl_downgrading_failed_status++ if ($rv);
	&execute_command("yum -y remove wbm-virtualmin-support wbm-virtualmin-wp-workbench webmin-virtualmin-support webmin-virtualmin-wp-workbench");
	}

unlink($licence_status);
&clear_links_cache();
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

# Display final message
if ($gpl_downgrading_failed_status) {
	&$first_print($gpl_downgrading_some_failed);
	}
else {
	&$first_print($gpl_downgrading_all_done);
	}

# Lock reseller accounts first
sub lock_all_resellers
{
my @resels = &list_resellers();
foreach my $resel (@resels) {
	my $oldresel = { %{$resel} };
	$resel->{'pass'} = "!".$resel->{'pass'} if ($resel->{'pass'} !~ /^!/);
	&modify_reseller($resel, $oldresel);
	}
}

