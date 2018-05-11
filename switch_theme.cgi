#!/usr/local/bin/perl
# Change the theme for the current user to the recommended theme

require './virtual-server-lib.pl';
&ReadParse();

if ($in{'cancel'}) {
	# User is happy with the current theme
	$config{'theme_switch_'.$recommended_theme} = 1;
	&lock_file($module_config_file);
	&save_module_config();
	&unlock_file($module_config_file);
	&redirect("");
	}
else {
	# Make the change
	&foreign_require("acl");
	my @users = &acl::list_users();
	my ($user) = grep { $_->{'name'} eq $base_remote_user } @users;
	$user || &error("User does not exist!");
	if (!$user->{'theme'} && &master_admin()) {
		# Switch all users
		&lock_file("$config_directory/config");
		$gconfig{'theme'} = $recommended_theme;
		&write_file("$config_directory/config", \%gconfig);
		&unlock_file("$config_directory/config");

		my %miniserv;
		&lock_file($ENV{'MINISERV_CONFIG'});
		&get_miniserv_config(\%miniserv);
		$miniserv{'preroot'} = $recommended_theme;
		&put_miniserv_config(\%miniserv);
		&unlock_file($ENV{'MINISERV_CONFIG'});
		}
	else {
		# Just switch this user
		$user->{'theme'} = $recommended_theme;
		&acl::modify_user($user->{'name'}, $user);
		}
	&reload_miniserv();

	# Redirect the whole page
	&ui_print_header(undef, $text{'index_title'}, "");
	print &js_redirect("/", "top");
	&ui_print_footer("/", $text{'index'});
	}
