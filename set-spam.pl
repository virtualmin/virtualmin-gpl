#!/usr/local/bin/perl

=head1 set-spam.pl

Change the spam and virus scanners for all domains

By default, Virtualmin uses the stand-alone ClamAV and SpamAssassin programs
for virus and spam scanning, named C<clamscan> and C<spamassassin> respectively.
However, on a system that receives a large amount of email, running these
programs for each incoming message can generate significant CPU load.

This command can tell Virtualmin to use the background scanning daemons
C<clamd> and C<spamd> instead, which are faster but consume additional memory
as then run all the time. To enable the ClamAV server, run it like so :

  virtualmin set-spam --enable-clamd
  virtualmin set-spam --use-clamdscan

To enable and use the SpamAssassin daemon process, run the commands :

  virtualmin set-spam --enable-spamd
  virtualmin set-spam --use-spamc

However, using C<spamc> makes it impossible to have separate per-domain
SpamAssassin configurations in Virtualmin.

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
	$0 = "$pwd/set-spam.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "set-spam.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Get current config
($old_virus_scanner, $old_virus_host) = &get_global_virus_scanner();
($old_spam_client, $old_spam_host, $old_spam_max) = &get_global_spam_client();

$config{'spam'} || &usage("Spam filtering is not enabled for Virtualmin");
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a =~ /^--use-(spamc|spamassassin)$/) {
		$spam_client = $1;
		}
	elsif ($a eq "--spamc-host") {
		$spam_host = shift(@ARGV);
		}
	elsif ($a eq "--no-spamc-host") {
		$spam_host = "";
		}
	elsif ($a eq "--spamc-max" || $a eq "--spam-max") {
		$spam_max = shift(@ARGV);
		}
	elsif ($a eq "--no-spamc-max" || $a eq "--no-spam-max") {
		$spam_max = 0;
		}
	elsif ($a =~ /^--use-(clamscan|clamdscan|clamd-stream-client)$/) {
		$virus_scanner = $1;
		}
	elsif ($a eq "--use-virus") {
		$virus_scanner = shift(@ARGV);
		}
	elsif ($a eq "--clamd-host") {
		$virus_host = shift(@ARGV);
		}
	elsif ($a eq "--show") {
		$show = 1;
		}
	elsif ($a eq "--enable-clamd") {
		$clamd = 1;
		}
	elsif ($a eq "--disable-clamd") {
		$clamd = 0;
		}
	elsif ($a eq "--enable-spamd") {
		$spamd = 1;
		}
	elsif ($a eq "--disable-spamd") {
		$spamd = 0;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--quota-behavior") {
		$exitcode = shift(@ARGV);
		if ($exitcode eq "bounce") {
			$exitcode = 73;
			}
		elsif ($exitcode eq "queue") {
			$exitcode = 75;
			}
		elsif ($exitcode !~ /^\d+$/) {
			&usage("--quota-behavior must be followed by ".
			       "bounce, queue or a number");
			}
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate inputs
$virus_scanner || $virus_host || $spam_client || $show || defined($clamd) ||
  defined($spamd) || defined($spam_max) || $exitcode || &usage("Nothing to do");
if ($spam_client) {
	&has_command($spam_client) ||
	    &usage("SpamAssassin client program $spam_client does not exist");
	}

# Don't allow changing virus settings when provisioning is in use
defined($clamd) && $config{'provision_virus_host'} &&
	&usage("Clamd cannot be enabled or disabled when a Cloudmin Services ".
	       "virus scanning system is in use");
$virus_host && $config{'provision_virus_host'} &&
	&usage("The ClamAV server host cannot be changed when a Cloudmin ".
	       "Services virus scanning system is in use");
defined($spamd) && $config{'provision_spam_host'} &&
	&usage("Spamd cannot be enabled or disabled when a Cloudmin Services ".
	       "spam filtering system is in use");
defined($spam_host) && $config{'provision_spam_host'} &&
	&usage("The spam server host cannot be changed when a Cloudmin ".
	       "Services spam filtering system is in use");

# Work out new commands
$new_virus_scanner = defined($virus_scanner) ? $virus_scanner
					     : $old_virus_scanner;
$new_virus_host = defined($virus_host) ? $virus_host
				       : $old_virus_host;

# Make sure the new virus scanner works
if ($virus_scanner || $virus_host) {
	local ($cmd, @args) = &split_quoted_string($new_virus_scanner);
	&has_command($cmd) ||
		&usage("Virus scanning command $cmd does not exist");
	if (!$clamd || $new_virus_scanner ne "clamdscan") {
		# Only test if we aren't enabling clamd anyway
		$err = &test_virus_scanner($new_virus_scanner, $new_virus_host);
		$err && &usage("Virus scanner failed : $err");
		}
	}

# Make sure clamd can be enabled
if (defined($clamd)) {
	$cs = &check_clamd_status();
	$cs >= 0 || &usage("Virtualmin does not know how to enable clamd on ".
			   "your system");
	}

# Make sure spamd can be enabled
if (defined($spamd)) {
	$cs = &check_spamd_status();
	$cs >= 0 || &usage("Virtualmin does not know how to enable spamd on ".
			   "your system");
	}

&obtain_lock_spam_all();

if ($spam_client || $spam_host || defined($spam_max)) {
	print "Updating all virtual servers with new SpamAssassin client ..\n";
	$spam_client = $old_spam_client if (!defined($spam_client));
	$spam_host = $old_spam_host if (!defined($spam_host));
	$spam_max = $old_spam_max if (!defined($spam_max));
	&save_global_spam_client($spam_client, $spam_host, $spam_max);
	print ".. done\n\n";
	}

# Enable or disable clamd
if (defined($clamd)) {
	if ($clamd) {
		print "Configuring and enabling clamd ..\n";
		&$indent_print();
		&enable_clamd();
		&$outdent_print();
		}
	else {
		print "Disabling clamd ..\n";
		&$indent_print();
		&disable_clamd();
		&$outdent_print();
		}
	}

# Enable or disable spamd
if (defined($spamd)) {
	if ($spamd) {
		print "Configuring and enabling spamd ..\n";
		&$indent_print();
		&enable_spamd();
		&$outdent_print();
		}
	else {
		print "Disabling spamd ..\n";
		&$indent_print();
		&disable_spamd();
		&$outdent_print();
		}
	}

if ($virus_scanner) {
	print "Updating all virtual servers with new virus scanner ..\n";
	&save_global_virus_scanner($virus_scanner, $virus_host);
	print ".. done\n\n";
	}

# Change lookup-domain exit code
if ($exitcode) {
	print "Changing over-quota email behaviour ..\n";
	&save_global_quota_exitcode($exitcode);
	print ".. done\n\n";
	}

&release_lock_spam_all();

&modify_all_webmin();	# Spam setting may have changed
&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

if ($show) {
	# Show current settings
	if ($config{'spam'}) {
		($client, $host, $max) = &get_global_spam_client();
		print "SpamAssassin client: $client\n";
		if ($host) {
			print "SpamAssassin spamc host: $host\n";
			}
		if ($max) {
			print "SpamAssassin spamc maximum size: $max\n";
			}
		}
	if ($config{'virus'}) {
		($scanner) = &get_global_virus_scanner();
		print "Virus scanner: $scanner\n";
		}
	$exitcode = &get_global_quota_exitcode();
	print "Over-quota behavior: ",
	      ($exitcode == 73 ? "Bounce" :
	       $exitcode == 75 ? "Queue" : $exitcode),"\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes the spam and virus scanning programs for all domains.\n";
print "\n";
print "virtualmin set-spam [--use-spamassassin | --use-spamc]\n";
print "                    [--spamc-host hostname | --no-spamc-host]\n";
print "                    [--spam-max bytes | --no-spam-max]\n";
print "                    [--use-clamscan | --use-clamdscan |\n";
print "                     --use-clamd-stream-client | --use-virus command]\n";
print "                    [--clamd-host hostname]\n";
if (&check_clamd_status() >= 0) {
	print "                    [--enable-clamd | --disable-clamd]\n";
	}
if (&check_spamd_status() >= 0) {
	print "                    [--enable-spamd | --disable-spamd]\n";
	}
print "                    [--quota-behavior \"queue\"|\"bounce\"]\n";
print "                    [--show]\n";
exit(1);
}

