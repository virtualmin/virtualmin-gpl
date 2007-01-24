#!/usr/local/bin/perl
# Receives Apache logs as input, and appends them to the server's log file

$no_acl_check++;
@ARGV == 2 || die "usage: writelogs.pl <domain-id> <file>";
($did, $file) = @ARGV;

if ($file !~ /^\//) {
	do './virtual-server-lib.pl';
	$d = &get_domain($did);
	$d || die "Invalid domain ID $did (user $< error $!)";
	$path = "$d->{'home'}/$file";
	}
else {
	$path = $file;
	}

# Intentionally ignore errors, like a missing logs dir
$| = 1;
if (-l $path) {
	print STDERR "Log target $path is a symlink\n";
	}
else {
	open(FILE, ">>$path") || print STDERR "Failed to open $path : $!";
	select(FILE); $| = 1; select(STDOUT);
	while(<STDIN>) {
		print FILE $_;
		}
	close(FILE);
	}

