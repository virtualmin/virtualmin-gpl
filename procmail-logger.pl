#!/usr/local/bin/perl
# Output email summary for Procmail log

$size = 0;
while(<STDIN>) {
	$size += length($_);
	if (/^From:\s*(.*)/) {
		$from = $1;
		}
	elsif (/^To:\s*(.*)/) {
		$to = $1;
		}
	last if ($from && $to);
	}
while(read(STDIN, $buf, 1024) > 0) {
	# Eat up input
	$size += length($buf);
	}
$from = &address_parts($from);
$to = &address_parts($to);

$now = time();
print "Time:$now From:$from To:$to User:$ENV{'LOGNAME'} Size:$size Dest:$ENV{'LASTFOLDER'}\n";

# address_parts(string)
# Returns the email addresses in a string
sub address_parts
{
local @rv;
local $rest = $_[0];
while($rest =~ /([^<>\s,'"\@]+\@[A-z0-9\-\.\!]+)(.*)/) {
	push(@rv, $1);
	$rest = $2;
	}
return wantarray ? @rv : $rv[0];
}


