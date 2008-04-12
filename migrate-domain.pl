#!/usr/local/bin/perl
# Migrate a domain from some other server

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/migrate-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "migrate-domain.pl must be run as root";
	}

&require_migration();

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
$template = "";
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
	elsif ($a eq "--ip") {
		$ip = shift(@ARGV);
		&check_ipaddress($ip) || &usage("Invalid IP address");
		if (!$config{'all_namevirtual'}) {
			$virt = 1;
			$virtalready = 1;
			}
		}
	elsif ($a eq "--allocate-ip") {
		$ip = "allocate";
		$virt = 1;
		}
	elsif ($a eq "--ip-already") {
		$virtalready = 1;
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
	else {
		&usage();
		}
	}
$src && $type || usage();
if ($template eq "") {
	$template = &get_init_template($parentdomain);
	}
$tmpl = &get_template($template);

# Work out the IP, if needed
if ($ip eq "allocate") {
	$tmpl->{'ranges'} ne "none" || &usage("The --allocate-ip option cannot be used unless automatic IP allocation is enabled - use --ip instead");
	$ip = &free_ip_address($tmpl);
	$ip || &usage("Failed to allocate IP address from ranges!");
	}
elsif ($ip) {
	$tmpl->{'ranges'} eq "none" || $config{'all_namevirtual'} || &usage("The --ip option cannot be used when automatic IP allocation is enabled - use --allocate-ip instead");
	}
else {
	$ip = &get_default_ip();
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
&$second_print(".. done");

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
		$ip, $virt, $pass, $parent, $prefix, $virtalready, $email);
&run_post_actions();

# Show the result
if (@doms) {
	print "The following servers were successfully migrated : ",join(" ", map { $_->{'dom'} } @doms),"\n";
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
print "usage: migrate-domain.pl --source file\n";
print "                         --type $types\n";
print "                         --domain name\n";
print "                         [--user username]\n";
print "                         [--pass password]\n";
print "                         [--webmin]\n";
print "                         [--template name]\n";
print "                         [--ip address] [--allocate-ip]\n";
print "                         [--ip-already]\n";
print "                         [--parent domain]\n";
print "                         [--prefix string]\n";
print "                         [--delete-existing]\n";
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

