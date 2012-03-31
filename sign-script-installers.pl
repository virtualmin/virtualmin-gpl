#!/usr/local/bin/perl
# Sign all script installer .pl files that are part of the Virtualmin core
# and upload them to some remote system.

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
        $0 = "$pwd/sign-script-installers.pl";
        require './virtual-server-lib.pl';
        $< == 0 || die "fetch-script-files.pl must be run as root";
        }
@OLDARGV = @ARGV;

# Parse command-line args
$user = "root";
while(@ARGV) {
        $a = shift(@ARGV);
        if ($a eq "--dir") {
                $dir = shift(@ARGV);
                }
	elsif ($a eq "--key") {
		$key = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$user = shift(@ARGV);
		}
	elsif ($a eq "--ssh-user") {
		$ssh_user = shift(@ARGV);
		}
	elsif ($a eq "--ssh-host") {
		$ssh_host = shift(@ARGV);
		}
	elsif ($a eq "--ssh-dir") {
		$ssh_dir = shift(@ARGV);
		}
	elsif ($a eq "--gpl-only") {
		$gplonly = 1;
		}
        else {
		&usage("Unknown parameter $a");
                }
        }

# Check for needed args
$dir || &usage("Missing --dir followed by SVN directory");
$key || &usage("Missing --key followed by GPG key email");
$ssh_user || &usage("Missing --ssh-user followed by remote SSH user");
$ssh_host || &usage("Missing --ssh-user followed by SSH server hostname");
$ssh_dir || &usage("Missing --ssh-user followed by SSH server directory");

# Run an SVN update to get checked-in scripts
print "Updating scripts from GIT ..\n";
system("cd ".quotemeta($dir)." && su $user -c 'git pull'");
if ($?) {
	print ".. SVN failed!\n";	
	exit(1);
	}
print ".. done\n";

# Build list of scripts and versions
print "Building list of scripts and versions ..\n";
@scripts_directories = ( $dir );
@plugins = ( );
@snames = &list_scripts();
foreach $sname (@snames) {
	$script = &get_script($sname);
	next if (!$script);
	$gfunc = $script->{'gpl_func'};
	$gpl = $gfunc && defined(&$gfunc) && &$gfunc();
	next if (!$gpl && $gplonly);
	push(@scripts, $script);
	push(@upload, $sname);
	}
if (@scripts) {
	print ".. found ",scalar(@scripts),"\n";
	}
else {
	print ".. none found!\n";
	exit(2);
	}

# Write out version file
print "Saving versions file ..\n";
$vfile = "$dir/scripts.txt";
&open_tempfile(VFILE, ">$vfile");
foreach $script (@scripts) {
	&print_tempfile(VFILE, $script->{'name'}."\t".
			       join(" ", @{$script->{'versions'}})."\t".
			       $script->{'release'}."\n");
	}
&close_tempfile(VFILE);
&set_ownership_permissions($user, undef, undef, $vfile);

# GPG sign version file
$sigvfile = $vfile."-sig.asc";
system("su $user -c 'rm -f $sigvfile ; gpg --armor --output $sigvfile --default-key $key --detach-sig $vfile'");
if ($?) {
	print ".. GPG failed!\n";
	exit(3);
	}
print ".. done\n";

# GPG sign any new script files
foreach my $sfile (glob("$dir/*.pl")) {
	$sigfile = $sfile."-sig.asc";
	@st = stat($sfile);
	@sigst = stat($sigfile);
	if ($st[9] > $sigst[9]) {
		# Needs re-signing
		print "Signing script $sfile ..\n";
		system("su $user -c 'rm -f $sigfile ; gpg --armor --output $sigfile --default-key $key --detach-sig $sfile'");
		if ($?) {
			print ".. GPG failed!\n";
			exit(3);
			}
		print ".. done\n";
		}
	}

# Upload via SSH
print "Uploading via SCP to $ssh_host ..\n";
$snames = "{".join(",", @upload)."}.pl*";
system("su $user -c 'scp $dir/$snames $dir/scripts.txt* ${ssh_user}\@${ssh_host}:${ssh_dir}/'");
if ($?) {
	print ".. SCP failed!\n";
	exit(4);
	}
print ".. done\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "SVN update, sign and SCP all script installers.\n";
print "\n";
print "usage: sign-script-installers.pl --dir svn-dir\n";
print "                                [--user svn-username]\n";
print "                                 --key gpg-key-name\n";
print "                                 --ssh-user ssh-login-name\n";
print "                                 --ssh-host ssh-server-name\n";
print "                                 --ssh-dir ssh-directory\n";
exit(1);
}

