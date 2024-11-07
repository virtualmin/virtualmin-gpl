#!/usr/local/bin/perl

=head1 create-scheduled-backup.pl

Create a scheduled backup for one or more virtual servers

This command creates a scheduled backup which behaves the same as one
created in the Virtualmin UI.

The schedule to backup on is set with the C<--schedule> flag followed
by a cron-format timespec, like "30 01 * * *" for 1:30am daily. By default
the scheduled backup will be enabled, but you can turn it off by with the
C<--disabled> flag.

To set an address to notify when the backup completes, use the C<--email>
flag followed by an address. To limit email reports to failures, use
the C<--email-errors> flag. And to include domain owners in the email,
use C<--email-owners>.

The C<--dest> option sets the backup destination, and can be a simple path like
C</backup/virtualmin.tgz> , an FTP URL like
C<ftp://user:pass@server:/backup/virtualmin.tgz> , or an SCP URL like
C<ssh://user:pass@server:/backup/virtualmin.tgz> . When backing up to a single
file, the path specifies a file that will be created. When creating one backup
per domain, it specifies a directory instead.

The C<--domain> and C<--all-domains> options can be used to control which virtual
servers are included in the backup. The C<--domain> parameter followed by a
domain name can be given multiple times, to select more than one server. You can
also add the C<--parent> flag to include all sub-servers and aliases of the
selected domains.

Alternately, virtual servers can be selected by C<--plan> followed by a plan
name, or C<-reseller> followed by a reseller name. In all cases, all
sub-servers will be included too.

Typically the C<--all-features> option will be used to include all virtual server
features in the backup, but you can instead use the C<--feature> option one or
more times to control exactly what gets included. In this case, it is wise to
use at least C<--feature dir> to include each server's home directory.

The C<--newformat> option tells the backup program to create a separate file for
each virtual server. As long as the entire domain is being backed up, this 
format also uses less temporary space as all databases and other additional
files are included in the home directory archive.

Using the C<--ignore-errors> option means than any errors
encountered backing up one feature or server will be reported and ignored,
rather than terminating the whole backup as happens by default.

To include core Virtualmin settings in the backup, the C<--all-virtualmin>
option can be specified as well. Alternately, you can select exactly which
settings to include with the C<--virtualmin> parameter. For example,
C<--virtualmin config> would only backup the module configuration.

By default, backups include all files in each domain's home directory. However,
if you use the C<--differential> parameter, only those changed since the last
non-differential backup will be included. This allows you to reduce the size of
backups for large websites that rarely change, but means that when restoring
both the full and differential backups are needed.

The alternative parameter C<--no-differential> can be used by prevent Virtualmin
from clearing the list of files that were included in the last full backup.
This is used if you have a scheduled differential backup setup, and don't want
to change its behavior by doing an ad-hoc full backup.

To exclude some files from each virtual server's home directory from the
backup, use the C<--exclude> flag followed by a relative filename, like
I<public_html/stats> or I<.bashrc>. Alternately, you can limit the backup to
only specific files and directories with the C<--include> flag.

To have Virtualmin automatically replace strftime-style date formatting
characters in the backup destination, you can use the C<--strftime> flag.
When this is enabled, the C<--purge> flag can also be given, followed by a 
number of days. The command will then delete backups in the same desination
directory older than the specified number of days.

On a Virtualmin Pro system, you can use the C<--key> flag followed by
a backup key ID or description to select the key to encrypt this backup with.
Keys can be found using the C<list-backup-keys> API call.

To override the default compression format set on the Virtualmin Configuration
page, use the C<--compression> flag followed by one of C<gzip>, C<bzip2>, 
C<tar> or C<zip>.

Scheduled backups can have an optional description, which can be set with the
C<--desc> flag.

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
	$0 = "$pwd/create-scheduled-backup.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-scheduled-backup.pl must be run as root";
	}
&licence_status();

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
$asowner = 0;
$enabled = 1;
@allplans = &list_plans();
@OLDARGV = @ARGV;
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
	elsif ($a eq "--parent") {
		$includesubs = 1;
		}
	elsif ($a eq "--reseller") {
		defined(&list_resellers) ||
			&usage("Your system does not support resellers");
		push(@resellers, shift(@ARGV));
		}
	elsif ($a eq "--plan") {
		$planname = shift(@ARGV);
		($plan) = grep { lc($_->{'name'}) eq lc($planname) ||
				 $_->{'id'} eq $planname } @allplans;
		$plan || &usage("No plan with name or ID $planname found");
		push(@plans, $plan);
		}
	elsif ($a eq "--all-features") {
		$all_bfeats = 1;
		}
	elsif ($a eq "--except-feature") {
		local $f = shift(@ARGV);
		@bfeats = grep { $_ ne $f } @bfeats;
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
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
	elsif ($a eq "--incremental" || $a eq "--differential") {
		&has_incremental_tar() || &usage("The tar command on this system does not support differential backups");
		$increment = 1;
		}
	elsif ($a eq "--no-incremental" || $a eq "--no-differential") {
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
	elsif ($a eq "--include") {
		$include = shift(@ARGV);
		push(@include, $include);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--compression") {
		my $c = shift(@ARGV);
		$compression = $c eq "gzip" ? 0 :
			       $c eq "bzip2" ? 1 :
			       $c eq "tar" ? 2 :
			       $c eq "zip" ? 3 : -1;
		&usage("Invalid compression format $c") if ($compression < 0);
		}
	elsif ($a eq "--schedule") {
		$schedule = shift(@ARGV);
		if ($schedule =~ /^(hourly|daily|weekly|monthly|yearly)$/) {
			$special = $schedule;
			}
		else {
			@schedule = split(/\s+/, $schedule);
			@schedule == 5 || &usage("--schedule must be followed by a valid cron spec");
			}
		}
	elsif ($a eq "--disabled") {
		$enabled = 0;
		}
	elsif ($a eq "--email") {
		$email = shift(@ARGV);
		}
	elsif ($a eq "--email-errors") {
		$email_err = 1;
		}
	elsif ($a eq "--email-owners") {
		$email_doms = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@dests || usage("No destinations specified");
@bdoms || $all_doms || @resellers || @plans || @vbs || $purge ||
	&usage("No domains specified");
if (@bdoms || @users || $all_doms) {
	@bfeats || $all_bfeats || usage("No features specified");
	}
foreach my $dname (@bdoms) {
	$d = &get_domain_by("dom", $dname);
	$d || &usage("Virtual server $dname does not exist");
	push(@doms, $d);
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
if ($increment) {
	&has_incremental_format($compression) || &usage("The configured backup format does not support differential backups");
	}

# Create a backup schedule object
my $sched = { };
$sched->{'desc'} = $desc;
for(my $i=0; $i<@dests; $i++) {
	$sched->{'dest'.$i} = $dests[$i];
	}
if ($all_doms) {
	$sched->{'all'} = 1;
	}
elsif (@doms) {
	$sched->{'doms'} = join(" ", map { $_->{'id'} } @doms);
	}
$sched->{'plan'} = join(" ", map { $_->{'id'} } @plans);
$sched->{'reseller'} = join(" ", @resellers);
$sched->{'parent'} = $includesubs;
$sched->{'virtualmin'} = join(" ", @vbs);
if ($all_bfeats) {
	$sched->{'feature_all'} = 1;
	}
else {
	$sched->{'features'} = join(" ", @bfeats);
	}
$sched->{'purge'} = $purge;
$sched->{'key'} = $keyid;
$sched->{'fmt'} = $newformat ? 2 : $separate ? 1 : 0;
$sched->{'mkdir'} = $mkdir;
$sched->{'errors'} = $ignore_errors;
$sched->{'increment'} = $increment;
$sched->{'compression'} = $compression;
$sched->{'strftime'} = $strftime;
$sched->{'onebyone'} = $onebyone;
$sched->{'exclude'} = join("\t", @exclude);
$sched->{'include'} = join("\t", @include);
foreach my $f (keys %opts) {
	$sched->{'backup_opts_'.$f} =
		join(",", map { $_."=".$opts{$f}->{$_} }
                              keys %{$opts{$f}});
	}

# Save scheduled-related options
if ($special) {
	$sched->{'special'} = $special;
	}
else {
	($sched->{'mins'}, $sched->{'hours'}, $sched->{'days'},
	 $sched->{'months'}, $sched->{'weekdays'}) = @schedule;
	}
$sched->{'enabled'} = $enabled;
$sched->{'email'} = $email;
$sched->{'email_err'} = $email_err;
$sched->{'email_doms'} = $email_doms;

# Save the scheduled backup
&save_scheduled_backup($sched);
print "Scheduled backup created with ID $sched->{'id'}\n";

&virtualmin_api_log(\@OLDARGV);

sub usage
{
if ($_[0]) {
	print $_[0],"\n\n";
	}
print "Creates a scheduled Virtualmin backup for the selected domains,\n";
print "features and schedule.\n";
print "\n";
print "virtualmin create-scheduled-backup [--dest file]+\n";
print "                         [--domain name] | [--all-domains]\n";
print "                         [--parent]\n";
print "                         [--reseller name]\n";
print "                         [--plan name]\n";
print "                         [--feature name] | [--all-features]\n";
print "                                            [--except-feature name]\n";
print "                         [--ignore-errors]\n";
print "                         [--newformat]\n";
print "                         [--onebyone]\n";
print "                         [--strftime] [--purge days]\n";
if (&has_incremental_tar()) {
	print "                         [--differential] | [--no-differential]\n";
	}
print "                         [--all-virtualmin] | [--virtualmin config] |\n";
print "                                              [--except-virtualmin config]\n";
print "                         [--option \"feature name value\"]\n";
print "                         [--as-owner]\n";
print "                         [--exclude file]*\n";
print "                         [--include file]*\n";
print "                         [--purge days]\n";
if (defined(&list_backup_keys)) {
	print "                         [--key id]\n";
	}
print "                         [--compression gzip|bzip2|tar|zip]\n";
print "                         [--desc \"backup description\"]\n";
print "                         [--disabled]\n";
print "                         [--schedule \"cron-spec\"]\n";
print "                         [--email address]\n";
print "                         [--email-errors]\n";
print "                         [--email-owners]\n";
print "\n";
print "Multiple domains may be specified with multiple --domain parameters.\n";
print "Features must be specified using their short names, like web and dns.\n";
print "\n";
print "The destination can be one of :\n";
print " - A local file, like /backup/yourdomain.com.tgz\n";
print " - A local directory can be given while passing --newformat option, like /backup/\n";
print " - An FTP destination, like ftp://login:pass\@server/backup/yourdomain.com.tgz\n";
print " - An SSH destination, like ssh://login:pass\@server/backup/yourdomain.com.tgz\n";
print " - An S3 bucket, like s3://accesskey:secretkey\@bucket\n";
print " - A Rackspace container, like rs://user:apikey\@container\n";
print " - A Google Cloud Storage bucket, like gcs://bucket\n";
print " - A Dropbox folder, like dropbox://folder\n";
print "Multiple destinations can be given by repeating this flag.\n";
exit(1);
}

