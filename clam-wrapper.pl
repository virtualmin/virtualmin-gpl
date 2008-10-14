#!/usr/local/bin/perl
# Runs clamdscan, and exits with 1 if the program reports a virus was found
# or 0 if not was found or some error happened

$prog = join(" ", map { quotemeta($_) } @ARGV);
$temp = "/tmp/clamwrapper.$$";
unlink($temp);

# Check if we are using the streaming client, which has slightly different
# semantics
$stream_client = $ARGV[0] =~ /clamd-stream-client/ ? 1 : 0;
$fullprog = $prog;
if (!$stream_client) {
	$fullprog .= " -";
	}

# Feel email to clamscan
$SIG{'PIPE'} = 'ignore';
$clampid = open(INPUT, "|$fullprog >$temp");
while(read(STDIN, $buf, 1024) > 0) {
	print INPUT $buf;
	}

# Wait at most 30 seconds for a response
$timed_out = 0;
$SIG{'ALRM'} = sub { $timed_out++ };
alarm(30);
close(INPUT);
alarm(0);
if ($timed_out) {
	print STDERR "Virus scanner failed to response within 30 seconds\n";
	kill('KILL', $clampid);
	unlink($temp);
	exit(0);
	}

# Read back status from clamscan, and exit non-zero if a virus was found
open(OUTPUT, $temp);
while(<OUTPUT>) {
	$out .= $_;
	}
close(OUTPUT);
unlink($temp);
if ($stream_client && $out =~ /\S/) {
	# Using clamd-stream-client - output contains a virus name if found
	exit(1);
	}
elsif (!$stream_client && $out =~ /FOUND/) {
	# Using clamscan or clamdscan - output contains FOUND if a virus
	# was detected
	exit(1);
	}
else {
	exit(0);
	}

