#!/usr/local/bin/perl
# disable_domain.cgi
# Temporarily disable a domain, after asking first

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_disable_domain($d) || &error($text{'edit_ecannot'});
$d->{'disabled'} && &error($text{'disable_ealready'});

if ($in{'confirm'}) {
	&ui_print_unbuffered_header(&domain_in($d), $text{'disable_title'}, "");
	}
else {
	&ui_print_header(&domain_in($d), $text{'disable_title'}, "");
	}

# Work out what can be disabled
@disable = &get_disable_features($d);

if (!@disable) {
	# Nothing to do!
	print "<p>$text{'disable_nothing'}<p>\n";
	}
elsif (!$in{'confirm'}) {
	# Ask the user if he is sure
	@distext = map { $text{"disable_f".$_} ||
			 &plugin_call($_, "feature_disname") } @disable;
	if (@distext == 1) {
		$distext = $distext[0];
		}
	elsif (@distext == 2) {
		$distext = &text('disable_and', $distext[0], $distext[1]);
		}
	else {
		$dislast = pop(@distext);
		$distext = &text('disable_and', join(", ", @distext), $dislast);
		}
	print &text('disable_rusure2', "<tt>$d->{'dom'}</tt>",
				       $distext),"<p>\n";
	print $text{'disable_undo'},"<p>\n";

	# Show the OK button
	print "<center>\n";
	print &ui_form_start("disable_domain.cgi");
	@grid = ( "<b>$text{'disable_why'}</b>",
		  &ui_textbox("why", undef, 50) );
	if (!$d->{'parent'}) {
		push(@grid, "<b>$text{'disable_subservers'}</b>",
			    &ui_yesno_radio("subservers", 0));
		}
	print &ui_grid_table(\@grid, 2, 50, [ "nowrap" ]);
	print &ui_hidden("dom", $in{'dom'});
	print &ui_form_end([ [ "confirm", $text{'disable_ok'} ] ]);
	print "</center>\n";
	}
else {
	# Build list of domains
	@doms = ( $d );
	if ($in{'subservers'} && !$d->{'parent'}) {
		foreach my $sd (&get_domain_by("parent", $d->{'id'})) {
			if (!$sd->{'disabled'}) {
				push(@doms, $sd);
				}
			}
		}

	foreach $dd (@doms) {
		if (@doms > 1) {
			&$first_print(&text('disable_doing',
					    &show_domain_name($dd)));
			&$indent_print();
			}

		$err = &disable_virtual_server($dd, 'manual', $in{'why'});
		&error(&text('disable_emaking', "<tt>$err</tt>"))
			if (defined($err));

		if (@doms > 1) {
			&$outdent_print();
			}
		}

	&run_post_actions();
	&webmin_log("disable", "domain", $d->{'dom'}, $d);

	# Call any theme post command
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain($d, 'modify');
		}
	}

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});

