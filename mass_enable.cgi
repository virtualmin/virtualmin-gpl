#!/usr/local/bin/perl
# Enable a bunch of virtual servers

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'massdomains_enaerr'});

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
	&ui_print_unbuffered_header(undef, $text{'massdomains_etitle'}, "");

	foreach $d (@doms) {
		&$first_print(&text('massdomains_edom', $d->{'dom'}));
		if (!&can_disable_domain($d)) {
			&$second_print($text{'massdomains_ecannotenable'});
			}
		elsif (!$d->{'disabled'}) {
			&$second_print($text{'massdomains_ealready'});
			}
		elsif (!(@enable = &get_enable_features($d))) {
			&$second_print($text{'massdomains_enone'});
			}
		else {
			# Do the enable
			&$indent_print();
			$err = &enable_virtual_server($d);
			&error($err) if ($err);
			&$outdent_print();
			&$second_print($text{'setup_done'});
			}
		}
	&run_post_actions();
	&webmin_log("enable", "domains", scalar(@doms));
	}
else {
	# Ask first
	&ui_print_header(undef, $text{'massdomains_etitle'}, "");

	print &ui_form_start("mass_enable.cgi");
	foreach my $d (@doms) {
		print &ui_hidden("d", $d->{'id'});
		}
	print &text('massdomains_enarusure', scalar(@doms)),"<p>\n";

	@dnames = map { $_->{'dom'} } @doms;
	print &text('massdomains_enadoms', 
		join(" ", map { "<tt>$_</tt>" } @dnames)),"<br>\n";

	print "<center>\n";
	print &ui_form_end([ [ "confirm", $text{'massdomains_enaok'} ] ]);
	print "</center>\n";
	}

&ui_print_footer("", $text{'index_return'});

