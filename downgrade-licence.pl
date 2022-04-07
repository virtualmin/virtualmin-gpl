#!/usr/local/bin/perl

=head1 downgrade-licence.pl

Downgrade system to GPL version

This program downgrades Virtualmin Pro system to GPL by performing various
actions like, swapping Pro package with GPL variant, locking resellers accounts,
automatically switching repositories and reverting the license to GPL.
The only required parameter to perform downgrade is C<--downgrade>.

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
	$< == 0 || die "downgrade-licence.pl must be run as root";
	}
&set_all_text_print();
@OLDARGV = @ARGV;

# Parse args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--downgrade") {
		$downgrade = 1;
		}
	}
$downgrade || &usage();

# Display a warning to GPL user trying to apply a license instead of properly upgrading
# Can be bypassed by using --force-update flag
my $gpl_repos_warning = "GPL version already installed!";
my $gpl_downgrading_repository = "Downgrading Virtualmin repository ..";
my $gpl_downgrading_package = "Downgrading Virtualmin package ..";
my $gpl_downgrading_license = "Downgrading Virtualmin license ..";
my $gpl_downgrading_all_done = "Your system has been successfully downgraded to Virtualmin GPL! Thank you for giving Virtualmin Pro a try.";
my $gpl_downgrading_done = ".. done";
my $gpl_downgrading_failed = ".. failed";

# Downgrade RHEL repo and the package
if (-r $virtualmin_yum_repo) {
	my $found = 0;
	my $lref = &read_file_lines($virtualmin_yum_repo);
	
	my $gpl_warning = ("@{$lref}" =~ /\/gpl\//);
	if ($gpl_warning) {
		print $gpl_repos_warning . "\n";
		exit(1);
		}

	&$first_print($gpl_downgrading_repository);
	&lock_file($virtualmin_yum_repo);
	foreach my $l (@$lref) {
		if ($l =~ /^baseurl=(https?):/) {
				$l =~ s/(:\/\/)[0-9]+:[a-zA-Z-0-9]+\@/$1/;	
				$l =~ s/(\/vm\/[\d]+)/$1\/gpl/;	
				$found++;
			}
		}
	&flush_file_lines($virtualmin_yum_repo);
	&unlock_file($virtualmin_yum_repo);
	&$second_print($found ? $gpl_downgrading_done : $gpl_downgrading_failed);

	# Downgrade package
	if ($found) {
		&lock_all_resellers;
		&$first_print($gpl_downgrading_package);
		&execute_command("yum clean all");
		my $rv = &execute_command("yum -y swap wbm-virtual-server wbm-virtual-server");
		&$second_print(!$rv ? $gpl_downgrading_done : "$gpl_downgrading_failed : $rv");
		&$second_print($gpl_downgrading_done);
		}
	else {
		&$first_print($gpl_downgrading_package);
		&$second_print($gpl_downgrading_failed);
		}
	}

# Downgrade Debian/Ubuntu repo and the package
if (-r $virtualmin_apt_repo) {
	local $found = 0;
	local $lref = &read_file_lines($virtualmin_apt_repo);
	
	my $gpl_warning = ("@{$lref}" =~ /\/gpl\//);
	if ($gpl_warning) {
		print $gpl_repos_warning . "\n";
		exit(1);
		}
	
	&$first_print($gpl_downgrading_repository);
	&lock_file($virtualmin_apt_repo);
	foreach my $l (@$lref) {
        if ($l =~ /^deb\s+(https?):/) {
                $l =~ s/(:\/\/)[0-9]+:[a-zA-Z-0-9]+\@/$1/;  
                $l =~ s/(\/vm\/[\d]+)/$1\/gpl/; 
				$found++;
            }
        }
	&flush_file_lines($virtualmin_apt_repo);
	&unlock_file($virtualmin_apt_repo);
	&$second_print($found ? $gpl_downgrading_done : $gpl_downgrading_failed);
	if (-d $virtualmin_apt_auth_dir) {
		unlink("$virtualmin_apt_auth_dir/virtualmin.conf");
		}

	# Downgrade package
	if ($found) {
		&lock_all_resellers;
		&$first_print($gpl_downgrading_package);
		&execute_command("apt-get clean && apt-get update");
		my $rv = &execute_command("apt-get -y install --allow-downgrades --reinstall webmin-virtual-server=*gpl");
		&$second_print(!$rv ? $gpl_downgrading_done : "$gpl_downgrading_failed : $rv");
		}
	else {
		&$first_print($gpl_downgrading_package);
		&$second_print($gpl_downgrading_failed);
		}
	}

# Downgrade Virtualmin licence file
&$first_print($gpl_downgrading_license);
&lock_file($virtualmin_license_file);
%lfile = ( 'SerialNumber' => "GPL",
           'LicenseKey' => "GPL" );
&write_env_file($virtualmin_license_file, \%lfile);
&unlock_file($virtualmin_license_file);
# Remove license status file too
unlink($licence_status);
&$second_print($gpl_downgrading_done);
&clear_links_cache();
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

# Display final message
&$first_print($gpl_downgrading_all_done);

# Lock reseller accounts first
sub lock_all_resellers
{
my @resels = &list_resellers();
foreach my $resel (@resels) {
    my $oldresel = { %{$resel} };
    $resel->{'pass'} = "!".$resel->{'pass'}
        if ($resel->{'pass'} !~ /^!/);
    &modify_reseller($resel, $oldresel);
}

}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Downgrade Virtualmin Pro system to GPL.\n";
print "\n";
print "virtualmin downgrade-licence --downgrade\n";
exit(1);
}


