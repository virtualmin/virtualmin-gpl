#!/usr/local/bin/perl

=head1 downgrade-licence.pl

Downgrade Virtualmin Pro system to GPL version

This program downgrades Virtualmin Pro system to GPL by performing various
actions like, swapping Pro package with GPL variant, locking resellers accounts,
automatically switching repositories and reverting the license to GPL.
The only required parameter to perform downgrade is C<--perform>. Be careful,
this program will not ask for confirmation before performing downgrade.

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
	if ($a eq "--perform") {
		$downgrade = 1;
		}
	}
$downgrade || &usage();

my $gpl_repos_warning = "GPL version is already installed!";
my $gpl_downgrading_repository = "Downgrading Virtualmin repository ..";
my $gpl_downgrading_package = "Downgrading Virtualmin package ..";
my $gpl_downgrading_license = "Downgrading Virtualmin license ..";
my $gpl_downgrading_all_done = "Your system has been successfully downgraded to Virtualmin GPL! Thank you for giving Virtualmin Pro a try.";
my $gpl_downgrading_some_failed = "Downgrading to Virtualmin GPL finished with errors! Thank you for giving Virtualmin Pro a try.";
my $gpl_downgrading_done = ".. done";
my $gpl_downgrading_failed = ".. failed";
my $gpl_downgrading_failed_not_supported = ".. failed : automated downgrading is not yet supported for installations using .wbm.gz files";
my $gpl_downgrading_failed_status;

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
			
			# Virtualmin 7 repo format (/vm/7/pro/rpm/noarch/)
			if ($l =~ /\/(vm\/(?|([7-9])|([0-9]{2,4}))\/(rpm|pro)(\/.*))/) {
				next if ($l !~ /noarch/);
				$l =~ s/(\/pro)/\/gpl/;
				$found++;
				}
			# Virtualmin 6 repo format
			else {
				$l =~ s/(\/vm\/[\d]+)/$1\/gpl/;	
				$found++;
				}
			}
		# New repos have Pro in title too
		if ($l =~ /^name=/ && $l =~ /Virtualmin\s+\d+\s+Professional/) {
			$l =~ s/(Professional)/GPL/;
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
		my $rv = &execute_command("yum -y downgrade wbm-virtual-server");
		&$second_print(!$rv ? $gpl_downgrading_done : "$gpl_downgrading_failed : $rv");
		$gpl_downgrading_failed_status++ if ($rv);
		}
	else {
		&$first_print($gpl_downgrading_package);
		&$second_print($gpl_downgrading_failed);
		$gpl_downgrading_failed_status++;
		}
	}

# Downgrade Debian/Ubuntu repo and the package
elsif (-r $virtualmin_apt_repo) {
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
		# Virtualmin 7 repo format (/vm/7/pro/rpm/noarch/)
		if ($l =~ /^deb(.*?)(http|https):\/\/$upgrade_virtualmin_host\/(vm\/(?|([7-9])|([0-9]{2,4}))\/(pro)(\/.*))/) {
			$l =~ s/(\/pro)/\/gpl/;
		       $found++;
			}
		# Virtualmin 6 repo format (/vm/7/gpl/apt virtualmin main)
		elsif ($l =~ /^deb(.*?)(https?):/) {
		       $l =~ s/(:\/\/)[0-9]+:[a-zA-Z-0-9]+\@/$1/;  
		       $l =~ s/(\/vm\/[\d]+)/$1\/gpl/; 
		       $found++;
			}
		}
	&flush_file_lines($virtualmin_apt_repo);
	&unlock_file($virtualmin_apt_repo);
	&$second_print($found ? $gpl_downgrading_done : $gpl_downgrading_failed);
	$gpl_downgrading_failed_status++ if (!$found);
	if (-d $virtualmin_apt_auth_dir) {
		unlink("$virtualmin_apt_auth_dir/virtualmin.conf");
		}

	# Downgrade package
	if ($found) {
		&lock_all_resellers;
		&$first_print($gpl_downgrading_package);
		&execute_command("apt-get clean && apt-get update");
		my $rv;
		foreach my $n (reverse(1..12)) {
			$rv = &execute_command("apt-get -y install --allow-downgrades --reinstall webmin-virtual-server=*.gpl-$n");
			last if (!$rv);
			}
		&$second_print(!$rv ? $gpl_downgrading_done : "$gpl_downgrading_failed : $rv");
		$gpl_downgrading_failed_status++ if ($rv);
		}
	else {
		&$first_print($gpl_downgrading_package);
		&$second_print($gpl_downgrading_failed);
		$gpl_downgrading_failed_status++;
		}
	}

# Downgrade wbm.gz install.
else {
	# https://software.virtualmin.com/vm/7/gpl/wbm/virtual-server-7.9.0.gpl-1.wbm.gz
	# Downgrade package
	&$first_print($gpl_downgrading_package);
	&$second_print($gpl_downgrading_failed_not_supported);
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
print "virtualmin downgrade-licence --perform\n";
exit(1);
}


