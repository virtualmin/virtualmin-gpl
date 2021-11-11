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
my %features = map { $_, 1 } grep { $sel{$_} } @features;
my %plugins = map { $_, 1 } grep { $sel{$_} } &list_feature_plugins();

# Can each be reset?
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
	}

# Run the before command
&set_domain_envs($d, "MODIFY_DOMAIN", \%newdom);
$merr = &making_changes();
&reset_domain_envs($d);
if (defined($merr)) {
	&error(&text('save_emaking', "<tt>$merr</tt>"));
	}

&ui_print_header(&domain_in($d), $text{'reset_title'}, "");

# Reset each feature or plugin that was selected
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
			next;
			}
		}

	# XXX actually do it

	&$second_print($text{'setup_done'});
	}

&ui_print_footer("", $text{'index_return'},
	 "edit_newvalidate.cgi?mode=reset", $text{'newvalidate_return'});
