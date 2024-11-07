#!/usr/local/bin/perl
# disable_domain.cgi
# Temporarily disable a domain, after asking first

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();
$d = &get_domain($in{'dom'});
&can_disable_domain($d) || &error($text{'edit_ecannot'});
$d->{'disabled'} && &error($text{'disable_ealready'});

# Work out what can be disabled
@disable = &get_disable_features($d);
@auto_disable_link = ( );
if ($in{'confirm'} || $in{'confirm_auto'}) {
	&ui_print_unbuffered_header(&domain_in($d), $text{'disable_title'}, "");

	# Disable the features
	if ($in{'confirm'}) {
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
		# Add link to re-enable domain
		@auto_disable_link = ( "enable_domain.cgi?dom=$in{'dom'}",
				       $text{'disable_domain_return'} );
		}
	elsif ($in{'confirm_auto'}) {
		# Update auto-disabled flag
		&error_setup($text{'disable_edomain_sched2'});
		my $auto_disable =
			$in{'autodisable_def'} ? undef :
				$in{'autodisable'} =~ /^(\d+)$/ ? $1 : undef;
		if (defined($auto_disable)) {
			my $ts = time();
			$auto_disable = int($auto_disable);
			$auto_disable || &error($text{'disable_save_eautodisable'});
			if ($auto_disable > 365*10 &&
			    $auto_disable < $ts) {
				&error($text{'disable_save_eautodisable2'});
				}
			my $tlabel = !$d->{'disabled_auto'} ? 
				'disable_save_autodisable3' :
				'disable_save_autodisable'; 
			$d->{'disabled_auto'} = 
				$auto_disable >= $ts ? $auto_disable :
				$ts + $auto_disable * 86400;
			if ($auto_disable < $ts) {
				&$first_print($text{$tlabel});
				&$second_print($text{'setup_done'});
				}
			}
		else {
			$in{'autodisable'} && &error($text{'disable_save_eautodisable'});
			if ($d->{'disabled_auto'}) {
				&$first_print($text{'disable_save_autodisable2'});
				delete($d->{'disabled_auto'});
				&$second_print($text{'setup_done'});
				}
			}
		print $text{'save_domain'},"<br>\n";
		&save_domain($d);
		&$second_print($text{'setup_done'});
		# Add link to show domain schedule
		@auto_disable_link =
			( "disable_domain.cgi?dom=$d->{'id'}&mode=schedule",
			  $text{'disable_domain_return2'} );
	}

	# Call any theme post command
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain($d, 'modify');
		}
	}
else {
	&ui_print_header(&domain_in($d), $text{'disable_title'}, "");

	if (!@disable) {
		# Nothing to do!
		print "<p>$text{'disable_nothing'}<p>\n";
		}
	else {
		my $prog = "disable_domain.cgi?dom=$in{'dom'}&mode=";
		my @tabs = ( [ "disable", $text{'disable_domain'},
				$prog."disable" ],
			  [ "schedule", $text{'disable_domain_sched'},
				$prog."schedule" ],
			);
		print &ui_tabs_start(\@tabs, "mode", $in{'mode'} || "disable", 1);
		print &ui_tabs_start_tab("mode", "disable");
		# Ask the user if he is sure
		my @distext = map { $text{"disable_f".$_} ||
				&plugin_call($_, "feature_disname") } @disable;
		if (@distext == 1) {
			$distext = $distext[0];
			}
		elsif (@distext == 2) {
			$distext = &text('disable_and',
				$distext[0], $distext[1]);
			}
		else {
			$dislast = pop(@distext);
			$distext = &text('disable_and',
				join(", ", @distext), $dislast);
			}
		print &text('disable_rusure2', "<tt>$d->{'dom'}</tt>",
				$distext)," $text{'disable_undo'}","<p>\n";

		print &ui_form_start("disable_domain.cgi");
		print &ui_table_start(undef, undef, 2);
		print &ui_table_row($text{'disable_why'},
			&ui_textbox("why", undef, 50));
		if (!$d->{'parent'}) {
			print &ui_table_row($text{'disable_subservers'},
				&ui_yesno_radio("subservers", 0));
			}
		print &ui_table_end();
		print &ui_hidden("dom", $in{'dom'});
		print &ui_form_end([ [ "confirm", $text{'disable_ok'} ] ]);
		print &ui_tabs_end_tab();

		# Schedule domain disable
		print &ui_tabs_start_tab("mode", "schedule");
		print &text('disable_sched_rusure', "<tt>$d->{'dom'}</tt>");
		print &ui_form_start("disable_domain.cgi");
		print &ui_table_start(undef, undef, 2);
		if (!$d->{'disabled'}) {
			my $disauto = $d->{'disabled_auto'};
			my $disautodaysround = 0;
			if ($disauto) {
				$disautodaysround = 
				    sprintf("%.0f", ($disauto-time())/86400);
				$disautodaysround = 1
					if (!$disautodaysround &&
					    $disauto-time() > 0)
				}
			my $disautodays = $disautodaysround > 0 ? 
				$disautodaysround : undef;
			my $autodisable = &ui_opt_textbox("autodisable",
				$disautodays, 4, $text{'no'},
				$text{'disable_autodisable_in'});
			print &ui_table_row($text{'disable_autodisable'},
				$autodisable);
			print &ui_table_row($text{'disable_autodisablealr'},
				$disauto ?
					&text($disauto > time() ? 
					  'disable_autodisable_on' :
						'disable_autodisable_on2',
					&make_date($disauto)) : 
					$text{'no'});
			}

		print &ui_table_end();
		print &ui_hidden("dom", $in{'dom'});
		print &ui_form_end([ [ "confirm_auto",
			$text{'disable_domain_sched2'} ] ]);
		print &ui_tabs_end_tab();
		print &ui_tabs_end(1);
		}
	}

&ui_print_footer(@auto_disable_link, &domain_footer_link($d),
		 "", $text{'index_return'});
