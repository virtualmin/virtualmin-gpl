#!/usr/local/bin/perl
# This program is designed to be called via HTTP requests from programs, and
# simply passes on parameters to a specified command-line program

package virtual_server;
use POSIX;
use Socket;
$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
&ReadParse();
&can_remote() || &api_error($text{'remote_ecannot'});

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

# Get output format
$format = defined($in{'json'}) ? 'json' :
          defined($in{'xml'}) ? 'xml' :
          defined($in{'perl'}) ? 'perl' :
                undef;

# Build the arg list
$main::virtualmin_remote_api = 1;
$ENV{'VIRTUALMIN_REMOTE_API'} = 1;
$in{'program'} =~ /^[a-z0-9\.\-]+$/i || &api_error($text{'remote_eprogram'});
$cmd = $dir = undef;
foreach $m ($module_name, "$module_name/pro", @plugins) {
	$mdir = &module_root_directory($m);
	$mcmd = "$mdir/$in{'program'}.pl";
	if (-x $mcmd) {
		$cmd = $mcmd;
		$dir = $mdir;
		}
	}
$cmd || &api_error(&text('remote_eprogram2', $in{'program'}));
if ($format && !defined($in{'simple-multiline'})) {
	# Always force multiline format, as JSON output makes no sense
	# without it
	$in{'multiline'} = '';
	}

# Build list of command-line args
@args = ( );
foreach $iv (@in) {
	($i, $v) = split(/=/, $iv, 2);
	$i =~ tr/\+/ /;
	$v =~ tr/\+/ /;
	$i =~ s/%(..)/pack("c",hex($1))/ge;
	$v =~ s/%(..)/pack("c",hex($1))/ge;
	next if ($i eq "program" || $i eq $format);
	if ($v eq "") {
		push(@args, "--$i");
		}
	else {
		push(@args, "--$i", $v);
		}
	}

# Print correct MIME type for output format
if ($format eq "xml") {
	print "Content-type: application/xml\n\n";
	}
elsif ($format eq "json") {
	print "Content-type: application/json\n\n";
	}
else {
	print "Content-type: text/plain\n\n";
	}

# Execute the command within the same perl interpreter
socketpair(SUBr, SUBw, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
$pid = &execute_webmin_script($cmd, $mod, \@args, SUBw);
if ($format) {
	# Capture and convert to selected format
        $err = &check_remote_format($format);
        if ($err) {
                print "Invalid format $format : $err\n";
                exit(0);
                }
	my $out;
	while(<SUBr>) {
		$out .= $_;
		}
	waitpid($pid, 0);
	print &convert_remote_format($out, $?, $in{'program'},
				     \%in, $format);
	}
else {
	# Stream output
	while(<SUBr>) {
		print $_;
		}
	close(SUBr);
	waitpid($pid, 0);
	print "\n";
	print "Exit status: $?\n";
	}

sub api_error
{
print "Content-type: text/plain\n\n";
if ($format) {
	$data = { 'status' => 'error',
		  'error' => join("", @_) };
	$ffunc = "create_".$format."_format";
	print &$ffunc($data);
	}
else {
	print "ERROR: ",@_,"\n";
	}
CORE::exit(0);
}

