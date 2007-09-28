# Functions for turning Virus filtering on or off on a per-domain basis

sub check_depends_virus
{
return !$_[0]->{'spam'} ? $text{'setup_edepvirus'} : undef;
}

sub init_virus
{
$clam_wrapper_cmd = "$module_config_directory/clam-wrapper.pl";
}

# setup_virus(&domain)
# Adds an entry to the procmail file for this domain to call clamscan too
sub setup_virus
{
&$first_print($text{'setup_virus'});
&require_spam();

local $spamrc = "$procmail_spam_dir/$_[0]->{'id'}";
&lock_file($spamrc);

# Find the clamscan recipe
local @recipes = &procmail::parse_procmail_file($spamrc);
local @clamrec = &find_clam_recipe(\@recipes);
if (@clamrec) {
	# Already there?
	&$second_print($text{'setup_virusalready'});
	}
else {
	# Copy the wrapper program
	&copy_source_dest("$module_root_directory/clam-wrapper.pl", $clam_wrapper_cmd);
	&set_ownership_permissions(undef, undef, 0755, $clam_wrapper_cmd);

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
	&unlock_file($spamrc);
	&$second_print($text{'setup_done'});
	}
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
&require_spam();
&lock_file($spamrc);
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
&unlock_file($spamrc);
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
local $out = &backquote_command("$config{'clamscan_cmd'} -V", 1);
local $vers = $out =~ /ClamAV\s+([0-9\.]+)/i ? $1 : "Unknown";
return ( [ $text{'sysinfo_virus'}, $vers ] );
}

# Update the procmail scripts for all domains that call clamscan so that they
# call the wrapper instead
sub fix_clam_wrapper
{
&require_spam();
&copy_source_dest("$module_root_directory/clam-wrapper.pl", $clam_wrapper_cmd);
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
elsif ($clamrec[1]->{'action'} =~ /^\$HOME\/mail\/virus$/) {
	return (4);
	}
elsif ($clamrec[1]->{'action'} =~ /^\$HOME\/Maildir\/.virus\/$/) {
	return (6);
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
&lock_file($spamrc);
local $r = $clamrec[1];
$r->{'action'} = $mode == 0 ? "/dev/null" :
		 $mode == 4 ? "\$HOME/mail/virus" :
		 $mode == 6 ? "\$HOME/Maildir/.virus/" :
		 $mode == 1 ? "\$HOME/$dest" :
			      $dest;
$r->{'type'} = $mode == 2 ? "!" : "";
&procmail::modify_recipe($r);
&unlock_file($spamrc);
return 1;
}

# full_clamscan_path()
# Returns the clamav scan command, using the full path plus any args
sub full_clamscan_path
{
local ($cmd, @args) = &split_quoted_string($config{'clamscan_cmd'});
local $fullcmd = &has_command($cmd);
return undef if (!$fullcmd);
local @rv = ( $fullcmd, @args );
return join(" ", map { /\s/ ? "\"$_\"" : $_ } @rv);
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
	if ($rv eq &has_command("clamscan")) {
		$rv = "clamscan";
		}
	elsif ($rv eq &has_command("clamdscan")) {
		$rv = "clamdscan";
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
		}
	$clamrec[0]->{'action'} = "$clam_wrapper_cmd $prog";
	&procmail::modify_recipe($clamrec[0]);
	}
}

# get_global_virus_scanner()
# Returns the virus scanning program used by all domains
sub get_global_virus_scanner
{
if ($config{'clamscan_cmd_global'}) {
	# We know it from the module config
	return $config{'clamscan_cmd'};
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
	return $maxcmd || $config{'clamscan_cmd'};
	}
}

# save_global_virus_scanner(command)
# Update all domains to use a new scanning command
sub save_global_virus_scanner
{
local ($cmd) = @_;
$config{'clamscan_cmd'} = $cmd;
$config{'clamscan_cmd_global'} = 1;
$config{'last_check'} = time()+1;
&save_module_config();
foreach my $d (grep { $_->{'virus'} } &list_domains()) {
	&save_domain_virus_scanner($d, $cmd);
	}
}

# test_virus_scanner(command)
# Tests some virus scanning command. Returns an error message on failure, undef
# on success.
sub test_virus_scanner
{
local ($cmd) = @_;
local $out = `$cmd - </dev/null 2>&1`;
if ($?) {
	return "<pre>".&html_escape($out)."</pre>";
	}
elsif ($out !~ /OK/) {
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
if (&find_byname("clamd")) {
	# Running already, so we assume everything is cool
	return 1;
	}
if (!&has_command("clamd")) {
	# No installed
	return -1;
	}
&foreign_require("init", "init-lib.pl");
if (&init::action_status("clamd-wrapper")) {
	return 0;	# Redhat, not setup yet
	}
elsif (&init::action_status("clamav-daemon")) {
	return 0;	# Ubuntu
	}
# XXX
return -1;
}

# enable_clamd()
# Do everything needed to configure and start clamd. May print stuff with the
# standard functions.
sub enable_clamd
{
local $st = &check_clamd_status();
return if ($st == 1 || $st == -1);

&foreign_require("init", "init-lib.pl");
if (&init::action_status("clamd-wrapper")) {
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
	foreach my $l (@$lref) {
		if ($l =~ /^\s*Example/) {
			$l = "# Example";
			}
		$l =~ s/<SERVICE>/$service/g;
		$l =~ s/<USER>/$user/g;
		$l =~ s/<GROUP>/$group/g;
		}
	&flush_file_lines($cfile);
	&unlock_file($cfile);
	local $othercfile = "/etc/clamd.conf";
	if (!-r $othercfile) {
		&symlink_logged($cfile, $othercfile);
		}
	&$second_print($text{'setup_done'});

	# Fix the init wrapper script
	local $ifile = &init::action_filename("clamd-wrapper");
	&$first_print(&text('clamd_initscript', "<tt>$ifile</tt>"));
	local $lref = &read_file_lines($ifile);
	local ($already) = grep { /^CLAMD_SERVICE=/ } @$lref;
	if ($already) {
		&$second_print($text{'clamd_initalready'});
		}
	else {
		&lock_file($ifile);
		for(my $i=0; $i<@$lref; $i++) {
			if ($lref->[$i] !~ /^#/) {
				splice(@$lref, $i, 0, "CLAMD_SERVICE=$service");
				last;
				}
			}
		&flush_file_lines($ifile);
		&set_ownership_permissions(undef, undef, 0755, $ifile);
		&unlock_file($ifile);
		&$second_print($text{'setup_done'});
		}

	# Copy the clamd program
	local $clamd = &has_command("clamd");
	local $clamdcopy = $clamd.".".$service;
	if (!-r $clamdcopy) {
		&$first_print(&text('clamd_copybin', "<tt>$clamdcopy</tt>"));
		&copy_source_dest($clamd, $clamdcopy);
		&$second_print($text{'setup_done'});
		}

	# Create the socket directory
	if (-d "/var/run/clamd.$service") {
		&make_dir("/var/run/clamd.$service", 0777);
		}

	# Start the daemon, and enable at boot
	&$first_print(&text('clamd_start'));
	&init::enable_at_boot("clamd-wrapper");
	local $out = &backquote_logged("$ifile start 2>&1");
	if ($? || $out =~ /failed|error/i) {
		&$second_print(&text('clamd_estart',
				"<tt>".&html_escape($out)."</tt>"));
		}
	else {
		&$second_print($text{'setup_done'});
		}
        }

elsif (&init::action_status("clamav-daemon")) {
	# Ubuntu .. all we have to do is enable and start the daemon!
	&$first_print(&text('clamd_start'));
	local $ifile = &init::action_filename("clamav-daemon");
	&init::enable_at_boot("clamav-daemon");
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
# Shut down the clamd process. May also print stuff.
sub disable_clamd
{
&foreign_require("init", "init-lib.pl");
foreach my $init ("clamd-wrapper", "clamav-daemon") {
	if (&init::action_status($init)) {
		&$first_print(&text('clamd_stop'));
		local $ifile = &init::action_filename($init);
		&init::enable_at_boot($init);
		local $out = &backquote_logged("$ifile stop 2>&1");
		if ($? || $out =~ /failed|error/i) {
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

$done_feature_script{'virus'} = 1;

1;

