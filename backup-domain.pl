#!/usr/local/bin/perl

=head1 backup-domain.pl

Backup one or more virtual servers

This program is analogous to the Backup Virtual Servers page in the Virtualmin web interface. It will create either a single backup file or multiple separate files containing the domains specified on the command line, either locally or on a remote SCP or FTP server.

The C<--dest> option sets the backup destination, and can be a simple path like
C</backup/virtualmin.tgz> , an FTP URL like
C<ftp://user:pass@server:/backup/virtualmin.tgz> , or an SCP URL like
C<ssh://user:pass@server:/backup/virtualmin.tgz> . When backing up to a single
file, the path specifies a file that will be created. When creating one backup
per domain, it specifies a directory instead.

The C<--domain> and C<--all-domains> options can be used to control which virtual
servers are included in the backup. The C<--domain> parameter followed by a
domain name can be given multiple times, to select more than one server.

Alternately, virtual servers can be selected with the C<--user> flag followed
by an administrator's username, or C<--plan> followed by a plan name. In both
cases, all sub-servers will be included too.

Typically the C<--all-features> option will be used to include all virtual server
features in the backup, but you can instead use the C<--feature> option one or
more times to control exactly what gets included. In this case, it is wise to
use at least C<--feature dir> to include each server's home directory.

The C<--separate> option tells the backup program to create a separate file for
each virtual server. The C<--newformat> also causes multiple files to be created,
but using the format supported by Virtualmin versions 2.86 and above which
puts all information into each domain's home directory, and thus avoids the
need to create a large file in C</tmp> during the backup process.

Using the C<--ignore-errors> option means than any errors
encountered backing up one feature or server will be reported and ignored,
rather than terminating the whole backup as happens by default.

To include core Virtualmin settings in the backup, the C<--all-virtualmin>
option can be specified as well. Alternately, you can select exactly which
settings to include with the C<--virtualmin> parameter. For example,
C<--virtualmin config> would only backup the module configuration.

By default, backups include all files in each domain's home directory. However,
if you use the C<--incremental> parameter, only those changed since the last
non-incremental backup will be included. This allows you to reduce the size of
backups for large websites that rarely change, but means that when restoring
both the full and incremental backups are needed.

The alternative parameter C<--no-incremental> can be used by prevent Virtualmin
from clearing the list of files that were included in the last full backup.
This is used if you have a scheduled incremental backup setup, and don't want
to change its behavior by doing an ad-hoc full backup.

To exclude some files from each virtual server's home directory from the
backup, use the C<--exclude> flag followed by a relative filename, like
I<public_html/stats> or I<.bashrc>.

To have Virtualmin automatically replace strftime-style date formatting
characters in the backup destination, you can use the C<--strftime> flag.
When this is enabled, the C<--purge> flag can also be given, followed by a 
number of days. The command will then delete backups in the same desination
directory older than the specified number of days.

On a Virtualmin Pro system, you can use the C<--key> flag followed by
a backup key ID or description to select the key to encrypt this backup with.
Keys can be found using the C<list-backup-keys> API call.

By default, only one backup to the same destination can be running at the
same time - the second backup will immediately fail. You can invert this
behavior with the C<--kill-running> flag, which terminates the first backup
and allows this one to continue.

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
	$0 = "$pwd/backup-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "backup-domain.pl must be run as root";
	}

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
$asowner = 0;
@allplans = &list_plans();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--dest") {
		push(@dests, shift(@ARGV));
		}
	elsif ($a eq "--feature") {
		local $f = shift(@ARGV);
		$f eq "virtualmin" || $config{$f} ||
		   &indexof($f, &list_backup_plugins()) >= 0 ||
			&usage("Feature $f is not enabled on this system");
		push(@bfeats, $f);
		}
	elsif ($a eq "--domain") {
		push(@bdoms, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--plan") {
		$planname = shift(@ARGV);
		($plan) = grep { lc($_->{'name'}) eq lc($planname) ||
				 $_->{'id'} eq $planname } @allplans;
		$plan || &usage("No plan with name or ID $planname found");
		push(@plans, $plan);
		}
	elsif ($a eq "--all-features") {
		@bfeats = grep { $config{$_} || $_ eq 'virtualmin' }
			       @backup_features;
		push(@bfeats, &list_backup_plugins());
		}
	elsif ($a eq "--except-feature") {
		local $f = shift(@ARGV);
		@bfeats = grep { $_ ne $f } @bfeats;
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--test") {
		$test = 1;
		}
	elsif ($a eq "--ignore-errors") {
		$ignore_errors = 1;
		}
	elsif ($a eq "--separate") {
		$separate = 1;
		}
	elsif ($a eq "--mkdir") {
		$mkdir = 1;
		}
	elsif ($a eq "--onebyone") {
		$onebyone = 1;
		}
	elsif ($a eq "--newformat") {
		$separate = 1;
		$newformat = 1;
		}
	elsif ($a eq "--strftime") {
		$strftime = 1;
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
		if (&indexof($v, @virtualmin_backups) < 0) {
			print STDERR "Unknown --virtualmin option $v. Available options are : ".join(" ", @virtualmin_backups)."\n";
			}
		else {
			push(@vbs, $v);
			}
		}
	elsif ($a eq "--all-virtualmin") {
		@vbs = @virtualmin_backups;
		}
	elsif ($a eq "--except-virtualmin") {
		$v = shift(@ARGV);
		@vbs = grep { $_ ne $v } @vbs;
		}
	elsif ($a eq "--incremental") {
		&has_incremental_format() || &usage("The configured backup format does not support incremental backups");
		&has_incremental_tar() || &usage("The tar command on this system does not support incremental backups");
		$increment = 1;
		}
	elsif ($a eq "--no-incremental") {
		$increment = 2;
		}
	elsif ($a eq "--purge") {
		$purge = shift(@ARGV);
		$purge =~ /^[0-9\.]+$/ || &usage("--purge must be followed by a number");
		}
	elsif ($a eq "--key") {
		$keyid = shift(@ARGV);
		}
	elsif ($a eq "--exclude") {
		$exclude = shift(@ARGV);
		push(@exclude, $exclude);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--kill-running") {
		$kill = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@dests || usage("No destinations specified");
@bdoms || @users || $all_doms || @plans || @vbs || $purge ||
	&usage("No domains specified");
if (@bdoms || @users || $all_doms) {
	@bfeats || usage("No features specified");
	}
foreach $dest (@dests) {
	# Validate destination URL
	($bmode, $derr, undef, $host, $path) = &parse_backup_url($dest);
	$bmode < 0 && &usage("Destination $dest is invalid : $derr");
	if ($bmode && $mkdir) {
		&usage("--mkdir option can only be used for local backups");
		}
	if ($onebyone && !$bmode) {
		&usage("--onebyone option can only be used with ".
		       "remote backups");
		}

	# Validate purging
	if ($purge) {
		$strftime || &usage("The --purge flag can only be used in ".
				    "conjunction with --strftime");
		$path =~ /%/ || $host =~ /%/ ||
			&usage("The --purge flag can only be used for backup ".
			      "destinations containing strftime substitutions");
		($basepath, $pattern) = &extract_purge_path($dest);
		$basepath || $pattern ||
			&usage("The --purge flag can only be used when a ".
			       "base directory can be extracted from the ".
			       "backup path, like /backup/virtualmin-%d-%m-%Y");
		}
	}
if ($keyid) {
	# Validate encryption key
	defined(&list_backup_keys) ||
		&usage("Backup encryption is not supported on this system");
	($key) = grep { $_->{'id'} eq $keyid ||
		  	$_->{'key'} eq $keyid ||
		  	$_->{'desc'} eq $keyid } &list_backup_keys();
	$key || &usage("No backup key with ID or description $keyid exists");
	}
if ($onebyone && !$newformat) {
	&usage("--onebyone option can only be used in conjunction ".
	       "with --newformat");
	}

# Work out what will be backed up
if ($all_doms) {
	# All domains
	@doms = &list_domains();
	}
else {
	# Get domains by name and user
	@doms = &get_domains_by_names_users(\@bdoms, \@users, \&usage, \@plans);
	}

if ($test) {
	# Just tell the user what will be done
	if (@doms) {
		print "The following servers will be backed up :\n";
		foreach $d (@doms) {
			print "\t$d->{'dom'}\n";
			}
		print "\n";
		print "The following features will be backed up :\n";
		foreach $f (@bfeats) {
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
		print "The following Virtualmin settings will be backed up :\n";
		foreach $v (@vbs) {
			print "\t",$text{'backup_v'.$v},"\n";
			}
		}
	exit(0);
	}

# Create a fake backup schedule object
my $sched = { 'id' => 'backup.pl.'.time() };
for(my $i=0; $i<@dests; $i++) {
	$sched->{'dest'.$i} = $dests[$i];
	}
if ($all_doms) {
	$sched->{'all'} = 1;
	}
elsif (@doms) {
	$sched->{'doms'} = join(" ", map { $_->{'id'} } @doms);
	}
$sched->{'virtualmin'} = join(" ", @vbs);
&start_running_backup($sched);

&start_print_capture();
$start_time = time();
if ($strftime) {
	@strfdests = map { &backup_strftime($_) } @dests;
	}
else {
	@strfdests = @dests;
	}
$opts{'dir'}->{'exclude'} = join("\t", @exclude);

# Do the backup, printing any output
if ($sched->{'doms'} || $sched->{'all'} || $sched->{'virtualmin'}) {
	&$first_print("Starting backup..");
	($ok, $size, $errdoms) = &backup_domains(
					\@strfdests,
					\@doms,
					\@bfeats,
					$separate,
					$ignore_errors,
					\%opts,
					$newformat,
					\@vbs,
					$mkdir,
					$onebyone,
					$asowner,
					undef,
					$increment,
					0,
					$key,
					$kill);
	if ($ok && !@$errdoms) {
		&$second_print("Backup completed successfully. Final size was ".
			       &nice_size($size));
		$ex = 0;
		}
	elsif ($ok && @$errdoms) {
		&$second_print("Backup partially completed. Final size was ".
			       &nice_size($size));
		$ex = 4;
		}
	else {
		&$second_print("Backup failed!");
		$ex = 2;
		}
	}
else {
	# Probably just purging
	$ok = 1;
	$size = 0;
	}

# Purge if requested
$pok = 1;
if ($purge && $ok) {
	$asd = $asowner ? &get_backup_as_domain(\@doms) : undef;
	foreach $dest (@dests) {
		$pok = &purge_domain_backups($dest, $purge, $start_time, $asd);
		if (!$pok) {
			$ex = 3;
			}
		}
	}

$output = &stop_print_capture();
&cleanup_backup_limits(0, 1);
foreach $dest (@strfdests) {
	&write_backup_log(\@doms, $dest, $increment, $start_time,
			  $size, $ok, "api", $output, $errdoms, undef, $key);
	}
&stop_running_backup($sched);
exit($ex);

sub usage
{
if ($_[0]) {
	print $_[0],"\n\n";
	}
print "Creates a Virtualmin backup, for the domains and features specified\n";
print "on the command line.\n";
print "\n";
print "virtualmin backup-domain [--dest file]+\n";
print "                         [--test]\n";
print "                         [--domain name] | [--all-domains]\n";
print "                         [--user name]\n";
print "                         [--plan name]\n";
print "                         [--feature name] | [--all-features]\n";
print "                                            [--except-feature name]\n";
print "                         [--ignore-errors]\n";
print "                         [--separate] | [--newformat]\n";
print "                         [--onebyone]\n";
print "                         [--strftime] [--purge days]\n";
if (&has_incremental_tar()) {
	print "                         [--incremental] | [--no-incremental]\n";
	}
print "                         [--all-virtualmin] | [--virtualmin config] |\n";
print "                                              [--except-virtualmin config]\n";
print "                         [--option \"feature name value\"]\n";
print "                         [--as-owner]\n";
print "                         [--exclude file]*\n";
print "                         [--purge days]\n";
if (defined(&list_backup_keys)) {
	print "                         [--key id]\n";
	}
print "                         [--kill-running]\n";
print "\n";
print "Multiple domains may be specified with multiple --domain parameters.\n";
print "Features must be specified using their short names, like web and dns.\n";
print "\n";
print "The destination can be one of :\n";
print " - A local file, like /backup/yourdomain.com.tgz\n";
print " - An FTP destination, like ftp://login:pass\@server/backup/yourdomain.com.tgz\n";
print " - An SSH destination, like ssh://login:pass\@server/backup/yourdomain.com.tgz\n";
print " - An S3 bucket, like s3://accesskey:secretkey\@bucket\n";
print " - A Rackspace container, like rs://user:apikey\@container\n";
print "Multiple destinations can be given, if they are all remote.\n";
exit(1);
}

