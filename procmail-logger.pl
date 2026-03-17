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
	elsif (/^X-Spam-Status:\s*Yes/) {
		$spam = 1;
		}
	last if ($from && $to);
	}
while(read(STDIN, $buf, 32768) > 0) {
	# Eat up input
	$size += length($buf);
	}
$from = &address_parts($from);
$to = &address_parts($to);

$now = time();
$dest = $ENV{'LASTFOLDER'};
if ($dest =~ /^\S+\/sendmail.*\s(\S+)$/) {
	$dest = $1;
	}
$mode = $ENV{'VIRUSMODE'} ? "Virus" :
	$ENV{'SPAMMODE'} || $spam ? "Spam" : "None";
print "Time:$now From:$from To:$to User:$ENV{'LOGNAME'} Size:$size Dest:$dest Mode:$mode\n";

# address_parts(string)
# Returns the email addresses in a string
sub address_parts
{
my @rv = map { $_->[0] } &split_addresses($_[0]);
return wantarray ? @rv : $rv[0];
}

# split_addresses(string)
# Splits a comma-separated list of addresses into [ email, real-name, original ]
# triplets
sub split_addresses
{
my ($str) = @_;
my @rv;
while(1) {
	$str =~ s/\\"/\0/g;
	if ($str =~ /^[\s,;]*(([^<>\(\)\s"]+)\s+\(([^\(\)]+)\))(.*)$/) {
		# An address like  foo@bar.com (Fooey Bar)
		push(@rv, [ $2, $3, $1 ]);
		$str = $4;
		}
	elsif ($str =~ /^[\s,;]*("([^"]*)"\s*<([^\s<>,]+)>)(.*)$/ ||
	       $str =~ /^[\s,;]*(([^<>\@]+)\s+<([^\s<>,]+)>)(.*)$/ ||
	       $str =~ /^[\s,;]*(([^<>\@]+)<([^\s<>,]+)>)(.*)$/ ||
	       $str =~ /^[\s,;]*(([^<>\[\]]+)\s+\[mailto:([^\s\[\]]+)\])(.*)$/||
	       $str =~ /^[\s,;]*(()<([^<>,]+)>)(.*)/ ||
	       $str =~ /^[\s,;]*(()([^\s<>,;]+))(.*)/) {
		# Addresses like  "Fooey Bar" <foo@bar.com>
		#                 Fooey Bar <foo@bar.com>
		#                 Fooey Bar<foo@bar.com>
		#		  Fooey Bar [mailto:foo@bar.com]
		#		  <foo@bar.com>
		#		  <group name>
		#		  foo@bar.com or foo
		my ($all, $name, $email, $rest) = ($1, $2, $3, $4);
		$all =~ s/\0/\\"/g;
		$name =~ s/\0/"/g;
		push(@rv, [ $email, $name eq "," ? "" : $name, $all ]);
		$str = $rest;
		}
	else {
		last;
		}
	}
return @rv;
}


