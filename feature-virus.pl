# Functions for turning Virus filtering on or off on a per-domain basis

sub check_depends_virus
{
return !$_[0]->{'spam'} ? $text{'setup_edepvirus'} : undef;
}

sub init_virus
{
$clam_wrapper_cmd = "$module_config_directory/clam-wrapper.pl";
$clamdscan_remote_wrapper_cmd = "$module_config_directory/clamdscan-remote-wrapper.pl";
}

# setup_virus(&domain)
# Adds an entry to the procmail file for this domain to call clamscan too
sub setup_virus
{
&$first_print($text{'setup_virus'});
&obtain_lock_virus($_[0]);
&require_spam();

local $spamrc = "$procmail_spam_dir/$_[0]->{'id'}";

# Find the clamscan recipe
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
if (@clamrec) {
	# Already there?
	&$second_print($text{'setup_virusalready'});
	}
else {
	# Copy the wrapper program
	&copy_clam_wrapper();

	# Add the recipe
	local $recipe0 = { 'flags' => [ 'c', 'w' ],
			   'type' => '|',
			   'action' => $clam_wrapper_cmd." ".
				       &full_clamscan_path() };
	local $varon = { 'name' => 'VIRUSMODE', 'value' => 1 };
	local $recipe1 = { 'flags' => [ 'e' ],
			   'action' => $config{'clam_delivery'} };
	local $varoff = { 'name' => 'VIRUSMODE', 'value' => 0 };
	if (@recipes > 1) {
		&procmail::create_recipe_before($recipe0, $recipes[1], $spamrc);
		&procmail::create_recipe_before($varon, $recipes[1], $spamrc);
		&procmail::create_recipe_before($recipe1, $recipes[1], $spamrc);
		&procmail::create_recipe_before($varoff, $recipes[1], $spamrc);
		}
	else {
		&procmail::create_recipe($recipe0, $spamrc);
		&procmail::create_recipe($varon, $spamrc);
		&procmail::create_recipe($recipe1, $spamrc);
		&procmail::create_recipe($varoff, $spamrc);
		}
	&$second_print($text{'setup_done'});
	}
&release_lock_virus($_[0]);
return 1;
}

# modify_virus(&domain, &olddomain)
# Doesn't have to do anything
sub modify_virus
{
}

# delete_virus(&domain)
# Just remove the procmail entry that calls clamscan
sub delete_virus
{
local $spamrc = "$procmail_spam_dir/$_[0]->{'id'}";
if (!-r $spamrc && !$_[0]->{'spam'}) {
	# Spam already deleted, so the whole procmail file will have been
	# already removed. So do nothing!
	return 1;
	}
&$first_print($text{'delete_virus'});
&obtain_lock_virus($_[0]);
&require_spam();
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
if (@clamrec) {
	&procmail::delete_recipe($clamrec[1]);
	&procmail::delete_recipe($clamrec[0]);

	# Also take out VIRUSMODE variables
	@recipes = &procmail::parse_procmail_file($spamrc);
	foreach my $r (reverse(@recipes)) {
		if ($r->{'name'} eq 'VIRUSMODE') {
			&procmail::delete_recipe($r);
			}
		}
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'delete_virusnone'});
	}
&release_lock_virus($_[0]);
return 1;
}

# clone_virus(&domain, &old-domain)
# Does nothing, as cloning the spamassassin config clones virus settings too
sub clone_virus
{
return 1;
}

# copy_clam_wrapper()
# Copies the clamav wrapper script into place
sub copy_clam_wrapper
{
&copy_source_dest("$module_root_directory/clam-wrapper.pl", $clam_wrapper_cmd);
&set_ownership_permissions(undef, undef, 0755, $clam_wrapper_cmd);
}

# validate_virus(&domain)
# Make sure the domain's procmail config file calls ClamAV
sub validate_virus
{
local ($d) = @_;
&require_spam();
local $spamrc = "$procmail_spam_dir/$d->{'id'}";
return &text('validate_espamprocmail', "<tt>$spamrc</tt>") if (!-r $spamrc);
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
return &text('validate_evirus', "<tt>$spamrc</tt>") if (!@clamrec);
return undef;
}

# check_virus_clash()
# No need to check for clashes ..
sub check_virus_clash
{
return 0;
}

# find_clam_recipe(&recipes)
# Returns the two recipes used for virus filtering
sub find_clam_recipe
{
local $i;
for($i=0; $i<@{$_[0]}; $i++) {
	if ($_[0]->[$i]->{'action'} =~ /clam(d?)scan/ ||
	    $_[0]->[$i]->{'action'} =~ /\Q$clam_wrapper_cmd\E/) {
		# Found clamscan .. but is the next one OK?
		if ($_[0]->[$i+1]->{'flags'}->[0] eq 'e') {
			return ( $_[0]->[$i], $_[0]->[$i+1] );
			}
		elsif ($_[0]->[$i+2]->{'flags'}->[0] eq 'e') {
			return ( $_[0]->[$i], $_[0]->[$i+2] );
			}
		}
	}
return ( );
}

# sysinfo_virus()
# Returns the ClamAV version
sub sysinfo_virus
{
local $out = &backquote_command("$config{'clamscan_cmd'} -V 2>/dev/null", 1);
local $vers = $out =~ /ClamAV\s+([0-9\.]+)/i ? $1 : "Unknown";
return ( [ $text{'sysinfo_virus'}, $vers ] );
}

# Update the procmail scripts for all domains that call clamscan so that they
# call the wrapper instead
sub fix_clam_wrapper
{
&require_spam();
foreach my $d (grep { $_->{'virus'} } &list_domains()) {
	local $spamrc = "$procmail_spam_dir/$d->{'id'}";
	local @recipes = &procmail::parse_procmail_file($spamrc);
	local @clamrec = &find_clam_recipe(\@recipes);
	if ($clamrec[0]->{'action'} !~ /\Q$clam_wrapper_cmd\E/ &&
	    $clamrec[0]->{'action'} =~ /^(\S*clam(d?)scan)\s+\-$/) {
		$clamrec[0]->{'action'} = "$clam_wrapper_cmd $1";
		&procmail::modify_recipe($clamrec[0]);
		}
	}
}

# get_domain_virus_delivery(&domain)
# Returns the delivery mode and dest for some domain. The modes can be :
# 0 - Throw away , 1 - File under home , 2 - Forward to email , 3 - Other file,
# 4 - Normal ~/mail/virus file, 5 - Deliver normally , 6 - ~/Maildir/.virus/ ,
# -1 - Broken!
sub get_domain_virus_delivery
{
local ($d) = @_;
&require_spam();
local $spamrc = "$procmail_spam_dir/$d->{'id'}";
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
if (!@clamrec) {
	return (-1);
	}
elsif (!$clamrec[1]) {
	return (5);
	}
elsif ($clamrec[1]->{'action'} eq '/dev/null') {
	return (0);
	}
elsif ($clamrec[1]->{'action'} =~ /^\$HOME\/mail\/(virus|Virus)$/) {
	return (4, $1);
	}
elsif ($clamrec[1]->{'action'} =~ /^\$HOME\/Maildir\/.(virus|Virus)\/$/) {
	return (6, $1);
	}
elsif ($clamrec[1]->{'action'} =~ /^\$HOME\/(.*)$/) {
	return (1, $1);
	}
elsif ($clamrec[1]->{'action'} =~ /\@/) {
	return (2, $clamrec[1]->{'action'});
	}
else {
	return (3, $clamrec[1]->{'action'});
	}
}

# save_domain_virus_delivery(&domain, mode, dest)
# Updates the delivery method for viruses for some domain
sub save_domain_virus_delivery
{
local ($d, $mode, $dest) = @_;
&require_spam();
local $spamrc = "$procmail_spam_dir/$d->{'id'}";
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
return 0 if (!@clamrec);
local $r = $clamrec[1];

# Preserve existing settings if not set
local ($oldmode, $olddest) = &get_domain_virus_delivery($d);
if (!defined($mode)) {
	($mode, $dest) = ($oldmode, $olddest);
	}
elsif (!defined($dest)) {
	$dest = $olddest;
	}

# Work out folder name, defaulting to upper case
local $folder;
if ($mode == 4 || $mode == 6) {
	if ($dest =~ /^[a-z0-9\.\_\-]+$/i) {
		$folder = $dest;
		}
	else {
		$folder = "Virus";
		}
	}
$r->{'action'} = $mode == 0 ? "/dev/null" :
		 $mode == 4 ? "\$HOME/mail/$folder" :
		 $mode == 6 ? "\$HOME/Maildir/.$folder/" :
		 $mode == 1 ? "\$HOME/$dest" :
			      $dest;
$r->{'type'} = $mode == 2 ? "!" : "";
&procmail::modify_recipe($r);
return 1;
}

# full_clamscan_path()
# Returns the clamav scan command, using the full path plus any args
sub full_clamscan_path
{
local $prog = $config{'clamscan_cmd'};
if ($prog eq "clamd-stream-client") {
	$prog .= &make_stream_client_args($config{'clamscan_host'});
	}
elsif ($prog eq "clamdscan") {
	$prog .= &get_clamdscan_args();
	}
local ($cmd, @args) = &split_quoted_string($prog);
local $fullcmd = &has_command($cmd);
return undef if (!$fullcmd);
local @rv = ( $fullcmd, @args );
return join(" ", map { /\s/ ? "\"$_\"" : $_ } @rv);
}

# make_stream_client_args([host[:port]])
# Convert a hostname with possible port into an arg string
sub make_stream_client_args
{
my ($hostport) = @_;
my ($host, $port) = split(/:/, $hostport);
my $rv;
if ($host) {
	$rv .= " -d ".$host;
	if ($port) {
		$rv .= " -p ".$port;
		}
	}
return $rv;
}

# get_clamdscan_args()
# Returns any extra args needed for clamdscan, like for the config file
sub get_clamdscan_args
{
local $scanfile = "/etc/clamd.d/scan.conf";
&foreign_require("init");
if (-r $scanfile && (&init::action_status("clamd\@scan") ||
		     &init::action_status("clamd.scan"))) {
	return " --config-file ".$scanfile;
	}
return undef;
}

# get_domain_virus_scanner(&domain)
# Returns the virus scanning command use for some domain. This can be clamscan,
# clamdscan or some other path.
sub get_domain_virus_scanner
{
local ($d) = @_;
&require_spam();
local $spamrc = "$procmail_spam_dir/$d->{'id'}";
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
if (@clamrec) {
	local $rv = $clamrec[0]->{'action'};
	$rv =~ s/^\Q$clam_wrapper_cmd\E\s+//;
	local @rvs = &split_quoted_string($rv);
	if ($rvs[0] eq &has_command("clamscan")) {
		$rv = "clamscan";
		}
	elsif ($rvs[0] eq &has_command("clamdscan")) {
		$rv = "clamdscan";
		}
	elsif ($rvs[0] eq &has_command("clamd-stream-client")) {
		$rv = "clamd-stream-client";
		}
	elsif ($rvs[0] eq $clamdscan_remote_wrapper_cmd) {
		$rv = "clamdscan-remote";
		}
	return $rv;
	}
else {
	return undef;
	}
}

# save_domain_virus_scanner(&domain, program)
# Updates the virus scanning program in the procmail config
sub save_domain_virus_scanner
{
local ($d, $prog) = @_;
&require_spam();
local $spamrc = "$procmail_spam_dir/$d->{'id'}";
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
if (@clamrec) {
	if ($prog eq "clamscan") {
		$prog = &has_command("clamscan");
		}
	elsif ($prog eq "clamdscan") {
		$prog = &has_command("clamdscan");
		$prog .= &get_clamdscan_args();
		}
	elsif ($prog eq "clamd-stream-client") {
		$prog = &has_command("clamd-stream-client");
		$prog .= &make_stream_client_args($config{'clamscan_host'});
		}
	elsif ($prog eq "clamdscan-remote") {
		$prog = $clamdscan_remote_wrapper_cmd;
		$prog .= &make_stream_client_args($config{'clamscan_host'});
		if (!-r $clamdscan_remote_wrapper_cmd) {
			&create_clamdscan_remote_wrapper_cmd();
			}
		}
	$clamrec[0]->{'action'} = "$clam_wrapper_cmd $prog";
	&procmail::modify_recipe($clamrec[0]);
	}
}

# create_clamdscan_remote_wrapper_cmd()
# Create a command to call clamdscan with a remote target in the /etc dir
sub create_clamdscan_remote_wrapper_cmd
{
&copy_source_dest("$module_root_directory/clamdscan-remote-wrapper.pl",
		  $clamdscan_remote_wrapper_cmd);
}

# get_global_virus_scanner()
# Returns the virus scanning program used by all domains, and possibly also
# the clamd hostname
sub get_global_virus_scanner
{
if ($config{'clamscan_cmd_global'}) {
	# We know it from the module config
	return ($config{'clamscan_cmd'}, $config{'clamscan_host'});
	}
else {
	# Find the most used one for all domains
	local (%cmdcount, $maxcmd);
	foreach my $d (grep { $_->{'virus'} } &list_domains()) {
		local $cmd = &get_domain_virus_scanner($d);
		if ($cmd) {
			$cmdcount{$cmd}++;
			if (!$maxcmd || $cmdcount{$cmd} > $cmdcount{$maxcmd}) {
				$maxcmd = $cmd;
				}
			}
		}
	return ($maxcmd || $config{'clamscan_cmd'}, undef);
	}
}

# save_global_virus_scanner(command, scanner-host)
# Update all domains to use a new scanning command
sub save_global_virus_scanner
{
local ($cmd, $host) = @_;
$config{'clamscan_cmd'} = $cmd;
$config{'clamscan_cmd_global'} = 1;
$config{'clamscan_host'} = $host;
$config{'last_check'} = time()+1;
&save_module_config();
foreach my $d (grep { $_->{'virus'} } &list_domains()) {
	&save_domain_virus_scanner($d, $cmd);
	}
}

# test_virus_scanner(command, [host])
# Tests some virus scanning command. Returns an error message on failure, undef
# on success. If clamscan takes more than 10 seconds, this typically assumes
# that it is working but slow.
sub test_virus_scanner
{
local ($cmd, $host) = @_;
local $fullcmd = $cmd;
if ($cmd eq "clamd-stream-client") {
	# Set remote host
	$fullcmd .= &make_stream_client_args($host);
	}
elsif ($cmd eq "clamdscan-remote") {
	# Use actual wrapper and set remote host
	$fullcmd = $clamdscan_remote_wrapper_cmd." ".
		   &make_stream_client_args($host);
	}
else {
	# Tell command to use stdin
	if ($cmd eq "clamdscan") {
		$fullcmd .= &get_clamdscan_args();
		}
	$fullcmd .= " -";
	}
local ($out, $timed_out) =
	&backquote_with_timeout("$fullcmd </dev/null 2>&1", 10, 1);
if ($timed_out) {
	return undef;
	}
elsif ($?) {
	return "<pre>".&html_escape($out)."</pre>";
	}
elsif ($cmd ne "clamd-stream-client" && $out !~ /OK/) {
	return $text{'sv_etestok'};
	}
else {
	return undef;
	}
}

# check_clamd_status()
# Checks if clamd is configured and running on this system. Returns 0 if not,
# 1 if yes, or -1 if we can't tell (due to a non-supported OS).
sub check_clamd_status
{
local %avahi_pids = map { $_, 1 }
			grep { $_ != $$ } &find_byname("avahi-daemon");
local @pids = grep { $_ != $$ && !$avahi_pids{$_} } &find_byname("clamd");
if (@pids) {
	# Running already, so we assume everything is cool
	return 1;
	}
local $clamd = &has_command("clamd") ||
	       &has_command("/opt/csw/sbin/clamd");
if (!$clamd) {
	# No installed
	return -1;
	}
&foreign_require("init");
if (&init::action_status("clamdscan-clamd")) {
	return 0;	# Joe's init script for redhat
	}
elsif (&init::action_status("clamd\@scan")) {
	return 0;	# EPEL 7/Fedora 20 clamav-scanner package
	}
elsif (&init::action_status("clamav-daemon")) {
	return 0;	# Ubuntu
	}
elsif (&init::action_status("clamd-wrapper") ||
       &init::action_status("clamd-virtualmin")) {
	return 0;	# Redhat, not setup yet
	}
elsif (&init::action_status("clamd")) {
	return 0;	# RHEL 6+, not setup yet
	}
elsif (&init::action_status("clamav-clamd")) {
	return 0;	# FreeBSD
	}
elsif (-r "/opt/csw/etc/clamd.conf.CSW") {
	return 0;	# Solaris CSW package
	}
return -1;
}

# enable_clamd()
# Do everything needed to configure and start clamd. May print stuff with the
# standard functions.
sub enable_clamd
{
local $st = &check_clamd_status();
return 1 if ($st == 1 || $st == -1);

# Check for simple init scripts
local $init;
&foreign_require("init");
foreach my $i ("clamav-daemon", "clamdscan-clamd", "clamav-clamd", "clamd", "clamd\@scan") {
	if (&init::action_status($i)) {
		$init = $i;
		last;
		}
	}

# Make sure socket file is valid in config
foreach my $c ("/etc/clamd.conf", "/etc/clamd.d/scan.conf",
	       "/etc/clamd.d/virtualmin.conf") {
	next if (!-r $c);
	local $lref = &read_file_lines($c);
	local $sfile;
	local $clamuser;
	local $added_socketmode = 0;
	foreach my $l (@$lref) {
		if ($l =~ /^\s*LocalSocket\s+(\S+)/) {
			$sfile = $1;
			}
		elsif ($l =~ /^\s*LocalSocketMode\s+/) {
			$l = "LocalSocketMode 666";
			$added_socketmode++;
			}
		elsif ($l =~ /^\s*User\s+(\S+)/) {
			$clamuser = $1;
			}
		}
	if (!$added_socketmode) {
		push(@$lref, "LocalSocketMode 666");
		}
	&flush_file_lines($c);
	if ($sfile =~ /^(\S+)\/([^\/]+)$/) {
		local $sdir = $1;
		if (!-d $sdir) {
			if ($clamuser) {
				&make_dir($sdir, 0755);
				&set_ownership_permissions($clamuser, undef,
							   0755, $sdir);
				}
			else {
				&make_dir($sdir, 0777);
				}
			}
		else {
			&set_ownership_permissions(undef, undef, 0755, $sdir);
			}
		}
	&set_ownership_permissions(undef, undef, 0666, $sfile);
	}

if ($init) {
	# Ubuntu, Joe's or FreeBSD .. all we have to do is enable and
	# start the daemon!
	&$first_print(&text('clamd_start'));
	&init::enable_at_boot($init);
	local ($ok, $out) = &init::start_action($init);
	if (!$ok || $out =~ /failed|error/i) {
		&$second_print(&text('clamd_estart',
				"<tt>".&html_escape($out)."</tt>"));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

elsif (&init::action_status("clamd-wrapper")) {
        # Looks like a Redhat system .. start by creating the .conf file
	local $service = "virtualmin";
	local $cfile = "/etc/clamd.d/$service.conf";
	local $srcpat = "/usr/share/doc/clamav-server-*/clamd.conf";
	local ($srcfile) = glob($srcpat);
	&$first_print(&text('clamd_copyconf', "<tt>$cfile</tt>"));
	if (!$srcfile && !-r $cfile) {
		&$second_print(&text('clamd_esrcfile', "<tt>$srcpat</tt>"));
		return 0;
		}
	local $user = "nobody";
	local @uinfo = getgrnam($user);
	local $group = getgrgid($uinfo[3]);
	&lock_file($cfile);
	if (!-r $cfile) {
		&copy_source_dest($srcfile, $cfile);
		}
	local $lref = &read_file_lines($cfile);
	local ($logfile, $socketfile);
	foreach my $l (@$lref) {
		if ($l =~ /^\s*Example/) {
			$l = "# Example";
			}
		$l =~ s/<SERVICE>/$service/g;
		$l =~ s/<USER>/$user/g;
		$l =~ s/<GROUP>/$group/g;
		if ($l =~ /^#+\s*LogFile\s+(\/\S+)/) {
			$l = "LogFile $1";
			$logfile = $1;
			}
		if ($l =~ /^#+\s*LocalSocket\s+(\S+)/) {
			$l = "LocalSocket $1";
			}
		if ($l =~ /^LocalSocket\s+(\S+)/) {
			$socketfile = $1;
			}
		}
	&flush_file_lines($cfile);
	&unlock_file($cfile);
	local $othercfile = "/etc/clamd.conf";
	if (!-r $othercfile) {
		&symlink_logged($cfile, $othercfile);
		}
	&$second_print($text{'setup_done'});

	# Create empty log
	if ($logfile && !-r $logfile) {
		&open_tempfile(LOG, ">$logfile", 0, 1);
		&close_tempfile(LOG);
		&set_ownership_permissions($user, $group, 0755, $logfile);
		}

	# Create directory for socket file
	if ($socketfile) {
		local $socketdir = $socketfile;
		$socketdir =~ s/\/[^\/]+$//;
		if (!-d $socketdir) {
			&make_dir($socketdir, 0755);
			&set_ownership_permissions($user, $group, 0755,
						   $socketdir);
			}
		}

	# Copy and fix the init wrapper script
	local $srcifile = &init::action_filename("clamd-wrapper");
	local $ifile = &init::action_filename("clamd-virtualmin");
	&$first_print(&text('clamd_initscript', "<tt>$ifile</tt>"));
	if (-r $srcifile && !-r $ifile) {
		&copy_source_dest($srcifile, $ifile);
		}
	local $lref = &read_file_lines($ifile);
	local ($already) = grep { /^CLAMD_SERVICE=/ } @$lref;
	if ($already) {
		&$second_print($text{'clamd_initalready'});
		}
	else {
		&lock_file($ifile);
		for(my $i=0; $i<@$lref; $i++) {
			if ($lref->[$i] =~ /^\#\s*Xchkconfig:\s+\-\s+(\d+)\s+(\d+)/) {
				# Fix chkconfig line
				$lref->[$i] = "# chkconfig: 2345 $1 $2";
				}
			elsif ($lref->[$i] =~ /^\#\s*Xdescription:(.*)/) {
				# Fix description line
				$lref->[$i] = "# description:$1";
				}
			elsif ($lref->[$i] !~ /^#/) {
				# Specify service name at top of file
				splice(@$lref, $i, 0, "CLAMD_SERVICE=$service");
				last;
				}
			}
		&flush_file_lines($ifile);
		&set_ownership_permissions(undef, undef, 0755, $ifile);
		&unlock_file($ifile);
		&$second_print($text{'setup_done'});
		}

	# Link the clamd program
	local $clamd = &has_command("clamd");
	local $clamdcopy = $clamd.".".$service;
	&$first_print(&text('clamd_linkbin', "<tt>$clamdcopy</tt>"));
	&unlink_file($clamdcopy);
	&symlink_logged($clamd, $clamdcopy);
	&$second_print($text{'setup_done'});

	# Create the socket directory
	if (-d "/var/run/clamd.$service") {
		&make_dir("/var/run/clamd.$service", 0777);
		}

	# Start the daemon, and enable at boot
	&$first_print(&text('clamd_start'));
	&init::enable_at_boot("clamd-virtualmin");
	&init::disable_at_boot("clamd-wrapper");
	local ($ok, $out);
	if (defined(&init::start_action)) {
		($ok, $out) = &init::start_action($init);
		}
	else {
		$out = &backquote_logged("$ifile start 2>&1");
		$ok = !$?;
		}
	if (!$ok || $out =~ /failed|error/i) {
		&$second_print(&text('clamd_estart',
				"<tt>".&html_escape($out)."</tt>"));
		}
	else {
		&$second_print($text{'setup_done'});
		}
        }

elsif (-r "/opt/csw/etc/clamd.conf.CSW") {
	# Solaris CSW package .. copy config file
	local $cfile = "/opt/csw/etc/clamd.conf";
	local $srcfile = "/opt/csw/etc/clamd.conf.CSW";
	&$first_print(&text('clamd_copyconf', "<tt>$cfile</tt>"));
	if (-r $cfile) {
		&$second_print($text{'clamd_esrcalready'});
		}
	else {
		&copy_source_dest($srcfile, $cfile);
		&$second_print($text{'setup_done'});
		}

	# Create the log directory
	&$first_print($text{'clamd_logdir'});
	local $lref = &read_file_lines($cfile);
	local ($logfile, $user);
	foreach my $l (@$lref) {
		if ($l =~ /^\s*LogFile\s+(\S+)/i) {
			$logfile = $1;
			}
		elsif ($l =~ /^\s*User\s+(\S+)/i) {
			$user = $1;
			}
		}
	if (-r $logfile) {
		&$second_print($text{'clamd_logalready'});
		}
	elsif ($logfile) {
		local $logdir = $logfile;
		$logdir =~ s/\/[^\/]+$//;
		&make_dir($logdir, 0700);
		if ($user) {
			&set_ownership_permissions($user, undef, undef,$logdir);
			}
		else {
			&set_ownership_permissions(undef, undef, 0777, $logdir);
			}
		&$second_print(&text('clamd_logdone', "<tt>$logdir</tt>"));
		}
	else {
		&$second_print($text{'clamd_lognone'});
		}

	# Create or enable bootup action
	&$first_print(&text('clamd_start'));
	local $init = "clamd-csw";
	local $clamd = &has_command("clamd") ||
		       &has_command("/opt/csw/sbin/clamd");
	&init::enable_at_boot($init, "Start ClamAV server",
			      $clamd,
			      "ps -ef | grep clamd | grep -v grep | grep -v \$\$ | awk '{ print \$2 }' | xargs kill");
	local $ifile = &init::action_filename($init);
	local $out = &backquote_logged("$ifile start 2>&1");
	if ($? || $out =~ /failed|error/i) {
		&$second_print(&text('clamd_estart',
				"<tt>".&html_escape($out)."</tt>"));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}

return 1;
}

# disable_clamd()
# Shut down the clamd process and disable at boot. May also print stuff.
sub disable_clamd
{
&foreign_require("init");
foreach my $init ("clamdscan-clamd", "clamav-daemon", "clamd-virtualmin",
		  "clamd-wrapper", "clamd-csw", "clamav-clamd", "clamd",
		  "clamd\@scan") {
	if (&init::action_status($init)) {
		&$first_print(&text('clamd_stop'));
		&init::disable_at_boot($init);
		local ($ok, $out) = &init::stop_action($init);
		if (!$ok || $out =~ /failed|error/i) {
			&$second_print(&text('clamd_estop',
					"<tt>".&html_escape($out)."</tt>"));
			return 0;
			}
		&$second_print($text{'setup_done'});
		return 1;
		}
	}
return 0;
}

# startstop_virus([&typestatus])
# Returns a hash containing the current status of the clamd server and short
# and long descriptions for the action to switch statuses
sub startstop_virus
{
local ($scanner, $host) = &get_global_virus_scanner();
if (!($scanner eq 'clamdscan' ||
      $scanner eq 'clamd-stream-client' && !$host)) {
	# Clamd isn't being used
	return ( );
	}
local @pids = grep { $_ != $$ } &find_byname("clamd");
if (@pids) {
	return ( { 'status' => 1,
		   'name' => $text{'index_clamname'},
		   'desc' => $text{'index_clamstop'},
		   'restartdesc' => $text{'index_clamrestart'},
		   'longdesc' => $text{'index_clamstopdesc'} } );
	}
else {
	return ( { 'status' => 0,
		   'name' => $text{'index_clamname'},
		   'desc' => $text{'index_clamstart'},
		   'longdesc' => $text{'index_clamstartdesc'} } );
	}
}

# start_service_virus()
# Attempts to start the clamd server, returning undef on success or any error
# message on failure.
sub start_service_virus
{
&push_all_print();
&set_all_null_print();
local $rv = &enable_clamd();
&pop_all_print();
return $rv ? undef : $text{'clamd_estartmsg'};
}

# stop_service_virus()
# Attempts to stop the clamd server, returning undef on success or any error
# message on failure.
sub stop_service_virus
{
&foreign_require("init");
foreach my $init ("clamdscan-clamd", "clamav-daemon", "clamd-virtualmin",
		  "clamd-wrapper", "clamd-csw", "clamav-clamd", "clamd",
		  "clamd\@scan") {
	if (&init::action_status($init)) {
		local ($ok, $out) = &init::stop_action($init);
		return $ok ? undef : "<tt>".&html_escape($out)."</tt>";
		}
	}
local @pids = grep { $_ != $$ } &find_byname("clamd");
if (@pids) {
	if (&kill_logged('TERM', @pids)) {
		return undef;
		}
	return &text('clamd_ekillmsg', $!);
	}
else {
	return $text{'clamd_estopmsg'};
	}
}

# Virus config files are the same as spam
sub obtain_lock_virus
{
&obtain_lock_spam(@_);
}

# Virus config files are the same as spam
sub release_lock_virus
{
&release_lock_spam(@_);
}

$done_feature_script{'virus'} = 1;

1;

