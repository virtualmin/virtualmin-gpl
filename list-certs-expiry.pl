#!/usr/local/bin/perl

=head1 list-certs-expiry.pl

Output the certificates expiry date for matching or all existing virtual servers.

This program can be used to print SSL expiry dates for all existing domains. The following output controls available :

C<--all-domains> All existing domains

C<--domain> Domain name or a regex to match

C<--sort> Select a column to sort on, either expiry date or domain name

C<--sort-order> Sort order applied to selected column, either ascending or descending

Required Perl dependencies Text::ASCIITable and Time::Piece will be automatically installed if missing

=cut

use POSIX;

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'}    ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/list-certs.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-certs.pl must be run as root";
	}

# Parse command-line args
&parse_common_cli_flags(\@ARGV);
while (@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--sort") {
		$sort = shift(@ARGV);
		}
	elsif ($a eq "--sort-order") {
		$sort_type = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Sanity check
($domain || $all_doms) || &usage("Missing --domain flag");
(!$sort || ($sort && ($sort eq 'name' || $sort eq 'expiry'))) || &usage("Incorrect --sort flag value");
(!$sort_type || ($sort_type && ($sort_type eq 'asc' || $sort_type eq 'desc'))) || &usage("Incorrect --sort-order flag value");

# Check for dependencies
&foreign_require("software");
my $error;
my %poss;
my %mods = ('Text::ASCIITable', ['libtext-asciitable-perl', 'perl-Text-ASCIITable'],
			'Time::Piece',      ['libtime-piece-perl',      'perl-Time-Piece']);
foreach my $mod (keys %mods) {
	eval "use $mod";
	if ($@) {
		$poss{ $mods{$mod}[0] } = $mod if ($software::update_system eq "apt");
		$poss{ $mods{$mod}[1] } = $mod if ($software::update_system eq "yum");
		}
	}

# Try installing missing dependencies
foreach my $pkg (keys %poss) {
	my $pkgname = $poss{$pkg};
	print &text('scripts_softwaremod', $pkg), "\n";
	&capture_function_output(\&software::update_system_install, $pkg);
	eval "use $pkgname";
	if ($@) {
		$error++;
		print ".. error: required Perl module $pkgname cannot be installed\n";
		}
	else {
		print $text{'setup_done'}, "\n";
		}
	}

exit if ($error);

# Get all domains known to Virtualmin
my $out = `virtualmin list-certs --all-domains --cert`;
my (@data) = $out =~ /(.*):\n.*\n.*File:\s+(.*?)\n/g;
my %rows;
if (@data) {
	my $fpm_in  = "%b  %d %H:%M:%S %Y";
	my $fpm_out = "%b %d, %Y";
	my $now     = Time::Piece->new();
	my $i = 1;
	foreach my $d (@data) {
		if ($i % 2 == 1) {
			my $domain          = $d;
			my $cfile           = $data[$i];
			my $expiration_date = `openssl x509 -enddate -noout -in "$cfile"`;
			($expiration_date) = $expiration_date =~ /notAfter=(.*)\sGMT/;
			my $valid_until    = Time::Piece->strptime($expiration_date, $fpm_in);
			my $valid_until_st = $valid_until->strftime("%s");
			my $now_st         = $now->strftime("%s");

			my $status = 'VALID';
			if ($now_st > $valid_until_st) {
				$status = 'EXPIRED';
				}
			my $diff = int(($valid_until_st - $now_st) / (3600 * 24));
			if ($diff < 0) {
				$diff = '';
				} 
			elsif ($diff > 365) {
				$diff = floor($diff / 365);
				if ($diff == 1) {
					$diff .= " year";
					} 
				else {
					$diff .= " years";
					}
				}
			elsif ($diff > 100) {
				$diff = floor($diff / 30);
				$diff .= " months";
				}
			else {
				if ($diff == 1) {
					$diff .= " day";
					}
				else {
					$diff .= " days";
					}
				}
			$rows{($sort eq 'name' ? $domain : $valid_until_st)} = 
				[$domain, $cfile, $valid_until->strftime($fpm_out), $diff, $status];
			}
		$i++;
		}

	# Sort results
	my @rows = $sort_type eq 'desc' ? reverse sort keys %rows : sort keys %rows;
	if ($multiline) {
		foreach my $column (@rows) {
			if ($all_doms || $rows{$column}[0] =~ /$domain/) {
				print "$rows{$column}[0]\n";
				print "  Path to certificate file: $rows{$column}[1]\n";
				print "  Valid until: $rows{$column}[2]\n";
				print "  Expires in: $rows{$column}[3]\n";
				print "  Status: $rows{$column}[4]\n";
				}
			}
		}
	else {
		my $table   = Text::ASCIITable->new({ headingText => 'SSL CERTIFICATES EXPIRATION DATES' });
		$table->setCols('DOMAIN NAME', 'PATH TO CERTIFICATE FILE', 'VALID UNTIL', 'EXPIRES IN', 'STATUS');
		foreach my $column (@rows) {
			if ($all_doms || $rows{$column}[0] =~ /$domain/) {
				$table->addRow($rows{$column}[0],
					       $rows{$column}[1], 
					       $rows{$column}[2],
					       $rows{$column}[3],
					       $rows{$column}[4]);
				}
			}
		if (@{$table->{'tbl_rows'}}) {
			$table->addRowLine();
			print $table;
			}
		else {
			print "No matching domain names found\n";
			}
		}
	} 
else {
print "There are no virtual servers with valid SSL certificates found\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Output the certificates expiry date for matching or all existing virtual servers.\n";
print "\n";
print "virtualmin list-certs-expiry --all-domains | --domain regex\n";
print "                            [--sort [expiry|name]\n";
print "                            [--sort-order [asc|desc]\n";
print "                            [--multiline | --json | --xml]\n";
exit(1);
}
