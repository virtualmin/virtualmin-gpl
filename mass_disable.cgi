#!/usr/local/bin/perl
# Disable a bunch of virtual servers

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'massdomains_diserr'});

# Validate inputs and get the domains
@d = split(/\0/, $in{'d'});
@d || &error($text{'massdelete_enone'});
foreach $did (@d) {
	$d = &get_domain($did);
	$d && $d->{'uid'} && ($d->{'gid'} || $d->{'ugid'}) ||
		&error("Domain $did does not exist!");
	&can_config_domain($d) || &error($text{'edit_ecannot'});
	push(@doms, $d);
	}

if ($in{'confirm'}) {
	# Do it
	&ui_print_unbuffered_header(undef, $text{'massdomains_dtitle'}, "");

	foreach $d (@doms) {
		&$first_print(&text('massdomains_ddom', $d->{'dom'}));
		if (!&can_disable_domain($d)) {
			&$second_print($text{'massdomains_ecannotdisable'});
			}
		elsif ($d->{'disabled'}) {
			&$second_print($text{'massdomains_dalready'});
			}
		elsif (!(@disable = &get_disable_features($d))) {
			&$second_print($text{'massdomains_dnone'});
			}
		else {
			# Do the disable
			&$indent_print();
			$err = &disable_virtual_server($d, 'manual',$in{'why'});
			&error($err) if ($err);
			&$outdent_print();
			&$second_print($text{'setup_done'});
			}
		}
	&run_post_actions();
	&webmin_log("disable", "domains", scalar(@doms));
	}
else {
	# Ask first
	&ui_print_header(undef, $text{'massdomains_dtitle'}, "");

	print &ui_form_start("mass_disable.cgi");
	foreach my $d (@doms) {
		print &ui_hidden("d", $d->{'id'});
		}
	print &text('massdomains_disrusure', scalar(@doms)),"<p>\n";
	print "<b>$text{'massdomains_why'}</b>\n";
	print &ui_textbox("why", undef, 60),"<p>\n";

	@dnames = map { $_->{'dom'} } @doms;
	print &text('massdomains_disdoms', 
		join(" ", map { "<tt>$_</tt>" } @dnames)),"<br>\n";

	print "<center>\n";
	print &ui_form_end([ [ "confirm", $text{'massdomains_disok'} ] ]);
	print "</center>\n";

	}

&ui_print_footer("", $text{'index_return'});

