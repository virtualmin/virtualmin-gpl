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

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/backup-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "backup-domain.pl must be run as root";
	}

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--dest") {
		$dest = shift(@ARGV);
		}
	elsif ($a eq "--feature") {
		local $f = shift(@ARGV);
		$f eq "virtualmin" || $config{$f} ||
		   &indexof($f, @backup_plugins) >= 0 ||
			&usage("Feature $f is not enabled");
		push(@bfeats, $f);
		}
	elsif ($a eq "--domain") {
		push(@bdoms, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--all-features") {
		@bfeats = grep { $config{$_} || $_ eq 'virtualmin' }
			       @backup_features;
		push(@bfeats, @backup_plugins);
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
		$opts{'mail'}->{'mailfiles'} = 1;
		}
	elsif ($a eq "--virtualmin") {
		$v = shift(@ARGV);
		&indexof($v, @virtualmin_backups) >= 0 ||
			&usage("Unknown --virtualmin option. Available options are : ".join(" ", @virtualmin_backups));
		push(@vbs, $v);
		}
	elsif ($a eq "--all-virtualmin") {
		@vbs = @virtualmin_backups;
		}
	elsif ($a eq "--incremental") {
		&has_incremental_tar() || &error("The tar command on this system does not support incremental backups");
		$increment = 1;
		}
	else {
		&usage();
		}
	}
$dest || usage();
@bdoms || @users || $all_doms || @vbs || usage();
if (@bdoms || @users || $all_doms) {
	@bfeats || usage();
	}
($bmode) = &parse_backup_url($dest);
if ($bmode && $mkdir) {
	&usage("--mkdir option can only be used for local backups");
	}
if ($onebyone && !$newformat) {
	&usage("--onebyone option can only be used in conjunction with --newformat");
	}
if ($onebyone && !$bmode) {
	&usage("--onebyone option can only be used with remote backups");
	}

# Work out what will be backed up
if ($all_doms) {
	# All domains
	@doms = &list_domains();
	}
else {
	# Get domains by name and user
	@doms = &get_domains_by_names_users(\@bdoms, \@users, \&usage);
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
			if (&indexof($f, @backup_plugins) >= 0) {
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

# Do the backup, printing any output
&$first_print("Starting backup..");
($ok, $size) = &backup_domains($dest, \@doms, \@bfeats,
			       $separate,
			       $ignore_errors,
			       \%opts,
			       $newformat,
			       \@vbs,
			       $mkdir,
			       $onebyone,
			       0,
			       undef,
			       $increment);
if ($ok) {
	&$second_print("Backup completed successfully. Final size was ".
		       &nice_size($size));
	}
else {
	&$second_print("Backup failed!");
	exit(2);
	}

sub usage
{
if ($_[0]) {
	print $_[0],"\n\n";
	}
print "Creates a Virtualmin backup, for the domains and features specified\n";
print "on the command line.\n";
print "\n";
print "usage: backup-domain.pl --dest file\n";
print "                        [--test]\n";
print "                        [--domain name] | [--all-domains]\n";
print "                        [--user name]\n";
print "                        [--feature name] | [--all-features]\n";
print "                                           [--except-feature name]\n";
print "                        [--ignore-errors]\n";
print "                        [--separate] | [--newformat]\n";
print "                        [--onebyone]\n";
if (&has_incremental_tar()) {
	print "                        [--incremental]\n";
	}
print "                        [--all-virtualmin] | [--virtualmin config]\n";
print "                        [--option feature name value]\n";
print "                        [--mailfiles]\n";
print "\n";
print "Multiple domains may be specified with multiple --domain parameters.\n";
print "Features must be specified using their short names, like web and dns.\n";
print "\n";
print "The destination can be one of :\n";
print " - A local file, like /backup/yourdomain.com.tgz\n";
print " - An FTP destination, like ftp://login:pass\@server/backup/yourdomain.com.tgz\n";
print " - An SSH destination, like ssh://login:pass\@server/backup/yourdomain.com.tgz\n";
if ($virtualmin_pro) {
	print " - An S3 bucket, like s3://accesskey:secretkey\@bucket\n";
	}
exit(1);
}

