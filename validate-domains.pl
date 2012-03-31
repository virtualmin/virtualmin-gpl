#!/usr/local/bin/perl

=head1 validate-domains.pl

Check the configuration of virtual servers

This program can be used to generate a report on selected features for selected virtual servers, to ensure that they are setup correctly. Validation is useful for detecting things such as manually removed Apache virtual hosts or BIND domains, wrong permissions and missing configuration files.

To specify the servers to check, you can either supply the C<--all-domains>
parameter, or C<--domain> followed by the domain name. Similar, you can select
features to check with the C<--feature> parameter followed by a feature name
(like web or dns), or the C<--all-features> option. Both C<--domain> and
C<--feature> can be given multiple times.

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
	$0 = "$pwd/validate-domains.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "validate-domains.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		# Add a domain to validate
		$dname = shift(@ARGV);
		$d = &get_domain_by("dom", $dname);
		$d || &usage("Virtual server $dname does not exist");
		push(@doms, $d);
		}
	elsif ($a eq "--all-domains") {
		# Validating all domains
		@doms = &list_domains();
		}
	elsif ($a eq "--feature") {
		# Add a feature to validate
		$f = shift(@ARGV);
		if (&indexof($f, @validate_features) >= 0) {
			push(@feats, $f);
			}
		elsif (&plugin_defined($f, "feature_validate")) {
			push(@feats, $f);
			}
		else {
			&usage("$f is not a valid feature or supported plugin");
			}
		}
	elsif ($a eq "--all-features") {
		# Validating all features and capable plugins
		@feats = @validate_features;
		foreach $f (&list_feature_plugins()) {
			if (&plugin_defined($f, "feature_validate")) {
				push(@feats, $f);
				}
			}
		}
	elsif ($a eq "--problems") {
		# Only report problem domains
		$problems = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate args
@doms || &usage("No virtual servers to validate specified");
@feats || &usage("No features to validate specified");

# Do it
foreach $d (@doms) {
	# Call all the feature validators
	@errs = ( );
	$count = 0;
	foreach $f (@feats) {
		next if (!$d->{$f});
		if (&indexof($f, &list_feature_plugins()) < 0) {
			# Core feature
			next if (!$config{$f});
			$vfunc = "validate_$f";
			$err = &$vfunc($d);
			$name = $text{'feature_'.$f};
			}
		else {
			# Plugin feature
			$err = &plugin_call($f, "feature_validate", $d);
			$name = &plugin_call($f, "feature_name");
			}
		push(@errs, "$name : ".
		     &html_tags_to_text(&entities_to_ascii($err))) if ($err);
		$count++;
		}

	# Don't print anything if there were no problems
	next if (!@errs && $problems);

	# Print message, if anything done
	if ($count) {
		print "$d->{'dom'}\n";
		if (@errs) {
			foreach $e (@errs) {
				print "    ",&html_tags_to_text($e),"\n";
				$errcount++;
				}
			}
		else {
			print "    $text{'newvalidate_good'}\n";
			}
		}
	}
exit($errcount);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Validates the configurations of selected virtual servers.\n";
print "\n";
print "virtualmin validate-domains --domain name | --all-domains\n";
print "                           [--feature name]* | [--all-features]\n";
print "                           [--problems]\n";
exit(1);
}

