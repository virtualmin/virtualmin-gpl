#!/usr/local/bin/perl

=head1 list-custom.pl

List custom fields for virtual servers

When this command is run with no parameters, it will display all custom fields
set for all virtual servers. The C<--domain> parameter can be used to limit the
display to a single named server, while the C<--names> parameter will switch the
display to show field codes rather than their full descriptions.

By default all fields are shown, but you can use the C<--field> flag followed
by a code to show just that field. To further limit the display to just values,
use the C<--value-only> flag.

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
	$0 = "$pwd/list-custom.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-custom.pl must be run as root";
	}

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--names") {
		$names = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--field") {
		$field = shift(@ARGV);
		}
	elsif ($a eq "--value-only") {
		$valueonly = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

if (@domains) {
	# Just showing listed domains
	foreach $domain (@domains) {
		$d = &get_domain_by("dom", $domain);
		$d || &usage("Virtual server $domain does not exist");
		push(@doms, $d);
		}
	}
else {
	# Showing all domains
	@doms = &list_domains();
	}
@doms = sort { $a->{'user'} cmp $b->{'user'} ||
	       $a->{'created'} <=> $b->{'created'} } @doms;

@fields = &list_custom_fields();
if ($field) {
	@fields = grep { $_->{'name'} eq $field } @fields;
	}

if ($valueonly) {
	# Show just values
	foreach $d (@doms) {
		foreach $f (@fields) {
			$v = $d->{'field_'.$f->{'name'}};
			$v =~ s/\n/\\n/g;
			print $v,"\n";
			}
		}
	}
else {
	# Show attributes on multiple lines
	foreach $d (@doms) {
		print "$d->{'dom'}\n";
		foreach $f (@fields) {
			$v = $d->{'field_'.$f->{'name'}};
			$v =~ s/\n/\\n/g;
			if (defined($v)) {
				if ($names) {
					print "    $f->{'name'}: $v\n";
					}
				else {
					($desc) = split(/;/, $f->{'desc'});
					print "    $desc: $v\n";
					}
				}
			}
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the values of custom fields for some or all servers\n";
print "\n";
print "virtualmin list-custom [--domain name]*\n";
print "                       [--names]\n";
print "                       [--field name]\n";
print "                       [--value-only]\n";
exit(1);
}


