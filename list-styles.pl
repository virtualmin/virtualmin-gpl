#!/usr/local/bin/perl

=head1 list-styles.pl

Lists all configuration templates

By default, this program outputs a table of content styles available for use
when creating a virtual server or replacing it's web content. To get a list of
just style names, use the C<--name-only> parameter.

=cut

$no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*)\/[^\/]+$/) {
	chdir($pwd = $1);
	}
else {
	chop($pwd = `pwd`);
	}
$0 = "$pwd/list-styles.pl";
require './virtual-server-lib.pl';
$< == 0 || die "list-styles.pl must be run as root";

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}

@styles = &list_content_styles();
$fmt = "%-15.15s %-60.60s\n";
if ($nameonly) {
	# Just show short names
	foreach $s (@styles) {
		print $s->{'name'},"\n";
		}
	}
else {
	# Show table of details
	printf $fmt, "Name", "Description";
	printf $fmt, ("-" x 15), ("-" x 60);
	foreach $s (@styles) {
		printf $fmt, $s->{'name'}, $s->{'desc'};
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the available content styles for new virtual servers.\n";
print "\n";
print "virtualmin list-styles [--name-only]\n";
exit(1);
}


