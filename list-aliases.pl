#!/usr/local/bin/perl

=head1 list-aliases.pl

List aliases for a virtual server

This program displays a list of mail aliases that exist in the virtual server
specified by the C<--domain> command line option. This may be given multiple
times to select more than one domain, or you can have aliases in all virtual
servers output using the C<--all-domains> flag. To output aliases in all
domains owned by some administrator the C<--user> parameter can be given,
followed by a Virtualmin username.

To get more details about each alias, use the C<--multiline> flag, which
switches the output to a format more easily parsed by other programs. To just
list the alias names, use the C<--name-only> parameter. To list full email
addresses, use the C<--email-only> flag.

In the regular table-format output mode, if an alias has an associated description and multiline mode is enabled,
it will be displayed after the alias's from address, separated by a #
character.

Some aliases managed by Virtualmin are not created by users directly,
but are instead created as part of some other process, such as the addition
of a mailing list. Such aliases are not displayed by default, as editing
them can cause problems with the associated mailing list. To include these
aliases in the list produced by C<list-aliases>, use the C<--plugins> command
line flag.

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
	$0 = "$pwd/list-aliases.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-aliases.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all = 1;
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--email-only") {
		$emailonly = 1;
		}
	elsif ($a eq "--plugins") {
		$plugins = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate args and get domains
@dnames || @users || $all || &usage("No domains or users specified");
if ($all) {
	@doms = &list_domains();
	}
else {
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}

foreach $d (@doms) {
	@aliases = &list_domain_aliases($d, !$plugins);
	if ($multi) {
		# Show each destination on a separate line
		foreach $a (@aliases) {
			print $a->{'from'},"\n";
			if ($a->{'cmt'}) {
				print "    Comment: $a->{'cmt'}\n";
				}
			foreach $t (@{$a->{'to'}}) {
				print "    To: $t\n";
				}
			}
		}
	elsif ($nameonly) {
		# Just show names
		foreach $a (@aliases) {
			print &nice_from($a->{'from'}),"\n";
			}
		}
	elsif ($emailonly) {
		# Just show emails
		foreach $a (@aliases) {
			print $a->{'from'},"\n";
			}
		}
	else {
		# Show all on one line
		if (@doms > 1) {
			print "Aliases in domain $d->{'dom'} :\n"; 
			}
		$fmt = "%-20s %-59s\n";
		printf $fmt, "Alias", "Destination";
		printf $fmt, ("-" x 20), ("-" x 59);
		foreach $a (@aliases) {
			printf $fmt, &nice_from($a->{'from'}),
				     join(", ", @{$a->{'to'}});
			}
		if (@doms > 1) {
			print "\n";
			}
		}
	}

sub nice_from
{
local $f = $_[0];
$f =~ s/\@\Q$d->{'dom'}\E$//;
return $f eq "" ? "*" : $f;
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the mail aliases in one or more virtual servers.\n";
print "\n";
print "virtualmin list-aliases --all-domains | --domain name | --user username\n";
print "                       [--multiline | --name-only | --email-only]\n";
print "                       [--plugins]\n";
exit(1);
}

