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
	print "<b>$text{'disable_why'}</b>\n",
	      &ui_textbox("why", undef, 50),"<p>\n";
	print &ui_hidden("dom", $in{'dom'});
	print &ui_form_end([ [ "confirm", $text{'disable_ok'} ] ]);
	print "</center>\n";
	}
else {
	# Go ahead and do it ..
	%disable = map { $_, 1 } @disable;
	$d->{'disabled_reason'} = 'manual';
	$d->{'disabled_why'} = $in{'why'};

	# Run the before command
	&set_domain_envs($d, "DISABLE_DOMAIN");
	$merr = &making_changes();
	&reset_domain_envs($d);
	&error(&text('disable_emaking', "<tt>$merr</tt>")) if (defined($merr));

	# Disable all configured features
	my $f;
	foreach $f (@features) {
		if ($d->{$f} && $disable{$f}) {
			local $dfunc = "disable_$f";
			if (&try_function($f, $dfunc, $d)) {
				push(@disabled, $f);
				}
			}
		}
	foreach $f (@feature_plugins) {
		if ($d->{$f} && $disable{$f}) {
			&plugin_call($f, "feature_disable", $d);
			push(@disabled, $f);
			}
		}

	# Save new domain details
	print $text{'save_domain'},"<br>\n";
	$d->{'disabled'} = join(",", @disabled);
	&save_domain($d);
	print $text{'setup_done'},"<p>\n";

	# Run the after command
	&run_post_actions();
	&set_domain_envs($d, "DISABLE_DOMAIN");
	&made_changes();
	&reset_domain_envs($d);
	&webmin_log("disable", "domain", $d->{'dom'}, $d);

	# Call any theme post command
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain($d, 'modify');
		}
	}

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});

