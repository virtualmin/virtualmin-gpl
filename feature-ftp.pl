# Functions for managing a virtual FTP server

sub require_proftpd
{
return if ($require_proftpd++);
&foreign_require("proftpd");
}

# check_depends_ftp(&domain)
# Ensure that a domain with FTP enabled has a home directory and possibly a
# private IP
sub check_depends_ftp
{
my ($d) = @_;
if (!$d->{'dir'}) {
	return $text{'setup_edepftpdir'};
	}
if (!$d->{'virt'} && !&supports_namebased_ftp()) {
	return $text{'setup_edepftp'};
	}
return undef;
}

# feature_depends_ftp()
# Checks for dependencies for the FTP feature
sub feature_depends_ftp
{
# Feature has no explicit dependencies
return 1;
}

# setup_ftp(&domain)
# Setup a virtual FTP server for some domain
sub setup_ftp
{
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
&$first_print($text{'setup_proftpd'});
&obtain_lock_ftp($d);
&require_proftpd();

# Get the template
my @dirs = &proftpd_template($tmpl->{'ftp'}, $d);

# Add the directives
my $conf = &proftpd::get_config();
my $l = $conf->[@$conf - 1];
my $addfile = $proftpd::config{'add_file'} || $l->{'file'};
my $lref = &read_file_lines($addfile);
my @ips = &get_proftpd_virtualhost_ips($d);
my @lines = ( "<VirtualHost ".join(" ", @ips).">" );
push(@lines, @dirs);
push(@lines, "</VirtualHost>");
push(@$lref, @lines);
&flush_file_lines($addfile);

# Create directory for FTP root
my ($fdir) = ($tmpl->{'ftp_dir'} || 'ftp');
my $ftp = "$d->{'home'}/$fdir";
if (!-d $ftp) {
	&make_dir($ftp, 0755);
	&set_ownership_permissions($d->{'uid'}, $d->{'ugid'}, 0755, $ftp);
	}

&release_lock_ftp($d);
&$second_print($text{'setup_done'});
&register_post_action(\&restart_proftpd);
undef(@proftpd::get_config_cache);

# Add the FTP server user to the domain's group, so that the directory
# can be accessed in anonymous mode
my $ftp_user = &get_proftpd_user($d);
if ($ftp_user) {
	&add_user_to_domain_group($d, $ftp_user, 'setup_ftpuser');
	}
return 1;
}

# delete_ftp(&domain)
# Delete the virtual server from the ProFTPd config
sub delete_ftp
{
my ($d) = @_;
&require_proftpd();
&$first_print($text{'delete_proftpd'});
&obtain_lock_ftp($d);
my ($virt, $vconf, $conf) = &get_proftpd_virtual($d);
if ($virt) {
	my $lref = &read_file_lines($virt->{'file'});
	splice(@$lref, $virt->{'line'}, $virt->{'eline'} - $virt->{'line'} + 1);
	&flush_file_lines();

	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_proftpd);
	undef(@proftpd::get_config_cache);
	}
else {
	&$second_print($text{'delete_noproftpd'});
	}
&release_lock_ftp($d);
return 1;
}

# clone_ftp(&domain, &old-domain)
# Copy proftpd directives to a new cloned domain
sub clone_ftp
{
my ($d, $oldd) = @_;
&$first_print($text{'clone_ftp'});
&require_proftpd();
my ($virt, $vconf, $conf, $anon, $aconf) = &get_proftpd_virtual($d);
my ($ovirt, $ovconf) = &get_proftpd_virtual($oldd);
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
my $olref = &read_file_lines($ovirt->{'file'});
my $lref = &read_file_lines($virt->{'file'});
my @lines = @$olref[$ovirt->{'line'}+1 .. $ovirt->{'eline'}-1];
foreach my $l (@lines) {
	$l =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/;
	}
splice(@$lref, $virt->{'line'}+1, $virt->{'eline'}-$virt->{'line'}-1, @lines);
&flush_file_lines($virt->{'file'});
($virt, $vconf, $conf, $anon, $aconf) = &get_proftpd_virtual($d);

# Fix server name
my $sname = &proftpd::find_directive_struct("ServerName", $vconf);
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
my ($d, $oldd) = @_;
my $rv = 0;

if ($d->{'dom'} eq $oldd->{'dom'} &&
    $d->{'home'} eq $oldd->{'home'} &&
    $d->{'ip'} eq $oldd->{'ip'}) {
	# Nothing important has changed, so exit now
	return 1;
	}

&obtain_lock_ftp($d);
&require_proftpd();
my ($virt, $vconf, $conf, $anon, $aconf) = &get_proftpd_virtual($oldd);
if (!$virt) {
	&release_lock_ftp($d);
	return 0;
	}
if ($d->{'dom'} ne $oldd->{'dom'}) {
	# Update domain name in ProFTPd servername or alias
	&$first_print($text{'save_proftpd2'});
	my $sname = &proftpd::find_directive_struct("ServerName", $vconf);
	if ($sname) {
		&proftpd::save_directive(
			"ServerName", [ $d->{'dom'} ], $vconf, $conf);
		}
	my @sa = map { s/\Q$oldd->{'dom'}\E/$d->{'dom'}/g; $_ }
			&apache::find_directive("ServerAlias", $vconf);
	&proftpd::save_directive("ServerAlias", \@sa, $vconf, $conf);
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($d->{'home'} ne $oldd->{'home'} && $anon) {
	# Update anonymous FTP directory in ProFTPd virtual server
	&$first_print($text{'save_proftpd3'});
	my $lref = &read_file_lines($anon->{'file'});
	$lref->[$anon->{'line'}] =~ s/$oldd->{'home'}/$d->{'home'}/;
	&flush_file_lines($anon->{'file'});
	$rv++;
	&$second_print($text{'setup_done'});
	}
if ($d->{'ip'} ne $oldd->{'ip'} || $d->{'ip6'} ne $oldd->{'ip6'} ||
    $d->{'dom'} ne $oldd->{'dom'}) {
	# Update IP address in ProFTPd virtualhost
	&$first_print($text{'save_proftpd'});
	my $lref = &read_file_lines($virt->{'file'});
	my @ips = &get_proftpd_virtualhost_ips($d);
	$lref->[$virt->{'line'}] = "<VirtualHost ".join(" ", @ips).">";
	&flush_file_lines();
	$rv++;
	&$second_print($text{'setup_done'});
	}
&release_lock_ftp($d);
&register_post_action(\&restart_proftpd) if ($rv);
return $rv;
}

# validate_ftp(&domain)
# Returns an error message if a domain's ProFTPd virtual server is not found
sub validate_ftp
{
my ($d) = @_;
my ($virt, $vconf, $conf, $anon, $aconf) = &get_proftpd_virtual($d);
return &text('validate_eftp', $d->{'ip'}) if (!$virt);
return undef;
}

# disable_ftp(&domain)
# Disable FTP for this server by adding a deny directive
sub disable_ftp
{
my ($d) = @_;
&$first_print($text{'disable_proftpd'});
&obtain_lock_ftp($d);
&require_proftpd();
my $ok;
my ($virt, $vconf, $conf, $anon, $aconf) = &get_proftpd_virtual($d);
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
	$ok = 1;
	}
else {
	&$second_print($text{'delete_noproftpd'});
	$ok = 0;
	}
&release_lock_ftp($d);
return $ok;
}

# enable_ftp(&domain)
# Enable FTP for this server by removing the deny directive
sub enable_ftp
{
my ($d) = @_;
&$first_print($text{'enable_proftpd'});
&obtain_lock_ftp($d);
&require_proftpd();
my ($virt, $vconf, $conf, $anon, $aconf) = &get_proftpd_virtual($d);
my $ok;
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
	$ok = 1;
	}
else {
	&$second_print($text{'delete_noproftpd'});
	$ok = 0;
	}
&release_lock_ftp($d);
return $ok;
}

# proftpd_template(text, &domain)
# Returns a suitably substituted ProFTPd template
sub proftpd_template
{
my ($dirs, $d) = @_;
$dirs =~ s/\t/\n/g;
$dirs = &substitute_domain_template($dirs, $d);
local @dirs = split(/\n/, $dirs);
return @dirs;
}

# check_proftpd_template([directives])
# Returns an error message if the default ProFTPd directives don't look valid
sub check_proftpd_template
{
my ($d, $gotuser, $gotgroup);
my @dirs = split(/\t+/, defined($_[0]) ? $_[0] : $config{'proftpd_config'});
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
my $conf = &proftpd::get_config();
my $st = &proftpd::find_directive("ServerType", $conf);
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

# get_proftpd_virtual(ip|&domain)
# Returns the list of configuration directives and the directive for the
# virtual server itself for some domain
sub get_proftpd_virtual
{
my ($ip) = @_;
my @match;
if (ref($ip)) {
	@match = ( $ip->{'ip'}, $ip->{'dom'} );
	}
else {
	@match = ( $ip );
	}
&require_proftpd();
my $conf = &proftpd::get_config();
foreach my $v (&proftpd::find_directive_struct("VirtualHost", $conf)) {
	if (&indexof($v->{'words'}->[0], @match) >= 0) {
		# Found it! Look for the anonymous block
		my @rv = ($v, $v->{'members'}, $conf);
		my $a = &proftpd::find_directive_struct(
				"Anonymous", $v->{'members'});
		if ($a) {
			push(@rv, $a, $a->{'members'});
			}
		return @rv;
		}
	}
return ();
}

# check_ftp_clash(&domain, [field])
# Returns 1 if a ProFTPd server already exists for some domain
sub check_ftp_clash
{
local ($d, $field) = @_;
if (!$field || $field eq 'ip') {
	local ($cvirt, $cconf) = &get_proftpd_virtual($d);
	return $cvirt ? 1 : 0;
	}
return 0;
}

# backup_ftp(&domain, file)
# Save the virtual server's ProFTPd config as a separate file
sub backup_ftp
{
my ($d, $file) = @_;
&$first_print($text{'backup_proftpdcp'});
my ($virt, $vconf) = &get_proftpd_virtual($d);
if ($virt) {
	my $lref = &read_file_lines($virt->{'file'});
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
my ($d, $file, $opts, $allopts, $homefmt, $oldd) = @_;
&$first_print($text{'restore_proftpdcp'});
&obtain_lock_ftp($d);
my ($virt, $vconf) = &get_proftpd_virtual($d);
my $rv;
if ($virt) {
	my $srclref = &read_file_lines($file);
	my $dstlref = &read_file_lines($virt->{'file'});
	splice(@$dstlref, $virt->{'line'}+1, $virt->{'eline'}-$virt->{'line'}-1,
	       @$srclref[1 .. @$srclref-2]);
	if ($oldd && $oldd->{'home'} && $oldd->{'home'} ne $d->{'home'}) {
		# Fix up any file-related directives
		foreach my $i ($virt->{'line'} .. $virt->{'line'}+scalar(@$srclref)-1) {
			$dstlref->[$i] =~ s/$oldd->{'home'}/$d->{'home'}/g;
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

&release_lock_ftp($d);
return $rv;
}

# get_proftpd_log([&domain])
# Given a virtual server IP, returns the path to its log file. If no IP is
# give, returns the global log file path.
sub get_proftpd_log
{
my ($d) = @_;
if (!&foreign_check("proftpd")) {
	return undef;
	}
&require_proftpd();
if ($d) {
	# Find by domain
	local ($virt, $vconf) = &get_proftpd_virtual($d);
	if ($virt) {
		return &proftpd::find_directive("ExtendedLog", $vconf) ||
		       &proftpd::find_directive("TransferLog", $vconf);
		}
	}
else {
	# Just return global log
	my $conf = &proftpd::get_config();
	my $global = &proftpd::find_directive_struct("Global", $conf);
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
my ($d, $start, $bwinfo) = @_;
my $log = &get_proftpd_log($d);
if ($log) {
	return &count_ftp_bandwidth($log, $start, $bwinfo, undef, "ftp");
	}
else {
	return $start;
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
my ($typestatus) = @_;
&require_proftpd();
my $conf = &proftpd::get_config();
my $st = &proftpd::find_directive("ServerType", $conf);
if ($st eq 'inetd') {
	# Running under inetd
	return ( );
	}
my $status;
if (defined($typestatus->{'proftpd'})) {
	$status = $typestatus->{'proftpd'} == 1;
	}
else {
	$status = &proftpd::get_proftpd_pid();
	}
my @links = ( { 'link' => '/proftpd/',
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
my ($tmpl) = @_;

# ProFTPd directives
my @ffields = ( "ftp", "ftp_dir", "ftp_dir_def" );
my $ndi = &none_def_input("ftp", $tmpl->{'ftp'}, $text{'tmpl_ftpbelow'}, 1,
			  0, undef, \@ffields);
print &ui_table_row(&hlink($text{'tmpl_ftp'}, "template_ftp"),
	$ndi."\n".
	&ui_textarea("ftp", $tmpl->{'ftp'} eq "none" ? "" :
				join("\n", split(/\t/, $tmpl->{'ftp'})),
		     10, 60));

# Directory for anonymous FTP
print &ui_table_row(&hlink($text{'newftp_dir'}, "template_ftp_dir_def"),
	&ui_opt_textbox("ftp_dir", $tmpl->{'ftp_dir'}, 20,
			"$text{'default'} (<tt>ftp</tt>)",
			$text{'newftp_dir0'}).
	("&nbsp;" x 3).$text{'newftp_dir0suf'});
}

# parse_template_ftp(&tmpl)
# Updates ProFTPd related template options from %in
sub parse_template_ftp
{
my ($tmpl) = @_;

# Save FTP directives
$tmpl->{'ftp'} = &parse_none_def("ftp");
if ($in{"ftp_mode"} == 2) {
	my $err = &check_proftpd_template($in{'ftp'});
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

# Return links to FTP log
sub links_ftp
{
my ($d) = @_;
my @rv;
my $lf = &get_proftpd_log($d);
if ($lf) {
	local $param = &master_admin() ? "file"
				       : "extra";
	push(@rv, { 'mod' => 'logviewer',
		    'desc' => $text{'links_flog'},
		    'page' => "view_log.cgi?view=1&nonavlinks=1".
			      "&linktitle=".&urlize($text{'links_flog'})."&".
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
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
my @dirs = &proftpd_template($tmpl->{'ftp'}, $d);
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
my @rv;
&require_proftpd();
my $conf = &proftpd::get_config();
$proftpd::conf = $conf;		# get_or_create is broken in Webmin 1.410
my $gconf = &proftpd::get_or_create_global($conf);
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
my ($chroots) = @_;
&require_proftpd();
my $conf = &proftpd::get_config();
$proftpd::conf = $conf;
my $gconf = &proftpd::get_or_create_global($conf);

# Find old directives that we can't configure yet
my @old = &proftpd::find_directive_struct("DefaultRoot", $gconf);
my @keep = grep { $_->{'words'}->[1] =~ /,/ } @old;
my @newv = map { $_->{'value'} } @keep;

# Add new ones
foreach my $chroot (@$chroots) {
	my @w = ( $chroot->{'dir'} );
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

# supports_namebased_ftp()
# Returns 1 if ProFTPd supports name-based FTP sites
sub supports_namebased_ftp
{
&require_proftpd();
$proftpd::site{'version'} ||= &proftpd::get_proftpd_version();
return $proftpd::site{'version'} >= 1.36;
}

# get_proftpd_virtualhost_ips(&domain)
# Returns the IPs or hostnames for use in a <VirtualHost> block
sub get_proftpd_virtualhost_ips
{
my ($d) = @_;
my @ips;
if ($d->{'virt'}) {
	# Accept all connections on an IP
	@ips = ( $d->{'ip'} );
	if ($d->{'virt6'}) {
		push(@ips, $d->{'ip6'});
		}
	}
else {
	# Match by hostname
	@ips = ( $d->{'dom'} );
	}
return @ips;
}

$done_feature_script{'ftp'} = 1;

1;

