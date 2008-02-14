#!/usr/local/bin/perl
# Makes sure all scripts installers have valid files, and that the
# latest version is available in Virtualmin.

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/check-scripts.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "check-scripts.pl must be run as root";
	}

# Parse command-line args
while(@ARGV) {
	$a = shift(@ARGV);
	if ($a eq "--debug") {
		$debug = 1;
		}
	else {
		push(@scripts, $a);
		}
	}

if (!@scripts) {
	@scripts = &list_available_scripts();
	}

foreach $s (@scripts) {
	$script = &get_script($s);
	next if (!$script->{'enabled'});

	# Make sure all of the versions are available
	foreach $v (@{$script->{'versions'}}) {
		print "Checking $s $v ..\n";
		@files = &{$script->{'files_func'}}(undef, $v, undef, undef);
		foreach $f (@files) {
			# Try a download
			($url, $def) = &convert_osdn_url($f->{'url'});
			if ($def == 1) {
				# Couldn't find OSDN file
				print ".. no such file\n";
				push(@errs, [ $script, $v, $url, "No such file" ]);
				next;
				}

			if ($url =~ /^ftp:\/\/([^\/]+)(\/.*)$/) {
				# Check FTP file
				print "Trying $url ..\n";
				$size = undef;
				for($i=0; $i<10; $i++) {
					$size = &ftp_size($1, $2);
					last if ($size);
					sleep($i*5);
					}
				if (!$size) {
					print ".. FTP file not found\n";
					push(@errs, [ $script, $v, $url, "FTP file not found" ]);
					}
				else {
					print ".. OK\n";
					}
				}
			else {
				# Do HTTP download
				print "Trying $url ..\n";
				($host, $port, $page, $ssl) = &parse_http_url($url);
				$h = &make_http_connection(
					$host, $port, $ssl, "HEAD", $page);
				if (!ref($h)) {
					print ".. failed : $h\n";
					push(@errs, [ $script, $v, $url, $h ]);
					next;
					}
				
				# Make sure the file exists
				&write_http_connection($h, "Host: $host\r\n");
				&write_http_connection($h, "User-agent: Webmin\r\n");
				&write_http_connection($h, "\r\n");
				$line = &read_http_connection($h);
				$line =~ s/\r|\n//g;
				if ($line !~ /^HTTP\/1\..\s+(200|302|301)\s+/) {
					print ".. HTTP error : $line\n";
					push(@errs, [ $script, $v, $url, $line ]);
					}
				else {
					print ".. OK\n";
					}
				&close_http_connection($h);
				}
			}
		}

	# Make sure Virtualmin has the latest version
	$lfunc = $script->{'latest_func'};
	$url = undef;
	if (defined(&$lfunc)) {
		foreach $v (@{$script->{'versions'}}) {
			($url, $re) = &$lfunc($v);
			next if (!$url);
			print "Checking $script->{'name'} website for $v ..\n";
			($host, $port, $page, $ssl) = &parse_http_url($url);
			$data = $err = undef;
			&http_download($host, $port, $page, \$data, \$err,
				       undef, $ssl, undef, undef, undef, 0, 1);
			if ($err || !$data) {
				push(@errs, [ $script, $v, $url,
					"Failed to find latest version" ]);
				print ".. Download failed : $err\n";
				next;
				}

			# Extract all the versions
			local @vers;
			if (ref($re)) {
				# By callback func on data
				@vers = &$re($data, $v);
				}
			else {
				# Using regexp
				while($data =~ /$re(.*)/is) {
					push(@vers, $1);
					$data = $2;
					}
				}

			if (@vers) {
				@vers = sort { &compare_versions($b, $a) }
					     &unique(@vers);
				$lver = $vers[0];
				if (&compare_versions($lver, $v) > 0) {
					push(@errs, [ $script, $v, $url,
						"Version $lver is available" ]);
					print ".. Found newer version $lver\n";
					}
				else {
					print ".. OK\n";
					}
				}
			else {
				push(@errs, [ $script, $v, $url,
					"Failed to find version number" ]);
				print ".. Failed to find version\n";
				}
			}
		}

	# Check for versions by querying osdn
	$clfunc = $script->{'check_latest_func'};
	if (defined(&$clfunc)) {
		foreach $v (@{$script->{'versions'}}) {
			print "Check $script->{'name'} versions for $v ..\n";
			$lver = &$clfunc($v);
			if ($lver) {
				push(@errs, [ $script, $v, $url,
					"Latest version is $lver" ]);
				print ".. Found never version : $lver\n";
				}
			else {
				print ".. OK\n";
				}
			}
		}

	}

# Send off any errors via email
if (@errs) {
	&foreign_require("mailboxes", "mailboxes-lib.pl");
	$body = "The following errors were detected downloading script files:\n";
	foreach $e (@errs) {
		$body .= "\n";
		$body .= "Script:  $e->[0]->{'name'}\n";
		$body .= "Version: $e->[1]\n";
		$body .= "URL:     $e->[2]\n";
		$body .= "Error:   $e->[3]\n";
		}
	if ($debug) {
		print STDERR $body;
		exit(1);
		}
	else {
		$mail = { 'headers' =>
			[ [ 'From', &mailboxes::get_from_address() ],
			  [ 'To', "jcameron\@webmin.com" ],
			  [ 'Subject', "Virtualmin script errors" ] ],
			'attach' =>
			[ { 'headers' => [ [ 'Content-type', 'text/plain' ] ],
			    'data' => $body } ] };
		&mailboxes::send_mail($mail);
		}
	}

sub ftp_size
{
local ($host, $file) = @_;

# connect to host and login
local $error;
&open_socket($host, 21, "SOCK", \$error) || return 0;
alarm(0);
if ($download_timed_out) {
	return 0;
	}
&ftp_command("", 2, \$error) || return 0;

# Login as anonymous
local @urv = &ftp_command("USER anonymous", [ 2, 3 ], \$error);
@urv || return 0;
if (int($urv[1]/100) == 3) {
	&ftp_command("PASS root\@".&get_system_hostname(), 2,
		     \$error) || return 0;
	}

# get the file size and tell the callback
&ftp_command("TYPE I", 2, \$error) || return 0;
local $size = &ftp_command("SIZE $file", 2, \$error);

&ftp_command("QUIT", 2, \$error) || return 0;
return $size;
}

