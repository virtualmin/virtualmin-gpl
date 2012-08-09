#!/usr/local/bin/perl
# check.cgi
# Make sure that all enabled features are valid, and check the status of quotas

require './virtual-server-lib.pl';
&can_check_config() || &error($text{'check_ecannot'});

&ui_print_unbuffered_header(undef, $text{'check_title'}, "");

# First show any warnings
print virtual_server::warning_messages();

&read_file("$module_config_directory/last-config", \%lastconfig);
print "<b>$text{'check_desc'}</b><br>\n";

&$indent_print();
$cerr = &check_virtual_server_config(\%lastconfig);
&check_error($cerr) if ($cerr);
&$outdent_print();

print "<b>$text{'check_done'}</b><p>\n";

# See if any options effecting Webmin users have changed
$webminchanged = 0;
foreach $k (keys %config) {
	if ($k eq 'leave_acl' || $k eq 'webmin_modules' ||
	    &indexof($k, @features) >= 0) {
		$webminchanged++ if ($config{$k} ne $lastconfig{$k});
		}
	}

if ($webminchanged) {
	if ($config{'post_check'}) {
		# Update all Webmin users
		&modify_all_webmin();
		if ($virtualmin_pro) {
			&modify_all_resellers();
			}
		}
	else {
		# Just offer to update
		print &ui_form_start("all_webmin.cgi");
		print "$text{'check_needupdate'}<p>\n";
		print &ui_form_end([ [ "now", $text{'check_updatenow'} ] ]);
		}
	}

# Setup the licence cron job (if needed)
&setup_licence_cron();

# Apply the new config
&run_post_config_actions(\%lastconfig);

# Clear cache of links
&clear_links_cache();

&run_post_actions();

&webmin_log("check");

# Call any theme post command
if (defined(&theme_post_save_domain)) {
	&theme_post_save_domain(\%dom, 'modify');
	}

&ui_print_footer("", $text{'index_return'});

sub check_error
{
print "<p>$_[0]<p>\n";
print "</ul>\n";
print "<b><font color=#ff0000>$text{'check_failed'}</font></b><p>\n";
&ui_print_footer("", $text{'index_return'});
exit;
}


