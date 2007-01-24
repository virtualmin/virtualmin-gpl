# Functions for managing a virtual FTP server

$feature_depends{'ftp'} = [ 'dir', 'virt' ];

sub require_proftpd
{
return if ($require_proftpd++);
&foreign_require("proftpd", "proftpd-lib.pl");
}

# setup_ftp(&domain)
# Setup a virtual FTP server for some domain
sub setup_ftp
{
local $tmpl = &get_template($_[0]->{'template'});
&$first_print($text{'setup_proftpd'});
&require_proftpd();

# Get the template
local @dirs = &proftpd_template($tmpl->{'ftp'}, $_[0]);

# Add the directives
local $conf = &proftpd::get_config();
local $l = $conf->[@$conf - 1];
&lock_file($l->{'file'});
local $lref = &read_file_lines($l->{'file'});
local @lines = ( "<VirtualHost $_[0]->{'ip'}>" );
push(@lines, @dirs);
push(@lines, "</VirtualHost>");
push(@$lref, @lines);
&flush_file_lines();
&unlock_file($l->{'file'});

# Create directory for FTP root
local ($fdir) = ($tmpl->{'ftp_dir'} || 'ftp');
local $ftp = "$_[0]->{'home'}/$fdir";
if (!-d $ftp) {
	&system_logged("mkdir '$ftp' 2>/dev/null");
	&system_logged("chmod 755 '$ftp'");
	&system_logged("chown $_[0]->{'uid'}:$_[0]->{'ugid'} '$ftp'");
	}

&$second_print($text{'setup_done'});
&register_post_action(\&restart_proftpd);
undef(@proftpd::get_config_cache);
}

# delete_ftp(&domain)
# Delete the virtual server from the ProFTPd config
sub delete_ftp
{
&require_proftpd();
local $conf = &proftpd::get_config();
&$first_print($text{'delete_proftpd'});
local ($virt, $vconf) = &get_proftpd_virtual($_[0]->{'ip'});
if ($virt) {
	&lock_file($virt->{'file'});
	local $lref = &read_file_lines($virt->{'file'});
	splice(@$lref, $virt->{'line'}, $virt->{'eline'} - $virt->{'line'} + 1);
	&flush_file_lines();
	&unlock_file($virt->{'file'});

	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_proftpd);
	undef(@proftpd::get_config_cache);
	}
else {
	&$second_print($text{'delete_noproftpd'});
	}
}

# modify_ftp(&domain, &olddomain)
# If the server has changed IP address, update the ProFTPd virtual server
sub modify_ftp
{
local $rv = 0;
&require_proftpd();
local $conf = &proftpd::get_config();
local ($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($_[1]->{'ip'});
return 0 if (!$virt);
&lock_file($virt->{'file'});
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
	&flush_file_lines();
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
&unlock_file($virt->{'file'});
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
&require_proftpd();
local ($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($_[0]->{'ip'});
if ($anon) {
	&lock_file($anon->{'file'});
	local @limit = &proftpd::find_directive_struct("Limit", $aconf);
	local ($login) = grep { $_->{'words'}->[0] eq "LOGIN" } @limit;
	if (!$login) {
		local $lref = &read_file_lines($anon->{'file'});
		splice(@$lref, $anon->{'eline'}, 0,
		       "<Limit LOGIN>", "DenyAll", "</Limit>");
		&flush_file_lines();
		}
	&unlock_file($anon->{'file'});
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_proftpd);
	}
else {
	&$second_print($text{'delete_noproftpd'});
	}
}

# enable_ftp(&domain)
# Enable FTP for this server by removing the deny directive
sub enable_ftp
{
&$first_print($text{'enable_proftpd'});
&require_proftpd();
local ($virt, $vconf, $anon, $aconf) = &get_proftpd_virtual($_[0]->{'ip'});
if ($virt) {
	&lock_file($anon->{'file'});
	local @limit = &proftpd::find_directive_struct("Limit", $aconf);
	local ($login) = grep { $_->{'words'}->[0] eq "LOGIN" } @limit;
	if ($login) {
		local $lref = &read_file_lines($anon->{'file'});
		splice(@$lref, $login->{'line'},
		       $login->{'eline'} - $login->{'line'} + 1);
		&flush_file_lines();
		}
	&unlock_file($anon->{'file'});
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_proftpd);
	}
else {
	&$second_print($text{'delete_noproftpd'});
	}
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
			return &text('fcheck_euserex', "<tt>$1</tt>");
		$gotuser++;
		}
	elsif ($d =~ /^\s*Group\s+(\S+)$/i) {
		defined(getgrnam($1)) ||
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
	&$first_print($text{'setup_proftpdpid'});
	# Call proftpd restart function
	local $err = &proftpd::apply_configuration();
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
&$first_print($text{'backup_proftpdcp'});
local ($virt, $vconf) = &get_proftpd_virtual($_[0]->{'ip'});
if ($virt) {
	local $lref = &read_file_lines($virt->{'file'});
	local $l;
	&open_tempfile(FILE, ">$_[1]");
	foreach $l (@$lref[$virt->{'line'} .. $virt->{'eline'}]) {
		&print_tempfile(FILE, "$l\n");
		}
	&close_tempfile(FILE);
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
local ($virt, $vconf) = &get_proftpd_virtual($_[0]->{'ip'});
if ($virt) {
	local $srclref = &read_file_lines($_[1]);
	local $dstlref = &read_file_lines($virt->{'file'});
	&lock_file($virt->{'file'});
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
	&unlock_file($virt->{'file'});
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'delete_noproftpd'});
	return 0;
	}

&register_post_action(\&restart_proftpd);
return 1;
}

# get_proftpd_log(ip)
# Given a virtual server IP, returns the path to its log file. If no IP is
# give, returns the global log file path.
sub get_proftpd_log
{
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
&require_proftpd();
local $conf = &proftpd::get_config();
local $st = &proftpd::find_directive("ServerType", $conf);
if ($st eq 'inetd') {
	# Running under inetd
	return undef;
        }
elsif (&proftpd::get_proftpd_pid()) {
	return { 'status' => 1,
		 'name' => $text{'index_fname'},
		 'desc' => $text{'index_fstop'},
		 'restartdesc' => $text{'index_frestart'},
		 'longdesc' => $text{'index_fstopdesc'} };
	}
else {
	return { 'status' => 0,
		 'name' => $text{'index_fname'},
		 'desc' => $text{'index_fstart'},
		 'longdesc' => $text{'index_fstartdesc'} };
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
print "<tr> <td valign=top>",&hlink("<b>$text{'tmpl_ftp'}</b>",
				    "template_ftp"),"</td> <td>\n";
print &none_def_input("ftp", $tmpl->{'ftp'}, $text{'tmpl_ftpbelow'}, 1);
print "<textarea name=ftp rows=10 cols=60>";
if ($tmpl->{'ftp'} ne "none") {
	print join("\n", split(/\t/, $tmpl->{'ftp'}));
	}
print "</textarea>\n";

print "<table>\n";

# Directory for anonymous FTP
print "<tr> <td valign=top>",&hlink("<b>$text{'newftp_dir'}</b>",
				    "template_ftp_dir_def"),"</td>\n";
printf "<td nowrap><input type=radio name=ftp_dir_def value=1 %s> %s (%s)\n",
	$tmpl->{'ftp_dir'} ? "" : "checked", $text{'default'},
	"<tt>ftp</tt>";
printf "<br><input type=radio name=ftp_dir_def value=0 %s> %s\n",
	$tmpl->{'ftp_dir'} ? "checked" : "", $text{'newftp_dir0'};
printf "<input name=ftp_dir size=20 value='%s'><br>%s</td> </tr>\n",
	$tmpl->{'ftp_dir'}, ("&nbsp;" x 3).$text{'newftp_dir0suf'};

print "</table>\n";
print "</td> </tr>\n";

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
local @rv;
if ($config{'avail_syslog'} && &get_webmin_version() >= 1.305) {
	# Links to FTP log
	local $lf = &get_proftpd_log($d->{'ip'});
	if ($lf) {
		local $param = &master_admin() ? "file"
					       : "extra";
		push(@rv, { 'mod' => 'syslog',
			    'desc' => $text{'links_flog'},
			    'page' => "save_log.cgi?view=1&".
				      "$param=".&urlize($lf),
			  });
		}
	}
return @rv;

}

$done_feature_script{'ftp'} = 1;

1;

