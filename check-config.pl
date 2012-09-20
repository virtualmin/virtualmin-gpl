#!/usr/local/bin/perl

=head1 check-config.pl

Run the Virtualmin config check

This program checks your system's Virtualmin configuration, outputting the
progress of the check as it goes. If any serious problems are found it will
halt and display the error found.

Unlike the I<Re-check Config> page in the Virtualmin web UI, it will not
perform any system changes triggered by configuration changes, such as updating
the Webmin modules available to domain owners.

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
	$0 = "$pwd/check-scripts.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "check-scripts.pl must be run as root";
	}
@OLDARGV = @ARGV;

while(@ARGV > 0) {
        local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

&set_all_text_print();
&read_file("$module_config_directory/last-config", \%lastconfig);
$cerr = &html_tags_to_text(&check_virtual_server_config(\%lastconfig));
if ($cerr) {
	print "ERROR: $cerr\n";
	}
else {
	# See if any options effecting Webmin users have changed
	if (&need_update_webmin_users_post_config(\%lastconfig)) {
		&modify_all_webmin();
                if ($virtualmin_pro) {
			&modify_all_resellers();
			}
		}

	# Setup the licence cron job (if needed)
	&setup_licence_cron();

	# Apply the new config
	&run_post_config_actions(\%lastconfig);

	# Clear cache of links
	&clear_links_cache();

	&run_post_actions();

	print "OK\n";
	}

&virtualmin_api_log(\@OLDARGV, $doms[0]);
exit($cerr ? 1 : 0);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Checks the current Virtualmin configuration.\n";
print "\n";
print "virtualmin check-config\n";
exit(1);
}

