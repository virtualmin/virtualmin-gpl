#!/usr/local/bin/perl

=head1 list-php-ini.pl

Show PHP variables for some or all domains.

This command can be used to list the value of a PHP configuration variable
(set in the php.ini file) for one or many virtual servers at once. The
servers to update can be selected with the C<--domain> or C<--user> flags,
or you can choose to modify them all with the C<--all-domains> option.

If your system supports multiple PHP versions, you can limit the changes
to the config for a specific version with the C<--php-version> flag folowed
by a number, like 4 or 5.

The variables to show are set with the C<--ini-name> flag, which can be
given multiple times to list more than one variable.

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
	$0 = "$pwd/list-php-ini.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-php-ini.pl must be run as root";
	}
&foreign_require("phpini", "phpini-lib.pl");
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--ini-name") {
		push(@ini_names, shift(@ARGV));
		}
	elsif ($a eq "--php-version") {
		$php_ver = shift(@ARGV);
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate parameters
@domains || @users || $all_doms || usage("No domains to modify specified");
@ini_names || &usage("The --ini-name parameter must be given at least once");

# Get the domains
if (@domains || @users) {
	@doms = &get_domains_by_names_users(\@domains, \@users, \&usage);
	}
else {
	@doms = &list_domains();
	}

# Get from domain
foreach my $d (@doms) {
	# Check if this domain even makes sense
	next if (!&domain_has_website($d) || $d->{'alias'});
	$mode = &get_domain_php_mode($d);
	next if ($mode eq "mod_php");

	# Get the ini files
	@inis = sort { $b->[0] <=> $a->[0] } &list_domain_php_inis($d);
	if ($php_ver) {
		($ini) = grep { $_->[0] == $php_ver } @inis;
		}
	else {
		$ini = $inis[0];
		}
	next if (!$ini);

	# Get the values
	$conf = &phpini::get_config($ini->[1]);
	if ($nameonly) {
		foreach $n (@ini_names) {
			$v = &phpini::find_value($n, $conf);
			print $v,"\n";
			}
		}
	else {
		print $d->{'dom'},"\n";
		foreach $n (@ini_names) {
			$v = &phpini::find_value($n, $conf);
			print "    ${n}: $v\n";
			}
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Shows PHP variables for some or all domains.\n";
print "\n";
print "virtualmin list-php-ini --domain name | --user name | --all-domains\n";
print "                       [--php-version number]\n";
print "                       <--ini-name name>+ <--ini-value value>+\n";
print "                       [--name-only]\n";
exit(1);
}
