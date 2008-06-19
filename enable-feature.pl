#!/usr/local/bin/perl

=head2 enable-feature.pl

Turn on some features for a virtual server

To enable features for one or more servers from the command line, use this
program. The features to enable can be specified in the same way as the
create-domain.pl program, such as C<--web>, C<--dns> and C<--virtualmin-svn>. The
servers to effect can either individually specified with the C<--domain> option
(which can occur multiple times), or with C<--all-domains> to update all virtual
server.

When updating multiple servers, this program may take some time to run due to
the amount of work it needs to do. However, the progress of each server and
step will be shown as it runs.

=cut

package virtual_server;
if (!$module_name) {
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
	# Get domains by name and user
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
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
	$derr = &virtual_server_depends(\%newdom, undef, $oldd);
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
	&set_domain_envs($d, "MODIFY_DOMAIN", \%newdom);
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
		if ($plugin{$f} && !$oldd->{$f}) {
			&plugin_call($f, "feature_setup", $d);
			}
		elsif ($oldd->{$f}) {
			&plugin_call($f, "feature_modify", $d, $oldd);
			}
		}
	# Save new domain details
	&save_domain($d);

	# Run the after command
	&set_domain_envs($d, "MODIFY_DOMAIN", undef, $oldd);
	&made_changes();
	&reset_domain_envs($d);

	if ($d->{'parent'}) {
		&refresh_webmin_user($d);
		}

	&$outdent_print();
	&$second_print(".. done");
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Enables features for one or more domains specified on the command line.\n";
print "\n";
print "usage: enable-feature.pl [--domain name] |\n";
print "                         [--user name] |\n";
print "                         [--all-domains]\n";
foreach $f (@features) {
	print "                         [--$f]\n" if ($config{$f});
	}
foreach $f (@feature_plugins) {
	print "                         [--$f]\n";
	}
exit(1);
}

