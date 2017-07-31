#!/usr/local/bin/perl
# Emulate the flags of clamdscan-stream-client

my $host;
my $port = 3310;
my $file = "-";
while(@ARGV) {
	my $a = shift(@ARGV);
	if ($a eq "-d") {
		$host = shift(@ARGV);
		}
	elsif ($a eq "-p") {
		$port = shift(@ARGV);
		}
	elsif ($a eq "-" || $a !~ /^\-/) {
		# Input file
		$file = $a;
		}
	else {
		die "Unknown flag $a";
		}
	}

# Create a temporary config file
my $cfile = "/tmp/clamdscan-remote-config-$$.conf";
open(CONF, ">", $cfile);
print CONF "TCPSocket $port\n";
print CONF "TCPAddr $host\n";
close(CONF);
my $rv = system("clamdscan -c $cfile --fdpass --stream $file");
unlink($cfile);
exit($rv);

