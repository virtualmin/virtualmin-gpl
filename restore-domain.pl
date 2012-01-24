#!/usr/local/bin/perl

=head1 restore-domain.pl

Restore one or more virtual servers

To restore a Virtualmin backup from the command line, you will need to use
this program. It takes very similar parameters to C<backup-domain>, with the
exceptions that C<--dest> is replace with C<--source>, and the C<--separate> and
C<--ignore-errors> options are not used. The extra option C<--reuid> can be
specified to force the re-allocation of Unix UIDs and GIDs for virtual servers
that are created by the restore process, which is usually a good idea as the
IDs in the backup file may already be in use.

Specific features to restore can be selected with the C<--feature> flag,
followed by a feature name like C<dns> to just restore a domain's DNS records.
However in most cases you will want to a full restore, in which case the
C<--all-features> parameter should be given.

If a virtual server that does not currently exist is selected to be restored,
it will be created as part of the restore process. Be careful using this
program, as it will not prompt for confirmation before restoring, which will
over-write the contents of restored directories, databases and configuration
files.

You can limit the restore to only domains that do not yet exist yet with
the C<--only-missing> flag. Conversely, you can specify only domains that
already exist with the C<--only-existing> flag, to prevent any new virtual
servers in the backup from being created.

To restore core Virtualmin settings (if included in the backup), the
C<--all-virtualmin> option can be specified as well. Alternately, you can select
exactly which settings to include with the C<--virtualmin> parameter. For example,
C<--virtualmin config> would only restore the module configuration.

When restoring a virtual server that originally had a private IP address,
the same address will be used by default. However, this may not be what you
want if you are restoring a domain on a different system that is not on the
same network. To use a different IP address, the C<--ip> flag can be given
followed by an address. Or you can use the C<--allocate-ip> flag to have
Virtualmin select one automatically, assuming that an allocation range is
defined in the template used.

If restoring multiple domains, some of which were on shared IP addresses and
some of which had private IPs, the C<--original-ip> flag can be used to
force IP allocation for domains that had a private address originally. Domains
which were on the old system's shared IP will be assigned this system's default
address.

When the restored server was on a shared address, it will by default be
given the system's default shared IP. However, if you have defined additional
shared addresses, a different one can be selected with the C<--shared-ip>
flag followed by an address.

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
	$0 = "$pwd/restore-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "restore-domain.pl must be run as root";
	}
@OLDARGV = @ARGV;

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
$asowner = 0;
$reuid = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--source") {
		$src = shift(@ARGV);
		}
	elsif ($a eq "--feature") {
		local $f = shift(@ARGV);
		$f eq "virtualmin" || $config{$f} ||
		   &indexof($f, &list_backup_plugins()) >= 0 ||
			&usage("Feature $f is not enabled");
		push(@rfeats, $f);
		}
	elsif ($a eq "--domain") {
		push(@rdoms, shift(@ARGV));
		}
	elsif ($a eq "--all-features") {
		@rfeats = grep { $config{$_} || $_ eq 'virtualmin' }
			       @backup_features;
		push(@rfeats, &list_backup_plugins());
		}
	elsif ($a eq "--except-feature") {
		local $f = shift(@ARGV);
		@rfeats = grep { $_ ne $f } @rfeats;
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--test") {
		$test = 1;
		}
	elsif ($a eq "--reuid") {
		$reuid = 1;
		}
	elsif ($a eq "--no-reuid") {
		$reuid = 0;
		}
	elsif ($a eq "--fix") {
		$fix = 1;
		}
	elsif ($a eq "--option") {
		$optf = shift(@ARGV);
		if ($optf =~ /^(\S+)\s+(\S+)\s+(\S+)$/) {
			$optf = $1;
			$optn = $2;
			$optv = $3;
			}
		else {
			$optn = shift(@ARGV);
			$optv = shift(@ARGV);
			}
		$optf && $optn && $optv || &usage("Invalid option specification");
		$opts{$optf}->{$optn} = $optv;
		}
	elsif ($a eq "--mailfiles") {
		# Convenience flag for --option mail mailfiles 1
		# Deprecated, as this is on by default now
		}
	elsif ($a eq "--as-owner") {
		# Run as domain owner
		$asowner = 1;
		}
	elsif ($a eq "--virtualmin") {
		$v = shift(@ARGV);
		&indexof($v, @virtualmin_backups) >= 0 ||
			&usage("Unknown --virtualmin option $v. Available options are : ".join(" ", @virtualmin_backups));
		push(@vbs, $v);
		}
	elsif ($a eq "--all-virtualmin") {
		@vbs = @virtualmin_backups;
		}
	elsif ($a eq "--only-features") {
		$onlyfeats = 1;
		}
	elsif ($a eq "--only-missing") {
		$onlymissing = 1;
		}
	elsif ($a eq "--only-existing") {
		$onlyexisting = 1;
		}

	# Alternate IP options
	elsif ($a eq "--shared-ip") {
		$sharedip = shift(@ARGV);
		&indexof($sharedip, &list_shared_ips()) >= 0 ||
		    &usage("$sharedip is not in the shared IP addresses list");
		$ipinfo = { 'virt' => 0, 'ip' => $sharedip,
			    'virtalready' => 0, 'mode' => 3 };
		}
	elsif ($a eq "--ip") {
		$ip = shift(@ARGV);
		&check_ipaddress($ip) || &usage("Invalid IP address");
		&check_virt_clash($ip) &&
			&usage("IP address is already in use");
		$ipinfo = { 'virt' => 1, 'ip' => $ip,
			    'virtalready' => 0, 'mode' => 1 };
		}
	elsif ($a eq "--allocate-ip") {
		$tmpl = &get_template(0);
		($ip, $netmask) = &free_ip_address($tmpl);
		$ipinfo = { 'virt' => 1, 'ip' => $ip,
			    'virtalready' => 0, 'netmask' => $netmask,
			    'mode' => 2 };
		}
	elsif ($a eq "--original-ip") {
		$tmpl = &get_template(0);
		($ip, $netmask) = &free_ip_address($tmpl);
		$ipinfo = { 'virt' => 1, 'ip' => $ip,
			    'virtalready' => 0, 'netmask' => $netmask,
			    'mode' => 5 };
		}
	elsif ($a eq "--skip-warnings") {
		$skipwarnings = 1;
		}
	else {
		&usage();
		}
	}
$src || usage("Missing --source parameter");
@rdoms || $all_doms || @vbs || usage("No domains to restore specified");
if (@rdoms || $all_doms) {
	@rfeats || $fix || usage("No features to restore specified");
	}
($mode) = &parse_backup_url($src);
$mode > 0 || -r $src || -d $src || &usage("Missing or invalid restore file");
$onlymissing && $onlyexisting && &usage("The --only-missing and --only-existing flags are mutually exclusive");

# Find the selected domains
($cont, $contdoms) = &backup_contents($src, 1);
ref($cont) || &usage("Failed to read backup file : $cont");
(keys %$cont) || &usage("Nothing in backup file!");
if ($all_doms) {
	# All in backup
	@rdoms = keys %$cont;
	}
foreach $dname (@rdoms) {
	local $dinfo = &get_domain_by("dom", $dname);
	if ($dname eq "virtualmin") {
		$got_vbs = 1;
		}
	elsif ($dinfo) {
		push(@doms, $dinfo);
		}
	else {
		push(@doms, { 'dom' => $dname,
			      'missing' => 1 });
		}
	}

# Filter by missing or existing flags
if ($onlymissing) {
	@doms = grep { $_->{'missing'} } @doms;
	}
elsif ($onlyexisting) {
	@doms = grep { !$_->{'missing'} } @doms;
	}

# Check for missing features
&$first_print("Checking for missing features ..");
@missing = &missing_restore_features($cont, $contdoms);
@critical = grep { $_->{'critical'} } @missing;
if (@critical) {
	&$second_print(
	  ".. WARNING - The following features were enabled for one or more\n".
	  "domains in the backup, but do not exist on this system. Restoring\n".
	  "this backup would break the configuration of the system : ".
	  join(", ", map { $_->{'desc'} } @critical));
	exit(2);
	}
elsif (@missing) {
	&$second_print(
	  ".. WARNING - The following features were enabled for one or more\n".
	  "domains in the backup, but do not exist on this system. Some\n".
	  "functions of the restored domains may not work : ".
	  join(", ", map { $_->{'desc'} } @missing));
	}
else {
	&$second_print(".. all features in backup are supported");
	}

if ($test) {
	# Just tell the user what will be done
	if (@doms) {
		print "The following servers will be restored :\n";
		foreach $d (@doms) {
			print "\t$d->{'dom'}\n";
			}
		print "\n";
		print "The following features will be restored :\n";
		foreach $f (@rfeats) {
			# Do any domains being restored have this feature?
			@fdoms = grep { $cont->{$_} &&
					&indexof($f, @{$cont->{$_}}) >= 0 }
				      @rdoms;
			next if (!@fdoms);

			# Get and show restore featurer name
			if (&indexof($f, &list_backup_plugins()) >= 0) {
				$fn = &plugin_call($f, "feature_backup_name") ||
				      &plugin_call($f, "feature_name");
				}
			else {
				$fn = $text{"backup_feature_".$f} || $text{"feature_".$f};
				}
			print "\t",($fn ? $fn." ($f)" : $f),"\n";
			}
		}
	if (@vbs) {
		print "The following Virtualmin settings will be restored :\n";
		foreach $v (@vbs) {
			print "\t",$text{'backup_v'.$v},"\n";
			}
		}
	exit(0);
	}

# Do it!
$opts{'reuid'} = $reuid;
$opts{'fix'} = $fix;
&$first_print("Starting restore..");
$ok = &restore_domains($src, \@doms, \@rfeats, \%opts, \@vbs, $onlyfeats,
		       $ipinfo, $asowner, $skipwarnings);
&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $doms[0]);
if ($ok) {
	&$second_print("Restore completed successfully.");
	}
else {
	&$second_print("Restore failed!");
	exit(1);
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Restores a Virtualmin backup, for the domains and features specified\n";
print "on the command line.\n";
print "\n";
print "virtualmin restore-domain --source file\n";
print "                         [--test]\n";
print "                         [--domain name] | [--all-domains]\n";
print "                         [--feature name] | [--all-features]\n";
print "                         [--except-feature name]\n";
print "                         [--reuid | --no-reuid]\n";
print "                         [--fix]\n";
print "                         [--option \"feature name value\"]\n";
print "                         [--all-virtualmin] | [--virtualmin config]\n";
print "                         [--only-features]\n";
print "                         [--shared-ip address | --ip address |\n";
print "                          --allocate-ip | --original-ip]\n";
print "                         [--only-missing | --only-existing]\n";
print "                         [--skip-warnings]\n";
print "\n";
print "Multiple domains may be specified with multiple --domain parameters.\n";
print "Features must be specified using their short names, like web and dns.\n";
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

