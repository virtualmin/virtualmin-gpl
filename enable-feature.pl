#!/usr/local/bin/perl
# Enable some features from the command line

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/enable-feature.pl";
require './virtual-server-lib.pl';
$< == 0 || die "enable-feature.pl must be run as root";

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
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
	       &indexof($1, @feature_plugins) >= 0) {
		$plugin{$1}++;
		}
	else {
		&usage();
		}
	}
@dnames || $all_doms || @users || usage();

# Get domains to update
if ($all_doms) {
	@doms = &list_domains();
	}
else {
	# Get domains by name
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		push(@doms, $d);
		}

	# Get domains by user
	foreach $uname (@users) {
		local $dinfo = &get_domain_by("user", $uname, "parent", "");
		if ($dinfo) {
			push(@doms, $dinfo);
			push(@doms, &get_domain_by("user", $uname, "parent",
						   $dinfo->{'id'}));
			}
		else {
			&usage("No top-level domain ownered by $uname exists");
			}
		}
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	@dom_features = $d->{'alias'} ? @alias_features :
			$d->{'parent'} ? ( grep { $_ ne "webmin" } @features ) :
					 @features;

	# Check for various clashes
	%newdom = %$d;
	$oldd = { %$d };
	my $f;
	foreach $f (@dom_features, @feature_plugins) {
		if ($feature{$f} || $plugin{$f}) {
			$newdom{$f} = 1;
			if (!$d->{$f}) {
				$check{$f}++;
				}
			}
		}
	$derr = &virtual_server_depends(\%newdom);
	if ($derr) {
		&$second_print($derr);
		next;
		}
	$cerr = &virtual_server_clashes(\%newdom, \%check);
	if ($cerr) {
		&$second_print($cerr);
		next;
		}

	# Run the before command
	&set_domain_envs($d, "MODIFY_DOMAIN");
	$merr = &making_changes();
	&reset_domain_envs($d);
	if (defined($merr)) {
		&$second_print(&text('save_emaking', "<tt>$merr</tt>"));
		next;
		}

	# Do it!
	&$indent_print();
	foreach $f (@dom_features, @feature_plugins) {
		if ($feature{$f} || $plugin{$f}) {
			$d->{$f} = 1;
			}
		}
	foreach $f (@dom_features) {
		if ($config{$f}) {
			local $sfunc = "setup_$f";
			local $mfunc = "modify_$f";
			if ($feature{$f} && !$oldd->{$f}) {
				&$sfunc($d);
				}
			elsif ($oldd->{$f}) {
				&$mfunc($d, $oldd);
				}
			}
		}
	foreach $f (@feature_plugins) {
		if ($plugin{$f} && !$olddom{$f}) {
			&plugin_call($f, "feature_setup", $d);
			}
		elsif ($oldd->{$f}) {
			&plugin_call($f, "feature_modify", $d, $oldd);
			}
		}
	# Save new domain details
	&save_domain($d);

	# Run the after command
	&set_domain_envs($d, "MODIFY_DOMAIN");
	&made_changes();
	&reset_domain_envs($d);

	&refresh_webmin_user($d);

	&$outdent_print();
	&$second_print(".. done");
	}

&run_post_actions();

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Enables features for one or more domains specified on the command line.\n";
print "\n";
print "usage: enable-feature.pl [--domain name] | [--all-domains]\n";
foreach $f (@features) {
	print "                         [--$f]\n" if ($config{$f});
	}
foreach $f (@feature_plugins) {
	print "                         [--$f]\n";
	}
exit(1);
}

