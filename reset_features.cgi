#!/usr/local/bin/perl
# Reset some features on a selected domain

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'reset_err'});
&can_edit_templates() || &error($text{'reset_ecannot'});

# Check and parse inputs
my $d = &get_domain($in{'server'});
$d && &can_edit_domain($d) || &error($text{'reset_edom'});
my %sel = map { $_, 1 } split(/\0/, $in{'features'});
%sel || &error($text{'reset_efeatures'});
my @dom_features = grep { $d->{$_} && $sel{$_} }
		 &list_ordered_features($d);
@dom_features || &error($text{'reset_efeatures2'});
my %feature = map { $_, 1 } grep { $sel{$_} } @features;
my %plugin = map { $_, 1 } grep { $sel{$_} } &list_feature_plugins();

# Can each be reset?
my %canmap;
foreach $f (@dom_features) {
	my $can = 1;
	my $fn = &feature_name($f, $d);
	if ($feature{$f}) {
		my $crfunc = "can_reset_".$f;
		$can = defined(&$crfunc) ? &$crfunc($d) : 1;
		}
	elsif ($plugin{$f}) {
		$can = &plugin_defined($f, "feature_can_reset") ?
			&plugin_call($f, "feature_can_reset", $d) : 1;
		}
	$can || &error(&text('reset_enoreset', $fn));
	$canmap{$f} = $can;
	}

# Run the before command
&set_domain_envs($d, "MODIFY_DOMAIN");
$merr = &making_changes();
&reset_domain_envs($d);
if (defined($merr)) {
	&error(&text('save_emaking', "<tt>$merr</tt>"));
	}

&ui_print_header(&domain_in($d), $text{'reset_title'}, "");

# Reset each feature or plugin that was selected
my $oldd = { %$d };
my $dataloss;
foreach $f (@dom_features) {
	my $err;
	my $fn = &feature_name($f, $d);
	&$first_print(&text('reset_doing', $fn));

	# Check if resetting is a good idea
	if ($feature{$f}) {
		my $prfunc = "check_reset_".$f;
		$err = defined(&$prfunc) ? &$prfunc($d) : undef;
		}
	elsif ($plugin{$f}) {
		$err = &plugin_call($f, "feature_check_reset", $d);
		}
	if ($err) {
		if ($in{'fullreset'}) {
			&$second_print(&text('reset_iwarning', $err));
			}
		elsif ($in{'skipwarnings'}) {
			&$second_print(&text('reset_swarning', $err));
			}
		else {
			&$second_print(&text('reset_dataloss', $err));
			$dataloss = 1;
			next;
			}
		}

	# Do the reset
	&$indent_print();
	if ($feature{$f}) {
		# Core feature of Virtualmin
		my $rfunc = "reset_".$f;
		my $afunc = "reset_also_".$f;
		if (defined(&$rfunc) &&
		    (!$in{'fullreset'} || $canmap{$f} == 2)) {
			# A reset function exists
			&try_function($f, $rfunc, $d);
			}
		else {
			# Turn on and off via delete and setup calls
			my @allf = ($f);
			push(@allf, &$afunc($d)) if (defined(&$afunc));
			foreach my $ff (reverse(@allf)) {
				$d->{$ff} = 0;
				&call_feature_func($ff, $d, $oldd);
				}
			foreach my $ff (@allf) {
				my $newoldd = { %$d };
				$d->{$ff} = 1;
				&call_feature_func($ff, $d, $newoldd);
				}
			}
		}
	elsif ($plugin{$f}) {
		# Defined by a plugin
		if (&plugin_defined($f, "feature_reset") &&
		    (!$in{'fullreset'} || $canmap{$f} == 2)) {
			# Call the reset function
			&plugin_call($f, "feature_reset", $d);
			}
		else {
			# Turn off and on again
			my @allf = ($f);
			if (&plugin_defined($f, "feature_reset_also")) {
				push(@allf, &plugin_call($f, "feature_reset_also", $d));
				}
			foreach my $ff (reverse(@allf)) {
				$d->{$ff} = 0;
				&plugin_call($ff, "feature_delete", $d);
				}
			foreach my $ff (@allf) {
				$d->{$ff} = 1;
				&plugin_call($ff, "feature_setup", $d);
				}
			}
		}
	&$outdent_print();

	&$second_print($text{'setup_done'});
	}

&run_post_actions();

# Offer to reset anyway
if ($dataloss) {
	print &ui_form_start("reset_features.cgi", "post");
	print &ui_hidden("server", $in{'server'});
	foreach my $f (keys %sel) {
		print &ui_hidden("features", $f);
		}
	print &ui_form_end( [ [ 'skipwarnings', $text{'reset_override'} ] ]);
	}

&ui_print_footer("", $text{'index_return'},
	 "edit_newvalidate.cgi?mode=reset", $text{'newvalidate_return'});
