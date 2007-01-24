#!/usr/local/bin/perl
# enable_domain.cgi
# Undo the disabling of a domain

require './virtual-server-lib.pl';
&ReadParse();
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

	print &check_clicks_function();
	print "<p>",&text('enable_rusure2', "<tt>$d->{'dom'}</tt>",
			  $distext),"<p>\n";
	print "<center><form action=enable_domain.cgi>\n";
	print "<input type=hidden name=dom value='$in{'dom'}'>\n";
	print "<input type=submit name=confirm ",
	      "value='$text{'enable_ok'}' onClick='check_clicks(form)'>\n";
	print "</form></center>\n";
	}
else {
	# Go ahead and do it
	%enable = map { $_, 1 } @enable;

	# Run the before command
	&set_domain_envs($d, "ENABLE_DOMAIN");
	$merr = &making_changes();
	&reset_domain_envs($d);
	&error(&text('enable_emaking', "<tt>$merr</tt>")) if (defined($merr));

	# Enable all disabled features
	my $f;
	foreach $f (@features) {
		if ($d->{$f} && $enable{$f}) {
			local $efunc = "enable_$f";
			&try_function($f, $efunc, $d);
			}
		}
	foreach $f (@feature_plugins) {
		if ($d->{$f} && $enable{$f}) {
			&plugin_call($f, "feature_enable", $d);
			}
		}

	# Save new domain details
	print $text{'save_domain'},"<br>\n";
	delete($d->{'disabled'});
	delete($d->{'disabled_reason'});
	delete($d->{'disabled_why'});
	&save_domain($d);
	print $text{'setup_done'},"<p>\n";

	# Run the after command
	&run_post_actions();
	&set_domain_envs($d, "ENABLE_DOMAIN");
	&made_changes();
	&reset_domain_envs($d);
	&webmin_log("enable", "domain", $d->{'dom'}, $d);
	}

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});
