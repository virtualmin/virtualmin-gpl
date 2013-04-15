#!/usr/local/bin/perl
# Enable or disable mail client auto-configuration

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'autoconfig_ecannot'});
&ReadParse();
&error_setup($text{'autoconfig_err'});

@doms = grep { $_->{'mail'} && &domain_has_website($_) && !$_->{'alias'} } &list_domains();
@doms || &error($text{'autoconfig_edoms'});

&ui_print_unbuffered_header(undef, $text{'newautoconfig_title'}, "");

&$first_print(&text($in{'autoconfig'} ? 'autoconfig_enable'
				      : 'autoconfig_disable', scalar(@doms)));
foreach $d (@doms) {
	if ($in{'autoconfig'}) {
		$err = &enable_email_autoconfig($d);
		}
	else {
		$err = &disable_email_autoconfig($d);
		}
	if ($err) {
		&$second_print(&text('autoconfig_failed',
				     &show_domain_name($d), $err));
		}
	}
&$second_print($text{'setup_done'});

# Save global setting
&lock_file($module_config_file);
$config{'mail_autoconfig'} = $in{'autoconfig'};
&save_module_config();
&unlock_file($module_config_file);

&run_post_actions();
&webmin_log("autoconfig", undef, undef, { 'enabled' => $in{'autoconfig'} });

&ui_print_footer("", $text{'index_return'});
