#!/usr/local/bin/perl
# Convert an alias server to a sub-server, after asking for confirmation

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_config_domain($d) || &error($text{'unalias_ecannot'});
($dleft, $dreason, $dmax) = &count_domains("realdoms");
&error(&text('setup_emax', $dmax)) if ($dleft == 0);

if ($in{'confirm'}) {
	# Do it, and show progress
	&ui_print_unbuffered_header(&domain_in($d), $text{'unalias_title'}, "");

	&$first_print(&text('unalias_doing', "<tt>$d->{'dom'}</tt>"));
	$ok = &unalias_virtual_server($d);
	if ($ok) {
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'unalias_failed'});
		}

	&webmin_log("unalias", "domain", $d->{'dom'}, $d);

	# Call any theme post command
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain($d, 'modify');
		}
	}
else {
	# Ask for confirmation first
	&ui_print_header(&domain_in($d), $text{'unalias_title'}, "", "unalias");

	print &ui_confirmation_form(
		"unalias.cgi", $text{'unalias_rusure'},
		[ [ 'dom', $d->{'id'} ] ],
		[ [ 'confirm', $text{'unalias_ok'} ] ],
		);
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

