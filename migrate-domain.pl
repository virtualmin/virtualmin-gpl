#!/usr/local/bin/perl

=head1 migrate-domain.pl

Imports a virtual server from some other product

Virtualmin has the capability to import servers from other hosting programs,
such as cPanel and Plesk. This program can perform an import from the command line,
which will create a new server in Virtualmin with all the same settings and
content as the original server.

The C<--source> parameter must be followed by the name of the backup or export
file to migrate from. The C<--type> parameter must be followed by the short name of the product that originally created the backup, such as C<cpanel>,
C<ensim>, C<plesk> or C<psa> (for Plesk 7).

By default, Virtualmin will attempt to work out the domain name from the
backup automatically. However, this can be overridden with the C<--domain>
parameter, which must be followed by a domain name. Similarly, the original
username and password will be used unless set with C<--user> and C<--pass>
respectively. Some migration formats do not contain the password, in which
case C<--pass> must be given (and an error will be displayed if it is missing).

To migrate a server under the ownership of an existing Virtualmin user, use
the C<--parent> parameter to specify the name of the parent domain. The optional
C<--webmin> parameter will cause a Webmin login to be created for the migrated
server, which is typically what you want unless using C<--parent>.

If the original server had a private IP address, either the C<--ip> or
C<--allocate-ip> parameter should be used to create an IP for the new virtual
server. Failure to do this may cause the migration attempt to be rejected, or
for features of the migrated server to not work properly (such as its SSL
virtual website). If you want to use a virtual IP that is already active on
the system, you must add the C<--ip-already> command-line option.

When the migrated server was on a shared address, it will by default be
given the system's default shared IP. However, if you have defined additional
shared addresses, a different one can be selected with the C<--shared-ip>
flag followed by an address.

Flags similar to all those above also exist for IPv6, if your system supports
it. The equivalent flags are named C<--ip6>, C<--allocate-ip6>,
C<--original-ip6> and C<--shared-ip6> respectively.

The C<--template> parameter can be used to specify a Virtualmin template by
name to use when creating the migrated virtual server. If not given, the
I<default settings> template will be used.

=cut

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
	$0 = "$pwd/migrate-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "migrate-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;

&require_migration();

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
$template = "";
$ipinfo = { };
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--source") {
		$src = shift(@ARGV);
		}
	elsif ($a eq "--type") {
		$type = shift(@ARGV);
		&indexof($type, @migration_types) >= 0 ||
			&usage("Invalid migration file type $type");
		}
	elsif ($a eq "--domain") {
		$domain = shift(@ARGV);
		$domain = lc(&parse_domain_name($domain));
		$err = &valid_domain_name($domain);
		&usage($err) if ($err);
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		$user =~ /^[a-z0-9\.\-\_]+$/i || &usage("Invalid username $user");
		defined(getpwnam($in{'user'})) && &usage("A user named $user already exists");
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--webmin") {
		$webmin = 1;
		}
	elsif ($a eq "--template") {
		$templatename = shift(@ARGV);
		($tmpl) = grep { $_->{'name'} eq $templatename }
				   &list_templates();
		$tmpl || &usage("Template $templatename does not exist");
		$template = $tmpl->{'id'};
		}
	elsif ($a eq "--parent") {
		$parentname = shift(@ARGV);
		$parent = &get_domain_by("dom", $parentname);
		$parent ||= &get_domain_by("user", $parentname, "parent", "");
		$parent || &usage("No parent server named $parentname found");
		}
	elsif ($a eq "--prefix") {
		$prefix = shift(@ARGV);
		}
	elsif ($a eq "--email") {
		$email = shift(@ARGV);
		}
	elsif ($a eq "--delete-existing") {
		$delete_existing = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--test") {
		$test_only = 1;
		}

	# Alternate IPv4 options
	elsif ($a eq "--shared-ip") {
		$sharedip = shift(@ARGV);
		&indexof($sharedip, &list_shared_ips()) >= 0 ||
		    &usage("$sharedip is not in the shared IP addresses list");
		$ipinfo = { %$ipinfo,
			    'virt' => 0, 'ip' => $sharedip,
			    'virtalready' => 0, 'mode' => 3 };
		}
	elsif ($a eq "--ip") {
		$ip = shift(@ARGV);
		&check_ipaddress($ip) || &usage("Invalid IP address");
		&check_virt_clash($ip) &&
			&usage("IP address is already in use");
		$ipinfo = { %$ipinfo,
			    'virt' => 1, 'ip' => $ip,
			    'virtalready' => 0, 'mode' => 1 };
		}
	elsif ($a eq "--allocate-ip") {
		$tmpl = &get_template(0);
		($ip, $netmask) = &free_ip_address($tmpl);
		$ipinfo = { %$ipinfo,
			    'virt' => 1, 'ip' => $ip,
			    'virtalready' => 0, 'netmask' => $netmask,
			    'mode' => 2 };
		}

	# Alternate IPv6 options
	elsif ($a eq "--default-ip6") {
		$ipinfo = { %$ipinfo,
			    'virt' => 0, 'ip6' => &get_default_ip6(),
			    'virtalready' => 0, 'mode6' => 0 };
		}
	elsif ($a eq "--shared-ip6") {
		$sharedip6 = shift(@ARGV);
		&indexof($sharedip6, &list_shared_ip6s()) >= 0 ||
		  &usage("$sharedip is not in the shared IPv6 addresses list");
		$ipinfo = { %$ipinfo,
			    'virt6' => 0, 'ip6' => $sharedip6,
			    'virt6already' => 0, 'mode6' => 3 };
		}
	elsif ($a eq "--ip6") {
		$ip6 = shift(@ARGV);
		&check_ip6address($ip6) || &usage("Invalid IPv6 address");
		&check_virt6_clash($ip) &&
			&usage("IPv6 address is already in use");
		$ipinfo = { %$ipinfo,
			    'virt6' => 1, 'ip6' => $ip6,
			    'virt6already' => 0, 'mode6' => 1 };
		}
	elsif ($a eq "--allocate-ip6") {
		$tmpl = &get_template(0);
		($ip6, $netmask6) = &free_ip6_address($tmpl);
		$ipinfo = { %$ipinfo,
			    'virt6' => 1, 'ip6' => $ip6,
			    'virt6already' => 0, 'netmask6' => $netmask6,
			    'mode6' => 2 };
		}

	else {
		&usage("Unknown parameter $a");
		}
	}
$src && $type || usage("Missing source or backup type");
if ($template eq "") {
	$template = &get_init_template($parentdomain);
	}
$tmpl = &get_template($template);
if (!$ipinfo->{'ip'}) {
	# Assume default IP
	$ipinfo->{'ip'} = &get_default_ip();
	$ipinfo->{'virt'} = 0;
	}

# Download the file, if needed
($mode) = &parse_backup_url($src);
$mode > 0 || -r $src || &usage("Source file does not exist");
$oldsrc = $src;
$nice = &html_tags_to_text(&nice_backup_url($oldsrc));
if ($mode > 0) {
	&$first_print("Downloading migration file from $nice ..");
	$temp = &transname();
	$err = &download_backup($src, $temp);
	if ($err) {
		&$second_print(".. download failed : $err");
		exit(2);
		}
	$src = $temp;
	@st = stat($src);
	&$second_print(".. downloaded ".&nice_size($st[7]));
	}

# Validate the file
&$first_print("Validating migration file ..");
$vfunc = "migration_${type}_validate";
($err, $domain, $user, $pass) =
	&$vfunc($src, $domain, $user, $parent, $prefix, $pass);
if ($err) {
	&$second_print(".. validation failed : $err");
	exit(3);
	}
if ($test_only) {
	&$second_print(".. found domain $domain user $user password $pass");
	exit(0);
	}
else {
	&$second_print(".. done");
	}

# Delete any existing clashing domain
if ($delete_existing && $domain) {
	$clash = &get_domain_by("dom", $domain);
	if ($clash) {
		&$first_print("Deleting existing virtual server $domain ..");
		&$indent_print();
		$err = &delete_virtual_server($clash);
		&$outdent_print();
		if ($err) {
			&$second_print(".. deletion failed : $err");
			exit(4);
			}
		else {
			&$second_print(".. done");
			}
		}
	}

# Start the migration
print "Starting migration of $domain from $nice ..\n\n";
&lock_domain_name($domain);
$mfunc = "migration_${type}_migrate";
@doms = &$mfunc($src, $domain, $user, $webmin, $template,
		$ipinfo, $pass, $parent, $prefix, $email);
&unlock_domain_name($domain);
&run_post_actions();

# Fix htaccess files
foreach my $d (@doms) {
	&fix_script_htaccess_files($d, &public_html_dir($d));
	}

# Show the result
if (@doms) {
	print "The following servers were successfully migrated : ",join(" ", map { $_->{'dom'} } @doms),"\n";
	&virtualmin_api_log(\@OLDARGV, $doms[0]);
	}
else {
	print "Migration failed! See the error output above.\n";
	exit(1);
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Migrates a Virtualmin server from a backup created by another product\n";
print "like cPanel, Ensim or Plesk.\n";
print "\n";
$types = join("|", @migration_types);
print "virtualmin migrate-domain --source file\n";
print "                          --type $types\n";
print "                          --domain name\n";
print "                         [--user username]\n";
print "                         [--pass \"password\"]\n";
print "                         [--webmin]\n";
print "                         [--template name]\n";
print "                         [--parent domain]\n";
print "                         [--prefix string]\n";
print "                         [--delete-existing]\n";
print "                         [--shared-ip address | --ip address |\n";
print "                          --allocate-ip]\n";
print "                         [--default-ip6 |\n";
print "                          --shared-ip6 address | --ip6 address |\n";
print "                          --allocate-ip6]\n";
print "                         [--test]\n";
print "\n";
print "The source can be one of :\n";
print " - A local file, like /backup/yourdomain.com.tgz\n";
print " - An FTP destination, like ftp://login:pass\@server/backup/yourdomain.com.tgz\n";
print " - An SSH destination, like ssh://login:pass\@server/backup/yourdomain.com.tgz\n";
if ($virtualmin_pro) {
	print " - An S3 bucket, like s3://accesskey:secretkey\@bucket\n";
	}
exit(1);
}

