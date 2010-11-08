#!/usr/bin/perl
# Show DKIM enable / disable form, domain and selector inputs

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'dkim_ecannot'});
&ui_print_header(undef, $text{'dkim_title'}, "", "dkim");
&ReadParse();

# Check if can use
$err = &check_dkim();
if ($err) {
	print &text('dkim_failed', $err),"<p>\n";
	if (&can_install_dkim()) {
		print &ui_form_start("install_dkim.cgi");
		print &text('dkim_installdesc'),"<p>\n";
		print &ui_form_end([ [ undef, $text{'dkim_install'} ] ]);
		}
	&ui_print_footer("", $text{'index_return'});
	return;
	}

# Show form to enable
print &ui_form_start("enable_dkim.cgi");
print &ui_table_start($text{'dkim_header'}, undef, 2);

# Enabled?
$dkim = &get_dkim_config();
print &ui_table_row($text{'dkim_enabled'},
	&ui_yesno_radio("enabled", $dkim && $dkim->{'enabled'}));

# Selector for record
@tm = localtime(time());
print &ui_table_row($text{'dkim_selector'},
	&ui_textbox("selector",
		    $dkim && $dkim->{'selector'} || $tm[5]+1900, 20));

# Verify incoming email?
print &ui_table_row($text{'dkim_verify'},
	&ui_yesno_radio("verify", $dkim->{'verify'}));

# Force new private key
if ($dkim && $dkim->{'keyfile'} && -r $dkim->{'keyfile'}) {
	print &ui_table_row($text{'dkim_makenewkey'},
		&ui_yesno_radio("newkey", 0));
	}

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
