#!/usr/local/bin/perl

=head1 disable-limit.pl

Removes access to some feature or edit capability for some virtual servers

This command can be used to deny the owner of some or all virtual servers
access to some functions in the Virtualmin user interface. The domains that
it applies to can be selected with the C<--domain> flag (which can be given
multiple times), or with C<--all-domains>.

To prevent owners of matching domans from enabling or disabling some feature,
use the feature code as a flag, such as C<--ssl> or C<--virtualmin-awstats>.
To take away access to some capability, use flags like C<--cannot-edit-users>
or C<--cannot-edit-dbs>.

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
	$0 = "$pwd/disable-limit.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "disable-limit.pl must be run as root";
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
	elsif ($a eq "--dbname") {
		$nodbname = 1;
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
	elsif ($a =~ /^--cannot-edit-(\S+)$/ &&
	       &indexof($1, @edit_limits) >= 0) {
		$edit{$1}++;
		}
	}
@dnames || $all_doms || usage();

# Get domains to update
if ($all_doms) {
	@doms = &list_domains();
	@doms = grep { $_->{'unix'} && !$_->{'alias'} } @doms;
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		$d->{'unix'} && !$d->{'alias'} || &usage("Domain $n doesn't have limits");
		push(@doms, $d);
		}
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	&$indent_print();
	@dom_features = $d->{'alias'} ? @alias_features :
			$d->{'parent'} ? ( grep { $_ ne "webmin" } @features ) :
					 @features;

	# Disable access to a bunch of features
	foreach $f (@dom_features, &list_feature_plugins()) {
		if ($feature{$f} || $plugin{$f}) {
			$d->{"limit_$f"} = 0;
			}
		}

	# Disallow choice of DB name
	if ($nodbname) {
		$d->{'nodbname'} = 1;
		}

	# Update edits
	foreach $ed (@edit_limits) {
		$d->{'edit_'.$ed} = 0 if ($edit{$ed});
		}

	# Save new domain details
	&save_domain($d);

	&refresh_webmin_user($d);

	&$outdent_print();
	&$second_print(".. done");
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Enables limits for one or more domains specified on the command line.\n";
print "\n";
print "virtualmin disable-limit --domain name | --all-domains\n";
print "                        [--dbname]\n";
foreach $f (@features) {
	print "                        [--$f]\n" if ($config{$f});
	}
foreach $f (&list_feature_plugins()) {
	print "                        [--$f]\n";
	}
foreach $f (@edit_limits) {
	print "                        [--cannot-edit-$f]\n";
	}
exit(1);
}

