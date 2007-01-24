#!/usr/local/bin/perl
# This program is designed to be called via HTTP requests from programs, and
# simply passes on parameters to a specified command-line program

require './virtual-server-lib.pl';
&ReadParse();
&can_remote() || &error($text{'remote_ecannot'});

if (!$in{'program'}) {
	# Tell the user what needs to be done
	print "Content-type: text/plain\n\n";
	print "This CGI is designed to be invoked by other programs wanting\n";
	print "to perform some Virtualmin action programatically, such as\n";
	print "creating or modifying domains and users.\n\n";

	print "You must supply at least the CGI parameter 'program', which\n";
	print "specifies which of the Virtualmin command-line scripts to\n";
	print "run. You must also supply appropriate parameters to the\n";
	print "program, similar to those that it accepts on the Unix command\n";
	print "line. For example, the change the password for a server, you\n";
	print "would request a URL like :\n\n";

	print "http://yourserver:10000/virtual-server/remote.cgi?program=modify-domain&domain=foo.com&pass=somenewpassword\n\n";
	
	print "All output from the command will be returned to the caller.\n";
	exit;
	}

# Run the program
$in{'program'} =~ /^[a-z0-9\.-]+$/i || &error($text{'remote_eprogram'});
$cmd = "$module_root_directory/$in{'program'}.pl";
-x $cmd || &error(&text('remote_eprogram2', "<tt>$cmd</tt>"));
foreach $i (keys %in) {
	next if ($i eq "program");
	if ($in{$i} eq "") {
		$cmd .= " --".quotemeta($i);
		}
	else {
		foreach $v (split(/\0/, $in{$i})) {
			$cmd .= " --".quotemeta($i)." ".quotemeta($v);
			}
		}
	}
print "Content-type: text/plain\n\n";
&open_execute_command(OUT, "$cmd 2>&1", 1);
while(<OUT>) {
	print $_;
	}
close(OUT);
print "\n";
print "Exit status: $?\n";
