#!/usr/local/bin/perl

=head1 disable-feature.pl

Turn off some features for a virtual server

This program is very similar to C<enable-feature>, and takes the same command
line parameters, but disables the specified features instead. Be careful when
using it, as it will not prompt for confirmation before disabling features
that may result in the loss of configuration files and other data.

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
	$0 = "$pwd/disable-feature.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "disable-feature.pl must be run as root";
	}
@OLDARGV = @ARGV;

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
	elsif ($a eq "--multiline") {
		$multiline = 1;
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
	# Get domains by name and user
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}

# Do it for all domains, aliases first
$failed = 0;
foreach $d (sort { ($b->{'alias'} ? 2 : $b->{'parent'} ? 1 : 0) <=>
		   ($a->{'alias'} ? 2 : $a->{'parent'} ? 1 : 0) } @doms) {
	&$first_print("Updating server $d->{'dom'} ..");

	# Check for various clashes
	%newdom = %$d;
	$oldd = { %$d };
	my $f;
	foreach $f (reverse(&list_ordered_features(\%newdom))) {
		if ($feature{$f} || $plugin{$f}) {
			$newdom{$f} = 0;
			if (!$d->{$f}) {
				$check{$f}++;
				}
			}
		}
	$derr = &virtual_server_depends(\%newdom, undef, $oldd);
	if ($derr) {
		&$second_print($derr);
		$failed++;
		next;
		}
	$cerr = &virtual_server_clashes(\%newdom, \%check);
	if ($cerr) {
		&$second_print($cerr);
		$failed++;
		next;
		}

	# Make sure no alias domains for this target have the feature
	my @ausers;
	foreach my $ad (&get_domain_by("alias", $d->{'id'})) {
		foreach my $f (reverse(&list_ordered_features($oldd))) {
			if ($ad->{$f} && $feature{$f}) {
				push(@ausers, $ad);
				}
			}
		}
	if (@ausers) {
		&$second_print(".. feature being disabled is in use by ".
		       "alias servers : ".
			join(" ", map { &show_domain_name($_) } @ausers));
		$failed++;
		next;
		}

	# Run the before command
	&set_domain_envs($d, "MODIFY_DOMAIN", \%newdom);
	$merr = &making_changes();
	&reset_domain_envs($d);
	if (defined($merr)) {
		&$second_print(&text('save_emaking', "<tt>$merr</tt>"));
		$failed++;
		next;
		}

	# Do it!
	&$indent_print();
	foreach $f (reverse(&list_ordered_features($oldd))) {
		if ($feature{$f} || $plugin{$f}) {
			$d->{$f} = 0;
			}
		}
	foreach $f (reverse(&list_ordered_features($oldd))) {
		&call_feature_func($f, $d, $oldd);
		}

	# Save new domain details
	&save_domain($d);

	# Run the after command
	&set_domain_envs($d, "MODIFY_DOMAIN");
	local $merr = &made_changes();
	&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
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
print "Enables features for one or more domains specified on the command line.\n";
print "\n";
print "virtualmin disable-feature --domain name | --user name | --all-domains\n";
foreach $f (@features) {
	print "                          [--$f]\n" if ($config{$f});
	}
foreach $f (&list_feature_plugins()) {
	print "                          [--$f]\n";
	}
exit(1);
}

