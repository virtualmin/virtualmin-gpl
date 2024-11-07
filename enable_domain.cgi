#!/usr/local/bin/perl
# enable_domain.cgi
# Undo the disabling of a domain

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
$d = &get_domain($in{'dom'});
&can_disable_domain($d) || &error($text{'edit_ecannot'});
$d->{'disabled'} || &error($text{'enable_ealready'});

if ($in{'confirm'}) {
	&ui_print_unbuffered_header(&domain_in($d), $text{'enable_title'}, "");
	}
else {
	&ui_print_header(&domain_in($d), $text{'enable_title'}, "");
	}

# Work out what can be enabled
@enable = &get_enable_features($d);
@disable_domain_link = ( );
if (!$in{'confirm'}) {
	# Ask the user if he is sure
	@distext = map { $text{"disable_f".$_} ||
			 &plugin_call($_, "feature_disname") } @enable;
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
	print &text('enable_rusure2', "<tt>$d->{'dom'}</tt>", $distext),"<p>\n";

	# Show OK button
	print &ui_form_start("enable_domain.cgi");
	print &ui_table_start(undef, undef, 2);
	if (!$d->{'parent'}) {
		print &ui_table_row($text{'enable_subservers'},
				&ui_yesno_radio("subservers", 0));
		}
	print &ui_table_end();
	print &ui_hidden("dom", $in{'dom'});
	print &ui_form_end([ [ "confirm", $text{'enable_ok'} ] ]);
	}
else {
	# Build list of domains
	@doms = ( $d );
	if ($in{'subservers'} && !$d->{'parent'}) {
		foreach my $sd (&get_domain_by("parent", $d->{'id'})) {
			if ($sd->{'disabled'}) {
				push(@doms, $sd);
				}
			}
		}

	foreach $d (@doms) {
		if (@doms > 1) {
			&$first_print(&text('enable_doing',
					    &show_domain_name($d)));
			&$indent_print();
			}
		$err = &enable_virtual_server($d);
		&error($err) if ($err);
		if (@doms > 1) {
			&$outdent_print();
			}
		}
	$d = $doms[0];

	&run_post_actions();
	&webmin_log("enable", "domain", $d->{'dom'}, $d);

	# Call any theme post command
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain($d, 'modify');
		}
	# Add link to the disabled domain
	@disable_domain_link = ( "disable_domain.cgi?dom=$in{'dom'}",
				 $text{'enable_return'} );
	}

&ui_print_footer(@disable_domain_link, &domain_footer_link($d),
	"", $text{'index_return'});
