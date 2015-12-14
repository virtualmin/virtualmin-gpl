# Functions for managing a virtual FTP server

$feature_depends{'ftp'} = [ 'dir' ];

sub require_proftpd
{
return if ($require_proftpd++);
&foreign_require("proftpd");
}

# setup_ftp(&domain)
# Setup a virtual FTP server for some domain
sub setup_ftp
{
local $tmpl = &get_template($_[0]->{'template'});
&$first_print($text{'setup_proftpd'});
&obtain_lock_ftp($_[0]);
&require_proftpd();

# Get the template
local @dirs = &proftpd_template($tmpl->{'ftp'}, $_[0]);

# Add the directives
local $conf = &proftpd::get_config();
local $l = $conf->[@$conf - 1];
local $addfile = $proftpd::config{'add_file'} || $l->{'file'};
local $lref = &read_file_lines($addfile);
local @lines = ( "<VirtualHost $_[0]->{'ip'}>" );
push(@lines, @dirs);
push(@lines, "</VirtualHost>");
push(@$lref, @lines);
&flush_file_lines($addfile);

# Create directory for FTP root
local ($fdir) = ($tmpl->{'ftp_dir'} || 'ftp');
local $ftp = "$_[0]->{'home'}/$fdir";
if (!-d $ftp) {
	&make_dir($ftp, 0755);
	&set_ownership_permissions($_[0]->{'uid'}, $_[0]->{'ugid'}, 0755, $ftp);
	}

&release_lock_ftp($_[0]);
&$second_print($text{'setup_done'});
&register_post_action(\&restart_proftpd);
undef(@proftpd::get_config_cache);

# Add the FTP server user to the domain's group, so that the directory
# can be accessed in anonymous mode
local $ftp_user = &get_proftpd_user($_[0]);
if ($ftp_user) {
	&add_user_to_domain_group($_[0], $ftp_user, 'setup_ftpuser');
	}
}

# delete_ftp(&domain)
# Delete the virtual server from the ProFTPd config
sub delete_ftp
{
&require_proftpd();
&$first_print($text{'delete_proftpd'});
&obtain_lock_ftp($_[0]);
local $conf = &proftpd::get_config();
local ($virt, $vconf) = &get_proftpd_virtual($_[0]->{'ip'});
if ($virt) {
	local $lref = &read_file_lines($virt->{'file'});
	splice(@$lref, $virt->{'line'}, $virt->{'eline'} - $virt->{'line'} + 1);
	&flush_file_lines();

	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_proftpd);
	undef(@proftpd::get_config_cache);
	}
else {
	&$second_print($text{'delete_noproftpd'});
	}
&release_lock_ftp($_[0]);
}

# clone_ftp(&domain, &old-domain)
# Copy proftpd directives to a new cloned domain
sub clone_ftp
{
local ($d, $oldd) = @_;
&$first_print($text{'clone_ftp'});
&require_proftpd();
local $conf = &proftpd::get_config();
local ($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($d->{'ip'});
local ($ovirt, $ovconf) = &get_proftpd_virtual($oldd->{'ip'});
if (!$ovirt) {
	&$second_print($text{'clone_ftpold'});
	return 0;
	}
if (!$virt) {
	&$second_print($text{'clone_ftpnew'});
	return 0;
	}
&obtain_lock_ftp($d);

# Splice across directives, fixing home
local $olref = &read_file_lines($ovirt->{'file'});
local $lref = &read_file_lines($virt->{'file'});
local @lines = @$olref[$ovirt->{'line'}+1 .. $ovirt->{'eline'}-1];
foreach my $l (@lines) {
	$l =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/;
	}
splice(@$lref, $virt->{'line'}+1, $virt->{'eline'}-$virt->{'line'}-1, @lines);
&flush_file_lines($virt->{'file'});
($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($d->{'ip'});

# Fix server name
local $sname = &proftpd::find_directive_struct("ServerName", $vconf);
if ($sname) {
	&proftpd::save_directive("ServerName", [ $d->{'dom'} ], $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}

&release_lock_ftp($d);
&register_post_action(\&restart_proftpd);
&$second_print($text{'setup_done'});
return 1;
}

# modify_ftp(&domain, &olddomain)
# If the server has changed IP address, update the ProFTPd virtual server
sub modify_ftp
{
local $rv = 0;

if ($_[0]->{'dom'} eq $_[1]->{'dom'} &&
    $_[0]->{'home'} eq $_[1]->{'home'} &&
    $_[0]->{'ip'} eq $_[1]->{'ip'}) {
	# Nothing important has changed, so exit now
	return 1;
	}

&obtain_lock_ftp($_[0]);
&require_proftpd();
local $conf = &proftpd::get_config();
local ($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($_[1]->{'ip'});
if (!$virt) {
	&release_lock_ftp($_[0]);
	return 0;
	}
if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
	# Update domain name in ProFTPd virtual server
	&$first_print($text{'save_proftpd2'});
	local $sname = &proftpd::find_directive_struct("ServerName", $vconf);
	if ($sname) {
		&proftpd::save_directive(
			"ServerName", [ $_[0]->{'dom'} ], $vconf, $conf);
		}
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($_[0]->{'home'} ne $_[1]->{'home'} && $anon) {
	# Update anonymous FTP directory in ProFTPd virtual server
	&$first_print($text{'save_proftpd3'});
	local $lref = &read_file_lines($anon->{'file'});
	$lref->[$anon->{'line'}] =~ s/$_[1]->{'home'}/$_[0]->{'home'}/;
	&flush_file_lines($anon->{'file'});
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($_[0]->{'ip'} ne $_[1]->{'ip'}) {
	# Update IP address in ProFTPd virtual server
	&$first_print($text{'save_proftpd'});
	local $lref = &read_file_lines($virt->{'file'});
	$lref->[$virt->{'line'}] = "<VirtualHost $_[0]->{'ip'}>";
	&flush_file_lines();
	$rv++;
	&$second_print($text{'setup_done'});
	}
&release_lock_ftp($_[0]);
&register_post_action(\&restart_proftpd) if ($rv);
return $rv;
}

# validate_ftp(&domain)
# Returns an error message if a domain's ProFTPd virtual server is not found
sub validate_ftp
{
local ($d) = @_;
local ($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($d->{'ip'});
return &text('validate_eftp', $d->{'ip'}) if (!$virt);
return undef;
}

# disable_ftp(&domain)
# Disable FTP for this server by adding a deny directive
sub disable_ftp
{
&$first_print($text{'disable_proftpd'});
&obtain_lock_ftp($_[0]);
&require_proftpd();
local ($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($_[0]->{'ip'});
if ($anon) {
	local @limit = &proftpd::find_directive_struct("Limit", $aconf);
	local ($login) = grep { $_->{'words'}->[0] eq "LOGIN" } @limit;
	if (!$login) {
		local $lref = &read_file_lines($anon->{'file'});
		splice(@$lref, $anon->{'eline'}, 0,
		       "<Limit LOGIN>", "DenyAll", "</Limit>");
		&flush_file_lines();
		}
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_proftpd);
	}
else {
	&$second_print($text{'delete_noproftpd'});
	}
&release_lock_ftp($_[0]);
}

# enable_ftp(&domain)
# Enable FTP for this server by removing the deny directive
sub enable_ftp
{
&$first_print($text{'enable_proftpd'});
&obtain_lock_ftp($_[0]);
&require_proftpd();
local ($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($_[0]->{'ip'});
if ($virt) {
	local @limit = &proftpd::find_directive_struct("Limit", $aconf);
	local ($login) = grep { $_->{'words'}->[0] eq "LOGIN" } @limit;
	if ($login) {
		local $lref = &read_file_lines($anon->{'file'});
		splice(@$lref, $login->{'line'},
		       $login->{'eline'} - $login->{'line'} + 1);
		&flush_file_lines();
		}
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_proftpd);
	}
else {
	&$second_print($text{'delete_noproftpd'});
	}
&release_lock_ftp($_[0]);
}

# proftpd_template(text, &domain)
# Returns a suitably substituted ProFTPd template
sub proftpd_template
{
local $dirs = $_[0];
$dirs =~ s/\t/\n/g;
$dirs = &substitute_domain_template($dirs, $_[1]);
local @dirs = split(/\n/, $dirs);
return @dirs;
}

# check_proftpd_template([directives])
# Returns an error message if the default ProFTPd directives don't look valid
sub check_proftpd_template
{
local ($d, $gotuser, $gotgroup);
local @dirs = split(/\t+/, defined($_[0]) ? $_[0] : $config{'proftpd_config'});
foreach $d (@dirs) {
	$d =~ s/#.*$//;
	if ($d =~ /^\s*User\s+(\S+)$/i) {
		defined(getpwnam($1)) ||
		    $1 eq '$USER' || $1 eq '${USER}' ||
			return &text('fcheck_euserex', "<tt>$1</tt>");
		$gotuser++;
		}
	elsif ($d =~ /^\s*Group\s+(\S+)$/i) {
		defined(getgrnam($1)) ||
		    $1 eq '$GROUP' || $1 eq '${GROUP}' ||
			return &text('fcheck_egroupex', "<tt>$1</tt>");
		$gotgroup++;
		}
	}
$gotuser || return $text{'fcheck_euser'};
$gotgroup || return $text{'fcheck_egroup'};
return undef;
}

# restart_proftpd()
# Tell ProFTPd to re-read its config file. Does nothing if run from inetd
sub restart_proftpd
{
&require_proftpd();
local $conf = &proftpd::get_config();
local $st = &proftpd::find_directive("ServerType", $conf);
if (lc($st) ne "inetd") {
	# Call proftpd restart function
	&$first_print($text{'setup_proftpdpid'});
	local $proftpdlock = "$module_config_directory/proftpd-restart";
	&lock_file($proftpdlock);
	local $err = &proftpd::apply_configuration();
	&unlock_file($proftpdlock);
	&$second_print($err ? &text('setup_proftpdfailed', $err)
			    : $text{'setup_done'});
	return $err ? 0 : 1;
	}
}

# get_proftpd_virtual(ip)
# Returns the list of configuration directives and the directive for the
# virtual server itself for some domain
sub get_proftpd_virtual
{
&require_proftpd();
local $conf = &proftpd::get_config();
local $v;
foreach $v (&proftpd::find_directive_struct("VirtualHost", $conf)) {
	if ($v->{'words'}->[0] eq $_[0]) {
		# Found it! Looks for 
		local $a = &proftpd::find_directive_struct("Anonymous", $v->{'members'});
		if ($a) {
			return ($v, $v->{'members'}, $a, $a->{'members'});
			}
		else {
			return ($v, $v->{'members'});
			}
		}
	}
return ();
}

# check_ftp_clash(&domain, [field])
# Returns 1 if a ProFTPd server already exists for some domain
sub check_ftp_clash
{
if (!$_[1] || $_[1] eq 'ip') {
	local ($cvirt, $cconf) = &get_proftpd_virtual($_[0]->{'ip'});
	return $cvirt ? 1 : 0;
	}
return 0;
}

# backup_ftp(&domain, file)
# Save the virtual server's ProFTPd config as a separate file
sub backup_ftp
{
local ($d, $file) = @_;
&$first_print($text{'backup_proftpdcp'});
local ($virt, $vconf) = &get_proftpd_virtual($d->{'ip'});
if ($virt) {
	local $lref = &read_file_lines($virt->{'file'});
	&open_tempfile_as_domain_user($d, FILE, ">$file");
	foreach my $l (@$lref[$virt->{'line'} .. $virt->{'eline'}]) {
		&print_tempfile(FILE, "$l\n");
		}
	&close_tempfile_as_domain_user($d, FILE);
	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	&$second_print($text{'delete_noproftpd'});
	return 0;
	}
}

# restore_ftp(&domain, file)
# Update the virtual server's ProFTPd configuration from a file. Does not
# change the actual <Virtualhost> lines!
sub restore_ftp
{
&$first_print($text{'restore_proftpdcp'});
&obtain_lock_ftp($_[0]);
local ($virt, $vconf) = &get_proftpd_virtual($_[0]->{'ip'});
local $rv;
if ($virt) {
	local $srclref = &read_file_lines($_[1]);
	local $dstlref = &read_file_lines($virt->{'file'});
	splice(@$dstlref, $virt->{'line'}+1, $virt->{'eline'}-$virt->{'line'}-1,
	       @$srclref[1 .. @$srclref-2]);
	if ($_[5]->{'home'} && $_[5]->{'home'} ne $_[0]->{'home'}) {
		# Fix up any file-related directives
		local $i;
		foreach $i ($virt->{'line'} .. $virt->{'line'}+scalar(@$srclref)-1) {
			$dstlref->[$i] =~ s/$_[5]->{'home'}/$_[0]->{'home'}/g;
			}
		}
	&flush_file_lines();
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_proftpd);
	$rv = 1;
	}
else {
	&$second_print($text{'delete_noproftpd'});
	$rv = 0;
	}

&release_lock_ftp($_[0]);
return $rv;
}

# get_proftpd_log(ip)
# Given a virtual server IP, returns the path to its log file. If no IP is
# give, returns the global log file path.
sub get_proftpd_log
{
if (!&foreign_check("proftpd")) {
	return undef;
	}
&require_proftpd();
if ($_[0]) {
	# Find by IP
	local ($virt, $vconf) = &get_proftpd_virtual($_[0]);
	if ($virt) {
		return &proftpd::find_directive("ExtendedLog", $vconf) ||
		       &proftpd::find_directive("TransferLog", $vconf);
		}
	}
else {
	# Just return global log
	local $conf = &proftpd::get_config();
	local $global = &proftpd::find_directive_struct("Global", $conf);
	return &proftpd::find_directive("TransferLog", $global->{'members'}) ||
	       &proftpd::find_directive("ExtendedLog", $global->{'members'}) ||
	       &proftpd::find_directive("TransferLog", $conf) ||
	       &proftpd::find_directive("ExtendedLog", $conf) ||
	       "/var/log/xferlog";
	}
return undef;
}

# bandwidth_ftp(&domain, start, &bw-hash)
# Searches through FTP log files for records after some date, and updates the
# day counters in the given hash
sub bandwidth_ftp
{
local $log = &get_proftpd_log($_[0]->{'ip'});
if ($log) {
	return &count_ftp_bandwidth($log, $_[1], $_[2], undef, "ftp");
	}
else {
	return $_[1];
	}
}

# sysinfo_ftp()
# Returns the ProFTPd version
sub sysinfo_ftp
{
&require_proftpd();
$proftpd::site{'version'} ||= &proftpd::get_proftpd_version();
return ( [ $text{'sysinfo_proftpd'}, $proftpd::site{'version'} ] );
}

sub startstop_ftp
{
local ($typestatus) = @_;
&require_proftpd();
local $conf = &proftpd::get_config();
local $st = &proftpd::find_directive("ServerType", $conf);
if ($st eq 'inetd') {
	# Running under inetd
	return ( );
	}
local $status;
if (defined($typestatus->{'proftpd'})) {
	$status = $typestatus->{'proftpd'} == 1;
	}
else {
	$status = &proftpd::get_proftpd_pid();
	}
local @links = ( { 'link' => '/proftpd/',
		   'desc' => $text{'index_fmanage'},
	 	   'manage' => 1 } );
if ($status) {
	return ( { 'status' => 1,
		   'name' => $text{'index_fname'},
		   'desc' => $text{'index_fstop'},
		   'restartdesc' => $text{'index_frestart'},
		   'longdesc' => $text{'index_fstopdesc'},
		   'links' => \@links } );
	}
else {
	return ( { 'status' => 0,
		   'name' => $text{'index_fname'},
		   'desc' => $text{'index_fstart'},
		   'longdesc' => $text{'index_fstartdesc'},
		   'links' => \@links } );
	}
}

# Call proftpd module's stop function
sub stop_service_ftp
{
&require_proftpd();
return &proftpd::stop_proftpd();
}

sub start_service_ftp
{
&require_proftpd();
return &proftpd::start_proftpd();
}

# show_template_ftp(&tmpl)
# Outputs HTML for editing ProFTPd related template options
sub show_template_ftp
{
local ($tmpl) = @_;

# ProFTPd directives
local @ffields = ( "ftp", "ftp_dir", "ftp_dir_def" );
local $ndi = &none_def_input("ftp", $tmpl->{'ftp'}, $text{'tmpl_ftpbelow'}, 1,
			     0, undef, \@ffields);
print &ui_table_row(&hlink($text{'tmpl_ftp'}, "template_ftp"),
	$ndi."<br>\n".
	&ui_textarea("ftp", $tmpl->{'ftp'} eq "none" ? "" :
				join("\n", split(/\t/, $tmpl->{'ftp'})),
		     10, 60));

# Directory for anonymous FTP
print &ui_table_row(&hlink($text{'newftp_dir'}, "template_ftp_dir_def"),
	&ui_opt_textbox("ftp_dir", $tmpl->{'ftp_dir'}, 20,
			"$text{'default'} (<tt>ftp</tt>)",
			$text{'newftp_dir0'})."<br>".
	("&nbsp;" x 3).$text{'newftp_dir0suf'});
}

# parse_template_ftp(&tmpl)
# Updates ProFTPd related template options from %in
sub parse_template_ftp
{
local ($tmpl) = @_;

# Save FTP directives
$tmpl->{'ftp'} = &parse_none_def("ftp");
if ($in{"ftp_mode"} == 2) {
	local $err = &check_proftpd_template($in{'ftp'});
	&error($err) if ($err);
	if ($in{'ftp_dir_def'}) {
		delete($tmpl->{'ftp_dir'});
		}
	else {
		$in{'ftp_dir'} =~ /^\S+$/ && $in{'ftp_dir'} !~ /^\// &&
		    $in{'ftp_dir'} !~ /\.\./ || &error($text{'newftp_edir'});
		$tmpl->{'ftp_dir'} = $in{'ftp_dir'};
		}
	}
}

sub links_ftp
{
local ($d) = @_;
# Links to FTP log
local @rv;
local $lf = &get_proftpd_log($d->{'ip'});
if ($lf) {
	local $param = &master_admin() ? "file"
				       : "extra";
	push(@rv, { 'mod' => 'syslog',
		    'desc' => $text{'links_flog'},
		    'page' => "save_log.cgi?view=1&".
			      "$param=".&urlize($lf),
		    'cat' => 'logs',
		  });
	}
return @rv;
}

# get_proftpd_user(&domain)
# Returns the Unix user that anonymous FTP access is done as. This is just
# taken from the User line in the template directives.
sub get_proftpd_user
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local @dirs = &proftpd_template($tmpl->{'ftp'}, $d);
foreach my $l (@dirs) {
	if ($l =~ /^\s*User\s+(\S+)/) {
		return $1;
		}
	}
foreach my $u ("ftp", "anonymous") {
	return $u if (defined(getpwnam($u)));
	}
return undef;
}

# Returns 1 if we can configure FTP chroot directories. Assume yes if proftpd
# is being used
sub has_ftp_chroot
{
return $config{'ftp'};
}

# list_ftp_chroots()
# Returns a list of chroot directories. Each is a hash ref with keys :
#  group - A group to restrict, or undef for all
#  neg - Negative if to apply to everyone except that group
#  dir - The chroot directory, or ~ for users' homes
sub list_ftp_chroots
{
local @rv;
&require_proftpd();
local $conf = &proftpd::get_config();
$proftpd::conf = $conf;		# get_or_create is broken in Webmin 1.410
local $gconf = &proftpd::get_or_create_global($conf);
foreach my $dr (&proftpd::find_directive_struct("DefaultRoot", $gconf)) {
	local $chroot = { 'dr' => $dr,
			  'dir' => $dr->{'words'}->[0] };
	if ($dr->{'words'}->[1] eq '') {
		# Applies to all groups
		}
	elsif ($dr->{'words'}->[1] =~ /,/) {
		# Applies to many .. too complex to support
		next;
		}
	elsif ($dr->{'words'}->[1] =~ /^(\!?)(\S+)$/) {
		$chroot->{'neg'} = $1;
		$chroot->{'group'} = $2;
		}
	push(@rv, $chroot);
	}
return @rv;
}

# save_ftp_chroots(&chroots)
# Updates the list of chroot'd directories. 
sub save_ftp_chroots
{
local ($chroots) = @_;
&require_proftpd();
local $conf = &proftpd::get_config();
$proftpd::conf = $conf;
local $gconf = &proftpd::get_or_create_global($conf);

# Find old directives that we can't configure yet
local @old = &proftpd::find_directive_struct("DefaultRoot", $gconf);
local @keep = grep { $_->{'words'}->[1] =~ /,/ } @old;
local @newv = map { $_->{'value'} } @keep;

# Add new ones
foreach my $chroot (@$chroots) {
	local @w = ( $chroot->{'dir'} );
	if ($chroot->{'group'}) {
		push(@w, ($chroot->{'neg'} ? "!" : "").$chroot->{'group'});
		}
	push(@newv, join(" ", @w));
	}
&proftpd::save_directive("DefaultRoot", \@newv, $gconf, $conf);
&flush_file_lines();

&register_post_action(\&restart_proftpd);
}

# Lock the ProFTPd config file
sub obtain_lock_ftp
{
return if (!$config{'ftp'});
&obtain_lock_anything();
if ($main::got_lock_ftp == 0) {
	&require_proftpd();
	&lock_file($proftpd::config{'proftpd_conf'});
	&lock_file($proftpd::config{'add_file'})
		if ($proftpd::config{'add_file'});
	undef(@proftpd::get_config_cache);
	}
$main::got_lock_ftp++;
}

# Unlock the ProFTPd config file
sub release_lock_ftp
{
return if (!$config{'ftp'});
if ($main::got_lock_ftp == 1) {
	&require_proftpd();
	&unlock_file($proftpd::config{'proftpd_conf'});
	&unlock_file($proftpd::config{'add_file'})
		if ($proftpd::config{'add_file'});
	}
$main::got_lock_ftp-- if ($main::got_lock_ftp);
&release_lock_anything();
}

$done_feature_script{'ftp'} = 1;

1;

