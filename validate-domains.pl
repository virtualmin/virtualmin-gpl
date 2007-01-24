#!/usr/local/bin/perl
# Calls the validation function on selected domains and virtual servers

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/validate-domains.pl";
require './virtual-server-lib.pl';
$< == 0 || die "validate-domains.pl must be run as root";

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
		if (&indexof($f, @features) >= 0) {
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
		@feats = @features;
		foreach $f (@feature_plugins) {
			if (&plugin_defined($f, "feature_validate")) {
				push(@feats, $f);
				}
			}
		}
	elsif ($a eq "--problems") {
		# Only report problem domains
		$problems = 1;
		}
	else {
		&usage();
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
		if (&indexof($f, @feature_plugins) < 0) {
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
		push(@errs, "$name : $err") if ($err);
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
print "usage: validate-domains.pl [--domain name]* | [--all-domains]\n";
print "                           [--feature name]* | [--all-features]\n";
print "                           [--problems]\n";
exit(1);
}

