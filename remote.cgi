#!/usr/local/bin/perl
# Dispatches API requests using the Webmin-authenticated caller's ACL.
# Dedicated API accounts also need a saved grant for the resolved provider.

$main::allow_rpc_only = 1;
# Opt in before module initialization checks the account's endpoint restriction.
$main::allow_api_only = 'virtual-server/remote.cgi';
package virtual_server;
use POSIX;
use Socket;
$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
&ReadParse();
# Choose the response format before authorization so denials use it too.
$format = exists($in{'json'}) ? 'json' :
          exists($in{'xml'}) ? 'xml' :
          exists($in{'perl'}) ? 'perl' : undef;
# A master HTTP login cannot invoke terminal-only account management either.
&is_api_account_command($in{'program'}) &&
	&api_error($text{'remote_eclionly'});
# Only dedicated API accounts need this edition check; other logins keep
# their existing permissions. Report it before the general grant denial.
if (&is_api_access_user()) {
	# Resolve aliases before applying the command's edition restriction.
	my $entry = &get_api_access_command($in{'program'});
	my $err = $entry && &api_account_pro_message($entry->{'name'});
	&api_error($err) if ($err);
	}
# Explain whether the request omitted a command or the caller cannot run it.
&can_remote($in{'program'}) || &api_error($in{'program'} ?
	&text('remote_ecannotprogram', $in{'program'}) :
	$text{'remote_enoprogram'});

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
if ($access{'api_id'}) {
	# Keep values intact and bind authorization to the resolved provider.
	eval {
		@args = &api_access_request_args(\@in, $format);
		if ($format && $in{'program'} =~ /^(list-|get-dns)/ &&
		    !defined($in{'simple-multiline'}) &&
		    !grep { $_ eq '--multiline' } @args) {
			# Listing conversion needs actual multiline command output.
			push(@args, '--multiline');
			}
		# Execute the canonical path tied to the account's saved grant.
		my $entry = &prepare_api_access_command($in{'program'}, \@args);
		$cmd = $entry->{'path'};
		};
	# Return validation and grant errors in the selected format.
	&api_error($@) if ($@);
	}
else {
	# Preserve newline-separated arguments for ordinary Webmin accounts.
	foreach $iv (@in) {
		($i, $v) = split(/=/, $iv, 2);
		$i =~ tr/\+/ /;
		$v =~ tr/\+/ /;
		$i =~ s/%(..)/pack("c",hex($1))/ge;
		$v =~ s/%(..)/pack("c",hex($1))/ge;
		next if ($i eq "program" || $i eq $format);
		if ($v eq "") {
			# Empty values represent flags without an argument.
			push(@args, "--$i");
			}
		else {
			# Legacy clients can send multiple arguments per value.
			push(@args, "--$i", split(/\n/, $v));
			}
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
				     \%in, $format, \%config);
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

# api_error(message, [more-messages...])
# Joins message fragments without a separator, emits the dispatch error in the
# requested format, and terminates the request.
sub api_error
{
print "Content-type: ",($format eq 'json' ? 'application/json' :
	$format eq 'xml' ? 'application/xml' : 'text/plain'),"\n\n";
if ($format) {
	# Return dispatch errors using the requested structured format.
	$data = { 'status' => 'error',
		  'error' => join("", @_) };
	$ffunc = "create_".$format."_format";
	print &$ffunc($data);
	}
else {
	# Text clients retain the legacy ERROR prefix.
	print "ERROR: ",@_,"\n";
	}
CORE::exit(0);
}

