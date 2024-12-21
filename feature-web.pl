
sub init_web
{
$default_web_port = $config{'web_port'} || 80;
$writelogs_cmd = "$module_config_directory/writelogs.pl";
}

sub require_apache
{
return if ($require_apache++);
&foreign_require("apache");
}

# setup_web(&domain)
# Setup a virtual website for some domain
sub setup_web
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $web_port = $d->{'web_port'} || $tmpl->{'web_port'} || 80;
local ($alias, $lockdom);
if ($d->{'alias'} && $tmpl->{'web_alias'} == 1) {
	&$first_print($text{'setup_webalias'});
	$lockdom = $alias = &get_domain($d->{'alias'});
	}
else {
	&$first_print($text{'setup_web'});
	$lockdom = $d;
	}
&require_apache();
&obtain_lock_web($lockdom);
local $conf = &apache::get_config();
local ($f, $newfile) = &get_website_file($d);

# Add NameVirtualHost if needed
local $nvstar = &add_name_virtual($d, $conf, $web_port, 1, $d->{'ip'});
local $nvstar6;
if ($d->{'ip6'}) {
	$nvstar6 = &add_name_virtual($d, $conf, $web_port, 1,
				     "[".$d->{'ip6'}."]");
	}

# We use a * for the address for name-based servers under Apache 2,
# if NameVirtualHost * exists.
local $vips = &get_apache_vhost_ips($d, $nvstar, $nvstar6, $web_port);

# Add Listen if needed
&add_listen($d, $conf, $web_port);

# If in FPM mode with a TCP port (from a restore), re-allocate it
if ($d->{'php_fpm_port'}) {
	delete($d->{'php_fpm_port'});
	}

local @dirs = &apache_template($tmpl->{'web'}, $d);
if ($apache::httpd_modules{'mod_proxy'}) {
	push(@dirs, "ProxyPass /.well-known !");
	}
if ($d->{'alias'} && $tmpl->{'web_alias'} == 1) {
	# Update the parent virtual host (and the SSL virtual host, if any)
	local @ports = ( $alias->{'web_port'} );
	push(@ports, $alias->{'web_sslport'}) if ($alias->{'ssl'});
	foreach my $p (@ports) {
		local ($pvirt, $pconf) = &get_apache_virtual(
						$alias->{'dom'}, $p);
		if (!$pvirt) {
			&$second_print($text{'setup_ewebalias'});
			return 0;
			}
		local @sa = &apache::find_directive("ServerAlias", $pconf);
		foreach my $dir (@dirs) {
			if ($dir =~ /^\s*Server(Name|Alias)\s+(.*)/) {
				push(@sa, $2);
				}
			}
		&apache::save_directive("ServerAlias", \@sa, $pconf, $conf);
		&flush_file_lines($pvirt->{'file'});
		}
	$d->{'alias_mode'} = 1;
	$d->{'php_mode'} = $alias->{'php_mode'};

	# If the target domain had redirects enabled, also do it for the alias
	if (&has_webmail_rewrite($d) &&
	    &get_webmail_redirect_directives($alias)) {
		&add_webmail_redirect_directives($d, $tmpl, 1);
		}

	# If the target domain had a www to non-www or vice-versa redirect
	# enabled, do it for the alias
	my ($r) = grep { &is_www_redirect($alias, $_) } &list_redirects($alias);
	if ($r) {
		my $func = &is_www_redirect($d, $r) == 1 ?
			\&get_non_www_redirect : \&get_www_redirect;
		foreach my $r (&$func($d)) {
			&create_redirect($alias, $r);
			}
		}
	}
else {
	# Add the actual <VirtualHost>

	# First build up the directives in the <VirtualHost>
	local $proxying;
	if ($d->{'alias'}) {
		# Because this is just an alias to an existing virtual server,
		# create a ProxyPass or Redirect
		@dirs = grep { /^\s*Server(Name|Alias)\s/i } @dirs;
		local $aliasdom = &get_domain($d->{'alias'});
		local $port = $aliasdom->{'web_port'} == 80 ? "" :
				":$aliasdom->{'web_port'}";
		local $urlhost = "www.".$aliasdom->{'dom'};
		if (!&to_ipaddress($urlhost)) {
			$urlhost = $aliasdom->{'dom'};
			}
		local $url = "http://$urlhost$port/";
		if ($apache::httpd_modules{'mod_proxy'} &&
		    $tmpl->{'web_alias'} == 2) {
			push(@dirs, "ProxyPass /.well-known !",
				    "ProxyPass / $url",
				    "ProxyPassReverse / $url");
			$proxying = 1;
			}
		elsif ($tmpl->{'web_alias'} == 0) {
			push(@dirs, "Redirect / $url");
			}
		elsif ($tmpl->{'web_alias'} == 4) {
			push(@dirs, "RedirectPermanent / $url");
			}
		}
	elsif ($d->{'subdom'}) {
		# Because this is a sub-domain, force the document directory
		# to be under the super-domain's public_html. Also, the logs
		# must be the same as the parent domain's logs.
		local $subdom = &get_domain($d->{'subdom'});
		local $subdir = &public_html_dir($d);
		local $mydir = &public_html_dir($d, 0, 1);
		local $subcgi = &cgi_bin_dir($d);
		local $mycgi = &cgi_bin_dir($d, 0, 1);
		local $clog = &get_apache_log(
				$subdom->{'dom'}, $subdom->{'web_port'}, 0);
		local $elog = &get_apache_log(
				$subdom->{'dom'}, $subdom->{'web_port'}, 1);
		foreach my $dir (@dirs) {
			if ($dir =~ /^\s*DocumentRoot/) {
				$dir = "DocumentRoot $subdir";
				}
			if ($dir =~ /^\s*ScriptAlias\s+\/cgi-bin\//) {
				$dir = "ScriptAlias /cgi-bin/ $subcgi/";
				}
			elsif ($dir =~ /^\s*<Directory\s+\Q$mydir\E>/) {
				$dir = "<Directory $subdir>";
				}
			elsif ($dir =~ /^\s*<Directory\s+\Q$mycgi\E>/) {
				$dir = "<Directory $subcgi>";
				}
			elsif ($dir =~ /^\s*ErrorLog/ && $elog) {
				$dir = "ErrorLog $elog";
				}
			elsif ($dir =~ /^\s*CustomLog\s+(.*)\s+(\S+)$/ && $clog) {
				$dir = "CustomLog $clog $2";
				}
			}
		$d->{'public_html_dir'} = $subdir;
		$d->{'cgi_bin_dir'} = $subcgi;
		foreach my $sd ($subdir, $subcgi) {
			if (!-d $sd) {
				&make_dir_as_domain_user($d, $sd, 0755, 1);
				}
			}
		}

	# Work out where in the file to add.
	# If this domain is foo.bar.com and a virtual host for *.bar.com exists
	# in the same file, we need to add before it.
	local $lref = &read_file_lines($f);
	local $pos = scalar(@$lref);
	if ($d->{'dom'} =~ /^([^\.]+)\.(\S+)$/) {
		local ($dsuffix, $dprefix) = ($1, $2);
		local ($starvirt, undef) = &get_apache_virtual("*.$dprefix",
							       $web_port);
		if ($starvirt && &same_file($starvirt->{'file'}, $f)) {
			# Insert before
			$pos = $starvirt->{'line'};
			}
		}

	# Add to the file
	splice(@$lref, $pos, 0, "<VirtualHost $vips>",
				(map { "    ".$_ } @dirs),
				"</VirtualHost>");
	&flush_file_lines($f);
	$d->{'web_port'} = $web_port;
	$d->{'web_urlport'} = $tmpl->{'web_urlport'};

	# Create a link from another Apache dir
	if ($newfile) {
		&apache::create_webfile_link($f);
		}
	undef(@apache::get_config_cache);

	# Set the public HTML directory based on the template or domain config
	if (!$d->{'alias'} && !$d->{'subdom'}) {
		my $htmldir;
		if ($d->{'public_html_dir'}) {
			# Typically set during migration
			$htmldir = $d->{'public_html_dir'};
			}
		elsif ($tmpl->{'web_html_dir'}) {
			# Custom template
			$htmldir = $tmpl->{'web_html_dir'};
			}
		else {
			# Standard default
			$htmldir = "public_html";
			}
		&set_public_html_dir($d, $htmldir);
		}

	# Redirect webmail and admin to Usermin and Webmin, if enabled in
	# the template
	if (&has_webmail_rewrite($d) && !$d->{'nowebmailredirect'}) {
		&add_webmail_redirect_directives($d, $tmpl, 0);
		}

	# For Apache 2.4+, add a "Require all granted" directive
	&add_require_all_granted_directives($d, $d->{'web_port'});

	# If the default ServerName matches this domain name, change it
	my $defsn = &get_apache_default_servername();
	if ($defdn eq $d->{'dom'}) {
		&apache::save_directive("ServerName", [ "nomatch.".$defsn ],
					$conf, $conf);
		&flush_file_lines();
		}

	# Create empty access and error log files, owned by the domain's user.
	# Apache opens them as root, so it will be able to write.
	local $log = &get_apache_log($d->{'dom'}, $d->{'web_port'}, 0);
	local $elog = &get_apache_log($d->{'dom'}, $d->{'web_port'}, 1);
	&setup_apache_logs($d, $log, $elog);
	&link_apache_logs($d, $log, $elog);
	$d->{'alias_mode'} = 0;
	}
&create_framefwd_file($d);
&$second_print($text{'setup_done'});

if (!$d->{'alias'} && !$d->{'notmplcgimode'}) {
	# Switch to the template CGI mode, if supported (unless restoring)
	my $mode = $tmpl->{'web_cgimode'};
	$mode = '' if ($mode eq 'none');
	my @cgimodes = &has_cgi_support();
	if (!$mode || &indexof($mode, @cgimodes) >= 0) {
		&$first_print($mode ? &text('setup_cgimode',
					$text{'tmpl_web_cgimode'.$mode})
				    : $text{'setup_cgimodenone'});
		my $err = &save_domain_cgi_mode($d, $mode);
		if ($err) {
			&$second_print(&text('setup_efcgiwrap', $err));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}
	}

&register_post_action(\&restart_apache);

# Add the Apache user to the group for this virtual server, if missing,
# unless the template says not to.
local $web_user = &get_apache_user($d);
if ($tmpl->{'web_user'} ne 'none' && $web_user) {
	&add_user_to_domain_group($d, $web_user, 'setup_webuser');
	}

# If creating web after domain creation,
# maybe add autoconfig DNS records
if ($config{'mail_autoconfig'} && $d->{'mail'} &&
    !$d->{'creating'} && !$d->{'alias'}) {
	&enable_email_autoconfig($d);
	}

# Add any proxypass directives
if (!$d->{'alias'} && $d->{'proxy_pass'}) {
	&update_apache_proxy_pass($d, undef);
	}

&$first_print($text{'setup_webpost'});
my $err;
eval {
	local $main::error_must_die = 1;

	# Make the web directory accessible under SElinux Apache
	if (&has_command("chcon")) {
		local $hdir = &public_html_dir($d);
		&execute_command("chcon -R -t httpd_sys_content_t ".
				 quotemeta($hdir));
		local $cgidir = &cgi_bin_dir($d);
		&execute_command("chcon -R -t httpd_sys_script_exec_t ".
				 quotemeta($cgidir));
		local $logdir = "$d->{'home'}/logs";
		&execute_command("chcon -R -t httpd_log_t ".
				 quotemeta($logdir));
		}

	# Setup the writelogs wrapper
	&setup_writelogs($d);

	# Create a root-owned file in ~/logs to prevent deletion of directory
	local $logsdir = "$d->{'home'}/logs";
	local $log = &get_apache_log($d->{'dom'}, $d->{'web_port'}, 0);
	if (-d $logsdir && !-e "$logsdir/.nodelete" &&
	    &is_under_directory($logsdir, $log)) {
		open(NODELETE, ">$logsdir/.nodelete");
		close(NODELETE);
		&set_ownership_permissions(0, 0, 0700, "$logsdir/.nodelete");
		}

	# Setup for script languages
	if (!$d->{'alias'} && $d->{'dir'}) {
		$err = &add_script_language_directives($d, $tmpl,
					        $d->{'web_port'});
		}

	# Re-apply limits, so that Apache directives are updated
	if (defined(&supports_resource_limits)) {
		local ($ok) = &supports_resource_limits();
		if ($ok) {
			local $pd = $d->{'parent'} ?
				&get_domain($d->{'parent'}) : $d;
			local $rv = &get_domain_resource_limits($pd);
			&save_domain_resource_limits($d, $rv, 1) if (%{$rv});
			}
		}

	# Apply symlink and mod_php fixes, in case the template wasn't
	# updated with them
	if ($config{'allow_symlinks'} ne '1' && !$d->{'alias'}) {
		&fix_symlink_security([ $d ]);
		}

	# Apply template SSI setting
	if ($tmpl->{'web_ssi'} == 1 && $tmpl->{'web_ssi_suffix'}) {
		&save_domain_web_ssi($d, $tmpl->{'web_ssi_suffix'});
		}
	elsif ($tmpl->{'web_ssi'} == 0) {
		&save_domain_web_ssi($d, undef);
		}
	};
if ($@) {
	&$second_print(&text('setup_ewebpost', "$@"));
	}
elsif ($err) {
	&$second_print(&text('setup_ewebpost', $err));
	}
else {
	&$second_print($text{'setup_done'});
	}

# If any alias domains with web already exist, re-set them up
local @adoms = &get_domain_by("alias", $d->{'id'},
			      "web", 1,
			      "alias_mode", 1);
foreach my $ad (@adoms) {
	&setup_web($ad);
	}

&release_lock_web($lockdom);
return 1;
}

# delete_web(&domain)
# Delete the virtual server from the Apache config
sub delete_web
{
local ($d) = @_;
&require_apache();
if ($d->{'alias_mode'}) {
	# Just delete ServerAlias directives from parent
	&$first_print($text{'delete_apachealias'});
	local $alias = &get_domain($d->{'alias'});
	&obtain_lock_web($alias);
	&remove_webmail_redirect_directives($d);
	local @ports = ( $alias->{'web_port'} );
	push(@ports, $alias->{'web_sslport'}) if ($alias->{'ssl'});
	foreach my $p (@ports) {
		local ($pvirt, $pconf, $conf) = &get_apache_virtual(
							$alias->{'dom'}, $p);
		if (!$pvirt) {
			&release_lock_web($alias);
			&$second_print($text{'setup_ewebalias'});
			return 0;
			}
		local @sa = &apache::find_directive("ServerAlias", $pconf);
		@sa = grep { !/(^|\.)\Q$d->{'dom'}\E$/ } @sa;
		&apache::save_directive("ServerAlias", \@sa, $pconf, $conf);
		&flush_file_lines($pvirt->{'file'});
		}

	# Also remove any host-based redirects for the alias
	foreach my $r (reverse(&list_redirects($alias))) {
		if ($r->{'host'} &&
		    ($r->{'host'} eq $d->{'dom'} ||
		     $r->{'host'} =~ /^[^\.]+\.\Q$d->{'dom'}\E$/)) {
			&delete_redirect($alias, $r);
			}
		}

	&release_lock_web($alias);
	&register_post_action(\&restart_apache);
	&$second_print($text{'setup_done'});
	}
elsif ($config{'delete_indom'}) {
	# Delete all matching virtual servers
	&$first_print($text{'delete_apache'});
	&obtain_lock_web($d);
	local $conf = &apache::get_config();
	if (!$d->{'alias_mode'}) {
		# Remove the custom Listen directive added for the domain
		&remove_listen($d, $conf, $d->{'web_port'});
		}
	local @virt = reverse(&apache::find_directive_struct("VirtualHost",
							     $conf));
	foreach $v (@virt) {
		local $sn = &apache::find_directive("ServerName",
						    $v->{'members'});
		local $vp = $v->{'words'}->[0] =~ /:(\d+)$/ ? $1 :
				$default_web_port;
		if ($sn =~ /\Q$d->{'dom'}\E$/ &&
		    $vp != $d->{'web_sslport'}) {
			# Check if a real sub-domain corresponds to this
			# virtualhost
			local $real = &get_domain_by("dom", $sn);
			if (!$real || $real->{'id'} == $d->{'id'}) {
				&delete_web_virtual_server($v);
				}
			}
		}
	&release_lock_web($d);
	&register_post_action(\&restart_apache);
	&$second_print($text{'setup_done'});
	}
else {
	# Just delete one virtual server
	&$first_print($text{'delete_apache'});
	&obtain_lock_web($d);
	local $conf = &apache::get_config();
	if (!$d->{'alias_mode'}) {
		# Remove the custom Listen directive added for the domain
		&remove_listen($d, $conf, $d->{'web_port'});
		}
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
						    $d->{'web_port'});
	if ($virt) {
		local $alog = &get_apache_log($d->{'dom'},
					      $d->{'web_port'}, 0);
		local $elog = &get_apache_log($d->{'dom'},
					      $d->{'web_port'}, 1);
		&delete_web_virtual_server($virt);
		&$second_print($text{'setup_done'});

		# Delete logs too, if outside home dir and if not a sub-domain
		if ($alog && !&is_under_directory($d->{'home'}, $alog) &&
		    !$d->{'subdom'} && !$d->{'web_nodeletelogs'}) {
			&$first_print($text{'delete_apachelog'});
			local @dlogs = ($alog, glob("${alog}.*"),
					glob("${alog}_*"), glob("${alog}-*"));
			if ($elog) {
				push(@dlogs, $elog, glob("${elog}.*"),
				     glob("${elog}_*"), glob("${elog}-*"));
				}
			&unlink_file(@dlogs);
			&$second_print($text{'setup_done'});
			}
		&register_post_action(\&restart_apache);
		}
	else {
		&$second_print($text{'delete_noapache'});
		}
	&release_lock_web($d);
	}
&delete_php_fpm_pool($d);	# May not exist, but delete just in case
if ($d->{'fcgiwrap_port'}) {
	&delete_fcgiwrap_server($d);
	delete($d->{'fcgiwrap_port'});
	}
undef(@apache::get_config_cache);
return 1;
}

# delete_web_virtual_server(&vhost)
# Delete a single virtual server from the Apache config
sub delete_web_virtual_server
{
local ($vhost) = @_;
&require_apache();
local $lref = &read_file_lines($vhost->{'file'});
splice(@$lref, $vhost->{'line'}, $vhost->{'eline'} - $vhost->{'line'} + 1);
&flush_file_lines($vhost->{'file'});
if (&is_empty($vhost->{'file'})) {
	# Don't keep around empty web files
	&unlink_file($vhost->{'file'});

	# Delete a link from another Apache dir
	&apache::delete_webfile_link($vhost->{'file'});
	}
}

# clone_web(&domain, &old-domain)
# Copy all Apache directives to a new domain
sub clone_web
{
local ($d, $oldd) = @_;
&$first_print($text{'clone_web'});
my $mode = &get_domain_php_mode($oldd);
if ($d->{'alias_mode'}) {
	# No copying needed for web alias domains
	&$second_print($text{'clone_webalias'});
	return 1;
	}
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
local ($ovirt, $ovconf) = &get_apache_virtual($oldd->{'dom'},
					      $oldd->{'web_port'});
if (!$ovirt) {
	&$second_print($text{'clone_webold'});
	return 0;
	}
if (!$virt) {
	&$second_print($text{'clone_webnew'});
	return 0;
	}
&obtain_lock_web($d);

# Fix up all the Apache directives
&clone_web_domain($oldd, $d, $ovirt, $virt, $d->{'web_port'});

# Update cached public_html and CGI dirs, re-create PHP wrappers with new home
&link_apache_logs($d);
&find_html_cgi_dirs($d);
if (&need_php_wrappers($d, $mode)) {
	&create_php_wrappers($d, $mode);
	}

# Force FPM port re-allocation and re-setup of PHP mode
my $mode = &get_domain_php_mode($oldd);
delete($d->{'php_fpm_port'});
&save_domain_php_mode($d, $mode);

# Update session dir and upload path in php.ini files
local @fixes = (
	[ "session.save_path", $oldd->{'home'}, $d->{'home'}, 1 ],
	[ "upload_tmp_dir", $oldd->{'home'}, $d->{'home'}, 1 ],
	);
&fix_php_ini_files($d, \@fixes);

&release_lock_web($d);
&register_post_action(\&restart_apache);
&$second_print($text{'setup_done'});
return 1;
}

# clone_web_domain(&old-vhost, &vhost, &old-domain, &domain, port)
# Copies across and fixes Apache directives for some vhost when cloning
sub clone_web_domain
{
local ($oldd, $d, $ovirt, $virt, $port) = @_;

# Splice across directives, fixing ServerName so that get_apache_virtual works
local $olref = &read_file_lines($ovirt->{'file'});
local $lref = &read_file_lines($virt->{'file'});
local @lines = @$olref[$ovirt->{'line'}+1 .. $ovirt->{'eline'}-1];
foreach my $l (@lines) {
	if ($l =~ /^(\s*)ServerName/) {
		$l = $1."ServerName ".$d->{'dom'};
		}
	}
splice(@$lref, $virt->{'line'}+1, $virt->{'eline'}-$virt->{'line'}-1, @lines);
&flush_file_lines($virt->{'file'});
undef(@apache::get_config_cache);
($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);

# Fix home dir
&modify_web_home_directory($d, $oldd, $virt);
local ($vconf, $conf);
($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);

# Fix username in suexec, if needed
if ($d->{'user'} ne $oldd->{'user'}) {
	&modify_web_user_group($d, $oldd, $virt, $vconf, $conf);
	}

# Fix domain name in apache config
&modify_web_domain($d, $oldd, $virt, $vconf, $conf, 0);

# Remove ServerAlias directives not for this domain, such as for an alias of
# the cloned source
local @sa = &apache::find_directive("ServerAlias", $vconf);
local @newsa;
foreach my $sa (@sa) {
	push(@newsa, $sa) if ($sa eq $d->{'dom'} || $sa =~ /\.\Q$d->{'dom'}\E/);
	}
if (@newsa) {
	&apache::save_directive("ServerAlias", \@newsa, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}
}

# is_empty(&lref|file)
# Returns 1 if a file or a reference to a list of lines contains no
# non-whitespace characters
sub is_empty
{
my ($lref_or_file) = @_;
my $lref;
if (ref($lref_or_file)) {
	$lref = $lref_or_file;
	}
else {
	$lref = &read_file_lines($lref_or_file, 1);
	}
foreach my $l (@$lref) {
	if ($l =~ /\S/) {
		return 0;
		}
	}
return 1;
}

# modify_web(&domain, &olddomain, [&alias, &oldalias])
# If this server has changed from name-based to IP-based hosting, update
# the Apache configuration
sub modify_web
{
my ($d, $oldd, $alias, $oldalias) = @_;
my $rv = 0;
&require_apache();

# Special case - converting an alias domain into a non-alias, or changing the
# alias target. Just delete and re-create.
if ($oldd->{'alias'} != $d->{'alias'}) {
	&delete_web($oldd);
	&setup_web($d);
	return 1;
	}

my $conf = &apache::get_config();
my $need_restart = 0;
my $mode = &get_domain_php_mode($oldd);

if ($d->{'alias'} && $d->{'alias_mode'}) {
	# Possibly just updating parent virtual server
	if ($d->{'dom'} ne $oldd->{'dom'}) {
		&$first_print($text{'save_apache5'});
		my $alias = &get_domain($d->{'alias'});
		&obtain_lock_web($alias);
		my @ports = ( $alias->{'web_port'} );
		push(@ports, $alias->{'web_sslport'}) if ($alias->{'ssl'});
		foreach my $p (@ports) {
			my ($pvirt, $pconf) = &get_apache_virtual(
							$alias->{'dom'}, $p);
			if (!$pvirt) {
				&$second_print($text{'setup_ewebalias'});
				next;
				}
			my @sa = &apache::find_directive("ServerAlias",
							    $pconf);
			foreach my $s (@sa) {
				$s =~ s/\Q$oldd->{'dom'}\E($|\s)/$d->{'dom'}$1/g;
				}
			&apache::save_directive("ServerAlias", \@sa, $pconf,
						$conf);
			&flush_file_lines($pvirt->{'file'});
			$rv++;
			}
		&$second_print($text{'setup_done'});
		&release_lock_web($alias);
		}
	}
else {
	# Update an actual virtual server
	&obtain_lock_web($d);
	my ($virt, $vconf, $conf) = &get_apache_virtual($oldd->{'dom'},
						    $oldd->{'web_port'});
	if ($d->{'name'} != $oldd->{'name'} ||
	    $d->{'ip'} ne $oldd->{'ip'} ||
	    $d->{'ip6'} ne $oldd->{'ip6'} ||
	    $d->{'virt6'} != $oldd->{'virt6'} ||
	    $d->{'name6'} != $oldd->{'name6'} ||
	    $d->{'ssl'} != $oldd->{'ssl'} ||
	    $d->{'web_port'} != $oldd->{'web_port'}) {
		# Name-based hosting mode or IP has changed .. update the
		# Listen directives, and the virtual host definition
		&$first_print($text{'save_apache'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		my $nvstar = &add_name_virtual($d, $conf,
						  $d->{'web_port'}, 0,
						  $d->{'ip'});
		my $nvstar6;
		if ($d->{'ip6'}) {
			$nvstar6 = &add_name_virtual(
				$d, $conf, $d->{'web_port'}, 0,
				"[".$d->{'ip6'}."]");
			}
		&add_listen($d, $conf, $d->{'web_port'});

		# Change the virtualhost IPs
		my $lref = &read_file_lines($virt->{'file'});
		$lref->[$virt->{'line'}] =
			"<VirtualHost ".
			&get_apache_vhost_ips($d, $nvstar, $nvstar6).
			">";
		&flush_file_lines($virt->{'file'});

		undef(@apache::get_config_cache);
		($virt, $vconf, $conf) = &get_apache_virtual($oldd->{'dom'},
						      $oldd->{'web_port'});
		$rv++;
		$need_restart = 1;
		&$second_print($text{'setup_done'});
		}
	if ($d->{'home'} ne $oldd->{'home'}) {
		# Home directory has changed .. update any directives that
		# referred to the old directory
		&$first_print($text{'save_apache3'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		&modify_web_home_directory($d, $oldd, $virt, $vconf, $conf, $mode);
		($virt, $vconf, $conf) = &get_apache_virtual($oldd->{'dom'},
						      $oldd->{'web_port'});
		$rv++;
		&find_html_cgi_dirs($d);

		# Re-create wrapper scripts, which contain home
		if (!$d->{'alias'} && &need_php_wrappers($d, $mode)) {
			&create_php_wrappers($d, $mode);
			}
		&$second_print($text{'setup_done'});
		}
	if (!$d->{'subdom'} && $oldd->{'subdom'}) {
		# No longer a sub-domain .. fix up any references to the old
		# HTML and CGI directories, and log files
		&$first_print($text{'save_apache11'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		my $phsrc = &public_html_dir($oldd);
		my $phdst = &public_html_dir($d);
		my $cgisrc = &cgi_bin_dir($oldd);
		my $cgidst = &cgi_bin_dir($d);
		my $lref = &read_file_lines($virt->{'file'});
		my $alogsrc = &get_apache_log($oldd->{'dom'},
						 $oldd->{'web_port'}, 0);
		my $elogsrc = &get_apache_log($oldd->{'dom'},
						 $oldd->{'web_port'}, 1);
		my $alogdst = &get_apache_template_log($d, 0);
		my $elogdst = &get_apache_template_log($d, 1);
		for($i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
			if ($phsrc && $phdst) {
				$lref->[$i] =~ s/\Q$phsrc\E/$phdst/g;
				}
			if ($cgisrc && $cgidst) {
				$lref->[$i] =~ s/\Q$cgisrc\E/$cgidst/g;
				}
			if ($alogsrc && $alogdst) {
				$lref->[$i] =~ s/\Q$alogsrc\E/$alogdst/g;
				}
			if ($elogsrc && $elogdst) {
				$lref->[$i] =~ s/\Q$elogsrc\E/$elogdst/g;
				}
			}
		&flush_file_lines($virt->{'file'});
		undef(@apache::get_config_cache);
		($virt, $vconf, $conf) = &get_apache_virtual($oldd->{'dom'},
						      $oldd->{'web_port'});
		&setup_apache_logs($d, $alogdst, $elogdst);
		&link_apache_logs($d, $alogdst, $elogdst);
		$rv++;
		&$second_print($text{'setup_done'});
		}
	if ($d->{'alias'} && $alias && $alias->{'dom'} ne $oldalias->{'dom'}) {
		# This is an alias, and the domain it is aliased to has
		# changed .. update all Proxy* and Redirect directives
		&$first_print($text{'save_apache4'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		my $lref = &read_file_lines($virt->{'file'});
		for($i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
			if ($lref->[$i] =~
			    /^\s*(Proxy|Redirect\s|RedirectPermanent\s)/) {
				$lref->[$i] =~ s/$oldalias->{'dom'}/$alias->{'dom'}/g;
				}
			}
		&flush_file_lines($virt->{'file'});
		undef(@apache::get_config_cache);
		($virt, $vconf, $conf) = &get_apache_virtual($oldd->{'dom'},
						      $oldd->{'web_port'});
		$rv++;
		&$second_print($text{'setup_done'});
		}
	if ($d->{'proxy_pass_mode'} == 1 &&
	    $oldd->{'proxy_pass_mode'} == 1 &&
	    $d->{'proxy_pass'} ne $oldd->{'proxy_pass'}) {
		# This is a proxying forwarding website and the URL has changed
		&$first_print($text{'save_apache6'});
		my $err = &update_apache_proxy_pass($d, $oldd);
		if ($err) {
			&$second_print(&text('save_eapache6', $err));
			}
		else {
			$rv++;
			&$second_print($text{'setup_done'});
			}
		}
	if ($d->{'proxy_pass_mode'} != $oldd->{'proxy_pass_mode'}) {
		# Proxy mode has been enabled or disabled
		my $mode = $d->{'proxy_pass_mode'} ||
			      $oldd->{'proxy_pass_mode'};
		&$first_print($mode == 2 ? $text{'save_apache8'}
					 : $text{'save_apache9'});
		my $err = &update_apache_proxy_pass($d, $oldd);
		if ($err) {
			&$second_print(&text('save_eapache8', $err));
			}
		else {
			$rv++;
			&$second_print($text{'setup_done'});
			}
		}
	if ($d->{'user'} ne $oldd->{'user'}) {
		# Username has changed .. update SuexecUserGroup
		&$first_print($text{'save_apache7'});
		&modify_web_user_group($d, $oldd, $virt, $vconf, $conf);
		$rv++;
		&$second_print($text{'setup_done'});

		# Set owner on log files
		my $web_user = &get_apache_user($d);
		my $gid = $web_user && $web_user ne 'none' ? $web_user
							: $d->{'gid'};
		my @ldv;
		foreach my $ld ("ErrorLog", "TransferLog", "CustomLog") {
			push(@ldv, &apache::find_directive($ld, $vconf, 1));
			}
		foreach my $ldv (@ldv) {
			if (&safe_domain_file($d, $ldv)) {
				&set_ownership_permissions(
					$d->{'uid'}, $gid, undef, $ldv);
				}
			}
		&link_apache_logs($d);

		# Add the Apache user to the group for the new domain
		my $tmpl = &get_template($d->{'template'});
		if ($tmpl->{'web_user'} ne 'none' && $web_user) {
			&add_user_to_domain_group($d, $web_user,
						  'setup_webuser');
			}

		# Update FPM config file with new username
		if ($mode eq "fpm") {
			&create_php_fpm_pool($d);
			}
		}
	if ($d->{'dom'} ne $oldd->{'dom'}) {
		# Domain name has changed .. update ServerName and ServerAlias,
		# and any log files that contain the domain name
		&$first_print($text{'save_apache2'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		&modify_web_domain($d, $oldd, $virt, $vconf, $conf, 1);
		$rv++;

		# If filename contains domain name, rename the Apache .conf file
		my $newfile = &get_website_file($d);
		my $oldfile = &get_website_file($oldd);
		if ($virt->{'file'} eq $oldfile &&
		    $newfile ne $oldfile &&
		    !-r $newfile) {
			&apache::delete_webfile_link($virt->{'file'});
			&rename_logged($virt->{'file'}, $newfile);
			&apache::create_webfile_link($newfile);
			undef(@apache::get_config_cache);
			($virt, $vconf, $conf) = &get_apache_virtual(
				$d->{'dom'}, $d->{'web_port'});
			}

		# Re-link Apache logs
		&link_apache_logs($d);
		&$second_print($text{'setup_done'});
		}
	if (($d->{'user'} ne $oldd->{'user'} ||
	     $d->{'dom'} ne $oldd->{'dom'}) && $d->{'fcgiwrap_port'}) {
		# Re-setup the fcgiwrap server
		&delete_fcgiwrap_server($oldd);
		&setup_fcgiwrap_server($d);
		}

	# If any other rename step fails becuase no <virtualhost> was found,
	# the code will jump to here.
	VIRTFAILED:
	if ($d->{'home'} ne $oldd->{'home'}) {
		# Update session dir and upload path in php.ini files
		my @fixes = (
		  [ "session.save_path", $oldd->{'home'}, $d->{'home'}, 1 ],
		  [ "upload_tmp_dir", $oldd->{'home'}, $d->{'home'}, 1 ],
		  );
		&fix_php_ini_files($d, \@fixes);
		}
	&release_lock_web($d);
	&create_framefwd_file($d);
	if ($need_restart && $rv) {
		# Need a full restart
		&register_post_action(\&restart_apache, 1);
		}
	elsif (!$need_restart && $rv) {
		# Just do a soft config apply
		&register_post_action(\&restart_apache, 0);
		}
	}
return $rv;
}

# validate_web(&domain)
# Returns an error message if no Apache virtual host exists
sub validate_web
{
local ($d) = @_;
if ($d->{'alias_mode'}) {
	# Find alias target, unless disabled
	if ($d->{'disabled'}) {
		return undef;
		}
	local $target = &get_domain($d->{'alias'});
	if ($target->{'disabled'}) {
		return undef;
		}
	local ($pvirt, $pconf) = &get_apache_virtual($d->{'dom'},
						     $target->{'web_port'});
	return &text('validate_eweb', "<tt>$d->{'dom'}</tt>") if (!$pvirt);
	}
else {
	# Find real domain
	local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'},
						    $d->{'web_port'});
	return &text('validate_eweb', "<tt>$d->{'dom'}</tt>") if (!$virt);

	# Do overall Apache validation, and check if there's an error in
	# this domain's block
	my $err = &apache::test_config();
	if ($err && $err =~ /\s+on\s+line\s+(\d+)\s+/) {
		my $lnum = $1;
		my $svirt;
		if ($d->{'ssl'}) {
			($svirt) = &get_apache_virtual($d->{'dom'},
						       $d->{'web_sslport'});
			}
		if ($lnum >= $virt->{'line'} && $lnum <= $virt->{'eline'} ||
		    ($svirt && $lnum >= $svirt->{'line'} && $lnum <= $svirt->{'eline'})) {
			$err =~ s/\r?\n/ /g;
			return &text('validate_ewebconfig',
				     "<tt>".&html_escape($err)."</tt>");
			}
		}

	# Check private IP addresses
	if ($d->{'virt'}) {
		local $ipp = $d->{'ip'}.":".$d->{'web_port'};
		&indexof($ipp, @{$virt->{'words'}}) >= 0 ||
			return &text('validate_ewebip', $ipp);
		}
	if ($d->{'virt6'}) {
		local $ipp = "[".$d->{'ip6'}."]:".$d->{'web_port'};
		&indexof($ipp, @{$virt->{'words'}}) >= 0 ||
			return &text('validate_ewebip6', $ipp);
		}

	# If using php via CGI or fcgi, check for wrappers
	local $need_suexec = 0;
	local $mode = &get_domain_php_mode($d);
	if ($mode eq "cgi" || $mode eq "fcgid") {
		local $dest = $mode eq "fcgid" ? "$d->{'home'}/fcgi-bin"
					       : &cgi_bin_dir($_[0]);
		local $suffix = $mode eq "fcgid" ? "fcgi" : "cgi";
		foreach my $dir (&list_domain_php_directories($d)) {
			local $path = "$dest/php".
				      $dir->{'version'}.".$suffix";
			if (!-x $path) {
				return &text('validate_ewebphp',
					     $dir->{'version'},
					     "<tt>$path</tt>");
				}
			}
		$need_suexec = 1;
		}

	# Validate the local PHP configuration
	if ($mode ne "mod_php") {
		local @dirvers = &unique(map { $_->{'version'} }
					     &list_domain_php_directories($d));
		foreach my $ver (&list_available_php_versions($d)) {
			next if (&indexof($ver->[0], @dirvers) < 0);
			my $errs = &check_php_configuration(
					$d, $ver->[0], $ver->[1]);
			if ($errs) {
				return &text('validate_ewebphpconfig',
					     $ver->[0], $errs);
				}
			}
		}

	# Validate the FPM port
	if ($mode eq "fpm") {
		my ($fpmerr) = &get_php_fpm_port_error($d);
		return $fpmerr if ($fpmerr);
		}

	# If there are suexec directives, validate them
	local ($suexec) = &apache::find_directive_struct(
		"SuexecUserGroup", $vconf);
	if ($suexec) {
		# Has suexec line - validate it
		if ($suexec->{'words'}->[0] ne $_[0]->{'user'} &&
		    $suexec->{'words'}->[0] ne '#'.$_[0]->{'uid'}) {
			return &text('validate_ewebuid',
			     $suexec->{'words'}->[0], $_[0]->{'uid'});
			}
		if ($suexec->{'words'}->[1] ne $_[0]->{'group'} &&
		    $suexec->{'words'}->[1] ne '#'.$_[0]->{'ugid'}) {
			return &text('validate_ewebgid',
			     $suexec->{'words'}->[1], $_[0]->{'ugid'});
			}
		}
	elsif ($need_suexec) {
		# Is missing suexec, but needs it
		return $text{'validate_ewebphpsuexec'};
		}

	# If using fcgiwrap, make sure the server is running
	if (&get_domain_cgi_mode($d) eq 'fcgiwrap') {
		my $st = &get_fcgiwrap_status($d);
		if ($st == 0) {
			return $text{'validate_efcgiwrapinit'};
			}
		elsif ($st == 1) {
			return $text{'validate_efcgiwraprun'};
			}
		}

	# Make sure a <Directory> exists for the document root, and that
	# DocumentRoot is valid
	if (!$d->{'alias'}) {
		local $pdir = &public_html_dir($d);
		local ($dir) = grep { $_->{'words'}->[0] eq $pdir ||
				      $_->{'words'}->[0] eq $pdir."/" }
			    &apache::find_directive_struct("Directory", $vconf);
		if (!$dir) {
			return &text('validate_ewebdir', $pdir);
			}
		local $root = &apache::find_directive("DocumentRoot", $vconf);
		if ($root ne $pdir && $root ne $pdir."/") {
			return &text('validate_ewebroot', $pdir);
			}
		}

	# If the <virtualhost> address uses a *, make sure that no other
	# virtualhost uses the domain's IP
	if ($virt->{'words'}->[0] =~ /^\*/) {
		my ($ipclash, $ipclashv);
		VHOST: foreach my $ovirt (&apache::find_directive_struct(
					"VirtualHost", $conf)) {
			foreach my $v (@{$ovirt->{'words'}}) {
				if ($v =~ /^([^:]+)(:(\d+))?/i &&
				    ($1 eq $d->{'ip'}) &&
				    (!$3 || $3 == $d->{'web_port'})) {
					$ipclash = $ovirt;
					$ipclashv = $v;
					last VHOST;
					}
				}
			}
		if ($ipclash) {
			my $sn = &apache::find_directive(
				"ServerName", $ipclash->{'members'});
			return &text('validate_envstar', $virt->{'words'}->[0],
							 $ipclashv, $sn);
			}
		}

	# If an IPv6 DNS record exists, make sure the Apache config supports it
	my $ip6addr;
	my $ip6name;
	my $system_hostname = &get_system_hostname();
	foreach my $try ("www.".$d->{'dom'}, $d->{'dom'}) {
		next if ($try eq $system_hostname);
		$ip6addr = &to_ip6address($try);
		if ($ip6addr) {
			$ip6name = $try;
			last;
			}
		}
	if ($ip6addr && !$d->{'dns_cloud'}) {
		if (!$d->{'ip6'}) {
			return &text('validate_ewebipv6', $ip6addr, $ip6name);
			}
		local $ipp = "[".$d->{'ip6'}."]:".$d->{'web_port'};
		if (&indexof($ipp, @{$virt->{'words'}}) < 0 &&
		    &indexof("*:".$d->{'web_port'}, @{$virt->{'words'}}) < 0) {
			return &text('validate_ewebipv6virt', $ip6addr);
			}
		}
	}
return undef;
}

# get_php_fpm_port_error(&domain)
# Returns any error message that should be displayed about the FPM port
sub get_php_fpm_port_error
{
my ($d) = @_;
my ($ok, $port) = &get_domain_php_fpm_port($d);
if ($ok == 0) {
	return (&text('validate_ewebphpfpmport', $port), undef);
	}
else {
	my ($clash, $conf, $port, $otherid) = &check_php_fpm_port_clash($d);
	my $cd = $clash ? &get_domain($clash) : undef;
	$cd = undef if ($cd && $cd->{'id'} eq $d->{'id'});
	if ($cd) {
		# Owned by another domain
		if ($otherid && $otherid ne $cd->{'id'}) {
			return (&text('validate_ewebphpfpmport4', $port,
				      &show_domain_name($cd)), $cd->{'id'});
			}
		else {
			return (&text('validate_ewebphpfpmport2', $port,
				      &show_domain_name($cd)), undef);
			}
		}
	elsif ($clash) {
		# Owned by another pool file
		return (&text('validate_ewebphpfpmport3', $port,
			      $conf->{'dir'}."/".$clash.".conf"), undef);
		}
	}
return ();
}

# disable_web(&domain)
# Adds a directive to force all requests to show an error page
sub disable_web
{
if ($_[0]->{'alias'} && $_[0]->{'alias_mode'} == 1) {
	# Just a ServerAlias in a real domain, so disabling is the same as
	# deletion. Unless the parent has already been disabled, in which case
	# nothing needs to be done.
	local $alias = &get_domain($_[0]->{'alias'});
	if ($alias->{'disabled'}) {
		return 1;
		}
	$_[0]->{'disable_alias_web_delete'} = 1;
	return &delete_web($_[0]);
	}
&$first_print($text{'disable_apache'});
&require_apache();
&obtain_lock_web($_[0]);
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_port'});
local $ok;
if ($virt) {
	&create_disable_directives($virt, $vconf, $_[0]);
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_apache);
	$ok = 1;
	}
else {
	&$second_print($text{'delete_noapache'});
	$ok = 0;
	}
&release_lock_web($_[0]);
return $ok;
}

# create_disable_directives(&virt, &vconf, &domain)
sub create_disable_directives
{
local ($virt, $vconf, $d) = @_;
local $tmpl = &get_template($d->{'template'});
local $conf = &apache::get_config();
if ($tmpl->{'disabled_url'} eq 'none') {
	# Disable is done via alias to local HTML
	local @am = &apache::find_directive("AliasMatch", $vconf);
	local $dis = &disabled_website_html($d);
	&apache::save_directive("AliasMatch",
				[ "^/.*\$ $dis", @am ], $vconf, $conf);

	# Also prevent undoing this via .htaccess
	local $pdir = &public_html_dir($d);
	local ($dir) = grep { $_->{'words'}->[0] eq $pdir }
			    &apache::find_directive_struct("Directory", $vconf);
	if ($dir) {
		local @ao = &apache::find_directive(
			"AllowOverride", $dir->{'members'});
		&apache::save_directive("AllowOverride",
			[ @ao, "None" ], $dir->{'members'}, $conf);
		}

	&flush_file_lines($virt->{'file'});
	local $def_tpl = &read_file_contents("$default_content_dir/index.html");
	local %hashtmp = %$d;
	%hashtmp = &populate_default_index_page($d, %hashtmp);
	$def_tpl = &replace_default_index_page($d, $def_tpl);
	$def_tpl = &substitute_virtualmin_template($def_tpl, \%hashtmp);
	local $msg = $tmpl->{'disabled_web'} eq 'none' ?
		$def_tpl :
		join("\n", split(/\t/, $tmpl->{'disabled_web'}));
	$msg = &substitute_domain_template($msg, $d);
	if (&is_under_directory($d->{'home'}, $dis)) {
		# Write as the domain user
		&open_tempfile_as_domain_user($d, DISABLED, ">$dis");
		&print_tempfile(DISABLED, $msg);
		&close_tempfile_as_domain_user($d, DISABLED);
		&set_permissions_as_domain_user($d, 0644, $dis);
		}
	else {
		# Write as root
		&open_lock_tempfile(DISABLED, ">$dis");
		&print_tempfile(DISABLED, $msg);
		&close_tempfile(DISABLED);
		&set_ownership_permissions(undef, undef, 0644,
					   $disabled_website);
		}
	}
else {
	# Disable is done via redirect
	local @rm = &apache::find_directive("RedirectMatch", $vconf);
	local $url = &substitute_domain_template($tmpl->{'disabled_url'}, $d);
	&apache::save_directive("RedirectMatch",
			[ "^/.*\$ $url", @rm ], $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}
}

# disabled_website_html(&domain, [force-new-mode])
# Returns the file for storing the disabled site file for some domain
sub disabled_website_html
{
local ($d, $mode) = @_;
&require_apache();
$mode = $apache::httpd_modules{'core'} >= 2.4 ? 1 : 0 if (!defined($mode));
if ($mode) {
	# Apache 2.4+ doesn't allow use of HTML files outside the <directory>
	# block for a domain
	return &public_html_dir($d)."/disabled_by_virtualmin.html";
	}
else {
	# Any location will work for older Apache versions
	if (!-d $disabled_website_dir) {
		mkdir($disabled_website_dir, 0755);
		&set_ownership_permissions(undef, undef,
					   $disabled_website_dir, 0755);
		}
	return "$disabled_website_dir/$d->{'id'}.html";
	}
}

# enable_web(&domain)
# Deletes the special error page directive
sub enable_web
{
if ($_[0]->{'alias'} && $_[0]->{'alias_mode'} == 1) {
	# Just a ServerAlias in a real domain, so enabling is the same as
	# creating.
	if ($_[0]->{'disable_alias_web_delete'}) {
		delete($_[0]->{'disable_alias_web_delete'});
		return &setup_web($_[0]);
		}
	return 1;
	}
&$first_print($text{'enable_apache'});
&require_apache();
&obtain_lock_web($_[0]);
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_port'});
local $ok;
if ($virt) {
	&remove_disable_directives($virt, $vconf, $_[0]);
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_apache);
	$ok = 1;
	}
else {
	&$second_print($text{'delete_noapache'});
	$ok = 0;
	}
&release_lock_web($_[0]);

# Remove disabled template file
local $dis_file = &public_html_dir($_[0])."/disabled_by_virtualmin.html";
&unlink_file($dis_file) if (-r $dis_file);
return $ok;
}

# remove_disable_directives(&virt, &vconf, &domain)
sub remove_disable_directives
{
local ($virt, $vconf, $d) = @_;

# Remove local disables
local @am = &apache::find_directive("AliasMatch", $vconf);
local $olddis = &disabled_website_html($d, 0);
local $newdis = &disabled_website_html($d, 1);
@am = grep { $_ ne "^/.*\$ $disabled_website" &&
	     $_ ne "^/.*\$ $olddis" &&
	     $_ ne "^/.*\$ $newdis" } @am;
local $conf = &apache::get_config();
&apache::save_directive("AliasMatch", \@am, $vconf, $conf);

# Remove remote disables
local @rm = &apache::find_directive("RedirectMatch", $vconf);
@rm = grep { substr($_, 0, 5) ne "^/.*\$" } @rm;
&apache::save_directive("RedirectMatch", \@rm, $vconf, $conf);

# Remove AllowOverride None
local $pdir = &public_html_dir($d);
local ($dir) = grep { $_->{'words'}->[0] eq $pdir }
		    &apache::find_directive_struct("Directory", $vconf);
if ($dir) {
	local @ao = &apache::find_directive(
		"AllowOverride", $dir->{'members'});
	@ao = grep { $_ ne "None" } @ao;
	&apache::save_directive("AllowOverride",
		\@ao, $dir->{'members'}, $conf);
	}


&flush_file_lines($virt->{'file'}, undef, 1);
}

# check_web_clash(&domain, [field])
# Returns 1 if an Apache webserver already exists for some domain
sub check_web_clash
{
local $tmpl = &get_template($_[0]->{'template'});
local $web_port = $tmpl->{'web_port'} || 80;
if (!$_[1] || $_[1] eq 'dom') {
	# Check for <virtualhost> clash by domain name
	local ($cvirt, $cconf) = &get_apache_virtual($_[0]->{'dom'}, $web_port);
	return 1 if ($cvirt);
	}
if (!$_[1] || $_[1] eq 'ip') {
	# Check for clash by IP and port with Webmin or Usermin
	local $err = &check_webmin_port_clash($_[0], $web_port);
	return $err if ($err);
	}
return 0;
}

# restart_apache([restart])
# Tell Apache to re-read its config file
sub restart_apache
{
local ($restart) = @_;
&require_apache();
if ($restart && $apache::httpd_modules{'core'} >= 2.2) {
	# Apache 2.2 doesn't need a full restart to open ports on new IPs
	$restart = 0;
	}
&$first_print($restart ? $text{'setup_webpid2'} : $text{'setup_webpid'});
if ($config{'check_apache'}) {
	# Do a config check first
	local $err = &apache::test_config();
	if ($err) {
		&$second_print(&text('setup_webfailed', "<pre>$err</pre>"));
		return 0;
		}
	}
&apache::format_modifed_config_files()
	if (defined(&apache::format_modifed_config_files));
local $apachelock = "$module_config_directory/apache-restart";
&lock_file($apachelock);
local $pid = &get_apache_pid();
if (!$pid || !kill(0, $pid)) {
	&$second_print($text{'setup_notrun'});
	return 0;
	}
if ($restart) {
	# Totally stop and start
	&apache::stop_apache();
	sleep(5);
	my $try = 0;
	while($try < 10 && &get_apache_pid()) {
		$try++;		# Wait up till 10 seconds for final exit
		}
	&apache::start_apache();
	}
else {
	# Just signal a re-load
	&apache::restart_apache();
	}
&unlock_file($apachelock);
&$second_print($text{'setup_done'});
return 1;
}

# get_apache_log(domain-name, [port], [errorlog])
# Given a domain name, returns the path to its log file
sub get_apache_log
{
local ($dname, $port, $errorlog) = @_;
&require_apache();
local ($virt, $vconf) = &get_apache_virtual($dname, $port);
if ($virt) {
	local $log;
	if ($errorlog) {
		# Looking for error log
		$log = &apache::find_directive("ErrorLog", $vconf);
		}
	else {
		# Looking for normal log
		$log = &apache::find_directive("TransferLog", $vconf) ||
		       &apache::find_directive("CustomLog", $vconf);
		}
	return &extract_writelogs_path($log, $dname);
	}
else {
	return undef;
	}
}

# extract_writelogs_path(log-command, domain-name)
# Given a log destination, which may be input to a command, return the
# real log file path.
sub extract_writelogs_path
{
local ($log, $dom) = @_;
my $log_ = $log;
local $w = &apache::wsplit($log);	# Extract first word
$log = $w->[0];
if ($log =~ /^\|\Q$writelogs_cmd\E\s+(\S+)\s+(\S+)/) {
	# Via writelogs .. return real path
	local $file = $2;
	if ($file =~ /^\//) {
		$log = $file;
		}
	else {
		local $d = &get_domain_by("dom", $_[0]);
		if ($d) {
			$log = "$d->{'home'}/$file";
			}
		}
	}
elsif ($log_ =~ /^(?:"|'|\\"|\\')?\|(\$)?(tee|\S+\/tee)(\s+\-a)?.*?([^'"\s]+(?:\Q$dom\E|\d{10,20})[^'"\s]+)/ ||
       $log_ =~ /^(?:"|'|\\"|\\')?\|(\$)?(tee|\S+\/tee)(\s+\-a)?.*?([^'"\s]+.?[^'"\s]+)/) {
	# Log via the tee command
	$log = $4;
	$log = $1 if ($log =~ /^"(.*)"$/);
	}
elsif ($log =~ /^\|/) {
	# Via some program .. so we don't know where the real log is
	$log = undef;
	}
if ($log && $log !~ /^\//) {
	# Convert to absolute path
	$log = &apache::server_root($log);
	}
return $log;
}

# get_apache_template_log(&domain, [errorlog])
# Returns the log file path that a domain's template would use
sub get_apache_template_log
{
local ($dom, $error) = @_;
local $tmpl = &get_template($dom->{'template'});
local @dirs = &apache_template($tmpl->{'web'}, $dom);
local $log;
foreach my $l (@dirs) {
	if ($error && $l =~ /^\s*ErrorLog\s+(\S+)/) {
		$log = $1;
		}
	elsif (!$error && $l =~ /^\s*(TransferLog|CustomLog)\s+(\S+)/) {
		$log = $2;
		}
	}
if (!$log) {
	$log = $errorlog ? "error_log" : "access_log";
	}
if ($log !~ /^\//) {
	$log = "$dom->{'home'}/logs/$log";
	}
return $log;
}

# get_apache_virtual(domain, [port], [file])
# Returns the directive for a virtual server and the list of configuration
# directives with in, for some domain
sub get_apache_virtual
{
&require_apache();
local $conf;
if ($_[2]) {
	# Looking in specified file
	$conf = [ &apache::get_config_file($_[2]) ];
	}
else {
	# Looking in global Apache config
	$conf = &apache::get_config();
	}
local $sp = $_[1] || $default_web_port;
foreach my $v (&apache::find_directive_struct("VirtualHost", $conf)) {
	local $vp = $v->{'words'}->[0] =~ /:(\d+)$/ ? $1 : $default_web_port;
	next if ($vp != $sp);
        local $sn = &apache::find_directive("ServerName", $v->{'members'});
	return ($v, $v->{'members'}, $conf) if (lc($sn) eq $_[0] ||
					        lc($sn) eq "www.$_[0]");
	local $n;
	foreach $n (&apache::find_directive_struct(
			"ServerAlias", $v->{'members'})) {
		local @lcw = map { lc($_) } @{$n->{'words'}};
		return ($v, $v->{'members'}, $conf)
			if (&indexof($_[0], @lcw) >= 0 ||
			    &indexof("www.$_[0]", @lcw) >= 0);
		}
        }
return ();
}

# get_apache_pid()
# Returns the Apache PID file, if it is running
sub get_apache_pid
{
&require_apache();
return &check_pid_file(&apache::get_pid_file());
}

# apache_template(text, &domain)
# Returns a suitably substituted Apache template, as a list of directive
# text lines
sub apache_template
{
my ($dirs, $d) = @_;
$dirs =~ s/\t/\n/g;
$dirs = &substitute_domain_template($dirs, $d);
local @dirs = split(/\n/, $dirs);
local $sudir;
foreach (@dirs) {
	$sudir++ if (/^\s*SuexecUserGroup\s/i);
	}
local $tmpl = &get_template($d->{'template'});
local $pdom = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
if (!$sudir && $pdom->{'unix'}) {
	# Automatically add suexec directives if missing
	unshift(@dirs, "SuexecUserGroup \"#$pdom->{'uid'}\" ".
		       "\"#$pdom->{'ugid'}\"");
	}
if ($tmpl->{'web_writelogs'}) {
	# Fix any CustomLog or ErrorLog directives to write via writelogs.pl
	foreach my $dir (@dirs) {
		if ($dir =~ /^(\s*)(CustomLog|ErrorLog)\s+(\S+)(\s*\S*)/) {
			$dir = "$1$2 \"|$writelogs_cmd $d->{'id'} $3\"$4";
			}
		}
	}
# Enable or Disable HTTPv2 if supported by Apache
my $supp = &supports_http2();
if ($supp) {
	if ($tmpl->{'web_http2'} == 1) {
		# Enable HTTPv2
		push(@dirs, "Protocols h2 h2c http/1.1")
		}
	elsif ($tmpl->{'web_http2'} == 2 && $supp == 2) {
		# Disable HTTPv2 explicitly, as Apache 2.4.37+ have HTTP2
		# enabled by default, but we want it to be disabled
		push(@dirs, "Protocols http/1.1")
		}
	}
if (!&supports_suexec()) {
	# Remove unsupported SuexecUserGroup directive
	@dirs = grep { !/^\s*SuexecUserGroup\s/i } @dirs;
	}
if ($d->{'dom_defnames'}) {
	# If domain level config has server default
	# names set, remove those not in the list
	@dirs = grep { &indexof($_, grep {
		$_ =~ /^(ServerName|ServerAlias)\s+(?<r_serv_name>.*)/ &&
		&indexof($+{r_serv_name}, split(/\s+/, $d->{'dom_defnames'})) < 0
		} @dirs) < 0 } @dirs;
	# XXXX Maybe add too? It already works in Nginx
	}
return @dirs;
}

# backup_web(&domain, file, &opts, home-format?, differential?, as-owner,
# 	     &all-opts)
# Save the virtual server's Apache config as a separate file, except for 
# ServerAlias lines for alias domains
sub backup_web
{
my ($d, $file, $opts, $homefmt, $increment, $asd, $allopts) = @_;
if ($d->{'alias'} && $d->{'alias_mode'}) {
	# For an alias domain, just save the old ServerAlias entries
	&$first_print($text{'backup_apachecp2'});
	my $alias = &get_domain($d->{'alias'});
	my ($pvirt, $pconf) = &get_apache_virtual($alias->{'dom'},
						     $alias->{'web_port'});
	if (!$pvirt) {
		&$second_print($text{'setup_ewebalias'});
		return 0;
		}
	my @aliasnames;
	foreach my $sa (&apache::find_directive_struct("ServerAlias", $pconf)) {
		foreach my $w (@{$sa->{'words'}}) {
			if ($w eq $d->{'dom'} ||
			    $w =~ /^([^\.]+)\.(\S+)/ && $2 eq $d->{'dom'}) {
				push(@aliasnames, $w);
				}
			}
		}
	&open_tempfile_as_domain_user($d, FILE, ">$file");
	foreach my $a (@aliasnames) {
		&print_tempfile(FILE, $a,"\n");
		}
	&close_tempfile_as_domain_user($d, FILE);
	&$second_print($text{'setup_done'});
	return 1;
	}
&$first_print($text{'backup_apachecp'});
my ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					    $d->{'web_port'});
if ($virt) {
	# Save the Apache config
	my $lref = &read_file_lines($virt->{'file'});
	my $l;
	my @adoms = &get_domain_by("alias", $d->{'id'});
	my %adoms = map { $_->{'dom'}, 1 } @adoms;
	&open_tempfile_as_domain_user($d, FILE, ">$file");
	foreach $l (@$lref[$virt->{'line'} .. $virt->{'eline'}]) {
		if ($l =~ /^(\s*)ServerAlias\s+(.*)/i) {
			# Exclude ServerAlias entries for alias domains
			my ($indent, $sa) = ($1, $2);
			my @sa = split(/\s+/, $sa);
			@sa = grep { !($adoms{$_} ||
				       /^([^\.]+)\.(\S+)/ && $adoms{$2}) } @sa;
			next if (!@sa);
			$l = $indent."ServerAlias ".join(" ", @sa);
			}
		&print_tempfile(FILE, "$l\n");
		}
	&close_tempfile_as_domain_user($d, FILE);
	&$second_print($text{'setup_done'});

	# If the Apache log is outside the home, back it up too
	my $alog = &get_apache_log($d->{'dom'}, $d->{'web_port'});
	if ($alog && -r $alog &&
	    !&is_under_directory($d->{'home'}, $alog) &&
	    !$allopts->{'dir'}->{'dirnologs'}) {
		&$first_print($text{'backup_apachelog'});
		my ($ok, $err) = &copy_write_as_domain_user(
			$d, $alog, $file."_alog");
		if ($config{'backup_rotated'} || $opts->{'rotated'}) {
			# Included rotated access log files
			&foreign_require("syslog");
			foreach my $l (&syslog::all_log_files($alog)) {
				$l =~ /^\Q$alog\E(.+)$/ || next;
				my $sfx = $1;
				&copy_write_as_domain_user(
					$d, $l, $file."_alog_".$sfx);
				}
			}

		# Also copy the error log
		my $elog = &get_apache_log($d->{'dom'}, $d->{'web_port'}, 1);
		if ($elog && -r $elog && $ok &&
		    !&is_under_directory($d->{'home'}, $elog)) {
			($ok, $err) = &copy_write_as_domain_user(
					$d, $elog, $file."_elog");
			}
		if ($ok) {
			&$second_print($text{'setup_done'});
			}
		else {
			&$second_print($err);
			return 0;
			}
		}

	# If there is an FPM pool file, back it up
	my $mode = &get_domain_php_mode($d);
	if ($mode eq "fpm") {
		my $pfile = &get_php_fpm_config_file($d);
		&copy_write_as_domain_user($d, $pfile, $file."_pool");
		}

	return 1;
	}
else {
	&$second_print($text{'delete_noapache'});
	return 0;
	}
}

# restore_web(&domain, file, &options, &all-options, home-format, &olddomain)
# Update the virtual server's Apache configuration from a file. Does not
# change the actual <Virtualhost> lines!
sub restore_web
{
my ($d, $file, $opts, $allopts, $homefmt, $oldd) = @_;
if ($d->{'alias'} && $d->{'alias_mode'}) {
	# Just re-add ServerAlias entries if missing
	&$first_print($text{'restore_apachecp2'});
	my $alias = &get_domain($d->{'alias'});
	my ($pvirt, $pconf, $conf) = &get_apache_virtual($alias->{'dom'},
						         $alias->{'web_port'});
	if (!$pvirt) {
		&$second_print($text{'setup_ewebalias'});
		return 0;
		}
	my @sa = &apache::find_directive("ServerAlias", $pconf);
	my $srclref = &read_file_lines($file, 1);
	push(@sa, @$srclref);
	&unflush_file_lines($file);
	@sa = &unique(@sa);
	&apache::save_directive("ServerAlias", \@sa, $pconf, $conf);
	&flush_file_lines($pvirt->{'file'});
	&$second_print($text{'setup_done'});
	return 1;
	}
&$first_print($text{'restore_apachecp'});
&obtain_lock_web($d);
my $rv;
my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
my $tmpl = &get_template($d->{'template'});
if ($virt) {
	my $srclref = &read_file_lines($file);
	my $dstlref = &read_file_lines($virt->{'file'});

	# Extract old logging-based directives before we change them, so they
	# can be restored later to match *this* system
	my %lmap;
	foreach $i ($virt->{'line'} .. $virt->{'line'}+scalar(@$srclref)-1) {
		if ($dstlref->[$i] =~
		    /^\s*(CustomLog|ErrorLog|TransferLog)\s+(.*)/i) {
			$lmap{lc($1)} = $2;
			}
		}

	splice(@$dstlref, $virt->{'line'}+1, $virt->{'eline'}-$virt->{'line'}-1,
	       @$srclref[1 .. @$srclref-2]);

	if ($allopts->{'reuid'}) {
		# Fix up any UID or GID in suexec lines
		my $i;
		foreach $i ($virt->{'line'} .. $virt->{'line'}+scalar(@$srclref)-1) {
			if ($dstlref->[$i] =~ /^\s*SuexecUserGroup\s/) {
				$dstlref->[$i] = "SuexecUserGroup ".
				  "\"#$d->{'uid'}\" \"#$d->{'ugid'}\"";
				}
			}
		}

	# Fix up any DocumentRoot or other file-related directives
	if ($oldd->{'home'} && $oldd->{'home'} ne $d->{'home'}) {
		my $i;
		foreach $i ($virt->{'line'} ..
			    $virt->{'line'}+scalar(@$srclref)-1) {
			$dstlref->[$i] =~
				s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
			}
		}

	# Change and CustomLog, ErrorLog or TransferLog directives to match
	# this system
	foreach $i ($virt->{'line'} .. $virt->{'line'}+scalar(@$srclref)-1) {
		if ($dstlref->[$i] =~
		    /^\s*(CustomLog|ErrorLog|TransferLog)\s/i &&
		    $lmap{lc($1)}) {
			$dstlref->[$i] = $1." ".$lmap{lc($1)};
			}
		}

	# Fix up AuthDigestFile / AuthUserFile change between Apache 2.0 and 2.2
	my ($oldn, $newn);
	if ($apache::httpd_modules{'core'} >= 2.2) {
		($oldn, $newn) = ('AuthDigestFile', 'AuthUserFile');
		}
	else {
		($oldn, $newn) = ('AuthUserFile', 'AuthDigestFile');
		}
	my $i;
	foreach $i ($virt->{'line'} ..  $virt->{'line'}+scalar(@$srclref)-1) {
		if ($dstlref->[$i] =~ /^\s*\Q$oldn\E\s+(.*)$/) {
			$dstlref->[$i] = "$newn $1";
			}
		}

	# If this system doesn't support mod_perl, remove any Perl directives
	# as set by virtualmin-google-analytics
	if (!$apache::httpd_modules{'mod_perl'}) {
		foreach $i ($virt->{'line'} ..  $virt->{'line'}+scalar(@$srclref)-1) {
			if ($dstlref->[$i] =~ /^\s*Perl/) {
				$dstlref->[$i] =~ s/^/#/g;
				}
			}
		}

	&flush_file_lines($virt->{'file'});
	undef(@apache::get_config_cache);

	# Re-generate PHP wrappers to match this system
	if (!$d->{'alias'}) {
		my $mode = &get_domain_php_mode($d);
		if (&need_php_wrappers($d, $mode)) {
			&create_php_wrappers($d, $mode);
			}
		}
	&$second_print($text{'setup_done'});

	# Make sure the PHP execution mode is valid
	my $mode;
	if (!$d->{'alias'}) {
		&$first_print($text{'restore_checkmode'});
		$mode = &get_domain_php_mode($d);
		my @supp = &supported_php_modes();
		if ($mode && &indexof($mode, @supp) < 0 && @supp) {
			# Need to fix
			my $fix = pop(@supp);
			&save_domain_php_mode($d, $fix);
			&$second_print(&text('restore_badmode', 
					$text{'phpmode_short_'.$mode},
					$text{'phpmode_short_'.$fix}));
			}
		else {
			# Looks good .. but re-save anyway, to update
			# compatible directives
			&save_domain_php_mode($d, $mode);
			&$second_print(&text('restore_okmode',
					$text{'phpmode_short_'.$mode}));
			}
		}

	# If the restored config contains php_value entries but this system
	# doesn't support mod_php, remove them
	&fix_mod_php_directives($d, $d->{'web_port'});

	# Correct system-specific entries in PHP config files
	if (!$d->{'alias'} && $oldd) {
		my $sock = &get_php_mysql_socket($d);
		my @fixes = (
		  [ "session.save_path", $oldd->{'home'}, $d->{'home'}, 1 ],
		  [ "upload_tmp_dir", $oldd->{'home'}, $d->{'home'}, 1 ],
		  [ "error_log", $oldd->{'home'}, $d->{'home'}, 1 ],
		  );
		if ($sock ne 'none') {
			push(@fixes, [ "mysql.default_socket", undef, $sock ]);
			}
		&fix_php_ini_files($d, \@fixes);
		&fix_php_fpm_pool_file($d, \@fixes);
		}

	# Fix broken PHP extension_dir directives
	if (($mode eq "fcgid" || $mode eq "cgi") && !$d->{'alias'}) {
		&fix_php_extension_dir($d);
		}

	# Fix unsupported CGI execution mode
	my $oldmode = &get_domain_cgi_mode($d);
	my @cgimodes = &has_cgi_support();
	if ($oldmode && &indexof($oldmodes, @cgimodes) < 0) {
		my $newmode = @cgimodes ? $cgimodes[0] : undef;
		if ($newmode) {
			&$first_print(&text('restore_cgimode',
				$text{'tmpl_web_cgimode'.$newmode}));
			}
		else {
			&$first_print($text{'restore_cgimodenone'});
			}
		my $err = &save_domain_cgi_mode($d, $newmode);
		if ($err) {
			&$second_print(&text('restore_ecgimode', $err));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}

	# Add Require all granted directive if this system is Apache 2.4
	&add_require_all_granted_directives($d, $d->{'web_port'});

	# Set new public_html and cgi-bin paths
	&find_html_cgi_dirs($d);

	# Create empty log files if needed
	&setup_apache_logs($d);

	# Copy back log files if they were in the backup
	if (-r $file."_alog") {
		&$first_print($text{'restore_apachelog'});

		# Restore the access log
		my $alog = &get_apache_log($d->{'dom'},
					      $d->{'web_port'});
		&copy_source_dest($file."_alog", $alog);
		&set_apache_log_permissions($d, $alog);

		# If the backup contained any rotated log files, restore them
		&foreign_require("syslog");
		my @alogs = grep { $_ ne $file }
				 &syslog::all_log_files($file."_alog");
		foreach my $l (@alogs) {
			$l =~ /^.*_alog_(.*)$/ || next;
			my $sfx = $1;
			&copy_source_dest($l, $alog.$sfx);
			}

		if (-r $file."_elog") {
			# Restore the error log
			my $elog = &get_apache_log($d->{'dom'},
						   $d->{'web_port'}, 1);
			&copy_source_dest($file."_elog", $elog);
			&set_apache_log_permissions($d, $elog);
			}
		&$second_print($text{'setup_done'});
		}

	# Re-link Apache logs if needed
	&link_apache_logs($d);

	# Fix Options lines
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'},
							$d->{'web_port'});
	if ($virt) {
		&fix_options_directives($vconf, $conf, 0);
		}

	# Handle case where there are DAV directives, but it isn't enabled
	&remove_dav_directives($d, $virt, $vconf, $conf);

	# If in FPM mode and there is a backup of the pool file, copy
	# back any custom PHP values
	my $mode = &get_domain_php_mode($d);
	if ($mode eq "fpm" && -r $file."_pool") {
		my $oldconfs = &list_php_fpm_file_config_values($file."_pool");
		my %done;
		foreach my $pv (&copyable_fpm_configs($oldconfs)) {
			$done{$pv->[0]}++;
			&save_php_fpm_config_value($d, $pv->[0], $pv->[1]);
			}
		my $confs = &list_php_fpm_config_values($d);
		foreach my $pv (&copyable_fpm_configs($confs)) {
			if (!$done{$pv->[0]}) {
				&save_php_fpm_config_value($d, $pv->[0], undef);
				}
			}
		}

	&register_post_action(\&restart_apache);
	$rv = 1;
	}
else {
	&$second_print($text{'delete_noapache'});
	$rv = 0;
	}
&release_lock_web($d);
return $rv;
}

%apache_mmap = ( 'jan' => 0, 'feb' => 1, 'mar' => 2, 'apr' => 3,
	  	 'may' => 4, 'jun' => 5, 'jul' => 6, 'aug' => 7,
	  	 'sep' => 8, 'oct' => 9, 'nov' => 10, 'dec' => 11 );

# bandwidth_web(&domain, start, &bw-hash)
# Searches through log files for records after some date, and updates the
# day counters in the given hash
sub bandwidth_web
{
my ($d, $start, $bwhash) = @_;
my @logs = ( &get_apache_log($d->{'dom'}, $d->{'web_port'}),
	     &get_apache_log($d->{'dom'}, $d->{'web_sslport'}) );
return if ($d->{'alias'} || $d->{'subdom'}); # never accounted separately
my $max_ltime = $start;
foreach my $l (&unique(@logs)) {
	foreach my $f (&all_log_files($l, $max_ltime)) {
		if ($f =~ /\.gz$/i) {
			open(LOG, "gunzip -c ".quotemeta($f)." |");
			}
		elsif ($f =~ /\.Z$/i) {
			open(LOG, "uncompress -c ".quotemeta($f)." |");
			}
		else {
			open(LOG, "<".$f);
			}
		while(<LOG>) {
			if (/^(\S+)\s+(\S+)\s+(\S+)\s+\[(\d+)\/(\S+)\/(\d+):(\d+):(\d+):(\d+)\s+(\S+)\]\s+"([^"]*)"\s+(\S+)\s+(\S+)/) {
				# Valid-looking log line .. work out the time
				my $ltime = timelocal(
				    $9, $8, $7, $4, $apache_mmap{lc($5)}, $6);
				if ($ltime > $start) {
					my $day = int($ltime / (24*60*60));
					$bwhash->{"web_".$day} += $13;
					}
				$max_ltime = $ltime if ($ltime > $max_ltime);
				}
			}
		close(LOG);
		}
	}
return $max_ltime;
}

# all_log_files(file, last-date)
# Returns all compressed rotated versions of some file, excluding those
# that have not been modified since some time
sub all_log_files
{
my ($file, $ltime) = @_;
if ($file =~ /\|$/) {
	# Running a command
	return ($file);
	}
if ($file !~ /^(.*)\/([^\/]+)$/) {
	# Not a valid path?!
	return ( );
	}
my $dir = $1;
my $base = $2;
my ($f, @rv, %mtime);
opendir(DIR, $dir);
foreach $f (readdir(DIR)) {
	if ($f =~ /^\Q$base\E/ && -f "$dir/$f" && $f ne $base.".offset") {
		my @st = stat("$dir/$f");
		if ($f ne $base) {
			next if ($ltime && $st[9] <= $ltime);
			}
		$mtime{"$dir/$f"} = $st[9];
		push(@rv, "$dir/$f");
		}
	}
closedir(DIR);
return sort { $mtime{$a} cmp $mtime{$b} } @rv;
}

# create_framefwd_file(&domain)
# Create a framefwd.html file for a server, if needed
sub create_framefwd_file
{
my ($d) = @_;
if ($d->{'proxy_pass_mode'} == 2) {
	my $template = &get_template($d->{'template'});
	my $ff = &framefwd_file($d);
	&unlink_file($ff);
	my $text = $template->{'frame'};
	$text =~ s/\t/\n/g;
	&open_tempfile_as_domain_user($d, FRAME, ">$ff");
	my %subs = %{$d};
	$subs{'proxy_title'} ||= $tmpl{'owner'};
	$subs{'proxy_meta'} ||= "";
	$subs{'proxy_meta'} = join("\n", split(/\t/, $subs{'proxy_meta'}));
	&print_tempfile(FRAME, &substitute_domain_template($text, \%subs));
	&close_tempfile_as_domain_user($d, FRAME);

	# Create a blank HTML page too, used in the frameset
	my $bl = &frameblank_file($d);
	&unlink_file($bl);
	&open_tempfile_as_domain_user($d, BLANK, ">$bl");
	&print_tempfile(BLANK, "<body bgcolor=#ffffff></body>\n");
	&close_tempfile_as_domain_user($d, BLANK);
	}
}

# public_html_dir(&domain, [relative], [no-subdomain])
# Returns the HTML documents directory for a virtual server
sub public_html_dir
{
my ($d, $rel, $nosubdom) = @_;

# First check for cache in domain object
my $want = $rel ? 'public_html_dir' : 'public_html_path';
if ($d->{$want} && !$nosubdom) {
	return $d->{$want};
	}
if ($d->{'subdom'} && !$nosubdom) {
	# Under public_html of parent domain
	my $subdom = &get_domain($d->{'subdom'});
	my $phtml = &public_html_dir($subdom, $rel);
	if ($rel) {
		return "../../$phtml/$d->{'subprefix'}";
		}
	else {
		return "$phtml/$d->{'subprefix'}";
		}
	}
else {
	# Under own home
	my $tmpl = &get_template($d->{'template'});
	my ($hdir) = ($tmpl->{'web_html_dir'} || 'public_html');
	if ($hdir ne 'public_html') {
		$hdir = &substitute_domain_template($hdir, $d);
		}
	return $rel ? $hdir : "$d->{'home'}/$hdir";
	}
}

# set_public_html_dir(&domain, sub-dir, rename-dir?)
# Sets the HTML directory for a virtual server, by updating the DocumentRoot
# and <Directory> block. Returns undef on success or an error message on
# failure.
sub set_public_html_dir
{
my ($d, $subdir, $rename) = @_;
my $p = &domain_has_website($d);
my $path = &simplify_path($d->{'home'}."/".$subdir);
my $oldpath = $d->{'public_html_path'};
if ($rename && (&is_under_directory($oldpath, $path) ||
		&is_under_directory($path, $oldpath))) {
	return "The old and new HTML directories cannot be sub-directories of ".
	       "each other";
	}
if (-f $path) {
	return "The HTML directory cannot be a file";
	}
if ($p ne "web") {
	# Call other webserver plugin's API
	my $err = &plugin_call($p, "feature_set_web_public_html_dir",
			       $d, $subdir);
	return $err if ($err);
	}
else {
	# Do it for Apache
	my @ports = ( $d->{'web_port'},
		      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
	foreach my $p (@ports) {
		my ($virt, $vconf, $conf) =
			&get_apache_virtual($d->{'dom'}, $p);
		next if (!$virt);
		&apache::save_directive("DocumentRoot", [ $path ],
					$vconf, $conf);
		my @dirs = &apache::find_directive_struct("Directory", $vconf);
		my ($dir) = grep { $_->{'words'}->[0] eq $oldpath ||
				   $_->{'words'}->[0] eq $oldpath."/"} @dirs;
		$dir ||= $dirs[0];
		$dir || return "No existing Directory block found!";
		my $olddir = { %$dir };
		$dir->{'value'} = $path;
		&apache::save_directive_struct($olddir, $dir, $vconf, $conf, 1);
		&flush_file_lines($virt->{'file'});
		}
	}
$d->{'public_html_dir'} = $subdir;
$d->{'public_html_path'} = $path;
&register_post_action(\&restart_apache);
if ($rename) {
	# Also rename the directory
	my $ok = &rename_as_domain_user($d, $oldpath, $path);
	return "Failed to rename $oldpath to $path" if (!$ok);
	}
return undef;
}

# cgi_bin_dir(&domain, [relative], [no-subdomain])
# Returns the CGI programs directory for a virtual server
sub cgi_bin_dir
{
my ($d, $rel, $nosubdom) = @_;

# First check for cache in domain object
my $want = $rel ? 'cgi_bin_dir' : 'cgi_bin_path';
if ($d->{$want} && !$nosubdom) {
	return $d->{$want};
	}
my $cdir = $d->{'cgi_bin_dir'} || "cgi-bin";
if ($d->{'subdom'} && !$nosubdom) {
	# Under cgi-bin of parent domain
	my $subdom = &get_domain($d->{'subdom'});
	my $pcgi = &cgi_bin_dir($subdom, $rel);
	return $rel ? "../../$pcgi/$d->{'subprefix'}"
		    : "$pcgi/$d->{'subprefix'}";
	}
else {
	# Under own home
	return $rel ? $cdir : "$d->{'home'}/$cdir";
	}
}

# framefwd_file(&domain)
sub framefwd_file
{
my ($d) = @_;
my $hdir = &public_html_dir($d);
return "$hdir/framefwd.html";
}

# frameblank_file(&domain)
sub frameblank_file
{
my ($d) = @_;
my $hdir = &public_html_dir($d);
return "$hdir/frameblank.html";
}

# check_depends_web(&dom)
# Ensure that a website has a home directory, if not proxying
sub check_depends_web
{
my ($d) = @_;
if (!$d->{'parent'} && !$d->{'unix'}) {
	# For a non-sub-server, we need a Unix user
	return $text{'setup_edepunix2'};
	}
if ($d->{'alias'}) {
	# If this is an alias domain, then no home is needed
	return undef;
	}
elsif ($d->{'proxy_pass_mode'} == 2) {
	# If proxying using frame forwarding, a home is needed
	return $d->{'dir'} ? undef : $text{'setup_edepframe'};
	}
elsif ($d->{'proxy_pass_mode'} == 1) {
	# If proxying using ProxyPass, no home is needed
	return undef;
	}
else {
	# For a normal website, we need a home
	return $d->{'dir'} ? undef : $text{'setup_edepweb'};
	}
}

# frame_fwd_input(forwardto)
sub frame_fwd_input
{
my ($fwdto) = @_;
my $label;
if ($config{'proxy_pass'} == 1) {
	$label = &hlink($text{'form_proxy'}, "proxypass");
	}
else {
	$label = &hlink($text{'form_framefwd'}, "framefwd");
	}
return &ui_table_row($label,
	&ui_opt_textbox("proxy", $fwdto, 40,
			$text{'form_plocal'}, $text{'form_purl'}), 3);
}

# setup_writelogs(&domain)
# Creates the writelogs wrapper
sub setup_writelogs
{
my ($d) = @_;
&foreign_require("cron");
&cron::create_wrapper($writelogs_cmd, $module_name, "writelogs.pl");
if (&has_command("chcon")) {
	&execute_command("chcon -t httpd_sys_script_exec_t ".
		quotemeta($writelogs_cmd).
		">/dev/null 2>&1");
	&execute_command("chcon -t httpd_sys_script_exec_t ".
	       quotemeta("$module_root_directory/writelogs.pl").
	       ">/dev/null 2>&1");
	}
}

# enable_writelogs(&domain)
# Enables logging via a program for some server
sub enable_writelogs
{
my ($d) = @_;
&require_apache();
my $conf = &apache::get_config();
my @ports = ( $d->{'web_port'},
	      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my $any = 0;
foreach my $p (@ports) {
	my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
	foreach my $ld ("CustomLog", "ErrorLog") {
		my $custom = &apache::find_directive($ld, $vconf);
		if ($custom !~ /$writelogs_cmd/ && $custom =~ /(\S+)(\s*\S*)/) {
			# Fix logging directive
			&$first_print($text{'save_fix'.lc($ld)});
			$custom = "\"|$writelogs_cmd $d->{'id'} $1\"$2";
			&apache::save_directive($ld, [ $custom ],
						$vconf, $conf);
			&$second_print($text{'setup_done'});
			$any++;
			}
		}
	}
if ($any) {
	&flush_file_lines();
	&register_post_action(\&restart_apache);
	}
}

# disable_writelogs(&domain)
# Disables logging via a program for some server
sub disable_writelogs
{
my ($d) = @_;
&require_apache();
my $conf = &apache::get_config();
my @ports = ( $d->{'web_port'},
	      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my $any = 0;
foreach my $p (@ports) {
	my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
	foreach my $ld ("CustomLog", "ErrorLog") {
		my $custom = &apache::find_directive($ld, $vconf);
		if ($custom =~ /^"\|$writelogs_cmd\s+(\S+)\s+(\S+)"(\s*\S*)/) {
			# Un-fix logging directive
			&$first_print($text{'save_unfix'.lc($ld)});
			$custom = "$2$3";
			&apache::save_directive($ld, [ $custom ],
						$vconf, $conf);
			&$second_print($text{'setup_done'});
			$any++;
			}
		}
	}
if ($any) {
	&flush_file_lines();
	&register_post_action(\&restart_apache);
	}
}

# get_writelogs_status(&domain)
# Returns 1 if some domain is doing logging via a program
sub get_writelogs_status
{
my ($d) = @_;
my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
my $custom = &apache::find_directive("CustomLog", $vconf);
return $custom =~ /^"\|$writelogs_cmd\s+(\S+)\s+(\S+)"(\s*\S*)/ ? 1 : 0;
}

# get_website_file(&domain)
# Returns the file to add a new website to, and optionally a flag indicating
# that this is a new file.
sub get_website_file
{
my ($d) = @_;
&require_apache();
my $vfile = $apache::config{'virt_file'} ?
	&apache::server_root($apache::config{'virt_file'}) :
	undef;
my ($rv, $newfile);
if ($vfile) {
	if (!-d $vfile) {
		$rv = $vfile;
		}
	else {
		my $tmpl = $apache::config{'virt_name'} || '${DOM}.conf';
		$rv = "$vfile/".&substitute_domain_template($tmpl, $d);
		$newfile = 1;
		}
	}
else {
	my $vconf = &apache::get_virtual_config();
	$rv = $vconf->[0]->{'file'};
	}
$rv =~ s/\/+/\//g;	# Fix use of //
return wantarray ? ($rv, $newfile) : $rv;
}

# get_apache_user([&domain])
# Returns the Unix user that the Apache process runs as, such as www or httpd
sub get_apache_user
{
my ($d) = @_;
if ($d) {
	my $tmpl = &get_template($d->{'template'});
	return $tmpl->{'web_user'} if ($tmpl->{'web_user'} &&
				       defined(getpwnam($tmpl->{'web_user'})));
	}
foreach my $u ("httpd", "apache", "www", "www-data", "wwwrun", "nobody") {
	return $u if (defined(getpwnam($u)));
	}
return undef;	# won't happen!
}

# sysinfo_web()
# Returns the Apache and mod_php versions
sub sysinfo_web
{
&require_apache();
local $ver = $apache::httpd_modules{'core'};
$ver =~ s/^(\d+)\.(\d)(\d+)$/$1.$2.$3/;
local @rv = ( [ $text{'sysinfo_apache'}, $ver ] );
if (defined(&list_available_php_versions)) {
	local @avail = &list_available_php_versions();
	local @vers;
	foreach my $a (grep { $_->[1] } @avail) {
		&clean_environment();
		local $out = &backquote_command("$a->[1] -v 2>&1 </dev/null");
		&reset_environment();
		if ($out =~ /PHP\s+([0-9\.]+)/) {
			push(@vers, $1);
			}
		else {
			push(@vers, $a->[0]);
			}
		}
	if (@vers) {
		push(@rv, [ $text{'sysinfo_php'}, join(", ", @vers) ]);
		}
	}
return @rv;
}

# add_name_virtual(&domain, $conf, port, star-doesnt-match, ip-string)
# Adds a NameVirtualHost entry for some domain, if needed. Returns 1 there is
# an existing NameVirtualHost entry for * or *:80 .
# For Apache 2.2 and above, NameVirtualHost * will no longer match
# virtualhosts like *:80, so we need to add *:80 even if * is already there.
# Returns 1 if there is a NameVirtualHost directive for *, 0 if not.
sub add_name_virtual
{
local ($d, $conf, $web_port, $no_star_match, $ip) = @_;
&require_apache();
if ($apache::httpd_modules{'core'} >= 2.4) {
	# Apache 2.4 doesn't need NameVirtualHost any more.
	# However, check if all existing <VirtualHost>s uses *, which means that
	# subsequent ones should as well. Otherwise, they can just use IPs.
	local @virt = &apache::find_directive_struct("VirtualHost", $conf);
	local $starcount = 0;
	local $ipcount = 0;
	foreach my $v (@virt) {
		if ($v->{'words'}->[0] =~ /^(\*|_DEFAULT_)(:(\d+))?/i &&
		    (!$3 || $3 == $web_port)) {
			$starcount++;
			}
		elsif ($v->{'words'}->[0] =~ /^(\S+)(:(\d+))?/i && $1 eq $ip &&
		       (!$3 || $3 == $web_port)) {
			$ipcount++;
			}
		}
	return $ipcount || !$starcount ? 0 : 1;
	}
local $nvstar;
if ($d->{'name'}) {
	local ($found, $found_no_port);
	local $defport = &apache::find_directive("Port", $conf);
	$defport ||= 80;
	local @nv = &apache::find_directive("NameVirtualHost", $conf);
	local $canstar = $apache::httpd_modules{'core'} < 2.2;
	foreach my $nv (@nv) {
		$found++ if ($nv =~ /^(\S+):(\S+)/ &&   # Like x.x.x.x:80
			      $1 eq $ip &&
			      $2 == $web_port ||
			     $nv eq '*' && $canstar &&	# Like *
			      $defport == $web_port ||
			     $nv =~ /^\*:(\d+)$/	# Like *:80
			      && $1 == $web_port
			      && !$no_star_match);
		$found_no_port++ if ($nv eq $ip);
		$nvstar++ if ($nv eq '*' && $canstar && # Like *
			       $defport == $web_port ||
			      $nv =~ /^\*:(\d+)$/ &&    # Like *:80
			       $1 == $web_port);
		}
	if (!$found) {
		@nv = grep { $_ ne $ip } @nv if ($found_no_port);
		&apache::save_directive("NameVirtualHost",
					[ @nv, "$ip:$web_port" ],
					$conf, $conf);
		&flush_file_lines();
		}
	}
return $nvstar;
}

# add_listen(&domain, &conf, port)
# Adds a Listen directive for some domain's port, if needed
sub add_listen
{
local ($d, $conf, $web_port) = @_;
&require_apache();
foreach my $dip ($d->{'ip'} ? ( $d->{'ip'} ) : ( ),
		 $d->{'ip6'} ? ( $d->{'ip6'} ) : ( )) {
	local $defport = &apache::find_directive("Port", $conf) || 80;
	local @listen = &apache::find_directive("Listen", $conf);
	local $lfound;
	foreach my $l (@listen) {
		$l =~ s/\s\S+$//;	# Remove trailing port name
		$lfound++ if (($l eq '*' && $web_port == $defport) ||
			      ($l =~ /^\*:(\d+)$/ && $web_port == $1) ||
			      ($l =~ /^0\.0\.0\.0:(\d+)$/ && $web_port == $1) ||
			      ($l =~ /^\d+$/ && $web_port == $l) ||
			      ($l =~ /^(\S+):(\d+)$/ &&
			       &to_ipaddress("$1") eq $dip &&
			       $2 == $web_port) ||
			      ($l =~ /^\[(\S+)\]:(\d+)$/ &&
			       &to_ip6address("$1") eq $dip &&
			       $2 == $web_port) ||
			      ($l !~ /:/ && &to_ipaddress($l) eq $dip));
		}
	if (!$lfound && @listen > 0) {
		# Apache is listening on some IP addresses and ports, but not
		# the needed one. Add a listen for that IP specifically.
		# Listening on * is no longer done, as it can cause conflicts
		# with other servers on port 443 or 80 and other IPs.
		local $ip = &check_ip6address($dip) ? "[$dip]" : $dip;
		&apache::save_directive("Listen", [ @listen, "$ip:$web_port" ],
					$conf, $conf);
		&flush_file_lines();
		}
	}
}

# remove_listen(&domain, &conf, port)
# Remove any Listen directive that exactly matches the domain's IP and the
# given port, if and only if the domain has a private IP address
sub remove_listen
{
local ($d, $conf, $web_port) = @_;
if ($d->{'virt'} && !$d->{'name'}) {
	local @listen = &apache::find_directive("Listen", $conf);
	local @newlisten = grep { $_ ne "$d->{'ip'}:$web_port" } @listen;
	if ($d->{'ip6'}) {
		@newlisten = grep { $_ ne "[$d->{'ip6'}]:$web_port" } @listen;
		}
	if (scalar(@listen) != scalar(@newlisten)) {
		&apache::save_directive("Listen", \@newlisten,
					$conf, $conf);
		&flush_file_lines();
		}
	}
}

sub links_web
{
local ($d) = @_;
return () if ($d->{'alias'});
local @rv;
my $link = $d->{'dom'}.":".$d->{'web_port'};
my $slink = $d->{'dom'}.":".$d->{'web_sslport'};

# Link to configure virtual host
push(@rv, { 'mod' => 'apache',
	    'desc' => $text{'links_web'},
	    'page' => "virt_index.cgi?virt=".$link,
	    'cat' => 'web',
	  });
if ($d->{'ssl'}) {
	# Link to configure SSL virtual host
	push(@rv, { 'mod' => 'apache',
		    'desc' => $text{'links_ssl'},
		    'page' => "virt_index.cgi?virt=".$slink,
		    'cat' => 'web',
		  });
	}

# Links to logs
foreach my $log ([ 0, $text{'links_alog'} ],
		 [ 1, $text{'links_elog'} ]) {
	local $lf = &get_apache_log($d->{'dom'},
				    $d->{'web_port'}, $log->[0]);
	if ($lf) {
		local $param = &master_admin() ? "file" : "extra";
		push(@rv, { 'mod' => 'logviewer',
			    'desc' => $log->[1],
			    'page' => "view_log.cgi?view=1&nonavlinks=1".
				      "&linktitle=".&urlize($log->[1])."&".
				      "$param=".&urlize($lf),
			    'cat' => 'logs',
			  });
		}
	}

# Link to PHP log, if enabled
my $phplog = &get_domain_php_error_log($d);
if ($phplog) {
	my $param = &master_admin() ? "file" : "extra";
	push(@rv, { 'mod' => 'logviewer',
		    'desc' => $text{'links_phplog'},
		    'page' => "view_log.cgi?view=1&nonavlinks=1".
			      "&linktitle=".&urlize($text{'links_phplog'})."&".
			      "$param=".&urlize($phplog),
		    'cat' => 'logs',
		  });
	}

# Links to edit PHP configs (if per-domain files exist)
my $mode = &get_domain_php_mode($d);
if ($mode eq "cgi" || $mode eq "fcgid") {
	# Link to phpini module for each PHP version that's in use
	my %availvers = map { $_->[0], $_ } &list_available_php_versions($d);
	my %dirvers = map { $_->{'version'}, $_ }
			  &list_domain_php_directories($d);
	foreach my $ini (grep { !$_->[0] || $availvers{$_->[0]} }
			   grep { $dirvers{$_->[0]} }
			      &find_domain_php_ini_files($d)) {
		push(@rv, { 'mod' => 'phpini',
			    'desc' => $ini->[0] ?
				&text('links_phpini2', $ini->[0]) :
				&text('links_phpini'),
			    'page' => 'list_ini.cgi?file='.
					&urlize($ini->[1]),
			    'cat' => 'web',
			  });
		}
	}
elsif ($mode eq "fpm") {
	# Link to phpini module for the FPM version
	my $conf = &get_php_fpm_config($d);
	if ($conf) {
		my $file = $conf->{'dir'}."/".$d->{'id'}.".conf";
		push(@rv, { 'mod' => 'phpini',
			    'desc' => &text('links_phpini3'),
			    'page' => 'list_ini.cgi?file='.
					&urlize($file),
			    'cat' => 'web',
			  });
		}
	}

return @rv;
}

# startstop_web([&typestatus])
# Returns a hash containing the current status of the web service and short
# and long descriptions for the action to switch statuses
sub startstop_web
{
local ($typestatus) = @_;
local $apid = defined($typestatus->{'apache'}) ?
		$typestatus->{'apache'} == 1 : &get_apache_pid();
local @links = ( { 'link' => '/apache/',
		   'desc' => $text{'index_amanage'},
		   'manage' => 1 } );
local @rv;
if ($apid) {
	push(@rv, { 'status' => 1,
		    'name' => $text{'index_aname'},
		    'desc' => $text{'index_astop'},
		    'restartdesc' => $text{'index_arestart'},
		    'longdesc' => $text{'index_astopdesc'},
		    'links' => \@links });
	}
else {
	push(@rv, { 'status' => 0,
		    'name' => $text{'index_aname'},
		    'desc' => $text{'index_astart'},
		    'longdesc' => $text{'index_astartdesc'},
		    'links' => \@links });
	}
foreach my $fpm (&list_php_fpm_configs()) {
	&foreign_require("init");
	next if (!$fpm->{'init'});
	next if (!defined(&init::status_action));
	my $st = &init::status_action($fpm->{'init'});
	next if ($st < 0);
	if ($st) {
		# Running, show buttons to stop and restart
		push(@rv, { 'status' => 1,
			    'feature' => 'fpm',
			    'id' => $fpm->{'version'},
			    'name' => &text('index_fpmname', $fpm->{'version'}),
			    'desc' => $text{'index_fpmstop'},
			    'restartdesc' => $text{'index_fpmrestart'},
			    'longdesc' => &text('index_fpmstopdesc',
						$fpm->{'version'}) });
		}
	else {
		# Down, show button to start
		push(@rv, { 'status' => 0,
			    'feature' => 'fpm',
			    'id' => $fpm->{'version'},
			    'name' => &text('index_fpmname', $fpm->{'version'}),
			    'desc' => $text{'index_fpmstart'},
			    'longdesc' => &text('index_fpmstartdesc',
						$fpm->{'version'}) });
		}
	}
return @rv;
}

# start_service_web()
# Attempts to start the web service, returning undef on success or any error
# message on failure.
sub start_service_web
{
&require_apache();
return &apache::start_apache();
}

# start_service_web()
# Attempts to stop the web service, returning undef on success or any error
# message on failure.
sub stop_service_web
{
&require_apache();
local $err = &apache::stop_apache();
sleep(1) if (!$err);
return $err;
}

# reload_service_web()
# Attempts to reload the web service config, returning undef on success or any
# error message on failure.
sub reload_service_web
{
&require_apache();
return &apache::restart_apache();
}

# start_service_fpm(version)
# Attempts to start the FPM server for some version
sub start_service_fpm
{
my ($ver) = @_;
my ($fpm) = grep { $_->{'version'} eq $ver } &list_php_fpm_configs();
return "Invalid version $ver" if (!$fpm || !$fpm->{'init'});
&foreign_require("init");
my ($ok, $err) = &init::start_action($fpm->{'init'});
return $ok ? undef : $err;
}

# stops_service_fpm(version)
# Attempts to stop the FPM server for some version
sub stop_service_fpm
{
my ($ver) = @_;
my ($fpm) = grep { $_->{'version'} eq $ver } &list_php_fpm_configs();
return "Invalid version $ver" if (!$fpm || !$fpm->{'init'});
&foreign_require("init");
my ($ok, $err) = &init::stop_action($fpm->{'init'});
return $ok ? undef : $err;
}

# reload_service_fpm(version)
# Attempts to reload the FPM server for some version
sub reload_service_fpm
{
my ($ver) = @_;
my ($fpm) = grep { $_->{'version'} eq $ver } &list_php_fpm_configs();
return "Invalid version $ver" if (!$fpm || !$fpm->{'init'});
&foreign_require("init");
my ($ok, $err) = &init::reload_action($fpm->{'init'});
if (!$ok && $err =~ /Not\s+implemented/i) {
	($ok, $err) = &init::restart_action($fpm->{'init'});
	}
return $ok ? undef : $err;
}

# show_template_web(&tmpl)
# Outputs HTML for editing webserver related template options
sub show_template_web
{
local ($tmpl) = @_;

my $hr;
my @cgimodes = &has_cgi_support();
if ($config{'web'}) {
	# Work out fields to disable when Apache is in default mode
	local @webfields = ( "web", "web_ssl", "user_def",
			     $tmpl->{'writelogs'} ? ( "writelogs" ) : ( ),
			     "html_dir", "html_dir_def", "html_perms",
			     "alias_mode", "web_port", "web_sslport",
			     "web_ssi", "web_ssi_suffix");
	if ($config{'webalizer'}) {
		push(@webfields, "stats_mode", "stats_dir", "stats_hdir",
				 "statspass", "statsnoedit");
		}
	if (defined(&get_domain_ruby_mode)) {
		push(@webfields, "web_ruby_suexec");
		}
	if (@cgimodes > 0) {
		push(@webfields, "cgimode");
		}

	# Apache directives
	local $ndi = &none_def_input(
		"web", $tmpl->{'web'}, $text{'tmpl_webbelow'}, 1,
		0, undef, \@webfields);
	print &ui_table_row(&hlink($text{'tmpl_web'}, "template_web"),
		$ndi."<br>\n".
		&ui_textarea("web", $tmpl->{'web'} eq "none" ? "" :
					join("\n", split(/\t/, $tmpl->{'web'})),
			     10, 60));

	# Extra SSL directives
	print &ui_table_row(&hlink($text{'tmpl_web_ssl'}, "template_web_ssl"),
		&ui_textarea("web_ssl",
			     join("\n", split(/\t/, $tmpl->{'web_ssl'})),
			     5, 60));

	# Input for logging via program. Deprecated so don't show unless enabled
	if ($tmpl->{'web_writelogs'}) {
		print &ui_table_row(&hlink($text{'newweb_writelogs'},
					   "template_writelogs"),
			&ui_yesno_radio("writelogs", $tmpl->{'web_writelogs'}));
		}

	# Input for Apache user to add to domain's group
	print &ui_table_row(&hlink($text{'newweb_user'}, "template_user_def"),
		&ui_radio("user_def", $tmpl->{'web_user'} eq 'none' ? 2 :
					   $tmpl->{'web_user'} ? 1 : 0,
	           [ [ 2, $text{'no'}."<br>" ],
		     [ 0, $text{'newweb_userdef'}."<br>" ],
		     [ 1, $text{'newweb_useryes'}." ".
		          &ui_user_textbox(
				"user", $tmpl->{'web_user'} eq 'none' ?  '' :
					  $tmpl->{'web_user'}) ] ]));
	}

# CGI script execution mode
if (@cgimodes > 0) {
	print &ui_table_row(
		&hlink($text{'tmpl_web_cgimode'}, "template_web_cgimode"),
		&ui_radio("cgimode", $tmpl->{'web_cgimode'},
			  [ [ 'none', $text{'tmpl_web_cgimodenone'} ],
			    map { [ $_, $text{'tmpl_web_cgimode'.$_} ] }
				reverse(@cgimodes) ]));
	}

# HTML sub-directory input
print &ui_table_row(&hlink($text{'newweb_htmldir'}, "template_html_dir_def"),
	&ui_opt_textbox("html_dir", $tmpl->{'web_html_dir'}, 20,
			"$text{'default'} (<tt>public_html</tt>)<br>",
			$text{'newweb_htmldir0'})."<br>\n".
	("&nbsp;" x 3).$text{'newweb_htmldir0suf'});
local $hdir = $tmpl->{'web_html_dir'} || "public_html";

# HTML directory permissions
print &ui_table_row(&hlink($text{'newweb_htmlperms'}, "template_html_perms"),
	&ui_textbox("html_perms", $tmpl->{'web_html_perms'}, 4));

if ($config{'web'}) {
	# Alias mode
	print &ui_table_row(&hlink($text{'tmpl_alias'}, "template_alias_mode"),
		&ui_radio("alias_mode", int($tmpl->{'web_alias'}),
			  [ [ 0, $text{'tmpl_alias0'}."<br>" ],
			    [ 4, $text{'tmpl_alias4'}."<br>" ],
			    [ 2, $text{'tmpl_alias2'}."<br>" ],
			    [ 1, $text{'tmpl_alias1'} ] ]));

	# Default SSI setting
	print &ui_table_row(
	    &hlink($text{'tmpl_webssi'}, "template_webssi"),
	    &ui_radio("web_ssi", $tmpl->{'web_ssi'},
		      [ [ 1, &text('phpmode_ssi1',
			   &ui_textbox("web_ssi_suffix",
				       $tmpl->{'web_ssi_suffix'}, 6)) ],
			[ 0, $text{'no'} ],
			[ 2, $text{'phpmode_ssi2'} ] ]));

	# Port for normal webserver
	print &ui_table_row(&hlink($text{'newweb_port'}, "template_web_port"),
		&ui_textbox("web_port", $tmpl->{'web_port'}, 6));

	# Port for SSL webserver
	print &ui_table_row(
		&hlink($text{'newweb_sslport'}, "template_web_sslport"),
		&ui_textbox("web_sslport", $tmpl->{'web_sslport'}, 6));

	# URL port for normal webserver
	print &ui_table_row(
		&hlink($text{'newweb_urlport'}, "template_web_urlport"),
		&ui_opt_textbox("web_urlport", $tmpl->{'web_urlport'}, 6,
				$text{'newweb_sameport'}));

	# URL port for SSL webserver
	print &ui_table_row(
		&hlink($text{'newweb_urlsslport'}, "template_web_urlsslport"),
		&ui_opt_textbox("web_urlsslport", $tmpl->{'web_urlsslport'}, 6,
				$text{'newweb_sameport'}));

	# Disallowed SSL protocol versions
	print &ui_table_row(
		&hlink($text{'newweb_sslprotos'}, "template_web_sslprotos"),
		&ui_opt_textbox("web_sslprotos", $tmpl->{'web_sslprotos'}, 30,
				$text{'newweb_sslprotos_def'}));

	if (defined(&get_domain_ruby_mode)) {
		# Run ruby scripts as user
		print &ui_table_row(
		    &hlink($text{'tmpl_rubymode'}, "template_rubymode"),
		    &ui_radio("web_ruby_suexec",int($tmpl->{'web_ruby_suexec'}),
			      [ [ -1, $text{'phpmode_noruby'}."<br>" ],
				[ 0, $text{'phpmode_mod_ruby'}."<br>" ],
				[ 1, $text{'phpmode_cgi'}."<br>" ] ]));
		}
	$hr++;
	}

if ($config{'web'} && $config{'webalizer'}) {
	print &ui_table_hr();

	# Webalizer stats sub-directory input
	local $smode = $tmpl->{'web_stats_hdir'} ? 2 :
		       $tmpl->{'web_stats_dir'} ? 1 : 0;
	local ($hdir) = ($tmpl->{'web_html_dir'} || 'public_html');
	print &ui_table_row(&hlink($text{'newweb_statsdir'}, "template_stats_dir"),
		&ui_radio("stats_mode", $smode,
		  [ [ 0, "$text{'default'} (<tt>$hdir/stats</tt>)<br>" ],
		    [ 1, &text('newweb_statsdir0', "<tt>$hdir</tt>")."\n".
			 &ui_textbox("stats_dir",
				     $tmpl->{'web_stats_dir'}, 20)."<br>" ],
		    [ 2, &text('newweb_statsdir2', "<tt>$hdir</tt>")."\n".
			 &ui_textbox("stats_hdir",
				     $tmpl->{'web_stats_hdir'}, 20) ] ]));

	# Password-protect webalizer dir
	print &ui_table_row(
		&hlink($text{'newweb_statspass'}, "template_statspass"),
		&ui_radio("statspass", $tmpl->{'web_stats_pass'} ? 1 : 0,
			  [ [ 1, $text{'yes'} ], [ 0, $text{'no'} ] ]));

	# Allow editing of Webalizer report
	print &ui_table_row(
		&hlink($text{'newweb_statsedit'}, "template_statsedit"),
		&ui_radio("statsnoedit", $tmpl->{'web_stats_noedit'} ? 1 : 0,
			  [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

	# Webalizer template
	print &ui_table_row(&hlink($text{'tmpl_webalizer'},
				   "template_webalizer"),
	    &none_def_input("webalizer", $tmpl->{'webalizer'},
			    $text{'tmpl_webalizersel'}, 0, 0,
			    $text{'tmpl_webalizernone'}, [ "webalizer" ])."\n".
	    &ui_textbox("webalizer", $tmpl->{'webalizer'} eq "none" ?
					"" : $tmpl->{'webalizer'}, 40));

	print &ui_table_hr();
	}

# Add redirects for webmail and admin
print &ui_table_hr()
	if ($hr);
foreach my $r ('webmail', 'admin') {
	my @opts = ( [ 1, $text{'yes'} ],
		     [ 0, $text{'no'} ] );
	if (!$tmpl->{'default'}) {
		unshift(@opts, [ '', $text{'tmpl_default'} ]);
		}
	print &ui_table_row(&hlink($text{'newweb_'.$r},
				   "template_".$r),
		&ui_radio($r, $tmpl->{'web_'.$r}, \@opts));

	# Domain name to use in webmail redirect
	print &ui_table_row(&hlink($text{'newweb_'.$r.'dom'},
				   "template_".$r."dom"),
		&ui_opt_textbox($r."dom",
				$tmpl->{'web_'.$r.'dom'}, 40,
				$text{'newweb_webmailsame'}));
	}

# Website default HTML
my $content_web_html;
if ($virtualmin_pro) { # Virtualmin Pro only feature as it was before
	my $content_web_file =
		"$module_var_directory/website-default-page-$tmpl->{'id'}";
	$content_web_html = &read_file_contents($content_web_file)
		if (-r $content_web_file);
	}
$tmpl->{'content_web'} = 2 if $tmpl->{'content_web'} eq '';
print &ui_table_row(&hlink($text{'tmpl_content_web'},
	'tmpl_content_web'.($virtualmin_pro ? '_pro' : '')),
  &ui_radio('content_web', $tmpl->{'content_web'},
	      [ [ 1, $text{'tmpl_content_web_dis'} ],
	        $virtualmin_pro ? [ 3, $text{'tmpl_content_web_later'} ] : ( ),
	        [ 2, $text{'form_content2'} ],
		$virtualmin_pro ? [ 0, $text{'form_content0'} ] : ( ) ]).
  ($virtualmin_pro ? ("<br>\n".
    &ui_textarea("content_web_html", $content_web_html, 5, 50)) : ""));

# Disabled website HTML
print &ui_table_row(&hlink($text{'tmpl_disabled_web'},
		    'disabled_web'),
  &none_def_input("disabled_web", $tmpl->{'disabled_web'},
		  $text{'tmpl_disabled_websel'}, 0, 0,
		  $text{'tmpl_disabled_webdef'}, [ "disabled_web" ])."<br>\n".
  &ui_textarea("disabled_web",
    $tmpl->{'disabled_web'} eq "none" ? undef :
      join("\n", split(/\t/, $tmpl->{'disabled_web'})),
    5, 50));

# Disabled website URL
$url = $tmpl->{'disabled_url'};
$url = "" if ($url eq "none");
print &ui_table_row(&hlink($text{'tmpl_disabled_url'},
		    'disabled_url'),
  &none_def_input("disabled_url", $tmpl->{'disabled_url'},
	  &text('tmpl_disabled_urlsel',
		&ui_textbox("disabled_url", $url, 30)), 0, 0,
	  $text{'tmpl_disabled_urlnone'}, [ "disabled_url" ]));

if ($config{'proxy_pass'} == 2) {
	# Frame-forwarding HTML (if enabled)
	print &ui_table_hr();

	print &ui_table_row(&hlink($text{'tmpl_frame'}, "template_frame"),
		&none_def_input("frame", $tmpl->{'frame'},
				$text{'tmpl_framebelow'}, 1, 0, undef,
				[ "frame" ])."<br>".
		&ui_textarea("frame", $tmpl->{'frame'} eq "none" ? undef :
				join("\n", split(/\t/, $tmpl->{'frame'})),
				10, 60));
	}

# Enable HTTP2 for new websites
my @opts = ( [ 0, $text{'newweb_http2_def'} ],
	     [ 1, $text{'yes'} ],
	     [ 2, $text{'no'} ] );
if (!$tmpl->{'default'}) {
	unshift(@opts, [ '', $text{'newweb_http2_inherit'} ]);
	}
print &ui_table_row(&hlink($text{'newweb_http2'}, 'template_web_http2'),
    &ui_radio("web_http2", $tmpl->{'web_http2'}, \@opts));

# Default redirects
print &ui_table_hr();
my @redirs = map { [ split(/\s+/, $_, 4) ] }
		 split(/\t+/, $tmpl->{'web_redirects'});
push(@redirs, [ "", "", "http,https" ]);
my $rtable = &ui_columns_start(
    [ $text{'newweb_rfrom'}, $text{'newweb_rto'},
      $text{'newweb_rhost'}, $text{'newweb_rprotos'} ]);
for(my $i=0; $i<@redirs; $i++) {
	my %protos = map { $_, 1 } split(/,/, $redirs[$i]->[2]);
	$rtable .= &ui_columns_row([
		&ui_textbox("rfrom_$i", $redirs[$i]->[0], 30),
		&ui_textbox("rto_$i", $redirs[$i]->[1], 30),
		&ui_opt_textbox("rhost_$i", $redirs[$i]->[3], 20,
				$text{'newweb_rany'}),
		&vui_ui_block_no_wrap(
			&ui_checkbox("rprotos_$i", "http", "HTTP",
				     $protos{'http'})." ".
			&ui_checkbox("rprotos_$i", "https", "HTTPS",
				     $protos{'https'}), 1)
		]);
	}
$rtable .= &ui_columns_end();
$rtable .= &ui_checkbox("sslredirect", 1, $text{'newweb_sslredirect'},
			$tmpl->{'web_sslredirect'});
print &ui_table_row(&hlink($text{'newweb_redirects'}, 'template_web_redirects'),
	$rtable);
}

# parse_template_web(&tmpl)
# Updates webserver related template options from %in
sub parse_template_web
{
local ($tmpl) = @_;

# Save web-related settings
$old_web_port = $web_port;
$old_web_sslport = $web_sslport;
if ($config{'web'}) {
	$tmpl->{'web'} = &parse_none_def("web");
	if ($in{"web_mode"} == 2) {
		$err = &check_apache_directives($in{"web"});
		&error($err) if ($err);
		$in{'web_ssl'} =~ s/\r?\n/\t/g;
		$tmpl->{'web_ssl'} = $in{'web_ssl'};
		if (defined($in{'writelogs'})) {
			$tmpl->{'web_writelogs'} = $in{'writelogs'};
			}
		if ($in{'html_dir_def'}) {
			delete($tmpl->{'web_html_dir'});
			}
		else {
			$in{'html_dir'} =~ /^\S+$/ && $in{'html_dir'} !~ /^\// &&
			    $in{'html_dir'} !~ /\.\./ || &error($text{'newweb_ehtml'});
			$tmpl->{'web_html_dir'} = $in{'html_dir'};
			}
		$in{'html_perms'} =~ /^[0-7]{3,4}$/ ||
			&error($text{'newweb_ehtmlperms'});
		$tmpl->{'web_html_perms'} = $in{'html_perms'};
		if ($in{'user_def'} == 0) {
			delete($tmpl->{'web_user'});
			}
		elsif ($in{'user_def'} == 2) {
			$tmpl->{'web_user'} = 'none';
			}
		else {
			defined(getpwnam($in{'user'})) || &error($text{'newweb_euser'});
			$tmpl->{'web_user'} = $in{'user'};
			}
		$tmpl->{'web_alias'} = $in{'alias_mode'};
		if (defined($in{'cgimode'})) {
			$tmpl->{'web_cgimode'} = $in{'cgimode'};
			}

		$in{'web_port'} =~ /^\d+$/ && $in{'web_port'} > 0 &&
			$in{'web_port'} < 65536 || &error($text{'newweb_eport'});
		$tmpl->{'web_port'} = $in{'web_port'};
		$in{'web_sslport'} =~ /^\d+$/ && $in{'web_sslport'} > 0 &&
			$in{'web_sslport'} < 65536 ||
				&error($text{'newweb_esslport'});
		$in{'web_port'} != $in{'web_sslport'} ||
				&error($text{'newweb_esslport2'});
		$tmpl->{'web_sslport'} = $in{'web_sslport'};

		$in{'web_urlport_def'} || $in{'web_urlport'} =~ /^\d+$/ ||
			&error($text{'newweb_eport'});
		$tmpl->{'web_urlport'} = $in{'web_urlport_def'} ?
						undef : $in{'web_urlport'};
		$in{'web_urlsslport_def'} || $in{'web_urlsslport'} =~ /^\d+$/ ||
			&error($text{'newweb_esslport'});
		$tmpl->{'web_urlsslport'} = $in{'web_urlsslport_def'} ?
						undef : $in{'web_urlsslport'};
		if ($in{'web_sslprotos_def'}) {
			$tmpl->{'web_sslprotos'} = undef;
			}
		else {
			foreach my $p (split(/\s+/, $in{'web_sslprotos'})) {
				$p =~ /^[\+\-]?(TLS|SSL)v[0-9\.]+$/ || $p eq "all" ||
					&error($text{'newweb_esslproto'});
				}
			$tmpl->{'web_sslprotos'} = $in{'web_sslprotos'};
			}

		# Parse SSI setting
		$tmpl->{'web_ssi'} = $in{'web_ssi'};
		if ($in{'web_ssi'} == 1) {
			$in{'web_ssi_suffix'} =~ /^\.([a-z0-9\.\_\-]+)$/i ||
				&error($text{'phpmode_essisuffix'});
			$tmpl->{'web_ssi_suffix'} = $in{'web_ssi_suffix'};
			}

		# Save ruby settings
		if (defined(&get_domain_ruby_mode)) {
			if ($in{'web_ruby_suexec'} > 0) {
				&has_command("ruby") ||
					&error($text{'tmpl_erubycmd'});
				}
			$tmpl->{'web_ruby_suexec'} = $in{'web_ruby_suexec'};
			}
		}
	}
else {
	# Some options apply to any webserver
	if ($in{'html_dir_def'}) {
		delete($tmpl->{'web_html_dir'});
		}
	else {
		$in{'html_dir'} =~ /^\S+$/ && $in{'html_dir'} !~ /^\// &&
		    $in{'html_dir'} !~ /\.\./ || &error($text{'newweb_ehtml'});
		$tmpl->{'web_html_dir'} = $in{'html_dir'};
		}
	$in{'html_perms'} =~ /^[0-7]{3,4}$/ ||
		&error($text{'newweb_ehtmlperms'});
	$tmpl->{'web_html_perms'} = $in{'html_perms'};
	if (defined($in{'cgimode'})) {
		$tmpl->{'web_cgimode'} = $in{'cgimode'};
		}
	}

if ($config{'web'} && $config{'webalizer'}) {
	# Save webalizer options
	delete($tmpl->{'web_stats_dir'});
	delete($tmpl->{'web_stats_hdir'});
	$smode = $in{'stats_mode'} == 1 ? "stats_dir" :
		 $in{'stats_mode'} == 2 ? "stats_hdir" : undef;
	if ($smode) {
		$in{$smode} =~ /^\S+$/ && $in{$smode} !~ /^\// &&
			$in{$smode} !~ /\.\./ || &error($text{'newweb_estats'});
		$tmpl->{"web_".$smode} = $in{$smode};
		}
	$tmpl->{'web_stats_pass'} = $in{'statspass'};
	$tmpl->{'web_stats_noedit'} = $in{'statsnoedit'};
	$tmpl->{'webalizer'} = &parse_none_def("webalizer");
	if ($in{"webalizer_mode"} == 2) {
		-r $in{'webalizer'} || &error($text{'tmpl_ewebalizer'});
		}
	}

# Parse webmail redirect
foreach my $r ('webmail', 'admin') {
	$tmpl->{'web_'.$r} = $in{$r};
	if ($in{$r.'dom_def'}) {
		delete($tmpl->{'web_'.$r.'dom'});
		}
	else {
		$in{$r.'dom'} =~ /^(http|https):\/\/\S+$/ ||
			&error($text{'newweb_e'.$r.'dom'});
		$tmpl->{'web_'.$r.'dom'} = $in{$r.'dom'};
		}
	}

# Save default website HTML
my $content_web_file =
	"$module_var_directory/website-default-page-$tmpl->{'id'}";
if ($in{'content_web'} eq "0") {
	my $data = $in{'content_web_html'};
	$data =~ s/\r\n/\n/g;
	$data || &error($text{'tmpl_content_web_html_eempty'});
	my $fh;
	if (!&open_tempfile($fh, ">$content_web_file")) {
		&error($text{'tmpl_content_web_html_esave'} . " : " .
			&html_escape("$!"));
		}
	&print_tempfile($fh, $data);
	&close_tempfile($fh);
	}
$tmpl->{'content_web'} = $in{'content_web'};
$tmpl->{'content_web_html'} =
	$tmpl->{'content_web'} eq "0" ? $content_web_file : undef;

# Save disabled website HTML
$tmpl->{'disabled_web'} = &parse_none_def("disabled_web");
if ($in{'disabled_url_mode'} == 2) {
	$in{'disabled_url'} =~ /^(http|https):\/\/\S+/ ||
		&error($text{'tmpl_edisabled_url'});
	}
$tmpl->{'disabled_url'} = &parse_none_def("disabled_url");

if ($config{'proxy_pass'} == 2) {
	# Save frame-forwarding settings
	$tmpl->{'frame'} = &parse_none_def("frame");
	}

# Save HTTP2 option
$tmpl->{'web_http2'} = $in{'web_http2'};

# Save default redirects
my @redirs;
my ($rfrom, $rto);
for(my $i=0; defined($rfrom = $in{"rfrom_$i"}); $i++) {
	$rto = $in{"rto_$i"};
	next if (!$rfrom && !$rto);
	$rfrom =~ /^\// || &error(&text('newweb_efrom', $i+1));
	$rto =~ /^\// || $rto =~ /^(http|https):/ ||
		&error(&text('newweb_eto', $i+1));
	$rprotos = join(",", split(/\0/, $in{"rprotos_$i"}));
	$rprotos || &error(&text('newweb_eprotos', $i+1));
	$rhost = $in{"rhost_${i}_def"} ? "" : $in{"rhost_${i}"};
	push(@redirs, [ $rfrom, $rto, $rprotos, $rhost ]);
	}
$tmpl->{'web_redirects'} = join("\t", map { join(" ", @$_) } @redirs);
$tmpl->{'web_sslredirect'} = $in{'sslredirect'};
}

# postsave_template_web(&template)
# Called after a template is saved
sub postsave_template_web
{
if ($tmpl->{'id'} == 0) {
	# If the web or SSL ports were changed, all existing virtual hosts
	# should be updated with the *old* setting to that we know what port
	# they were created on
	if ($old_web_port != $in{'web_port'} ||
	    $old_web_sslport != $in{'web_sslport'}) {
		foreach $d (&list_domains()) {
			&save_domain($d);
			}
		}
	}
}

sub show_template_php
{
my ($tmpl) = @_;
my @fields = ( "web_phpver", "web_phpchildren", "web_phpchildren_def",
	       "web_php_noedit", "php_fpm", "php_sock", "php_log",
	       "php_log_path", "php_log_path_def" );
my $dis1 = &js_disable_inputs(\@fields, [ ]);
my $dis2 = &js_disable_inputs([ ], \@fields);

# Run PHP scripts using mode
my $mmap = &php_mode_numbers_map();
my %cannums = map { $mmap->{$_}, 1 } &supported_php_modes();
if ($tmpl->{'web_php_suexec'} ne '') {
	$cannums{int($tmpl->{'web_php_suexec'})} = 1;
	}
my @opts = grep { $cannums{$_->[0]} }
		([ 4, $text{'phpmode_none'}, undef, "onClick='$dis2'" ],
	         [ 3, $text{'phpmode_fpm'}, undef, "onClick='$dis2'" ],
	         [ 2, $text{'phpmode_fcgid'}, undef, "onClick='$dis2'" ],
	         [ 1, $text{'phpmode_cgi'}, undef, "onClick='$dis2'" ],
		 [ 0, &ui_text_color($text{'phpmode_mod_php'}, 'danger'),
		      undef, "onClick='$dis2'" ],
		);
if (!$tmpl->{'default'}) {
	unshift(@opts, [ '', $text{'tmpl_default'}, undef, "onClick='$dis1'" ]);
	}
print &ui_table_row(
    &hlink($text{'tmpl_phpmode'}, "template_phpmode"),
    &ui_radio_table("web_php_suexec", $tmpl->{'web_php_suexec'}, \@opts));

# Default PHP version to setup
print &ui_table_row(
    &hlink($text{'tmpl_phpver'}, "template_phpver"),
    &ui_select("web_phpver", $tmpl->{'web_phpver'},
	       [ [ "", $text{'tmpl_phpverdef'} ],
		 map { my $fullver = &get_php_version($_->[1]);
		       [ $_->[0], $fullver || $_->[0] ] }
		     &list_available_php_versions() ]));

# Default number of PHP child processes
print &ui_table_row(
    &hlink($text{'tmpl_phpchildren'}, "template_phpchildren"),
    &ui_opt_textbox("web_phpchildren", $tmpl->{'web_phpchildren'}, 5,
	int($tmpl->{'web_php_suexec'}) == 2 ? 
	$text{'tmpl_phpchildrenauto'} :
	&text('tmpl_phpchildrennone', &get_php_max_childred_allowed())));

# Allow editing of PHP configs
print &ui_table_row(
    &hlink($text{'tmpl_php_noedit'}, "template_php_noedit"),
    &ui_radio("web_php_noedit", $tmpl->{'web_php_noedit'},
	      [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

# FPM specific options
if (&indexof("fpm", &supported_php_modes()) >= 0) {
	# Template pool config file
	print &ui_table_row(
		&hlink($text{'tmpl_php_fpm'}, "template_php_fpm"),
		&ui_textarea("php_fpm",
			$tmpl->{'php_fpm'} eq 'none' ? '' :
			join("\n", split(/\t/, $tmpl->{'php_fpm'})), 5, 80));

	# Use socket file or TCP port?
	print &ui_table_row(
		&hlink($text{'tmpl_php_sock'}, "template_php_sock"),
		&ui_radio("php_sock", $tmpl->{'php_sock'},
		  [ $tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ),
		    [ 0, $text{'tmpl_php_sock0'} ],
		    [ 1, $text{'tmpl_php_sock1'} ] ]));
	}

# Default PHP log file
print &ui_table_row(
	&hlink($text{'tmpl_php_log'}, "template_php_log"),
	&ui_radio("php_log", $tmpl->{'php_log'},
	  [ $tmpl->{'default'} ? ( ) : ( [ "", $text{'default'} ] ),
	    [ 1, $text{'yes'} ],
	    [ 0, $text{'no'} ] ]));

print &ui_table_row(
	&hlink($text{'tmpl_php_log_path'}, "template_php_log_path"),
	&ui_opt_textbox("php_log_path", $tmpl->{'php_log_path'}, 60,
			$text{'default'}." (<tt>logs/php_log</tt>)"));

print &ui_table_hr();

# PHP variables for scripts
local $i = 0;
local @pv = $tmpl->{'php_vars'} eq "none" ? ( ) :
	split(/\t+/, $tmpl->{'php_vars'});
local @pfields;
local @table;
foreach $pv (@pv, "", "") {
	local ($n, $v) = split(/=/, $pv, 2);
	local $diff = $n =~ s/^(\+|\-)// ? $1 : undef;
	push(@table, [ &ui_textbox("phpname_$i", $n, 25),
		       &ui_select("phpdiff_$i", $diff,
				  [ [ '', $text{'tmpl_phpexact'} ],
				    [ '+', $text{'tmpl_phpatleast'} ],
				    [ '-', $text{'tmpl_phpatmost'} ] ]),
		       &ui_textbox("phpval_$i", $v, 35), ]);
	push(@pfields, "phpname_$i", "phpdiff_$i", "phpval_$i");
	$i++;
	}
local $ptable = &ui_columns_table(
	[ $text{'tmpl_phpname'}, $text{'tmpl_phpdiff'}, $text{'tmpl_phpval'} ],
	undef,
	\@table,
	undef,
	1);
print &ui_table_row(
	&hlink($text{'tmpl_php_vars'}, "template_php_vars"),
	&none_def_input("php_vars", $tmpl->{'php_vars'},
			$text{'tmpl_disabled_websel'}, 0, 0, undef,
			\@pfields)."<br>\n".
	$ptable);
}

# parse_template_php(&tmpl)
# Updates PHP related template options from %in
sub parse_template_php
{
local ($tmpl) = @_;

# Save PHP settings
&require_apache();
if ($in{'web_php_suexec'} ne '') {
	if ($in{'web_php_suexec'} == 1 || $in{'web_php_suexec'} == 2) {
		my @vers = grep { $_->[1] }
				&list_available_php_versions(undef, "cgi");
		@vers || &error($text{'tmpl_ephpcmd'});
		}
	$tmpl->{'web_php_suexec'} = $in{'web_php_suexec'};

	# Check that PHP version is valid for the mode
	my $mmap = &php_mode_numbers_map();
	$mmap = { reverse(%$mmap) };
	my $mode = $mmap->{$in{'web_php_suexec'}};
	if ($in{'web_phpver'} && $mode && $mode ne "none") {
		my @vers = map { $_->[0] }
			       &list_available_php_versions(undef, $mode);
		my ($gotver) = grep { $_ eq $in{'web_phpver'} } @vers;
		$gotver || &error(&text('tmpl_ephpvers', $in{'web_phpver'},
					$mode, join(", ", @vers)));
		}
	$tmpl->{'web_phpver'} = $in{'web_phpver'};

	# Save PHP child processes
	if ($in{'web_phpchildren_def'} ||
	    !defined($in{'web_phpchildren_def'})) {
		$tmpl->{'web_phpchildren'} = undef;
		}
	else {
		if ($in{'web_phpchildren'} < 1) {
			&error($text{'phpmode_echildren'});
			}
		$tmpl->{'web_phpchildren'} = $in{'web_phpchildren'};
		}

	# Save option to edit php.ini
	$tmpl->{'web_php_noedit'} = $in{'web_php_noedit'};

	# Save FPM specific options
	if (&indexof("fpm", &supported_php_modes()) >= 0) {
		if ($in{'php_fpm'}) {
			$tmpl->{'php_fpm'} =
				join("\t", split(/\r?\n/, $in{'php_fpm'}));
			}
		else {
			$tmpl->{'php_fpm'} = 'none';
			}
		$tmpl->{'php_sock'} = $in{'php_sock'};
		}
	$tmpl->{'php_log'} = $in{'php_log'};
	$tmpl->{'php_log_path'} = $in{'php_log_path_def'} ? undef : $in{'php_log_path'};
	}
else {
	$tmpl->{'web_php_suexec'} = '';
	}

# Save PHP variables
if ($in{"php_vars_mode"} == 0) {
	$tmpl->{'php_vars'} = "none";
	}
elsif ($in{"php_vars_mode"} == 1) {
	delete($tmpl->{'php_vars'});
	}
elsif ($in{"php_vars_mode"} == 2) {
	for($i=0; defined($n = $in{"phpname_$i"}); $i++) {
		next if (!$n);
		$n =~ /^\S+$/ ||
			&error(&text('tmpl_ephp_var', $n));
		$v = $in{"phpval_$i"};
		$diff = $in{"phpdiff_$i"};
		push(@phpvars, $diff.$n."=".$v);
		}
	$tmpl->{'php_vars'} = join("\t", @phpvars);
	}
}

# list_php_wrapper_templates([only-installed])
# Returns the list of template names for PHP wrappers, based on the installed
# PHP versions
sub list_php_wrapper_templates
{
my ($only) = @_;
my @vers;
if ($only) {
	@vers = map { $_->[0] } &list_available_php_versions();
	}
push(@vers, @all_possible_php_versions);
@vers = &unique(@vers);
my @rv;
push(@rv, map { "php".$_."cgi" } @vers);
push(@rv, map { "php".$_."fcgi" } @vers);
return @rv;
}

# show_template_phpwrappers(&template)
# Outputs HTML for setting custom PHP wrapper scripts
sub show_template_phpwrappers
{
local ($tmpl) = @_;
foreach my $w (&unique(&list_php_wrapper_templates(1))) {
	local $ndi = &none_def_input($w, $tmpl->{$w},
				     $text{'tmpl_wrapperbelow'}, 0, 0,
				     $text{'tmpl_wrappernone'}, [ $w ]);
	$w =~ /^php([0-9\.]+)(cgi|fcgi)/ || next;
	local ($v, $t) = ($1, $2);
	print &ui_table_row(&hlink(&text('tmpl_php'.$t, $v), "template_php".$t),
			    $ndi."<br>".
		&ui_textarea($w, $tmpl->{$w} eq "none" ? "" :
				join("\n", split(/\t/, $tmpl->{$w})),
			     5, 60));
	}
}

# parse_template_phpwrappers(&template)
# Update the template with inputs from show_template_phpwrappers
sub parse_template_phpwrappers
{
local ($tmpl) = @_;
foreach my $w (&unique(&list_php_wrapper_templates(1))) {
	$w =~ /^php([0-9\.]+)(cgi|fcgi)/ || next;
	local ($v, $t) = ($1, $2);
	if ($in{$w."_mode"} == 0) {
		$tmpl->{$w} = 'none';
		}
	elsif ($in{$w."_mode"} == 1) {
		delete($tmpl->{$w});
		}
	elsif ($in{$w."_mode"} == 2) {
		$in{$w} =~ s/\r//g;
		$in{$w} =~ /^\#\!/ || &error(&text('tmpl_ephp'.$t, $v));
		$tmpl->{$w} = $in{$w};
		$tmpl->{$w} =~ s/\n/\t/g;
		}
	}
}

# get_domain_suexec(&domain)
# Returns 1 if some virtual host is setup to use suexec
sub get_domain_suexec
{
local ($d) = @_;
&require_apache();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return 0 if (!$virt);
local $su = &apache::find_directive("SuexecUserGroup", $vconf);
return $su ? 1 : 0;
}

# template_to_php_mode(&tmpl)
# Returns the default PHP execution mode selected by a template
sub template_to_php_mode
{
my ($tmpl) = @_;
my $mmap = &php_mode_numbers_map();
$mmap = { reverse(%$mmap) };
return $mmap->{int($tmpl->{'web_php_suexec'})};
}

# add_script_language_directives(&domain, &tmpl, port)
# Adds directives needed to enable PHP, Ruby and other languages to the
# <virtualhost> for some new domain.
sub add_script_language_directives
{
local ($d, $tmpl, $port) = @_;
my $err;

# Find a usable PHP mode
&require_apache();
my $mode = $d->{'default_php_mode'} || &template_to_php_mode($tmpl);
delete($d->{'default_php_mode'});
my @supp = &supported_php_modes();
if (&indexof($mode, @supp) < 0) {
	if (@supp) {
		$mode = $supp[0];
		}
	else {
		$err = &text('setup_ewebphpmode', $mode);
		$mode = undef;
		}
	}
if ($mode) {
	&save_domain_php_mode($d, $mode, $port, 1);
	if ($d->{'php_error_log'}) {
		&save_domain_php_error_log($d, $d->{'php_error_log'});
		}
	elsif ($tmpl->{'php_log'}) {
		&save_domain_php_error_log($d, &get_default_php_error_log($d));
		}
	}

if (defined(&save_domain_ruby_mode)) {
	if ($tmpl->{'web_ruby_suexec'} >= 0) {
		# Setup for Ruby
		&save_domain_ruby_mode($d,
			$tmpl->{'web_ruby_suexec'} == 0 ? "mod_ruby" :
			$tmpl->{'web_ruby_suexec'} == 1 ? "cgi" : "fcgid",
			$port, 1);
		}
	}

return $err;
}

# add_webmail_redirect_directives(&domain, &template, [force-enable])
# Add mod_rewrite directives to direct webmail.$DOM and admin.$DOM to
# Usermin and Webmin. Also updates the ServerAlias if needed.
sub add_webmail_redirect_directives
{
my ($d, $tmpl, $force) = @_;
$tmpl ||= &get_template($d->{'template'});
my $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_add_web_webmail_redirect", $d, $tmpl,
			    $force);
	}
&require_apache();
my $reald = $d->{'alias'} ? &get_domain($d->{'alias'}) : $d;
my @ports = ( $reald->{'web_port'} );
push(@ports, $reald->{'web_sslport'}) if ($reald->{'ssl'});

my $fixed = 0;
my @redirects = &list_redirects($reald);
foreach my $r ('webmail', 'admin') {
	next if (!$tmpl->{'web_'.$r} && !$force);

	# Work out the URL to redirect to
	my $url = $tmpl->{'web_'.$r.'dom'};
	if ($url) {
		# Sub in any template
		$url = &substitute_domain_template($url, $d);
		}
	else {
		# Work out URL
		my ($port, $proto);
		if ($r eq 'webmail') {
			# From Usermin
			($port, $proto) = &get_usermin_miniserv_port_proto();
			}
		else {
			# From Webmin
			($port, $proto) = &get_miniserv_port_proto();
			}
		$url = "$proto://$d->{'dom'}:$port/";
		}

	# Check for and add the redirect
	my $rhost = "$r.$d->{'dom'}";
	my ($r) = grep { $_->{'host'} eq $rhost } @redirects;
	if (!$r) {
		$r = { 'path' => '/',
		       'dest' => $url,
		       'host' => $rhost,
		       'http' => 1,
		       'https' => 1,
		       'alias' => 0 };
		$r = &add_wellknown_redirect($r);
		&create_redirect($reald, $r);
		}

	# Add a ServerAlias directive
	my $fixedone = 0;
	foreach my $port (@ports) {
		my ($virt, $vconf, $conf) =
			&get_apache_virtual($reald->{'dom'}, $port);
		next if (!$virt);

		# Add the ServerAlias
		my @sa = &apache::find_directive("ServerAlias", $vconf);
		my $foundsa;
		foreach my $s (@sa) {
			$foundsa++ if (&indexof($rhost, split(/\s+/, $s)) >= 0);
			}
		push(@sa, $rhost) if (!$foundsa);
		&apache::save_directive("ServerAlias", \@sa, $vconf, $conf);
		$fixedone++;
		}
	if ($fixedone) {
		&flush_file_lines($virt->{'file'});
		$fixed++;
		}
	}
if ($fixed) {
	&register_post_action(\&restart_apache);
	}
}

# remove_webmail_redirect_directives(&domain)
# Take out webmail and admin redirects from the Apache config
sub remove_webmail_redirect_directives
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_remove_web_webmail_redirect", $d);
	}

# Find the redirects to remove
my @redirects = &list_redirects($d);
foreach my $r (reverse(@redirects)) {
	if ($r->{'host'} eq 'admin.'.$d->{'dom'} ||
	    $r->{'host'} eq 'webmail.'.$d->{'dom'}) {
		&delete_redirect($d, $r);
		}
	}

# Fix up the ServerAlias directives
my $fixed = 0;
&require_apache();
my $reald = $d->{'alias'} ? &get_domain($d->{'alias'}) : $d;
my @ports = ( $reald->{'web_port'} );
push(@ports, $reald->{'web_sslport'}) if ($reald->{'ssl'});
foreach my $port (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($reald->{'dom'}, $port);
	next if (!$virt);
	my @sa = &apache::find_directive("ServerAlias", $vconf);
	my @newsa;
	foreach my $s (@sa) {
		my @sav = split(/\s+/, $s);
		@sav = grep { $_ ne "webmail.$d->{'dom'}" &&
			      $_ ne "admin.$d->{'dom'}" } @sav;
		if (@sav) {
			push(@newsa, join(" ", @sav));
			}
		}
	&apache::save_directive("ServerAlias", \@newsa, $vconf, $conf);
	$fixed++;
	}

if ($fixed) {
	&flush_file_lines($virt->{'file'});
	&register_post_action(\&restart_apache);
	}
return $fixed;
}

# get_webmail_redirect_directives(&domain)
# Returns the list of hostnames,path pairs if a domain has webmail redirects
# configured
sub get_webmail_redirect_directives
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_get_web_webmail_redirect", $d);
	}
my @rv;
my $reald = $d->{'alias'} ? &get_domain($d->{'alias'}) : $d;
my @redirects = &list_redirects($reald);
foreach my $r (@redirects) {
	if ($r->{'host'} eq 'admin.'.$d->{'dom'} ||
	    $r->{'host'} eq 'webmail.'.$d->{'dom'}) {
		push(@rv, [ $r->{'host'}, $r->{'path'} ]);
		}
	}
return @rv;
}

# add_require_all_granted_directives(&dom, [port])
# For Apache 2.4+, add a "Require all granted" directive, if no other Require
# exists with a granted value for anything
sub add_require_all_granted_directives
{
local ($d, $oneport) = @_;
local @ports = $oneport ? ( $oneport ) :
	       $d->{'ssl'} ? ( $d->{'web_port'}, $d->{'web_sslport'} ) :
			     ( $d->{'web_port'} );
foreach my $port (@ports) {
	local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);
	if ($virt && $apache::httpd_modules{'core'} >= 2.4) {
		foreach my $pdir (&public_html_dir($d), &cgi_bin_dir($d)) {
			local ($dir) = grep { $_->{'words'}->[0] eq $pdir ||
					      $_->{'words'}->[0] eq $pdir."/" }
			    &apache::find_directive_struct("Directory", $vconf);
			if ($dir) {
				local @req = &apache::find_directive("Require",
							$dir->{'members'});
				local ($g) = grep { /granted/i } @req;
				if (!$g) {
					push(@req, "all granted");
					&apache::save_directive("Require",\@req,
						$dir->{'members'}, $conf);
					&flush_file_lines($dir->{'file'});
					}
				}
			}
		}
	}
}

# find_html_cgi_dirs(&domain)
# Updates the public_html_dir and cgi_bin_dir values in a domain's hash with
# their paths from Apache.
sub find_html_cgi_dirs
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p ne "web") {
	return &plugin_call($p, "feature_find_web_html_cgi_dirs", $d);
	}
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
if ($virt) {
	# Set public_html directory from document root
	local $str = &apache::find_directive_struct("DocumentRoot", $vconf);
	if ($str && !$d->{'public_html_correct'}) {
		$d->{'public_html_path'} = $str->{'words'}->[0];
		if ($d->{'public_html_path'} =~ /^\Q$d->{'home'}\E\/(.*)$/) {
			$d->{'public_html_dir'} = $1;
			}
		elsif ($d->{'public_html_path'} eq $d->{'home'}) {
			# Same as home directory!
			$d->{'public_html_dir'} = ".";
			}
		else {
			delete($d->{'public_html_dir'});
			}
		}

	# Set CGI directory from ScriptAlias for /cgi-bin/
	local @str = &apache::find_directive_struct("ScriptAlias", $vconf);
	@str = grep { $_->{'words'}->[0] eq '/cgi-bin/' ||
		      $_->{'words'}->[0] eq '/cgi-bin' } @str;
	if (@str && !$d->{'cgi_bin_correct'}) {
		$d->{'cgi_bin_path'} = $str[0]->{'words'}->[1];
		$d->{'cgi_bin_path'} =~ s/\/$//;
		if ($d->{'cgi_bin_path'} =~ /^\Q$d->{'home'}\E\/(.*)$/) {
			$d->{'cgi_bin_dir'} = $1;
			}
		else {
			delete($d->{'cgi_bin_dir'});
			}
		}
	}
}

# apache_in_domain_group(&domain)
# Returns 1 if the user Apache runs as is in the group for some domain,
# indicating that it can read files that are group-readable only
sub apache_in_domain_group
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $web_user = &get_apache_user($d);
if ($tmpl->{'web_user'} ne 'none' && $web_user) {
	# An Apache user is defined.. but is it a group member?
	local @uinfo = getpwnam($web_user);
	if ($uinfo[3] == $d->{'gid'} ||
            &indexof($d->{'group'}, &other_groups($web_user)) >= 0) {
		return 1;
		}
	}
return 0;
}

# obtain_lock_web(&domain)
# Lock the Apache config file for some domain
sub obtain_lock_web
{
local ($d) = @_;
return if (!$config{'web'});
&obtain_lock_anything($d);

# Where is the domain's .conf file? We have to guess, as actually checking could
# mean reading the whole Apache config in twice.
local $file = &get_website_file($d);
if ($main::got_lock_web_file{$file} == 0) {
	&lock_file($file);
	}
$main::got_lock_web_file{$file}++;
$main::got_lock_web_path{$d->{'id'}} = $file;

# Always lock main config file too, as we may modify it with a Listen
&require_apache();
local ($conf) = &apache::find_httpd_conf();
if ($conf) {
	if ($main::got_lock_web_file{$conf} == 0) {
		&lock_file($conf);
		}
	$main::got_lock_web_file{$conf}++;
	}
$main::got_lock_web_conf = $conf;
}

# release_lock_web(&domain)
# Un-lock the Apache config file for some domain
sub release_lock_web
{
local ($d) = @_;
return if (!$config{'web'});
local $file = $main::got_lock_web_path{$d->{'id'}};
if ($main::got_lock_web_file{$file} == 1) {
	&unlock_file($file);
	}
$main::got_lock_web_file{$file}-- if ($main::got_lock_web_file{$file});

# Unlock main config file too
local $conf = $main::got_lock_web_conf;
if ($conf) {
	if ($main::got_lock_web_file{$conf} == 1) {
		&unlock_file($conf);
		}
	$main::got_lock_web_file{$conf}-- if ($main::got_lock_web_file{$conf});
	}
&release_lock_anything($d);
}

# get_domain_web_star(&domain)
# Returns 1 if the webserver is configured to accept requests for any
# sub-domain under the domain, with a *.domain.com serveralias
sub get_domain_web_star
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_get_web_domain_star", $d);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
&require_apache();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
local @sa = &apache::find_directive("ServerAlias", $vconf);
my $withstar = "*.".$d->{'dom'};
foreach my $sa (@sa) {
	my @saw = split(/\s+/, $sa);
	return 1 if (&indexoflc($withstar, @saw) >= 0);
	}
return 0;
}

# save_domain_web_star(&domain, star-mode)
# Toggle accepting of *.domain.com requests on or off
sub save_domain_web_star
{
local ($d, $star) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_save_web_domain_star", $d, $star);
	}
elsif (!$p) {
	return "Virtual server does not have a website";
	}
&require_apache();
my $conf = &apache::get_config();
my @ports = ( $d->{'web_port'},
	      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my $withstar = "*.".$d->{'dom'};
foreach my $p (@ports) {
	my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	my @sa = &apache::find_directive("ServerAlias", $vconf);
	my $found;
	foreach my $sa (@sa) {
		local @saw = split(/\s+/, $sa);
		$found++ if (&indexoflc($withstar, @saw) >= 0);
		}
	my $done;
	if ($star && !$found) {
		# Need to add
		push(@sa, $withstar);
		$done++;
		}
	elsif (!$star && $found) {
		# Take away
		foreach my $sa (@sa) {
			local @saw = split(/\s+/, $sa);
			@saw = grep { lc($_) ne $withstar } @saw;
			$sa = join(" ", @saw);
			}
		$done++;
		}
	if ($done) {
		&apache::save_directive("ServerAlias", \@sa, $vconf, $conf);
		&flush_file_lines($virt->{'file'});
		$any++;
		}
	}
if ($any) {
	&register_post_action(\&restart_apache);
	}
}

# get_domain_supported_http_protocols(&domain)
# Returns an array ref of possible protocols for a domain's webserver, using the
# Apache names, or an error message. An empty array ref indicates no support
# for changing protocols.
sub get_domain_supported_http_protocols
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p eq 'web') {
	return &supports_http2() ? [ 'h2', 'h2c', 'http/1.1' ] : [ ];
	}
elsif ($p) {
	return &plugin_call($p, "feature_get_supported_http_protocols", $d);
	}
else {
	return "No website enabled for this domain";
	}
}

# get_domain_http_protocols(&domain)
# Returns an array ref of HTTP protocols currently enabled for a domain, an
# empty list if none are set, or an error message.
sub get_domain_http_protocols
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p eq 'web') {
	my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
	return "No Apache virtualhost found" if (!$virt);
	my ($prots) = &apache::find_directive("Protocols", $vconf);
	return [ ] if (!$prots);
	return [ split(/\s+/, $prots) ];
	}
elsif ($p) {
	return &plugin_call($p, "feature_get_http_protocols", $d);
	}
else {
	return "No website enabled for this domain";
	}
}

# get_default_http_protocols(&domain)
# Returns an array ref of HTTP protocols that will be used if none are set for
# a domain. If empty, there is no default.
sub get_default_http_protocols
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p eq 'web') {
	&require_apache();
	my $conf = &apache::get_config();
	my ($prots) = &apache::find_directive("Protocols", $conf);
	return $prots ? [ split(/\s+/, $prots) ] : [ 'http/1.1' ];
	}
elsif ($p) {
	if (&plugin_defined($p, "feature_default_http_protocols")) {
		return &plugin_call($p, "feature_default_http_protocols", $d);
		}
	else {
		return [ ];
		}
	}
else {
	return "No website enabled for this domain";
	}
}

# save_domain_http_protocols(&domain, &protocols)
# Updates the list of supported HTTP protocols, or sets to the default if the
# protocols list is empty. Returns undef on success or an error message on
# failure.
sub save_domain_http_protocols
{
my ($d, $prots) = @_;
my $p = &domain_has_website($d);
if ($p eq 'web') {
	my @ports = ( $d->{'web_port'},
		      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
	my @pdirs = ref($prots) && @$prots ? ( join(" ", @$prots) ) : ( );
	foreach my $p (@ports) {
		my ($virt, $vconf, $conf) =
			&get_apache_virtual($d->{'dom'}, $p);
		return "No Apache virtualhost found" if (!$virt);
		&apache::save_directive("Protocols", \@pdirs, $vconf, $conf);
		&flush_file_lines($virt->{'file'}, undef, 1);
		}
	&register_post_action(\&restart_apache);
	return undef;
	}
elsif ($p) {
	return &plugin_call($p, "feature_save_http_protocols", $d, $prots);
	}
else {
	return "No website enabled for this domain";
	}
}

# get_suexec_path()
# Returns the full path to the Apache suexec command, if installed, or undef
sub get_suexec_path
{
&require_apache();
local $httpd_dir = &apache::find_httpd();
$httpd_dir =~ s/\/[^\/]+$//;
foreach my $p ("suexec",			# In path
	       "/usr/lib/apache2/suexec",	# Debian
	       "/usr/lib/apache/suexec",
	       "/usr/local/bin/suexec",		# FreeBSD
	       "/usr/local/sbin/suexec",
	       "/opt/csw/apache2/sbin/suexec",	# Solaris CSW
	       "/opt/csw/apache/sbin/suexec",
	       "$httpd_dir/suexec",		# Same dir as httpd
	      ) {
	local $fp = &has_command($p) || &has_command($p."2");
	return $fp if ($fp);
	}
return undef;
}

# get_suexec_document_root()
# Returns the directories under which suexec will run binaries, or undef 
# if unknown
sub get_suexec_document_root
{
local $suexec = &get_suexec_path();
return ( ) if (!$suexec);
local $out = &backquote_command("$suexec -V 2>&1 </dev/null");
if ($out =~ /AP_DOC_ROOT="([^"]+)"/ ||
    $out =~ /AP_DOC_ROOT=(\S+)/) {
	return split(/:/, $1);
	}
# Try new Debian-style suexec config files
local $user = &get_apache_user();
if ($out =~ /SUEXEC_CONFIG_DIR="([^"]+)"/ ||
    $out =~ /SUEXEC_CONFIG_DIR=(\S+)/) {
	foreach my $cf ("$1/$user", "$1/www-data") {
		my @roots;
		next if (!-r $cf);
		my $lref = &read_file_lines($cf);
		foreach my $l (@$lref) {
			if ($l =~ /^(\/\S+)/) {
				push(@roots, $1);
				}
			}
		return @roots if (@roots);
		}
	}
return ( );
} 

# check_suexec_install(&template)
# Returns an error message if suexec does not appear to be installed properly.
sub check_suexec_install
{
local ($tmpl) = @_;
&require_useradmin();

# Make sure suexec is actually installed
local $suexec = &get_suexec_path();
local @suhome = &get_suexec_document_root();
if (!$suexec) {
	return $text{'check_ewebsuexecbin'};
	}

# Work out CGI base directory
local @dirs = split(/\t/, $tmpl->{'web'});
local $cgibase;
foreach my $l (@dirs) {
	if ($l =~ /^\s*ScriptAlias\s+\/cgi-bin\/?\s+(\/[^\$]*)/) {
		$cgibase = $1;
		}
	}
$cgibase =~ s/\/$//;

# Make sure home base is under a base directory, or template CGI directory is
if (@suhome) {
	foreach my $suhome (@suhome) {
		if (&same_file($suhome, $home_base) ||
		    &is_under_directory($suhome, $home_base) ||
		    $cgibase && &is_under_directory($suhome, $cgibase)) {
			# Got a match on a configured directory
			return undef;
			}
		}
	return &text('check_ewebsuexechome',
		     "<tt>$home_base</tt>", "<tt>".join(", ", @suhome)."</tt>");
	}
return undef;
}

# supports_suexec([&domain])
# Returns 1 if suexec is usable for a domain, 2 if usable and enabled and
# thus it can run CGI scripts. Otherwise return 0.
sub supports_suexec
{
local ($d) = @_;

# Does Apache even support suexec?
&require_apache();
if ($apache::httpd_modules{'core'} >= 2.0 &&
    !$apache::httpd_modules{'mod_suexec'}) {
	return 0;
	}

# Make sure suexec is actually installed
local $suexec = &get_suexec_path();
return 0 if (!$suexec);

# Is the domain's CGI directory under one of the roots?
&require_useradmin();
local @suhome = &get_suexec_document_root();
local $cgi = $d ? &cgi_bin_dir($d) : $home_base;
local $under = 0;
foreach my $suhome (@suhome) {
	if (&is_under_directory($suhome, $cgi)) {
		$under = 1;
		last;
		}
	}
return 0 if (!$under);

if ($d) {
	# Is suEXEC enabled in the Apache config?
	local ($virt, $vconf) = &get_apache_virtual(
					$d->{'dom'}, $d->{'web_port'});
	return 1 if (!$virt);
	local ($suexec) = &apache::find_directive_struct(
					"SuexecUserGroup", $vconf);
	return 1 if (!$suexec);
	return 2;
	}

return 1;
}

# supports_fcgiwrap()
# Returns 1 if fcgiwrap is supported by Apache on this system
sub supports_fcgiwrap
{
return 0 if (!&has_command("fcgiwrap"));
&require_apache();
if ($apache::site{'fullversion'}) {
	return &compare_versions($apache::site{'fullversion'}, "2.4.26") >= 0;
	}
else {
	return $apache::httpd_modules{'core'} >= 2.426;
	}
}

sub supports_check_peer_name
{
&require_apache();
return $apache::site{'fullversion'} &&
       &compare_versions($apache::site{'fullversion'}, "2.4.30") >= 0;
}

# supports_http2()
# Returns 1 if HTTPv2 is supported by Apache on this system, 2 if it is enabled
# by default, or 0 if not supported at all
sub supports_http2
{
&require_apache();
my $err;
if (!$apache::httpd_modules{'mod_http2'}) {
	$err = "Missing Apache <tt>mod_http2</tt> module";
	}
elsif ($apache::httpd_modules{'mod_mpm_prefork'}) {
	$err = "Incompatible Apache <tt>mpm_prefork</tt> module is enabled";
	}
elsif (!$apache::site{'fullversion'} ||
       &compare_versions($apache::site{'fullversion'}, "2.4.17") < 0) {
	$err = "Apache must be at least version 2.4.17";
	}
my $ok = $err ? 0 :
	 &compare_versions($apache::site{'fullversion'}, "2.4.37") >= 0 ? 2 : 1;
my @rv = ($ok, $err);
return wantarray ? @rv : $rv[0];
}

# setup_apache_logs(&domain, [access-log, error-log])
# Create empty Apache log files for a domain, and set their ownership
sub setup_apache_logs
{
local ($d, $log, $elog) = @_;
$log ||= &get_apache_log($d->{'dom'}, $d->{'web_port'}, 0);
$elog ||= &get_apache_log($d->{'dom'}, $d->{'web_port'}, 1);
local $auser = &get_apache_user($d);
local $gid = $auser && $auser ne 'none' ? $auser : $d->{'gid'};
foreach my $l ($log, $elog) {
	if ($l && !-r $l) {
		local $dir = $l;
		$dir =~ s/\/([^\/]+)$//;
		if (&is_under_directory($d->{'home'}, $dir)) {
			# If under home, create as the domain owner
			if (-l $l) {
				# Remove old symlink
				&unlink_file_as_domain_user($d, $l);
				}
			if (!-d $dir) {
				&make_dir_as_domain_user($d, $dir, 0711, 1);
				}
			&open_tempfile_as_domain_user($d, LOG, ">$l", 0, 1);
			&close_tempfile_as_domain_user($d, LOG);
			}
		else {
			# Can create as root
			if (!-d $dir) {
				# Create parent dir, such as /var/log/virtualmin
				&make_dir($dir, 0711, 1);
				}
			&open_tempfile(LOG, ">$l", 0, 1);
			&close_tempfile(LOG);
			}
		}
	# Make non-world-readable
	&set_apache_log_permissions($d, $l);
	}
}

# set_apache_log_permissions(&domain, logfile)
# Set correct ownership and permissions on an Apache log
sub set_apache_log_permissions
{
local ($d, $l) = @_;
local $auser = &get_apache_user($d);
if (&is_under_directory($d->{'home'}, $l)) {
	&set_permissions_as_domain_user($d, 0660, $l);
	}
else {
	my @uinfo = getpwnam($auser);
	my $agroup = getgrgid($uinfo[3]) || $uinfo[3];
	&set_ownership_permissions($d->{'uid'}, $agroup, 0660, $l);
	}
}

# link_apache_logs(&domain, [access-log, error-log])
# If a domain's logs are not under it's home, create symlinks from the logs
# directory to the actual location.
sub link_apache_logs
{
local ($d, $log, $elog) = @_;
return if ($d->{'subdom'});	# Sub-domains have no separate logs
$log ||= &get_apache_log($d->{'dom'}, $d->{'web_port'}, 0);
$elog ||= &get_apache_log($d->{'dom'}, $d->{'web_port'}, 1);
local $loglink = "$d->{'home'}/logs/access_log";
local $eloglink = "$d->{'home'}/logs/error_log";
if ($log && (!-e $loglink || -l $loglink) &&
    !&is_under_directory($d->{'home'}, $log)) {
	&lock_file($loglink);
	&unlink_file_as_domain_user($d, $loglink);
	&symlink_file_as_domain_user($d, $log, $loglink);
	&unlock_file($loglink);
	}
if ($elog && (!-e $eloglink || -l $eloglink) &&
    !&is_under_directory($d->{'home'}, $elog)) {
	&lock_file($eloglink);
	&unlink_file_as_domain_user($d, $eloglink);
	&symlink_file_as_domain_user($d, $elog, $eloglink);
	&unlock_file($eloglink);
	}
}

# can_default_website(&domain)
# Returns 1 if the current user can change the default website for an IP.
# Only true for the master admin, or if he owns all the sites on that IP.
sub can_default_website
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p ne 'web') {
	# Does this website type support it?
	return 0 if (!&plugin_defined($p, "feature_supports_web_default") ||
		     !&plugin_call($p, "feature_supports_web_default", $d));
	}
return 1 if (&master_admin());
if ($p eq 'web') {
	# Find all Apache vhosts on the IP and their domains, and make sure
	# the user can edit all of them
	foreach my $o (&list_apache_domains_on_ip($d)) {
		if ($o->[1] && !&can_edit_domain($o->[1])) {
			return 0;
			}
		}
	}
else {
	# Just find all domains on the IP, and make sure the user can edit
	# all of them
	foreach my $o (&get_domain_by("ip", $d->{'ip'})) {
		return 0 if (!&can_edit_domain($o));
		}
	}
return 1;
}

# list_apache_domains_on_ip(&domain, [port])
# Returns a list of Apache virtualhost hash refs and virtual servers that are
# using the same IP in the Apache config as this one. If it is name-based
# (* in the virtualhost), then all similar servers will be matched.
# XXX will a request to some IP match both domains on that IP, and * ?
sub list_apache_domains_on_ip
{
local ($d, $port) = @_;
$port ||= $d->{'web_port'};
&require_apache();
local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);
return ( ) if (!$virt);		# Cannot find our own site?
local @rv;
foreach my $v (&apache::find_directive_struct("VirtualHost", $conf)) {
	if (&indexof($virt->{'words'}->[0], @{$v->{'words'}}) >= 0) {
		# Matches IP .. find the domain if we can
		local $sn = &apache::find_directive("ServerName",
						    $v->{'members'});
		local $vd = &get_domain_by("dom", $sn);
		if (!$vd) {
			# Search by ServerAlias
			foreach my $sa (&apache::find_directive_struct(
					  "ServerAlias", $v->{'members'})) {
				foreach my $saw (map { lc($_) }
						     @{$n->{'words'}}) {
					$vd = &get_domain_by("dom", $saw);
					last if ($vd);
					}
				}
			}
		push(@rv, [ $v, $vd ]);
		}
	}
return @rv;
}

# get_default_apache_website(&domain, [port])
# Returns the Apache virtualhost and possibly virtual server hash for the
# default website on some domain's IP
sub get_default_apache_website
{
local ($d, $port) = @_;
local @onip = &list_apache_domains_on_ip($d, $port);
return @onip ? @{$onip[0]} : ( );
}

# set_default_website(&domain)
# Make sure virtual server the default website for its IP, by re-ordering
# entries in httpd.conf
sub set_default_website
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p ne 'web') {
	return &plugin_call($p, "feature_set_web_default", $d);
	}
&require_apache();
foreach my $port ($d->{'web_port'},
		  $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( )) {
	local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);
	$virt || return "No Apache virtualhost found for $d->{'dom'}:$port";
	local ($oldvirt, $oldd) = &get_default_apache_website($d, $port);
	if ($virt && $oldvirt && $virt ne $oldvirt) {
		if ($virt->{'file'} eq $oldvirt->{'file'}) {
			# Need to move up in file
			local $lref = &read_file_lines($virt->{'file'});
			local @oldl = @$lref[$virt->{'line'} .. $virt->{'eline'}];
			splice(@$lref, $virt->{'line'},
			       $virt->{'eline'} - $virt->{'line'} + 1);
			splice(@$lref, $oldvirt->{'line'}, 0, @oldl);
			&flush_file_lines($virt->{'file'});
			}
		else {
			# Swap file order
			$virt->{'file'} =~ /^(.*)\/([^\/]+)$/;
			local ($dir, $file) = ($1, $2);
			$oldvirt->{'file'} =~ /^(.*)\/([^\/]+)$/;
			local ($olddir, $oldfile) = ($1, $2);
			local $adddir = $apache::config{'virt_file'} ?
			  &apache::server_root($apache::config{'virt_file'}) :
			  undef;
			if ($dir eq $olddir && $dir eq $adddir) {
				# Separate files in the add-to dir
				&apache::delete_webfile_link("$dir/$file");
				&rename_logged("$dir/$file", "$dir/0-$file");
				&apache::create_webfile_link("$dir/0-$file");
				if ($oldfile =~ /^0-(.*)$/) {
					&apache::delete_webfile_link(
							"$dir/$oldfile");
					&rename_logged("$dir/$oldfile",
						       "$dir/$1");
					&apache::create_webfile_link("$dir/$1");
					}
				}
			else {
				# Cannot handle this case
				return "Cannot handle swap between $virt->{'file'} and $oldvirt->{'file'}";
				}
			}
		undef(@apache::get_config_cache);
		&register_post_action(\&restart_apache);
		}
	}
return undef;
}

# is_default_website(&domain)
# Returns 1 if some domain is the default website for it's IP, 0 otherwise
sub is_default_website
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p ne 'web') {
	return &plugin_call($p, "feature_is_web_default", $d);
	}
else {
	local ($defvirt, $defd) = &get_default_apache_website($d);
	if (!$defd || $defd->{'id'} ne $d->{'id'}) {
		# No default found, or not the default
		return 0;
		}
	elsif ($defvirt->{'file'} =~ /\/\Q$d->{'dom'}\E\.conf$/) {
		# This domain is the default, but filename is based on
		# domain name .. so it is only accidentally the default
		return 2;
		}
	else {
		# Definately the default
		return 1;
		}
	}
}

# find_default_website(&domain)
# Finds the domain that has the default website for the IP the given domain
# is on
sub find_default_website
{
my ($d) = @_;
local $p = &domain_has_website($d);
if ($p eq 'web') {
	# Can just use the default apache site function
	local (undef, $defd) = &get_default_apache_website($d);
	return $defd;
	}
else {
	# Iterate through domains
	foreach my $defd (&get_domain_by("ip", $d->{'ip'})) {
		return $defd if (&is_default_website($defd));
		}
	return undef;
	}
}

# get_apache_vhost_ips(&domain, star-namevirtualhost-ip4,
# 		       star-namevirtualhost-ip6, [port])
# Returns a string listing the IPs for a domain's <virtualhost> block.
# A star is used for the IP if the virtual host is name based, and the IP
# is shared with other domains.
sub get_apache_vhost_ips
{
my ($d, $nvstar, $nvstar6, $port) = @_;
my $parent = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;
$port ||= $d->{'web_port'};
&require_apache();
my @vips;
if ($d->{'ip'}) {
	my $vip = $config{'apache_star'} == 2 ? "*" :
		     $config{'apache_star'} == 1 ? $d->{'ip'} :
		     $d->{'name'} &&
		       $apache::httpd_modules{'core'} >= 1.312 &&
		       &is_shared_ip($d->{'ip'}) &&
		       $nvstar ? "*" : $d->{'ip'};
	push(@vips, "$vip:$port");
	}
if ($d->{'ip6'}) {
	my $vip6 = $config{'apache_star'} == 2 ? "*" :
		      $config{'apache_star'} == 1 ? $d->{'ip6'} :
		      $d->{'name'} &&
		        &is_shared_ip($d->{'ip6'}) &&
		        $nvstar6 ? "*" : $d->{'ip6'};
	if ($vip6 ne "*") {
		# If already matching *:port for the IPv4 part, no need to
		# repeat it for IPv6
		push(@vips, "[$vip6]:$port");
		}
	}
return join(" ", @vips);
}

# list_apache_directives()
# Returns a list of directives and modules (as array refs) supported by Apache
sub list_apache_directives
{
&require_apache();
local $httpd = &apache::find_httpd();
local @rv;
open(DIRS, "$httpd -L 2>/dev/null </dev/null |");
while(<DIRS>) {
	if (/^(\S+)\s+\((\S+)\.c\)/) {
		push(@rv, [ $1, $2 ]);
		}
	}
close(DIRS);
return @rv;
}

# change_access_log(&domain, logfile)
# Update the Apache config to use a new access log file, move the old one to
# the new location, and update any links
sub change_access_log
{
local ($d, $accesslog) = @_;
$accesslog =~ /^\/\S+$/ ||
	return "Access log $accesslog must be an absolute path";
local $p = &domain_has_website($d);
if ($p ne "web") {
	return &plugin_call($p, "feature_change_web_access_log",
			    $d, $accesslog);
	}
local $err = &change_apache_log($d, $accesslog, "CustomLog");
if ($err) {
	$err = &change_apache_log($d, $accesslog, "TransferLog");
	}
&link_apache_logs($d);
&register_post_action(\&restart_apache);
return $err;
}

# change_error_log(&domain, logfile)
# Update the Apache config to use a new error log file, move the old one to
# the new location, and update any links
sub change_error_log
{
local ($d, $errorlog) = @_;
$errorlog =~ /^\/\S+$/ ||
	return "Error log $errorlog must be an absolute path";
local $p = &domain_has_website($d);
if ($p ne "web") {
	return &plugin_call($p, "feature_change_web_error_log",
			    $d, $errorlog);
	}
local $err = &change_apache_log($d, $errorlog, "ErrorLog");
&link_apache_logs($d);
&register_post_action(\&restart_apache);
return $err;
}

# change_apache_log(&domain, logfile, directive)
# Update the Apache config to use a log file of some kind, move the old one to
# the new location, and update any links
sub change_apache_log
{
local ($d, $log, $dir) = @_;
-d $log && return "Log file $log is a directory";
local $logdir = $log;
$logdir =~ s/[^\/]+$//;
-d $logdir || return "Log parent directory $logdir does not exist";

# Update the Apache config
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
local $movelog;
foreach my $p (@ports) {
	local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	local $oldlog = &apache::find_directive($dir, $vconf);
	next if (!$oldlog);
	local $oldlogfile = &extract_writelogs_path($oldlog, $d->{'dom'});
	$oldlog =~ s/\Q$oldlogfile\E/$log/;
	$movelog ||= $oldlogfile;
	&apache::save_directive($dir, [ $oldlog ], $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}
$movelog || return "No log directives found for $dir";

# Move the file if needed
if (!&same_file($log, $movelog) || -l $log) {
	if (-e $log) {
		&unlink_file($log);
		}
	if (-r $movelog) {
		&rename_logged($movelog, $log);
		}
	}

# Fix logrotate config
if ($d->{'logrotate'}) {
	local $lconf = &get_logrotate_section($movelog);
	if ($lconf) {
		local $parent = &logrotate::get_config_parent();
		foreach my $n (@{$lconf->{'name'}}) {
			if ($n eq $movelog) {
				$n = $log;
				}
			}
		&logrotate::save_directive($parent, $lconf, $lconf);
		&flush_file_lines($lconf->{'file'});
		}
	}

return undef;
}

# modify_web_home_directory(&domain, &old-domain, &virt, &vconf, &apache-config,
# 			    [php-mode])
# Updates all directives that refer to the old home directory or domain ID, by
# modifying the Apache config files directly. Also updates PHP config files.
# Invalidates the Apache config cache.
sub modify_web_home_directory
{
local ($d, $oldd, $virt, $vconf, $conf, $mode) = @_;
local $lref = &read_file_lines($virt->{'file'});
for(my $i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
	$lref->[$i] =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
	$lref->[$i] =~ s/\Q$oldd->{'id'}\E/$d->{'id'}/g;
	}
&flush_file_lines($virt->{'file'});
undef(@apache::get_config_cache);

# Fix all php.ini files that use old path
$mode ||= &get_domain_php_mode($d);
if (&foreign_check("phpini")) {
	&foreign_require("phpini");
	my $inimode = $mode;
	$inimode = "cgi" if ($inimode eq "mod_php" || $inimode eq "fpm");
	foreach my $ini (&list_domain_php_inis($d, $inimode)) {
		&lock_file($ini->[1]);
		my $conf = &phpini::get_config($ini->[1]);
		my $fixed = 0;
		foreach my $c (@$conf) {
			if ($c->{'value'} =~ /^\Q$oldd->{'home'}\E\//) {
				$c->{'value'} =~
				    s/^\Q$oldd->{'home'}\E\//$d->{'home'}\//g;
				&phpini::save_directive($conf,
				   $c->{'name'}, $c->{'value'});
				$fixed++;
				}
			}
		if ($fixed) {
			&flush_file_lines($ini->[1]);
			}
		&unlock_file($ini->[1]);
		}
	}

# Fix all PHP settings in FPM files that use the old path
if ($mode eq "fpm") {
	my $inis = &list_php_fpm_ini_values($d);
	foreach my $v (@$inis) {
		if ($v->[1] =~ /^\Q$oldd->{'home'}\E\//) {
			$v->[1] =~ s/^\Q$oldd->{'home'}\E\//$d->{'home'}\//g;
			&save_php_fpm_ini_value($d, $v->[0], $v->[1], $v->[2]);
			}
		}
	}

# Fix paths in .htaccess files
my $filename = ".htaccess";
local $out = &run_as_domain_user($d, "find ".quotemeta($d->{'home'}).
				     " -type f -name ".quotemeta($filename).
				     " 2>/dev/null");
foreach my $file (split(/\r?\n/, $out)) {
	next if (!-r $file);
	eval {
		local $main::error_must_die = 1;
		&lock_file($file);
		local $lref = &read_file_lines_as_domain_user($d, $file);
		foreach my $l (@$lref) {
			if ($l =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g) {
				$fixed++;
				}
			}
		if ($fixed) {
			&flush_file_lines_as_domain_user($d, $file);
			}
		else {
			&unflush_file_lines($file);
			}
		&unlock_file($file);
		};
	}
}

# modify_web_domain(&domain, &old-domain, &virt, &vconf, &apache-config,
# 		    [rename-log-files])
# Update the Apache config for a virtual host to fix the domain name. May also
# rename actual log files if changed.
sub modify_web_domain
{
local ($d, $oldd, $virt, $vconf, $conf, $rlogs) = @_;
&apache::save_directive("ServerName", [ $d->{'dom'} ],
			$vconf, $conf);
local @sa = map { s/\Q$oldd->{'dom'}\E/$d->{'dom'}/g; $_ }
		&apache::find_directive("ServerAlias", $vconf);
&apache::save_directive("ServerAlias", \@sa, $vconf, $conf);

# Update log paths
foreach my $ld ("ErrorLog", "TransferLog", "CustomLog") {
	local @ldv = &apache::find_directive($ld, $vconf);
	next if (!@ldv);
	foreach my $l (@ldv) {
		my $oldl = $l;
		if ($l =~ /\/[^\/]*\Q$oldd->{'dom'}\E[^\/]*$/ &&
		    !$_[0]->{'subdom'}) {
			$l =~ s/\Q$oldd->{'dom'}\E/$d->{'dom'}/g;
			}
		if ($l ne $oldl && $rlogs) {
			# Rename log file too
			local $wl = &apache::wsplit($l);
			local $woldl = &apache::wsplit($oldl);
			&rename_file($woldl->[0], $wl->[0]);
			}
		}
	&apache::save_directive($ld, \@ldv, $vconf, $conf);
	}

# Update RewriteCond / RewriteRule / Redirect* directives for
# webmail and awstats redirects
foreach my $ld ("RewriteCond", "RewriteRule",
		"Redirect", "RedirectMatch") {
	local @ldv = &apache::find_directive($ld, $vconf);
	next if (!@ldv);
	foreach my $l (@ldv) {
		$l =~ s/\Q$oldd->{'dom'}\E/$d->{'dom'}/g;
		}
	&apache::save_directive($ld, \@ldv, $vconf, $conf);
	}
&flush_file_lines();
}

# modify_web_user_group(&domain, &old-domain, &virt, &vconf, &apache-config)
# Update the Apache config for a virtual host to fix the user and group names
sub modify_web_user_group
{
local ($d, $oldd, $virt, $vconf, $conf) = @_;
local $suexec = &apache::find_directive_struct("SuexecUserGroup", $vconf);
if ($suexec && ($suexec->{'words'}->[0] eq $oldd->{'user'} ||
		$suexec->{'words'}->[0] eq '#'.$oldd->{'uid'})){
	&apache::save_directive("SuexecUserGroup",
			[ "#$d->{'uid'} #$d->{'ugid'}" ],
			$vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}
}

# fix_symlink_security([&domains], [find-only])
# Goes through all virtual servers, and for any with Options FollowSymLinks 
# set change them to SymLinksifOwnerMatch
sub fix_symlink_security
{
local ($doms, $findonly) = @_;
$doms ||= [ &list_domains() ];
local @flush;
local @fixdoms;
&require_apache();
local @lockdoms;
foreach my $d (@$doms) {
        next if (!$d->{'web'} || $d->{'alias'});
	local @ports = ( $d->{'web_port'},
			 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
	local $domfixed = 0;
	if (!$findonly) {
		&obtain_lock_web($d);
		&obtain_lock_ssl($d) if ($d->{'ssl'});
		push(@lockdoms, $d);
		}
	foreach my $p (@ports) {
		local ($virt, $vconf, $conf) = &get_apache_virtual(
						$d->{'dom'}, $p);
		next if (!$virt);
		local @dirs = &apache::find_directive_struct("Directory",
							     $vconf);
		foreach my $dir (@dirs) {
			# Fix Options line
			my $fixed;
			my @opts = &apache::find_directive("Options",
							   $dir->{'members'});
			foreach my $o (@opts) {
				if ($o =~ /(\s|\+)FollowSymLinks/) {
					$o =~ s/FollowSymLinks/SymLinksifOwnerMatch/g;
					$fixed++;
					}
				}
			if ($fixed) {
				&apache::save_directive("Options", \@opts,
						$dir->{'members'}, $conf);
				push(@flush, $dir->{'file'});
				}

			# For Apache 2.2 or later, disable other options
			my $ofixed;
			my $olist = &get_allowed_options_list();
			if ($apache::httpd_modules{'core'} >= 2.2) {
				my @allow = &apache::find_directive(
					"AllowOverride", $dir->{'members'});
				if (!@allow) {
					# AllowOverride not set at all .. add
					# a line for it
					push(@allow, "All ".$olist);
					$ofixed++;
					}
				elsif ($allow[0] !~ /$olist/) {
					if ($allow[0] =~ /Options=(\S+)/) {
						# Fix existing options
						$allow[0] =~ s/Options=(\S+)/$olist/;
						}
					else {
						# Append correct options
						$allow[0] .= " ".$olist;
						}
					$ofixed++;
					}
				if ($ofixed) {
					&apache::save_directive(
						"AllowOverride", \@allow,
						$dir->{'members'}, $conf);
					push(@flush, $dir->{'file'});
					}
				}
			$domfixed++ if ($fixed || $ofixed);
			}
		}

	# Replace awstats symlinks with copies
	local $htmldir = &public_html_dir($d);
	local @dirs = ( "icon", "awstats-icon", "awstatsicons" );
	if ($domfixed && !$findonly && $d->{'virtualmin-awstats'} &&
	    -l "$htmldir/$dirs[0]") {
		local $dest = readlink("$htmldir/$dirs[0]");
		&unlink_logged_as_domain_user($d, "$htmldir/$dirs[0]");
		&copy_source_dest($dest, "$htmldir/$dirs[0]");
		&system_logged("chown -R $d->{'uid'}:$d->{'gid'} ".
			       quotemeta("$htmldir/$dirs[0]"));
		foreach my $dir (@dirs[1..$#dirs]) {
			&unlink_file_as_domain_user($d, "$htmldir/$dir");
			&virtual_server::symlink_logged_as_domain_user(
				$d, $dirs[0], "$htmldir/$dir");
			}
		}

	push(@fixdoms, $d) if ($domfixed);
	}
@flush = &unique(@flush);
if ($findonly) {
	# Roll back all changes, since we are only testing for fixes
	foreach my $f (@flush) {
		&unflush_file_lines($f);
		}
	}
else {
	# Actually save the files
	foreach my $f (@flush) {
		&flush_file_lines($f);
		}
	if (@flush) {
		&register_post_action(\&restart_apache);
		}
	}
# Unlock all locked domains
foreach my $d (@lockdoms) {
	&release_lock_ssl($d) if ($d->{'ssl'});
	&release_lock_web($d);
	}
return @fixdoms;
}

# fix_symlink_templates()
# Fix all templates that have Apache directives set to replace FollowSymLinks
# with SymLinksifOwnerMatch
sub fix_symlink_templates
{
my $olist = &get_allowed_options_list();
&require_apache();
foreach my $tmpl (&list_templates()) {
	next if ($tmpl->{'id'} == 1);	# Skip sub-server settings
	&lock_file($tmpl->{'file'} || $module_config_file);
	if ($tmpl->{'web'} && $tmpl->{'web'} ne 'none' &&
	    $tmpl->{'web'} =~ /(\s|\+)FollowSymLinks/) {
		$tmpl->{'web'} =~ s/FollowSymLinks/SymLinksifOwnerMatch/g;
		&save_template($tmpl);
		}
	if ($apache::httpd_modules{'core'} >= 2.2 &&
	    $tmpl->{'web'} && $tmpl->{'web'} ne 'none' &&
	    $tmpl->{'web'} !~ /AllowOverride[^\t\r\n]*$olist/) {
		$tmpl->{'web'} =~ s/AllowOverride\s+([^\t\r\n]*)/AllowOverride $1 $olist/g;
		&save_template($tmpl);
		}
	&unlock_file($tmpl->{'file'} || $module_config_file);
	}
}

sub get_allowed_options_list
{
return "Options=ExecCGI,Includes,IncludesNOEXEC,".
       "Indexes,MultiViews,SymLinksIfOwnerMatch";
}

# supports_ssi(&domain)
# Does this webserver support server-side includes?
sub supports_ssi
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	# Check with plugin
	if (&plugin_defined($p, "feature_web_supports_ssi")) {
		return &plugin_call($p, "feature_web_supports_ssi", $d);
		}
	return 0;
	}
elsif ($p) {
	# Check Apache module
	&require_apache();
	return $apache::httpd_modules{'mod_include'} ? 1 : 0;
	}
else {
	return 0;
	}
}

# get_domain_web_ssi(&domain)
# Returns 1 and the file suffix if server-side includes are enabled for a
# domain, 0 and an optional error if not, and 2 if the global settings are
# in effect.
sub get_domain_web_ssi
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_get_web_domain_ssi", $d);
	}
elsif (!$p) {
	return (0, "Virtual server does not have a website");
	}
&require_apache();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return (0, "No Apache configuration found") if (!$virt);

# Get options for public_html
local @dirs = &apache::find_directive_struct("Directory", $vconf);
local $phd = &public_html_dir($d);
local ($dir) = grep { $_->{'words'}->[0] eq $phd } @dirs;
return (0, "No directory block for $phd found") if (!$dir);
local @opts = &apache::find_directive("Options", $dir->{'members'});
local $foundincludes;
foreach my $o (@opts) {
	if ($o =~ /(^|\s|\+)(Includes|IncludesNOEXEC)(\s|$)/) {
		$foundincludes = 1;
		}
	}
return (0) if (!$foundincludes);

# Look for AddOutputFilter INCLUDES suffix
local @filters = &apache::find_directive("AddOutputFilter", $dir->{'members'});
local $foundfilter;
foreach my $f (@filters) {
	if ($f =~ /^INCLUDES\s+(\S+)/) {
		$foundfilter = $1;
		}
	}
return (2) if (!$foundfilter);

return (1, $foundfilter);
}

# save_domain_web_ssi(&domain, suffix)
# Enable or disable SSI for a domain, with files of some suffix. Returns undef
# on success or an error message on failure.
sub save_domain_web_ssi
{
local ($d, $suffix) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_save_web_domain_ssi", $d, $suffix);
	}
elsif (!$p) {
	return (0, "Virtual server does not have a website");
	}
&require_apache();

&obtain_lock_web($d);
local @ports = ( $d->{'web_port'} );
push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});

foreach my $p (@ports) {
	local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);

	# Fix options for public_html
	local @dirs = &apache::find_directive_struct("Directory", $vconf);
	local $phd = &public_html_dir($d);
	local ($dir) = grep { $_->{'words'}->[0] eq $phd } @dirs;
	next if (!$dir);
	local @opts = &apache::find_directive("Options", $dir->{'members'});
	if ($suffix) {
		# Adding to Options
		local $foundincludes;
		foreach my $o (@opts) {
			if ($o =~ /(^|\s|\+)(Includes|IncludesNOEXEC)(\s|$)/) {
				$foundincludes = 1;
				}
			}
		if (!$foundincludes) {
			$opts[0] .= " IncludesNOEXEC";
			}
		}
	else {
		# Removing from Options
		foreach my $o (@opts) {
			$o =~ s/(^|\s+)\+?(Includes|IncludesNOEXEC)(\s|$)/$3/g;
			}
		}
	&apache::save_directive("Options", \@opts, $dir->{'members'}, $conf);

	# Add AddOutputFilter directive for the suffix
	local @filters = &apache::find_directive("AddOutputFilter",
						 $dir->{'members'});
	local $idx;
	local $oldsuffix;
	for(my $i=0; $i<@filters; $i++) {
		if ($filters[$i] =~ /^INCLUDES\s+(\S+)/) {
			$idx = $i;
			$oldsuffix = $1;
			}
		}
	if (defined($idx) && $suffix) {
		# Fix existing line
		$filters[$idx] = "INCLUDES $suffix";
		}
	elsif (defined($idx) && !$suffix) {
		# Remove existing line
		splice(@filters, $idx, 1);
		}
	elsif (!defined($idx) && $suffix) {
		# Add new line
		push(@filters, "INCLUDES $suffix");
		}
	&apache::save_directive("AddOutputFilter", \@filters,
				$dir->{'members'}, $conf);

	# Add AddType directive for the suffix, if not .html
	local @types = &apache::find_directive("AddType", $dir->{'members'});
	local $idx;
	if ($oldsuffix) {
		for(my $i=0; $i<@types; $i++) {
			if ($types[$i] =~ /^(\S+)\s+\Q$oldsuffix\E/) {
				$idx = $i;
				}
			}
		}
	if (defined($idx) && $suffix) {
		# Fix existing line
		$types[$idx] = "text/html $suffix";
		}
	elsif (defined($idx) && !$suffix) {
		# Remove existing line
		splice(@types, $idx, 1);
		}
	elsif (!defined($idx) && $suffix) {
		# Add new line
		push(@types, "text/html $suffix");
		}
	&apache::save_directive("AddType", \@types, $dir->{'members'}, $conf);

	&flush_file_lines($virt->{'file'});
	}

&release_lock_web($d);
&register_post_action(\&restart_apache);
return undef;
}

# fix_options_directives(&vconf, &config, [ignore-version])
# If running Apache 2.4+, Options lines with a mix of + and non+ are not
# allowed, so fix them up.
sub fix_options_directives
{
my ($vconf, $conf, $ignore) = @_;
&require_apache();
return 0 if ($apache::httpd_modules{'core'} < 2.4 && !$ignore);
my @o = &apache::find_directive("Options", $vconf);
my $changed = 0;
foreach my $o (@o) {
	my @w = split(/\s+/, $o);
	my $plus_minus = 0;
	my $other = 0;
	foreach my $w (@w) {
		$plus_minus++ if ($w =~ /^[\-\+]/);
		$other++ if ($w !~ /^[\-\+]/);
		}
	if ($plus_minus && $other) {
		# Upgrade all non-decorated to +
		foreach my $w (@w) {
			if ($w !~ /^[\-\+]/) {
				$w = "+".$w;
				}
			}
		$o = join(" ", @w);
		$changed++;
		}
	}
if ($changed) {
	&apache::save_directive("Options", \@o, $vconf, $conf);
	&flush_file_lines($vconf->[0]->{'file'});
	}
foreach my $dir (&apache::find_directive_struct("Directory", $vconf)) {
	$changed += &fix_options_directives($dir->{'members'}, $conf, $ignore);
	}
return $changed;
}

# remove_dav_directives(&domain, &virt, &vconf, &conf)
# Remove DAV related directives from an Apache virtualhost
sub remove_dav_directives
{
my ($d, $virt, $vconf, $conf) = @_;
return 0 if ($d->{'virtualmin-dav'} &&
	     &indexof('virtualmin-dav', @plugins) >= 0);
my @locs = &apache::find_directive_struct("Location", $vconf);
my ($dav) = grep { $_->{'value'} eq '/dav' } @locs;
return 0 if (!$dav);
&apache::save_directive_struct($dav, undef, $vconf, $conf);

my @al = &apache::find_directive("Alias", $vconf);
@al = grep { !/^\/dav\s/ } @al;
&apache::save_directive("Alias", \@al, $vconf, $conf);

my @pp = &apache::find_directive("ProxyPass", $vconf);
@pp = grep { !/^\/dav\/\s/ } @pp;
&apache::save_directive("ProxyPass", \@pp, $vconf, $conf);

my @ppr = &apache::find_directive("ProxyPassReverse", $vconf);
@ppr = grep { !/^\/dav\/\s/ } @ppr;
&apache::save_directive("ProxyPassReverse", \@ppr, $vconf, $conf);

&flush_file_lines($virt->{'file'});
return 1;
}

# list_mod_php_directives()
# Returns names of directives associated with mod_php
sub list_mod_php_directives
{
return ('php_value', 'php_flag', 'php_admin_value', 'php_admin_flag');
}

# fix_mod_php_directives(&domain, port, [force])
# Remove php_value directives if not supported by this system
sub fix_mod_php_directives
{
my ($d, $port, $force) = @_;
my $count = 0;
if (!&get_apache_mod_php_version() || $force) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);
	if ($virt) {
		my @dtargs = &list_mod_php_directives();
		foreach my $pval (@dtargs) {
			my @phpv = &apache::find_directive($pval, $vconf);
			$count += scalar(@phpv);
			&apache::save_directive($pval, [ ], $vconf, $conf);
			}
		my @dirs;
		foreach my $dirname ("Directory", "DirectoryMatch",
				     "Files", "FilesMatch",
				     "Location", "LocationMatch") {
			push(@dirs, &apache::find_directive_struct(
					$dirname, $vconf));
			}
		foreach my $dir (@dirs) {
			foreach my $pval (@dtargs) {
				my @phpv = &apache::find_directive(
					$pval, $dir->{'members'});
				$count += scalar(@phpv);
				&apache::save_directive(
					$pval, [ ], $dir->{'members'}, $conf);
				}
			}
		&flush_file_lines($virt->{'file'}, undef, 1);
		&register_post_action(\&restart_apache);
		}
	}
return $count;
}

# fix_options_template(&tmpl, [ignore-version]))
# If some template has Options lines for the web setting that are a mix of +
# and non+, fix them up
sub fix_options_template
{
my ($tmpl, $ignore) = @_;
&require_apache();
return 0 if ($apache::httpd_modules{'core'} < 2.4 && !$ignore);
return 0 if (!$tmpl->{'web'} || $tmpl->{'web'} eq 'none');
my @lines = split(/\t/, $tmpl->{'web'});
my $changed = 0;
foreach my $l (@lines) {
	if ($l =~ /^\s*Options\s*(.*)/) {
		my @w = split(/\s+/, $1);
		my $plus_minus = 0;
		my $other = 0;
		foreach my $w (@w) {
			$plus_minus++ if ($w =~ /^[\-\+]/);
			$other++ if ($w !~ /^[\-\+]/);
			}
		if ($plus_minus && $other) {
			# Upgrade all non-decorated to +
			foreach my $w (@w) {
				if ($w !~ /^[\-\+]/) {
					$w = "+".$w;
					}
				}
			$l = "Options ".join(" ", @w);
			$changed++;
			}
		}
	}
if ($changed) {
	$tmpl->{'web'} = join("\t", @lines);
	&save_template($tmpl);
	}
}

# path_glob_match(glob-path, dir)
# Returns 1 if a path that could contain globs like * matches a directory
sub path_glob_match
{
my ($glob, $dir) = @_;
$glob =~ s/\?/./g;
$glob =~ s/\*/.*/g;
return $dir =~ /^$glob$/;
}

# get_apache_default_servername()
# Returns the servername that Apache uses for the default server
sub get_apache_default_servername
{
&require_apache();
my $conf = &apache::get_config();
my ($sn) = &apache::find_directive("ServerName", $conf);
if (!$sn) {
	$sn = &get_system_hostname();
	}
return $sn;
}

# get_domain_fcgiwrap(&domain)
# Returns 1 if fcgiwrap is enabled for a domain
sub get_domain_fcgiwrap
{
my ($d) = @_;
&require_apache();
my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return 0 if (!$virt);
my @dirs = &apache::find_directive_struct("Directory", $vconf);
my $cgid = &cgi_bin_dir($d);
my ($dir) = grep { $_->{'words'}->[0] eq $cgid } @dirs;
return 0 if (!$dir);
my @sh = &apache::find_directive("SetHandler", $dir->{'members'});
return @sh ? 1 : 0;
}

# setup_fcgiwrap_server(&domain)
# Starts up a fcgiwrap process running as the domain user, and enables it
# at boot time. Returns an OK flag and the port number selected to listen on.
sub setup_fcgiwrap_server
{
my ($d) =  @_;

# Work out socket file for fcgiwrap
my $socketdir = "/var/fcgiwrap";
if (!-d $socketdir) {
	&make_dir($socketdir, 0777);
	}
my $domdir = "$socketdir/$d->{'id'}.sock";
if (!-d $domdir) {
	&make_dir($domdir, 0770);
	}
my $user = &get_apache_user();
&set_ownership_permissions($user, $d->{'gid'}, undef, $domdir);
my $port = "$domdir/socket";

# Get the command
my ($cmd, $log, $pidfile) = &get_fcgiwrap_server_command($d, $port);
$cmd || return (0, $text{'setup_ewebfcgidcmd'});

# Create init script
&foreign_require("init");
my $old_init_mode = $init::init_mode;
if ($init::init_mode eq "upstart") {
	$init::init_mode = "init";
	}
my $name = &init_script_fcgiwrap_name($d);
my %cmds_abs = (
	'echo', &has_command('echo'),
	'cat', &has_command('cat'),
	'chmod', &has_command('chmod'),
	'kill', &has_command('kill'),
	'sleep', &has_command('sleep'),
	'fuser', &has_command('fuser'),
	'rm', &has_command('rm'),
	);
if (defined(&init::enable_at_boot_as_user)) {
	# Init system can run commands as the user
	&init::enable_at_boot_as_user($name,
		      "Apache fcgiwrap server for $d->{'dom'}",
		      "$cmds_abs{'rm'} -f $port ; $cmd >>$log 2>&1 </dev/null & $cmds_abs{'echo'} \$! >$pidfile && sleep 2 && $cmds_abs{'chmod'} 777 $port",
		      "$cmds_abs{'kill'} `$cmds_abs{'cat'} $pidfile` ; ".
		      "$cmds_abs{'sleep'} 1 ; ".
		      "$cmds_abs{'rm'} -f $port",
		      undef,
		      { 'fork' => 1,
			'pidfile' => $pidfile },
		      $d->{'user'},
		      );
	}
else {
	# Older Webmin requires use of command_as_user
	&init::enable_at_boot($name,
		      "Apache fcgiwrap server for $d->{'dom'}",
		      &command_as_user($d->{'user'}, 0,
			"$cmd >>$log 2>&1 </dev/null")." & $cmds_abs{'echo'} \$! >$pidfile && $cmds_abs{'chmod'} +r $pidfile && sleep 2 && $cmds_abs{'chmod'} 777 $port",
		      &command_as_user($d->{'user'}, 0,
			"$cmds_abs{'kill'} `$cmds_abs{'cat'} $pidfile`").
			" ; $cmds_abs{'sleep'} 1".
			($cmds_abs{'fuser'} ? " ; $cmds_abs{'fuser'} $port | xargs kill"
					    : "").
			" ; $cmds_abs{'rm'} -f $port",
		      undef,
		      { 'fork' => 1,
			'pidfile' => $pidfile },
		      );
	}
$init::init_mode = $old_init_mode;

# Launch it, and save the PID
&init::start_action($name);

return (1, $port);
}

# delete_fcgiwrap_server(&domain)
# Shut down the fcgiwrap process, and delete it from starting at boot
sub delete_fcgiwrap_server
{
my ($d) = @_;

# Stop the server
&foreign_require("init");
my $name = &init_script_fcgiwrap_name($d);
&init::stop_action($name);

# Delete init script
my $old_init_mode = $init::init_mode;
if ($init::init_mode eq "upstart") {
        $init::init_mode = "init";
        }
&init::disable_at_boot($name);
&init::delete_at_boot($name);
$init::init_mode = $old_init_mode;

# Delete socket file, if any
if ($d->{'fcgiwrap_port'} =~ /^(\/\S+)\/socket$/) {
	my $domdir = $1;
	&unlink_file($d->{'fcgiwrap_port'});
	&unlink_file($domdir);
	delete($d->{'fcgiwrap_port'});
	}
}

# get_fcgiwrap_server_command(&domain, port)
# Returns a command to run the fcgiwrap server, log file and PID file
sub get_fcgiwrap_server_command
{
my ($d, $port) = @_;
my $cmd = &has_command("fcgiwrap");
$cmd .= " -s unix:".$port;
my $log = "$d->{'home'}/logs/fcgiwrap.log";
my $piddir = "/var/fcgiwrap";
if (!-d $piddir) {
	&make_dir($piddir, 0777);
	}
my $pidfile = "$piddir/$d->{'id'}.fcgiwrap.pid";
return ($cmd, $log, $pidfile);
}

# init_script_fcgiwrap_name(&domain)
# Returns the name of the init script for the FCGId server
sub init_script_fcgiwrap_name
{
my ($d) = @_;
my $name = "fcgiwrap-$d->{'dom'}";
$name =~ s/\./-/g;
return $name;
}

# get_fcgiwrap_status(&domain)
# Returns 0 if no init script exists, 1 if it exists but is down, or 2 if 
# exists and is running
sub get_fcgiwrap_status
{
my ($d) = @_;
my $name = &init_script_fcgiwrap_name($d);
&foreign_require("init");
my $st = &init::action_status($name);
return 0 if (!$st);
my $r = &init::status_action($name);
return $r == 1 ? 2 : 1;
}

# enable_apache_fcgiwrap(&domain)
# Turn on fcgiwrap for running CGIs for a domain
sub enable_apache_fcgiwrap
{
my ($d) = @_;
my ($ok, $port) = &setup_fcgiwrap_server($d);
return $port if (!$ok);
$d->{'fcgiwrap_port'} = $port;
my @ports = ( $d->{'web_port'} );
push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
foreach my $p (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	my @dirs = &apache::find_directive_struct("Directory", $vconf);
	my $cgid = &cgi_bin_dir($d);
	my ($dir) = grep { $_->{'words'}->[0] eq $cgid } @dirs;
	if ($dir) {
		&apache::save_directive("SetHandler",
		  [ "proxy:unix:$port|fcgi://localhost" ],
		  $dir->{'members'}, $conf);
		&apache::save_directive("ProxyFCGIBackendType", ["GENERIC"],
					$dir->{'members'}, $conf);
		my @sca = &apache::find_directive("ScriptAlias", $vconf);
		@sca = grep { !/^\/cgi-bin\/\s/ } @sca;
		push(@sca, "/cgi-bin/ ".&cgi_bin_dir($d)."/");
		&apache::save_directive("ScriptAlias", \@sca, $vconf, $conf);
		&flush_file_lines($virt->{'file'});
		}
	else {
		return "$cgid not found";
		}
	}
&register_post_action(\&restart_apache);
return undef;
}

# disable_apache_fcgiwrap(&domain)
# Remove Apache directives for fcgiwrap, and shut down the fcgiwrap server
sub disable_apache_fcgiwrap
{
my ($d) = @_;
my @ports = ( $d->{'web_port'} );
push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
my $port = $d->{'fcgiwrap_port'};
foreach my $p (@ports) {
        my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
        next if (!$virt);
        my @dirs = &apache::find_directive_struct("Directory", $vconf);
        my $cgid = &cgi_bin_dir($d);
        my ($dir) = grep { $_->{'words'}->[0] eq $cgid } @dirs;
	if ($dir) {
		if ($port) {
			my @sh = &apache::find_directive("SetHandler", $vconf);
			@sh = grep { !/proxy:unix:\Q$port\E:/ } @sh;
			&apache::save_directive("SetHandler", \@sh,
						$dir->{'members'}, $conf);
			}
		&apache::save_directive("ProxyFCGISetEnvIf", [],
					$dir->{'members'}, $conf);
		&apache::save_directive("ProxyFCGIBackendType", [],
					$dir->{'members'}, $conf);
		&flush_file_lines($virt->{'file'}, undef, 1);
		}
	}
&register_post_action(\&restart_apache);
&delete_fcgiwrap_server($d);
delete($d->{'fcgiwrap_port'});
return undef;
}

# enable_apache_suexec(&domain)
# Adds Apache directives for running CGI scripts with suexec
sub enable_apache_suexec
{
my ($d) = @_;
my @ports = ( $d->{'web_port'} );
push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
my $found = 0;
foreach my $p (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	&apache::save_directive("SuexecUserGroup",
		[ "#$d->{'uid'} #$d->{'ugid'}" ], $virt->{'members'}, $conf);
	my @sca = &apache::find_directive("ScriptAlias", $vconf);
	@sca = grep { !/^\/cgi-bin\/\s/ } @sca;
	push(@sca, "/cgi-bin/ ".&cgi_bin_dir($d)."/");
	&apache::save_directive("ScriptAlias", \@sca, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	$found++;
	}
&register_post_action(\&restart_apache) if ($found);
return $found ? undef : "No Apache virtualhost found!";
}

# disable_apache_suexec(&domain)
# Removes Apache directives for running CGI scripts with suexec
sub disable_apache_suexec
{
my ($d) = @_;
my @ports = ( $d->{'web_port'} );
push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
my $found = 0;
foreach my $p (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	&apache::save_directive("SuexecUserGroup", [], $vconf, $conf);
	my @sca = &apache::find_directive("ScriptAlias", $vconf);
	@sca = grep { !/^\/cgi-bin\/\s/ } @sca;
	&apache::save_directive("ScriptAlias", \@sca, $vconf, $conf);
	&flush_file_lines($virt->{'file'}, undef, 1);
	$found++;
	}
&register_post_action(\&restart_apache) if ($found);
return $found ? undef : "No Apache virtualhost found!";
}

# can_reset_web()
# The Apache website can be reset
sub can_reset_web
{
return 1;
}

# reset_also_web(&domain)
# When doing a full reset of a website, do SSL first
sub reset_also_web
{
my ($d) = @_;
return $d->{'ssl'} ? ('ssl') : ( );
}

# reset_web(&domain)
# Turn the website feature off and on again, but preserve redirects
sub reset_web
{
my ($d) = @_;
my $ssl = $d->{'ssl'};

# Save redirects, PHP version, PHP mode and per-directory settings
my (@redirs, $mode, @dirs);
if (!$d->{'alias'}) {
	@redirs = &list_redirects($d);
	$mode = &get_domain_php_mode($d);
	@dirs = &list_domain_php_directories($d);
	}

# Remove the SSL and regular websites
if ($ssl) {
	$d->{'ssl'} = 0;
	&delete_ssl($d);
	}
$d->{'web'} = 0;
$d->{'web_nodeletelogs'} = 1;
&delete_web($d);

# Recreate the SSL and regular websites
$d->{'web'} = 1;
$d->{'web_nodeletelogs'} = 0;
&setup_web($d);
if ($ssl) {
	$d->{'ssl'} = 1;
	&setup_ssl($d);
	}

if (!$d->{'alias'}) {
	# Put back redirects
	&$first_print($text{'reset_webrestore'});
	foreach my $r (@redirs) {
		&create_redirect($d, $r);
		}

	# Put back PHP mode
	&save_domain_php_mode($d, $mode);

	# Put back per-domain PHP versions
	if ($mode ne "none" && $mode ne "mod_php") {
		foreach my $dir (@dirs) {
			next if (!$dir->{'version'});
			&save_domain_php_directory($d, $dir->{'dir'},
						   $dir->{'version'});
			}
		}
	&$first_print($text{'setup_done'});
	}
}

# list_webserver_user_dirs(&domain, user)
# Returns a list of directories that the webserver user has access to
sub list_webserver_user_dirs
{
my ($d, $user) = @_;
my @rv;
if (&plugin_defined("virtualmin-htpasswd", "can_directory")) {
	my @dirs = grep { &plugin_call("virtualmin-htpasswd", "can_directory", $_->[0], $d) }
		&htaccess_htpasswd::list_directories();
	my %currwebdirs = &plugin_call("virtualmin-htpasswd", "get_in_dirs", \@dirs, $user->{'user'});
	my @currwebdirs = keys %currwebdirs;
	# Add directories from @addwebdirs to @currwebdirs if they're not already present
	@currwebdirs = (@currwebdirs, grep { my $__ = $_; not grep { $__ eq $_ } @currwebdirs } @addwebdirs)
		if (@addwebdirs);
	# Remove directories listed in @delwebdirs from @currwebdirs
	@currwebdirs = grep { my $__ = $_; not grep { $__ eq $_ } @delwebdirs } @currwebdirs
		if (@delwebdirs);
	@rv = @currwebdirs;
	}
return @rv;
}

# modify_webserver_user(&user, &old-user, &domain, &input-data)
# Create or update a webserver user
sub modify_webserver_user
{
my ($user, $olduser, $d, $indata) = @_;
# Encrypt user initial password if given
$user->{'pass'} = &encrypt_user_password($user, $user->{'pass'})
	if ($user->{'pass'});
# Use new encrypted password if was given or use old one
$user->{'pass_crypt'} = $user->{'pass'} || $user->{'pass_crypt'};
# Validate plugins
if (&plugin_defined("virtualmin-htpasswd", "mailbox_validate")) {
	$err = &plugin_call("virtualmin-htpasswd", "mailbox_validate", $user, $olduser,
				$indata, $in{'new'}, $d);
	&error($err) if ($err);
	}
# Run plugin save functions
if (&plugin_defined("virtualmin-htpasswd", "mailbox_save")) {
    &plugin_call("virtualmin-htpasswd", "mailbox_save", $user, $olduser,
				$indata, $in{'new'}, $d);
	}
# Add user to domain config
&update_extra_user($d, $user, $olduser);
}

# revoke_webserver_user_access(&user, &domain)
# Remove a webserver user access
sub revoke_webserver_user_access
{
my ($user, $d) = @_;
if (&plugin_defined("virtualmin-htpasswd", "mailbox_delete")) {
	&plugin_call("virtualmin-htpasswd", "mailbox_delete", $user, $d);
	}
}

# delete_webserver_user(&user, &domain)
# Delete a webserver user
sub delete_webserver_user
{
my ($user, $d) = @_;
# Remove a webserver user access
&revoke_webserver_user_access($user, $d);
# Delete user from domain config
&delete_extra_user($d, $user);
}

# update_apache_proxy_pass(&domain, &old-domain)
# Enable or disable Apache proxying of the whole site. Returns undef on success
# or an error message on failure.
sub update_apache_proxy_pass
{
my ($d, $oldd) = @_;
my @balancers = &list_proxy_balancers($d);
my @redirects = &list_redirects($d);
if ($d->{'proxy_pass_mode'} && (!$oldd || !$oldd->{'proxy_pass_mode'})) {
	# Proxying enabled
	if ($d->{'proxy_pass_mode'} == 1) {
		# Need to add proxy directives
		my $b = { 'path' => '/',
			  'websockets' => 1,
			  'urls' => [ $d->{'proxy_pass'} ] };
		return &create_proxy_balancer($d, $b);
		}
	else {
		# Setup frame forwarding
		&create_framefwd_file($d);
		my $ff = &framefwd_file($d);
		my $r = { 'path' => '/',
			  'regexp' => 1,
			  'alias' => 1,
			  'dest' => $ff,
			  'http' => 1,
			  'https' => 1 };
		return &create_redirect($d, $r);
		}
	}
elsif (!$d->{'proxy_pass_mode'} && $oldd && $oldd->{'proxy_pass_mode'}) {
	# Proxying disabled
	if ($oldd->{'proxy_pass_mode'} == 1) {
		# Need to remove proxy directives
		my ($b) = grep { $_->{'path'} eq '/' } @balancers;
		return "Missing proxy for /" if (!$b);
		return &delete_proxy_balancer($d, $b);
		}
	else {
		# Turn off frame forwarding
		my ($r) = grep { $_->{'path'} eq '/' } @redirects;
		return "Missing redirect for /" if (!$r);
		return &delete_redirect($d, $r);
		}
	}
elsif ($d->{'proxy_pass_mode'} && $oldd && $oldd->{'proxy_pass_mode'} &&
       $d->{'proxy_pass'} ne $oldd->{'proxy_pass'}) {
	# URL has changed
	if ($d->{'proxy_pass_mode'} == 1) {
		my ($b) = grep { $_->{'path'} eq '/' } @balancers;
                return "Missing proxy for /" if (!$b);
		my $oldb = { %$b };
		$b->{'urls'} = [ $d->{'proxy_pass'} ];
		return &modify_proxy_balancer($d, $b, $oldb);
		}
	else {
		# Update frame forwarding, which is all in the HTML
		&create_framefwd_file($d);
		return undef;
		}
	}
return undef;
}

$done_feature_script{'web'} = 1;

1;

