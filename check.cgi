#!/usr/local/bin/perl
# check.cgi
# Make sure that all enabled features are valid, and check the status of quotas

require './virtual-server-lib.pl';
&can_check_config() || &error($text{'check_ecannot'});

&ui_print_unbuffered_header(undef, $text{'check_title'}, "");

# First show any warnings
print &warning_messages();

&read_file("$module_config_directory/last-config", \%lastconfig);
print "$text{'check_desc'}<br><p></p>\n";

&$indent_print();
$cerr = &check_virtual_server_config(\%lastconfig);
&check_error($cerr) if ($cerr);
&$outdent_print();

print "<p></p>$text{'check_done'}".&vui_brh()."<p></p>\n";

# See if any options effecting Webmin users have changed
if (&need_update_webmin_users_post_config(\%lastconfig)) {
	if ($config{'post_check'}) {
		print "<p></p>";
		# Update all Webmin users
		&modify_all_webmin();
		if ($virtualmin_pro) {
			&modify_all_resellers();
			}
		}
	else {
		# Just offer to update
		my $form = &ui_form_start("all_webmin.cgi");
		$form .= "$text{'check_needupdate'}<p></p>\n";
		$form .= &ui_form_end([ [ "now", $text{'check_updatenow'} ] ]);
		print &ui_alert_box($form, 'warn');
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
	&theme_post_save_domain(undef, 'modify');
	}

&ui_print_footer("", $text{'index_return'});

sub check_error
{
print "</ul><p></p>\n";
print &ui_alert_box($text{'check_failed'} . " : $_[0]", 'warn', undef, undef, ' ');
print "<p></p>\n";
&ui_print_footer("", $text{'index_return'});
exit;
}


