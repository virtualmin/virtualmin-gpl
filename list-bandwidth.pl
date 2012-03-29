#!/usr/local/bin/perl

=head1 list-bandwidth.pl

Shows bandwidth usage for some domain over a date range

This command is useful for dumping Virtualmin's bandwidth data (usually used
to draw graphs) in CSV format for importing into other programs. This is
useful for implementing your own billing system, or generating your own graphs.

The domains to dump stats for are selected by either the C<--domain> parameter,
which can occur multiple times and which must be followed by a virtual server
domain name, or C<--all-domains> to show them all. To include usage by
sub-servers of the selected domains, use the C<--include-subservers> flag.

The date range to output stats for are selected with the optional C<--start> and
C<--end> flags, each of which must be followed by a date formatted like
I<2001-09-16>. If omitted, all available bandwidth information for the domains
selected is displayed.

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
	$0 = "$pwd/list-bandwidth.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-bandwidth.pl must be run as root";
	}
use POSIX;

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_domains = 1;
		}
	elsif ($a eq "--start") {
		$start = int(&date_to_time(shift(@ARGV), 1) / (24*60*60));
		}
	elsif ($a eq "--end") {
		$end = int(&date_to_time(shift(@ARGV), 1) / (24*60*60));
		}
	elsif ($a eq "--include-subservers") {
		$subs = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}
@domains || $all_domains || &usage("No domain names specified");

# Get the domains
if (@domains) {
	foreach $dname (@domains) {
		$d = &get_domain_by("dom", $dname);
		$d || &usage("Virtual server $dname does not exist");
		push(@doms, $d);
		}
	}
else {
	@doms = &list_domains();
	}
if ($subs) {
	# We only want parents
	@doms = grep { !$_->{'parent'} } @doms;
	@doms || &usage("None of the selected virtual servers are top-level");
	}

# Show the bandwidth report for each
foreach my $d (@doms) {
	print $d->{'dom'},":\n";

	# Get the relevant domains
	@subdoms = $subs ? ( $d, &get_domain_by("parent", $d->{'id'}) )
			 : ( $d );

	# Build per-day maps
	%daymap = ( );
	%allfeatures = ( );
	$mindt = undef;
	foreach my $sd (@subdoms) {
		$bwinfo = &get_bandwidth($sd);
		foreach my $k (keys %$bwinfo) {
			local ($f, $dt) = split(/_/, $k);
			next if ($dt !~ /^\d+$/);
			$daymap{$dt}->{$f} += $bwinfo->{$k};
			$allfeatures{$f} = 1;
			$mindt = $dt if ($dt < $mindt || !defined($mindt));
			}
		}

	# Get the time ranges
	$dstart = $start || $mindt;
	next if (!defined($dstart));
	$dend = $end || int(time()/(24*60*60));

	# Show usage within range
	for($i=$dstart; $i<=$dend; $i++) {
		print "    ",strftime("%Y-%m-%d:", localtime($i*24*60*60));
		foreach my $f (@bandwidth_features) {
			if ($allfeatures{$f}) {
				print " ",$f,":",int($daymap{$i}->{$f});
				}
			}
		print "\n";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Shows bandwidth usage by domain, date and feature\n";
print "\n";
print "virtualmin list-bandwidth --domain name | --all-domains\n";
print "                         [--start yyyy-mm-dd]\n";
print "                         [--end yyyy-mm-dd]\n";
print "                         [--include-subservers]\n";
exit(1);
}


