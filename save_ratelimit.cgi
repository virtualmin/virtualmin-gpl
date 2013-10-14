#!/usr/bin/perl
# Enable and configure or disable rate limiting

require './virtual-server-lib.pl';
&error_setup($text{'ratelimit_err'});
&can_edit_templates() || &error($text{'ratelimit_ecannot'});
&ReadParse();

# Validate inputs
# XXX

&ui_print_unbuffered_header(undef, $text{'ratelimit_title'}, "");

if ($in{'enable'} && !&is_ratelimit_enabled()) {
	# Need to enable
	&enable_ratelimit();
	}
elsif (!$in{'enable'} && &is_ratelimit_enabled()) {
	# Need to disable
	&disable_ratelimit();
	}

# Update config
# XXX

&ui_print_footer("ratelimit.cgi", $text{'ratelimit_return'});
