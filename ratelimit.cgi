#!/usr/bin/perl
# Show rate limiting enable / disable form

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'ratelimit_ecannot'});
&ui_print_header(undef, $text{'ratelimit_title'}, "", "ratelimit");
&ReadParse();

# Check if can use
$err = &check_ratelimit();
if ($err) {
	print &text('ratelimit_failed', $err),"<p>\n";
	if (&can_install_ratelimit()) {
		print &ui_form_start("install_ratelimit.cgi");
		print &text('ratelimit_installdesc'),"<p>\n";
		print &ui_form_end([ [ undef, $text{'dkim_install'} ] ]);
		}
	&ui_print_footer("", $text{'index_return'});
	return;
	}

# Show form to enable
print &ui_form_start("save_ratelimit.cgi");
print &ui_table_start($text{'ratelimit_header'}, undef, 2);

# Enabled?
print &ui_table_row($text{'ratelimit_enabled'},
	&ui_yesno_radio("enable", &is_ratelimit_enabled()));

# Max messages / hour for all domains
print &ui_table_row($text{'ratelimit_max'},
	&ui_opt_textbox("max", $max, 6, $text{'form_unlimit'},
			$text{'form_atmost'})." ".$text{'ratelimit_hour'});

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
