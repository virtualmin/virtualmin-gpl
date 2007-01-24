#!/usr/local/bin/perl
# Runs clamd, an exits with 1 if the program reports a virus was found
# or 0 if not was found or some error happened

$prog = join(" ", map { quotemeta($_) } @ARGV);
$temp = "/tmp/clamwrapper.$$";
unlink($temp);
$SIG{'PIPE'} = 'ignore';
open(INPUT, "|$prog - >$temp");
while(read(STDIN, $buf, 1024) > 0) {
	print INPUT $buf;
	}
close(INPUT);
open(OUTPUT, $temp);
while(<OUTPUT>) {
	$out .= $_;
	}
close(OUTPUT);
unlink($temp);
if ($out =~ /FOUND/) {
	exit(1);
	}
else {
	exit(0);
	}

