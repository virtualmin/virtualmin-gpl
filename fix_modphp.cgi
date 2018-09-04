#!/usr/local/bin/perl
# Fix mod_php permissions on all domains

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'fixmodphp_ecannot'});
&ReadParse();

if ($in{'ignore'}) {
	# User chose not to fix
	&lock_file($module_config_file);
	$config{'allow_modphp'} = 0;
	&save_module_config();
	&unlock_file($module_config_file);
	&webmin_log("nofixmodphp");
	&redirect("");
	}
else {
	&ui_print_unbuffered_header(undef, $text{'fixmodphp_title'}, "");

	# Fix mod_php access
	&$first_print($text{'fixmodphp_doing'});
	@fixdoms = &fix_mod_php_security(undef, 0);
	&fix_symlink_templates();
	&$second_print(&text('fixmodphp_done', scalar(@fixdoms)));
	&lock_file($module_config_file);
	$config{'allow_modphp'} = 0;
	&save_module_config();
	&unlock_file($module_config_file);

	&run_post_actions();

	&webmin_log("fixmodphp");
	&ui_print_footer("", $text{'index_return'});
	}
