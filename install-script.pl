#!/usr/local/bin/perl
# Installs a new script into a virtual server

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/install-script.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "install-script.pl must be run as root";
	}
@OLDARGV = @ARGV;

&foreign_require("mailboxes", "mailboxes-lib.pl");
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--type") {
		$sname = shift(@ARGV);
		}
	elsif ($a eq "--version") {
		$ver = shift(@ARGV);
		}
	elsif ($a eq "--unsupported") {
		$unsupported = 1;
		}
	elsif ($a eq "--path") {
		$opts->{'path'} = shift(@ARGV);
		$opts->{'path'} =~ /^\/\S*$/ ||&usage("Path must start with /");
		}
	elsif ($a eq "--force-dir") {
		$forcedir = shift(@ARGV);
		$forcedir =~ /^\/\S*$/ ||&usage("Forced directory must start with /");
		}
	elsif ($a eq "--db") {
		$dbtype = shift(@ARGV);
		if ($dbtype =~ /^(\S+)\s+(\S+)$/) {
			$dbtype = $1;
			$dbname = $2;
			}
		else {
			$dbname = shift(@ARGV);
			}
		&indexof($dbtype, @all_database_types) >= 0 ||
			&usage("$dbtype is not a valid database type. Allowed types are : ".join(" ", @all_database_types));
		$dbname =~ /^\S+$/ ||
			&usage("Missing or invalid database name");
		$opts->{'db'} = $dbtype."_".$dbname;
		}
	elsif ($a eq "--newdb") {
		$opts->{'newdb'} = 1;
		}
	elsif ($a eq "--opt") {
		$oname = shift(@ARGV);
		if ($oname =~ /^(\S+)\s+(\S+)$/) {
			$oname = $1;
			$ovalue = $2;
			}
		else {
			$ovalue = shift(@ARGV);
			}
		$opts->{$oname} = $ovalue;
		}
	elsif ($a eq "--upgrade") {
		$id = shift(@ARGV);
		}
	elsif ($a eq "--mongrels") {
		$opts->{'mongrels'} = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$domuser = shift(@ARGV);
		$domuser =~ /^[a-z0-9\.\-\_]+$/ ||
			&usage("Invalid default script username");
		}
	elsif ($a eq "--pass") {
		$dompass = shift(@ARGV);
		}
	else {
		&usage();
		}
	}

# Validate args
$domain && $sname || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$script = &get_script($sname);
$script || &usage("Script type $sname is not known");
$ver || &usage("Missing version number. Available versions are : ".
	       join(" ", @{$script->{'versions'}}));
if ($opts->{'mongrels'} > 1 && &has_proxy_balancer($d) != 2) {
	&error("This virtual server does not support more than one Mongrel");
	}
if ($ver eq "latest") {
	$ver = $script->{'versions'}->[0];
	}
else {
	&indexof($ver, @{$script->{'versions'}}) >= 0 || $unsupported ||
	       &usage("Version $ver is not valid for script. ".
		      "Available versions are : ".
		      join(" ", @{$script->{'versions'}}));
	}
if ($id) {
	# Find script being upgraded
	@scripts = &list_domain_scripts($d);
	($sinfo) = grep { $_->{'id'} eq $id } @scripts;
	$sinfo || &usage("No script install to upgrade with ID $id was found");
	$opts = $sinfo->{'opts'};
	$domuser = $sinfo->{'user'} || $d->{'user'};
	$dompass = $sinfo->{'pass'} || $d->{'pass'};
	}
else {
	$domuser ||= $d->{'user'};
	$dompass ||= $d->{'pass'};
	}

# Check domain features
$d->{'web'} && $d->{'dir'} ||
	&usage("Scripts can only be installed into virtual servers with a ".
	       "website and home directory");

# Validate options
if ($opts->{'path'}) {
	# Convert the path into a directory
	if ($forcedir) {
		# Explicitly set by user
		$opts->{'dir'} = $forcedir;
		}
	else {
		# Work out from path
		$perr = &validate_script_path($opts, $script, $d);
		&usage($perr) if ($perr);
		}
	}
if ($opts->{'db'}) {
	($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
	@dbs = &domain_databases($d);
	($db) = grep { $_->{'type'} eq $dbtype &&
		       $_->{'name'} eq $dbname } @dbs;
	if (!$sinfo) {
		if (!$opts->{'newdb'}) {
			$db ||
			    &usage("$dbtype database $dbname does not exist");
			}
		else {
			$db &&
			    &usage("$dbtype database $dbname already exists");
			}
		}
	}
if (defined(&{$script->{'check_func'}}) && !$sinfo) {
	$oerr = &{$script->{'check_func'}}($d, $ver, $opts, $sinfo);
	if ($oerr) {
		&usage("Options problem detected : $oerr");
		}
	}

# Check for a clash, unless upgrading
if (!$sinfo) {
	($clash) = grep { $_->{'opts'}->{'path'} eq $opts->{'path'} } @got;
	$clash && &usage(&text('scripts_eclash', $opts->{'dir'}));
	}

# Check dependencies
&$first_print("Checking dependencies ..");
$derr = &check_script_depends($script, $d, $ver, $sinfo);
if ($derr) {
	&$second_print(".. failed : $derr");
	exit(1);
	}
else {
	&$second_print(".. done");
	}

# Get locks
&obtain_lock_web($d);
&obtain_lock_cron($d);

# Check PHP version
$phpvfunc = $script->{'php_vers_func'};
if (defined(&$phpvfunc)) {
	&$first_print("Checking PHP version ..");
	@vers = &$phpvfunc($d, $ver);
	$phpver = &setup_php_version($d, \@vers, $opts->{'path'});
	if (!$phpver) {
		&$second_print(".. version ",join(" or ", @vers),
			       " of PHP is required, but not available");
		exit(1);
		}
	else {
		&$second_print(".. done");
		}
	$opts->{'phpver'} = $phpver;
	}

# First fetch needed files
&$first_print("Fetching required files ..");
$ferr = &fetch_script_files($d, $ver, $opts, $sinfo, \%gotfiles, 1);
if ($ferr) {
	&$second_print(".. failed : $ferr");
	exit(1);
	}
else {
	&$second_print(".. done");
	}

# Install needed PHP and Perl modules
&setup_script_requirements($d, $script, $ver, $phpver, $opts) || exit(1);

# Apply Apache config if needed, for new PHP version or modules or settings
&run_post_actions();

# Call the install function
&$first_print(&text('scripts_installing', $script->{'desc'}, $ver));
($ok, $msg, $desc, $url, $suser, $spass) =
	&{$script->{'install_func'}}($d, $ver, $opts, \%gotfiles, $sinfo,
				     $domuser, $dompass);
if ($msg =~ /</) {
	$msg = &mailboxes::html_to_text($msg);
	$msg =~ s/^\s+//;
	$msg =~ s/\s+$//;
	}
print "$msg\n";

if ($ok) {
	&$second_print($ok < 0 ? $text{'scripts_epartial'}
			       : $text{'setup_done'});

	if (!$sinfo && $ok > 0) {
		# Show username and password
		if ($suser && $spass) {
			print &text('scripts_userpass',
				    $suser, $spass),"\n\n";
			}
		elsif ($suser) {
			print &text('scripts_useronly', $suser),"\n\n";
			}
		elsif ($spass) {
			print &text('scripts_passonly', $spass),"\n\n";
			}
		}

	# Record script install in domain
	if ($sinfo) {
		&remove_domain_script($d, $sinfo);
		}
	&add_domain_script($d, $sname, $ver, $opts, $desc, $url,
			   $sinfo ? ( $sinfo->{'user'}, $sinfo->{'pass'} )
				  : ( $suser, $spass ),
			   $ok < 0 ? $msg : undef);
	&run_post_actions();
	&virtualmin_api_log(\@OLDARGV, $d);
	}
else {
	&$second_print($text{'scripts_failed'});
	}

&release_lock_web($d);
&release_lock_cron($d);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Installs a third-party script into some virtual server.\n";
print "\n";
print "usage: install-script.pl --domain domain.name\n";
print "                         --type name\n";
print "                         --version number|\"latest\" [--unsupported]\n";
print "                         [--path url-path]\n";
print "                         [--db type name]\n";
print "                         [--opt name value]\n";
print "                         [--upgrade id]\n";
print "                         [--force-dir directory]\n";
print "                         [--mongrels number]\n";
exit(1);
}

