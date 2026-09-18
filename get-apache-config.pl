#!/usr/local/bin/perl

=head1 get-apache-config.pl

Output Apache virtualhost config for a domain.

Given a domain name with the C<--domain> flag, this command outputs 
the full <VirtualHost> block for the server.

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
	$0 = "$pwd/get-apache-config.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "get-apache-config.pl must be run as root";
	}

# Parse command line
my $ssl = 0;
while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--ssl") {
		$ssl = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate inputs and get the domain
$dname || &usage("Missing --domain parameter");
$d = &get_remote_api_domain("dom", $dname);
$d || &usage("Virtual server $dname does not exist");
if ($ssl) {
	&domain_has_ssl($d) eq 'ssl' ||
	    &usage("Virtual server $dname does not have Apache SSL enabled");
	}
else {
	&domain_has_website($d) eq 'web' ||
	    &usage("Virtual server $dname does not have Apache enabled");
	}

# Get and dump the Apache config block
($virt, $vconf) = &get_apache_virtual($d->{'dom'},
			$ssl ? $d->{'web_sslport'} : $d->{'web_port'});
$virt || &usage("Apache config for $dname does not exist!");

my $lref = &read_file_lines($virt->{'file'});
for(my $i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
	print $lref->[$i],"\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Output Apache virtualhost config for a domain.\n";
print "\n";
print "virtualmin get-apache-config --domain name\n";
print "                            [--ssl]\n";
exit(1);
}

