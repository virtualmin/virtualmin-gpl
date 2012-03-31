#!/usr/local/bin/perl

=head1 list-simple-aliases.pl

Lists mail aliases in a simple format for some domain

This program is similar to C<list-aliases>, and takes all the same
command-line parameters. However, it simplifies the display of aliases using
autoreponders to show the reply content, instead of just the path to the
autoreply file.

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
	$0 = "$pwd/list-simple-aliases.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-simple-aliases.pl must be run as root";
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
			$simple = &get_simple_alias($d, $a);
			next if (!$simple);
			print $a->{'from'},"\n";
			print "    Domain: $d->{'dom'}\n";
			print "    Comment: $a->{'cmt'}\n" if ($a->{'cmt'});
			foreach $f (@{$simple->{'forward'}}) {
				print "    Forward: $f\n";
				}
			if ($simple->{'bounce'}) {
				print "    Bounce: Yes\n";
				}
			if ($simple->{'local'}) {
				print "    Local user: $simple->{'local'}\n";
				}
			if ($simple->{'everyone'}) {
				print "    Everyone: Yes\n";
				}
			if ($simple->{'auto'}) {
				$msg = $simple->{'autotext'};
				$msg =~ s/\n/\\n/g;
				print "    Autoreply message: $msg\n";
				}
			if ($simple->{'period'}) {
				print "    Autoreply period: $simple->{'period'}\n";
				}
			if ($simple->{'from'}) {
				print "    Autoreply from: $simple->{'from'}\n";
				}
			}
		}
	else {
		# Show all on one line
		if (@doms > 1) {
			print "Aliases in domain $d->{'dom'} :\n"; 
			}
		$fmt = "%-20.20s %-59.59s\n";
		printf $fmt, "Alias", "Destination";
		printf $fmt, ("-" x 20), ("-" x 59);
		foreach $a (@aliases) {
			$simple = &get_simple_alias($d, $a);
			next if (!$simple);
			@to = @{$simple->{'forward'}};
			push(@to, "Bounce") if ($simple->{'bounce'});
			push(@to, $simple->{'local'}) if ($simple->{'local'});
			push(@to, "Autoreply") if ($simple->{'auto'});
			push(@to, "Everyone") if ($simple->{'everyone'});
			printf $fmt, &nice_from($a->{'from'}),
				     join(", ", @to);
			}
		if (@doms > 1) {
			print "\n";
			}
		}
	}

sub nice_from
{
local $f = $_[0];
$f =~ s/\@$domain$//;
return $f eq "%1" || !$f ? "*" : $f;
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the simple mail aliases in some virtual server.\n";
print "\n";
print "virtualmin list-simple-aliases --all-domains | --domain name | --user username\n";
print "                              [--multiline]\n";
print "                              [--plugins]\n";
exit(1);
}

