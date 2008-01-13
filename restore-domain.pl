#!/usr/local/bin/perl
# Restore some domains from some file

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/restore-domain.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "restore-domain.pl must be run as root";
	}

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--source") {
		$src = shift(@ARGV);
		}
	elsif ($a eq "--feature") {
		local $f = shift(@ARGV);
		$f eq "virtualmin" || $config{$f} ||
		   &indexof($f, @backup_plugins) >= 0 ||
			&usage("Feature $f is not enabled");
		push(@rfeats, $f);
		}
	elsif ($a eq "--domain") {
		push(@rdoms, shift(@ARGV));
		}
	elsif ($a eq "--all-features") {
		@rfeats = grep { $config{$_} || $_ eq 'virtualmin' }
			       @backup_features;
		push(@rfeats, @backup_plugins);
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
	elsif ($a eq "--only-features") {
		$onlyfeats = 1;
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

# Check for missing features
&$first_print("Checking for missing features ..");
@missing = &missing_restore_features($cont, $contdoms);
if (@missing) {
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
$ok = &restore_domains($src, \@doms, \@rfeats, \%opts, \@vbs, $onlyfeats);
&run_post_actions();
if ($ok) {
	&$second_print("Restore completed successfully.");
	}
else {
	&$second_print("Restore failed!");
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Restores a Virtualmin backup, for the domains and features specified\n";
print "on the command line.\n";
print "\n";
print "usage: restore-domain.pl --source file\n";
print "                  [--test]\n";
print "                  [--domain name] | [--all-domains]\n";
print "                  [--feature name] | [--all-features]\n";
print "                                     [--except-feature name]\n";
print "                  [--reuid]\n";
print "                  [--fix]\n";
print "                  [--option feature name value]\n";
print "                  [--all-virtualmin] | [--virtualmin config]\n";
print "                  [--only-features]\n";
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

