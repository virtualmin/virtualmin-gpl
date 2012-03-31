#!/usr/local/bin/perl
# Download all files used by scripts to some directory

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/fetch-script-files.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "fetch-script-files.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
while(@ARGV) {
	$a = shift(@ARGV);
	if ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a !~ /^\-/) {
		push(@scripts, $a);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

$dest || die "usage: fetch-script-files.pl --dest dir";
if (!@scripts) {
	@scripts = &list_available_scripts();
	}

@rv = ( );
foreach $s (@scripts) {
	$script = &get_script($s);
	next if (!$script->{'enabled'});

	$d = { 'dom' => 'example.com' };
	foreach $ver (@{$script->{'versions'}}) {
		@files = &{$script->{'files_func'}}($d, $ver, undef, undef);
		foreach $f (grep { $_->{'url'} } @files) {
			next if ($f->{'nofetch'});
			local $url = &convert_osdn_url($f->{'url'}) ||
				     $f->{'url'};
			local $destfile = "$dest/$f->{'file'}";
			next if (-r $destfile);		# Already gotten
			local $temp = &transname($f->{'file'});
			local $error;
			print "script:$script->{'name'} version:$ver url:$url\n";
			if ($url =~ /^http/) {
				# Via HTTP
				my ($host, $port, $page, $ssl) =
					&parse_http_url($f->{'url'});
				&http_download($host, $port, $page, $temp,
					       \$error, undef, $ssl, undef,
					       undef, undef, 1,
					       $f->{'nocache'});
				}
			elsif ($url =~ /^ftp:\/\/([^\/]+)(\/.*)/) {
				# Via FTP
				my ($host, $page) = ($1, $2);
				&ftp_download($host, $page, $temp, \$error);
				}
			if ($error) {
				# HTTP failed
				print "status: FAILED $error\n";
				}
			else {
				# Looks OK .. but was it really a file?
				$fmt = &compression_format($temp);
				$cont = undef;
				if (!$fmt && $temp =~ /\.(pl|php)$/i) {
					$cont = &read_file_contents($temp);
					}
				if (!$fmt &&
				    $cont !~ /^\#\!\s*\S+(perl|php)/i &&
				    $cont !~ /^\s*<\?php/i) {
					print "status: BADFILE\n";
					}
				else {
					@st = stat($temp);
					print "status: OK $st[7]\n";
					&copy_source_dest($temp, $destfile);
					&set_ownership_permissions(undef, undef,
						0755, $destfile);
					}
				}
			unlink($temp);
			}
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Download files for some script.\n";
print "\n";
print "usage: fetch-script-files.pl\n";
exit(1);
}

