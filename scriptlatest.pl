#!/usr/local/bin/perl
# Download updates to script installers that we don't have yet

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';

if ($ARGV[0] eq "-debug" || $ARGV[0] eq "--debug") {
	$debug = 1;
	}

# Get Virtualmin serial and key for authentication
&read_env_file($virtualmin_license_file, \%licence);
($user, $pass) = ($licence{'SerialNumber'}, $licence{'LicenseKey'});

# Check if GPG is available
&foreign_require("webmin");
($gpgbad, $err) = &webmin::gnupg_setup();
if (!$gpgbad) {
	# Import key if needed
	@keys = &webmin::list_keys();
	($key) = grep { $_->{'email'}->[0] eq $script_latest_key } @keys;
	if (!$key) {
		&webmin::list_keys();
		$out = &backquote_command("$webmin::gpgpath --import ".
			"$module_root_directory/latest-scripts-key.asc 2>&1");
		if ($?) {
			if ($debug) {
				print STDERR "GPG key import failed : $out\n";
				}
			$gpgbad = 1;
			}
		}
	}
elsif ($debug) {
	print STDERR "GPG verification not available : $err\n";
	}

# Try to fetch the scripts index
&http_download($script_latest_host, $script_latest_port,
	       $script_latest_dir.$script_latest_file,
	       \$lstr, \$err, undef, 0, $user, $pass, 30, 0, 1);
if ($err) {
	if ($debug) {
		print STDERR "Failed to fetch http://$script_latest_host$script_latest_dir$script_latest_file : $err\n";
		}
	exit(0);
	}

if (!$gpgbad) {
	# Fetch the scripts index signature and verify
	$script_latest_sig = $script_latest_file."-sig.asc";
	&http_download($script_latest_host, $script_latest_port,
		       $script_latest_dir.$script_latest_sig,
		       \$lsigstr, \$err, undef, 0, $user, $pass, 30, 0, 1);
	if ($err) {
		if ($debug) {
			print STDERR "Failed to fetch http://$script_latest_host$script_latest_dir$script_latest_sig : $err\n";
			}
		exit(0);
		}
	($ok, $err) = &webmin::verify_data($lstr, $lsigstr);
	if ($ok > 1) {
		if ($debug) {
			print STDERR "GPG verification failed for index file : $err\n";     
			}
		exit(0);
		}
	}

# Parse the scripts index
foreach $l (split(/\r?\n/, $lstr)) {
	($lname, $lvers, $lrelease) = split(/\t/, $l);
	$latest{$lname} = [ split(/\s+/, $lvers) ];
	$release{$lname} = $lrelease;
	}
if ($debug) {
	print STDERR "Found ",scalar(keys %latest)," available scripts\n";
	}

# See which scripts to update
if ($config{'scriptlatest'}) {
	%want = map { $_, 1 } split(/\s+/, $config{'scriptlatest'});
	}
else {
	%want = ( '*' => 1 );
	}

# Compare with versions we have, to find newer ones
foreach $sname (&list_scripts()) {
	next if (!$want{$sname} && !$want{'*'});
	$script = &get_script($sname);
	@lvers = @{$latest{$sname}};
	next if (!@lvers);		# No update
	@lvers = sort { &compare_versions($a, $b, $script) } @lvers;
	@svers = sort { &compare_versions($a, $b, $script) }
		      @{$script->{'versions'}};
	$want_download = 0;	# Need to download installer?
	$any_local_newer = 0;	# Are local versions newer?
	if (scalar(@lvers) != scalar(@svers)) {
		# More versions exist, so this update must be better
		if ($debug) {
			print STDERR "$sname has ",scalar(@lvers)," latest versions ",scalar(@svers)," installed versions\n";
			}
		$want_download++;
		}
	else {
		# See if any latest version is better
		for(my $i=0; $i<scalar(@lvers); $i++) {
			$vdiff = &compare_versions($lvers[$i], $svers[$i],
						   $script);
			if ($vdiff > 0) {
				if ($debug) {
					print STDERR "$sname has latest $lvers[$i] installed $svers[$i]\n";
					}
				$want_download++;
				}
			elsif ($vdiff < 0) {
				$any_local_newer++;
				}
			}
		}
	if (!$want_download && $release{$sname} > $script->{'release'} &&
	    !$any_local_newer) {
		# New version of installer itself
		if ($debug) {
			print STDERR "$sname has new release $release{$sname} ",
				     "compared to $script->{'release'}\n";
			}
		$want_download++;
		}
	if ($want_download) {
		push(@download, $sname);
		}
	}

if (!@download) {
	if ($debug) {
		print STDERR "No needed script installer updates found\n";
		}
	exit(0);
	}

# Download new scripts
foreach $down (@download) {
	if ($debug) {
		print STDERR "Updating $down ..\n";
		}

	# Get the script
	$sdata = $sigdata = undef;
	$err = undef;
	&http_download($script_latest_host, $script_latest_port,
		       $script_latest_dir.$down.".pl", \$sdata, \$err,
		       undef, 0, $user, $pass, 30, 0, 1);
	if ($err) {
		if ($debug) {
			print STDERR "Failed to download $down : $err\n";
			}
		next;
		}

	# If we have GPG, get the signature too
	if (!$gpgbad) {
		$err = undef;
		&http_download($script_latest_host, $script_latest_port,
			       $script_latest_dir.$down.".pl-sig.asc",
			       \$sigdata, \$err,
			       undef, 0, $user, $pass, 30, 0, 1);
		if ($err) {
			if ($debug) {
				print STDERR "Failed to download ${down}-sig.asc  : $err\n";
				}
			next;
			}

		# Validate the file
		($ok, $err) = &webmin::verify_data($sdata, $sigdata);
		if ($ok > 1) {
			if ($debug) {
				print STDERR "GPG verification failed for $down : $err\n";
				}
			next;
			}
		}

	# Run a Perl sanity check
	$temp = &transname($down.".pl");
	&open_tempfile(SCRIPT, ">$temp");
	&print_tempfile(SCRIPT, $sdata);
	&close_tempfile(SCRIPT);
	$perl = &get_perl_path();
	$out = &backquote_command("$perl -c $temp 2>&1");
	if ($?) {
		if ($debug) {
			print STDERR "Perl verification of $down failed : $out\n";
			}
		next;
		}

	# Finally save into the right dir
	$destdir = "$module_config_directory/latest-scripts";
	if (!-d $destdir) {
		&make_dir($destdir, 0755);
		}
	&copy_source_dest($temp, "$destdir/$down.pl");
	if ($debug) {
		print STDERR "Updated $down to latest version\n";
		}
	}

