#!/usr/local/bin/perl
# Convert a sub-domain to a sub-server, after asking for confirmation

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_move_domain($d) || &error($text{'unsub_ecannot'});

if ($in{'confirm'}) {
	# Do it, and show progress
	&ui_print_unbuffered_header(&domain_in($d), $text{'unsub_title'}, "");

	&$first_print(&text('unsub_doing', "<tt>$d->{'dom'}</tt>"));
	$ok = &unsub_virtual_server($d);
	if ($ok) {
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'unsub_failed'});
		}

	&webmin_log("unsub", "domain", $d->{'dom'}, $d);

	# Call any theme post command
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain($d, 'modify');
		}
	}
else {
	# Ask for confirmation first
	&ui_print_header(&domain_in($d), $text{'unsub_title'}, "", "unsub");

	print &ui_confirmation_form(
		"unsub.cgi", $text{'unsub_rusure'},
		[ [ 'dom', $d->{'id'} ] ],
		[ [ 'confirm', $text{'unsub_ok'} ] ],
		);
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

