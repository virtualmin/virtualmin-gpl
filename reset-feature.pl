#!/usr/local/bin/perl

=head1 reset-feature.pl

Reset some virtual server feature back to it's default.

This command resets the configuration for one or more features for selected
virtual servers back to their default configurations, while preserving any
customization if possible.

The servers to reset are selected with the C<--domain> or C<--user> flags,
and the features with flags like C<--web> or C<--dns>. By default the command
will skip resetting if this would result in the loss of custom settings, but
this can be over-ridden with the C<--skip-warnings> flag.

To force a complete reset back to defaults for selected features, you can
instead use the C<--full-reset> flag.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/reset-feature.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "reset-feature.pl must be run as root";
	}
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a =~ /^--(\S+)$/ &&
	       &indexof($1, @features) >= 0) {
		$config{$1} || &usage("The $a option cannot be used unless the feature is enabled in the module configuration");
		$feature{$1}++;
		}
	elsif ($a =~ /^--(\S+)$/ &&
	       &indexof($1, &list_feature_plugins()) >= 0) {
		$plugin{$1}++;
		}
	elsif ($a eq "--skip-warnings") {
		$skipwarnings = 1;
		}
	elsif ($a eq "--full-reset") {
		$fullreset = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Get domains to update
@dnames || @users || usage("No domains or users specified");
@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);

# Do it for all domains, aliases first
$failed = 0;
DOMAIN:
foreach $d (sort { ($b->{'alias'} ? 2 : $b->{'parent'} ? 1 : 0) <=>
		   ($a->{'alias'} ? 2 : $a->{'parent'} ? 1 : 0) } @doms) {
	&$first_print("Resetting server $d->{'dom'} ..");
	%newdom = %$d;
	$oldd = { %$d };
	my @dom_features = grep { $d->{$_} && ($feature{$_} || $plugin{$_}) }
			    &list_ordered_features($d);
	if (!@dom_features) {
		&$second_print(".. none of the selected features are enabled");
		$failed = 1;
		next DOMAIN;
		}

	# Check if resetting is even possible
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
		if (!$can) {
			&$second_print(".. feature $fn cannot be reset");
			$failed = 1;
			next DOMAIN;
			}
		$canmap{$f} = $can;
		}

	# Check if resetting could cause any data loss
	foreach $f (@dom_features) {
		my $err;
		my $fn = &feature_name($f, $d);
		if ($feature{$f}) {
			my $prfunc = "check_reset_".$f;
			$err = defined(&$prfunc) ? &$prfunc($d) : undef;
			}
		elsif ($plugin{$f}) {
			$err = &plugin_call($f, "feature_check_reset", $d);
			}
		if ($err) {
			if ($fullreset) {
				&$second_print(".. ignoring warning for $fn : $err");
				}
			elsif ($skipwarnings) {
				&$second_print(".. skipping warning for $fn : $err");
				}
			else {
				&$second_print(".. resetting $fn would cause data loss : $err");
				$failed = 1;
				next DOMAIN;
				}
			}
		}

	# Run the before command
	&set_domain_envs($d, "MODIFY_DOMAIN", \%newdom);
	$merr = &making_changes();
	&reset_domain_envs($d);
	if (defined($merr)) {
		&$second_print(&text('save_emaking', "<tt>$merr</tt>"));
		$failed = 1;
		next;
		}

	# Do it!
	&$indent_print();
	foreach $f (@dom_features) {
		if ($feature{$f}) {
			# Core feature of Virtualmin
			my $rfunc = "reset_".$f;
			my $afunc = "reset_also_".$f;
			if (defined(&$rfunc) &&
			    (!$fullreset || $canmap{$f} == 2)) {
				# A reset function exists and should be used
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
			    (!$fullreset || $canmap{$f} == 2)) {
				# Call the reset function
				&plugin_call($f, "feature_reset", $d);
				}
			else {
				# Turn off and on again
				my @allf = ($f);
				if (&plugin_defined($f, "feature_reset_also")) {
					push(@allf, &plugin_call($f,
						"feature_reset_also", $d));
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
		}

	# Save new domain details
	&save_domain($d);

	# Run the after command
	&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
	local $merr = &made_changes();
	&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
		if (defined($merr));
	&reset_domain_envs($d);

	if ($d->{'parent'}) {
		&refresh_webmin_user($d);
		}

	&$outdent_print();
	&$second_print(".. done");
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);
exit($failed);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Reset some virtual server feature back to it's default.\n";
print "\n";
print "virtualmin reset-feature --domain name | --user name\n";
foreach $f (@features) {
	my $crfunc = "can_reset_".$f;
	$can = defined(&$crfunc) ? &$crfunc() : 1;
	print "                         [--$f]\n" if ($config{$f} && $can);
	}
foreach $f (&list_feature_plugins()) {
	$can = &plugin_defined($f, "feature_can_reset") ?
		&plugin_call($f, "feature_can_reset") : 1;
	print "                         [--$f]\n" if ($can);
	}
print "                         [--skip-warnings]\n";
print "                         [--full-reset]\n";
exit(1);
}

