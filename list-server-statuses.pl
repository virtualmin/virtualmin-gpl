#!/usr/local/bin/perl

=head1 list-server-statuses.pl

Outputs the status of all servers managed by Virtualmin.

This command checks the status of your system's web server, mail server, DNS
and others, and reports it.

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
	$0 = "$pwd/check-scripts.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-server-statuses.pl must be run as root";
	}
@OLDARGV = @ARGV;

&parse_common_cli_flags(\@ARGV);
while(@ARGV > 0) {
        local $a = shift(@ARGV);
	&usage("Unknown parameter $a");
	}

@ss = &get_startstop_links();
if ($multiline) {
	foreach my $ss (@ss) {
		print $ss->{'feature'},"\n";
		print "    ID: ",$ss->{'id'},"\n" if ($ss->{'id'});
		print "    Status: ",($ss->{'status'} ? "Up" : "Down"),"\n";
		print "    Description: ",$ss->{'name'},"\n";
		}
	}
else {
	$fmt = "%-10.10s %-5.5s %-60.60s\n";
	printf $fmt, "Feature", "Status", "Description";
	printf $fmt, ("-" x 10), ("-" x 5), ("-" x 60);
	foreach my $ss (@ss) {
		printf $fmt, $ss->{'feature'}, ($ss->{'status'} ? "Up" : "Down"), $ss->{'name'};
		}
	}

&virtualmin_api_log(\@OLDARGV, $doms[0]);
exit($cerr ? 1 : 0);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Outputs the status of all servers managed by Virtualmin.\n";
print "\n";
print "virtualmin list-server-statuses\n";
exit(1);
}

