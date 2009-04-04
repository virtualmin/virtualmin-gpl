#!/usr/local/bin/perl
# Show greylisting enable / disable flag and whitelists

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'postgrey_ecannot'});
&ui_print_header(undef, $text{'postgrey_title'}, "", "postgrey");

# Check if can use
$err = &check_postgrey();
if ($err) {
	&ui_print_endpage(&text('postgrey_failed', $err));
	}

# Show button to enable / disable
print $text{'postgrey_desc'},"<p>\";
$ok = &is_postgrey_enabled();
print &ui_buttons_start();
if ($ok) {
	print &ui_buttons_row("enable_postgrey.cgi",
			      $text{'postgrey_enable'},
			      $text{'postgrey_enabledesc'});
	}
else {
	print &ui_buttons_row("disable_postgrey.cgi",
			      $text{'postgrey_disable'},
			      $text{'postgrey_disabledesc'});
	}
print &ui_buttons_end();

if ($ok) {
	# Show whitelists of emails and clients
	# XXX
	}

&ui_print_footer("", $text{'index_return'});

