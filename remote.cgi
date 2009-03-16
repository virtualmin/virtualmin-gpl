#!/usr/local/bin/perl
# This program is designed to be called via HTTP requests from programs, and
# simply passes on parameters to a specified command-line program

package virtual_server;
$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
&ReadParse();
&can_remote() || &api_error($text{'remote_ecannot'});
use subs qw(exit);

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

# Build the arg list
$main::virtualmin_remote_api = 1;
$in{'program'} =~ /^[a-z0-9\.\-]+$/i || &api_error($text{'remote_eprogram'});
$cmd = $dir = undef;
foreach $m ($module_name, @plugins) {
	$mdir = &module_root_directory($m);
	$mcmd = "$mdir/$in{'program'}.pl";
	if (-x $mcmd) {
		$cmd = $mcmd;
		$dir = $mdir;
		}
	}
$cmd || &api_error(&text('remote_eprogram2', $in{'program'}));
@args = ( );
foreach $i (keys %in) {
	next if ($i eq "program");
	if ($in{$i} eq "") {
		push(@args, "--".$i);
		}
	else {
		foreach $v (split(/\0/, $in{$i})) {
			push(@args, "--".$i, $v);
			}
		}
	}

# Setup handler if script calls exit. Only needed for this-module calls
sub exit
{
if ($dir eq $module_root_directory) {
	print "\n";
	print "Exit status: $_[0]\n";
	}
CORE::exit(0);
}

# Run the script within this same Perl process
print "Content-type: text/plain\n\n";
if ($dir eq $module_root_directory) {
	# Can just eval in this module
	@ARGV = @args;
	do $cmd;
	print "\n";
	print "Exit status: 0\n";
	}
else {
	# Need to call in other module
	$cmd .= " ".join(" ", map { quotemeta($_) } @args);
	&clean_environment();
	&open_execute_command(CMD, $cmd, 1);
	while(<CMD>) {
		print;
		}
	close(CMD);
	print "\n";
	print "Exit status: $?\n";
	&reset_environment();
	}

sub api_error
{
print "Content-type: text/plain\n\n";
print "ERROR: ",@_,"\n";
CORE::exit(0);
}

