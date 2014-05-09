
sub init_web
{
$default_web_port = $config{'web_port'} || 80;
$writelogs_cmd = "$module_config_directory/writelogs.pl";
}

sub require_apache
{
return if ($require_apache++);
&foreign_require("apache", "apache-lib.pl");
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

local @dirs = &apache_template($tmpl->{'web'}, $d, $tmpl->{'web_suexec'});
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

	# Redirect webmail and admin in the alias to Usermin and Webmin
	if (&has_webmail_rewrite($d)) {
		&add_webmail_redirect_directives($d, $tmpl);
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
			push(@dirs, "ProxyPass / $url",
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
				&make_dir_as_domain_user($d, $sd, 0755);
				}
			}
		}
	elsif ($d->{'public_html_path'}) {
		# If a custom HTML directory was requested, set it up
		local $mydir;
		foreach my $dir (@dirs) {
			if ($dir =~ /^\s*DocumentRoot\s+"([^"]+)"/ ||
			    $dir =~ /^\s*DocumentRoot\s+(\S+)/) {
				$mydir = $1;
				$dir = "DocumentRoot $d->{'public_html_path'}";
				}
			elsif ($dir =~ /^\s*<Directory\s+\Q$mydir\E>/ && $mydir) {
				$dir = "<Directory $d->{'public_html_path'}>";
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
				@dirs,
				"</VirtualHost>");
	&flush_file_lines($f);
	$d->{'web_port'} = $web_port;
	$d->{'web_urlport'} = $tmpl->{'web_urlport'};

	# Create a link from another Apache dir
	if ($newfile) {
		&apache::create_webfile_link($f);
		}
	undef(@apache::get_config_cache);

	# Same the HTML and CGI dirs that we set
	if (!$d->{'alias'} && !$d->{'subdom'}) {
		&find_html_cgi_dirs($d);
		}

	# Add <Proxy *> section, to ensure that proxypass works
	if ($proxying) {
		&add_proxy_allow_directives($d);
		}

	# Redirect webmail and admin to Usermin and Webmin
	if (&has_webmail_rewrite($d)) {
		&add_webmail_redirect_directives($d, $tmpl);
		}

	# For Apache 2.4+, add a "Require all granted" directive
	local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'},
						    $d->{'web_port'});
	if ($virt && $apache::httpd_modules{'core'} >= 2.4) {
		local $pdir = &public_html_dir($d);
		local ($dir) = grep { $_->{'words'}->[0] eq $pdir ||
				      $_->{'words'}->[0] eq $pdir."/" }
			    &apache::find_directive_struct("Directory", $vconf);
		if ($dir) {
			local @req = &apache::find_directive("Require",
						$dir->{'members'});
			local ($g) = grep { /all\s+granted/i } @req;
			if (!$g) {
				push(@req, "all granted");
				&apache::save_directive("Require", \@req,
					$dir->{'members'}, $conf);
				&flush_file_lines($dir->{'file'});
				}
			}
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
&register_post_action(\&restart_apache);

# Add the Apache user to the group for this virtual server, if missing,
# unless the template says not to.
local $web_user = &get_apache_user($d);
if ($tmpl->{'web_user'} ne 'none' && $web_user) {
	&add_user_to_domain_group($d, $web_user, 'setup_webuser');
	}

&$first_print($text{'setup_webpost'});
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
	if (-d $logsdir && !-e "$logsdir/.nodelete") {
		open(NODELETE, ">$logsdir/.nodelete");
		close(NODELETE);
		&set_ownership_permissions(0, 0, 0700, "$logsdir/.nodelete");
		}

	# Setup for script languages
	if (!$d->{'alias'} && $d->{'dir'}) {
		&add_script_language_directives($d, $tmpl,
					        $d->{'web_port'});
		}

	# Re-apply limits, so that Apache directives are updated
	if (defined(&supports_resource_limits)) {
		local ($ok) = &supports_resource_limits();
		if ($ok) {
			local $pd = $d->{'parent'} ?
				&get_domain($d->{'parent'}) : $d;
			local $rv = &get_domain_resource_limits($pd);
			&save_domain_resource_limits($d, $rv, 1);
			}
		}

	# Apply symlink and mod_php fixes, in case the template wasn't
	# updated with them
	if ($config{'allow_modphp'} ne '1' && !$d->{'alias'}) {
		&fix_mod_php_security([ $d ]);
		}
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
		@sa = grep { !/\Q$d->{'dom'}\E$/ } @sa;
		&apache::save_directive("ServerAlias", \@sa, $pconf, $conf);
		&flush_file_lines($pvirt->{'file'});
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
		    !$d->{'subdom'}) {
			&$first_print($text{'delete_apachelog'});
			local @dlogs = ($alog, glob("$alog.*"),
					glob("$alog-*"));
			if ($elog) {
				push(@dlogs, $elog, glob("$elog.*"),
				     	     glob("$elog-*"));
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
undef(@apache::get_config_cache);
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

# Splice across directives, fixing ServerName so that get_apache_virtual works
local $olref = &read_file_lines($ovirt->{'file'});
local $lref = &read_file_lines($virt->{'file'});
local @lines = @$olref[$ovirt->{'line'}+1 .. $ovirt->{'eline'}-1];
foreach my $l (@lines) {
	if ($l =~ /^ServerName/) {
		$l = "ServerName ".$d->{'dom'};
		}
	}
splice(@$lref, $virt->{'line'}+1, $virt->{'eline'}-$virt->{'line'}-1, @lines);
&flush_file_lines($virt->{'file'});
undef(@apache::get_config_cache);
($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});

# Fix home dir
&modify_web_home_directory($d, $oldd, $virt);
($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});

# Fix username in suexec, if needed
if ($d->{'user'} ne $oldd->{'user'}) {
	&modify_web_user_group($d, $oldd, $virt, $vconf, $conf);
	}

# Fix domain name in apache config
&modify_web_domain($d, $oldd, $virt, $vconf, $conf, 0);
&link_apache_logs($d);

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

# Update cached public_html and CGI dirs, re-create PHP wrappers with new home
&find_html_cgi_dirs($d);
if (defined(&create_php_wrappers)) {
	&create_php_wrappers($d);
	}

&release_lock_web($d);
&register_post_action(\&restart_apache);
&$second_print($text{'setup_done'});
return 1;
}

# is_empty(&lref|file)
sub is_empty
{
local ($lref_or_file) = @_;
local $lref;
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
local $rv = 0;
&require_apache();

# Special case - converting an alias domain into a non-alias, or changing the
# alias target. Just delete and re-create.
if ($_[1]->{'alias'} != $_[0]->{'alias'}) {
	&delete_web($_[1]);
	&setup_web($_[0]);
	return 1;
	}

local $conf = &apache::get_config();
local $need_restart = 0;

if ($_[0]->{'alias'} && $_[0]->{'alias_mode'}) {
	# Possibly just updating parent virtual server
	if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
		&$first_print($text{'save_apache5'});
		local $alias = &get_domain($_[0]->{'alias'});
		&obtain_lock_web($alias);
		local @ports = ( $alias->{'web_port'} );
		push(@ports, $alias->{'web_sslport'}) if ($alias->{'ssl'});
		foreach my $p (@ports) {
			local ($pvirt, $pconf) = &get_apache_virtual(
							$alias->{'dom'}, $p);
			if (!$pvirt) {
				&$second_print($text{'setup_ewebalias'});
				next;
				}
			local @sa = &apache::find_directive("ServerAlias",
							    $pconf);
			foreach my $s (@sa) {
				$s =~ s/\Q$_[1]->{'dom'}\E($|\s)/$_[0]->{'dom'}$1/g;
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
	&obtain_lock_web($_[0]);
	local ($virt, $vconf, $conf) = &get_apache_virtual($_[1]->{'dom'},
						    $_[1]->{'web_port'});
	if ($_[0]->{'name'} != $_[1]->{'name'} ||
	    $_[0]->{'ip'} ne $_[1]->{'ip'} ||
	    $_[0]->{'ip6'} ne $_[1]->{'ip6'} ||
	    $_[0]->{'virt6'} != $_[1]->{'virt6'} ||
	    $_[0]->{'name6'} != $_[1]->{'name6'} ||
	    $_[0]->{'ssl'} != $_[1]->{'ssl'} ||
	    $_[0]->{'web_port'} != $_[1]->{'web_port'}) {
		# Name-based hosting mode or IP has changed .. update the
		# Listen directives, and the virtual host definition
		&$first_print($text{'save_apache'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		local $nvstar = &add_name_virtual($_[0], $conf,
						  $_[0]->{'web_port'}, 0,
						  $_[0]->{'ip'});
		local $nvstar6;
		if ($_[0]->{'ip6'}) {
			$nvstar6 = &add_name_virtual(
				$_[0], $conf, $_[0]->{'web_port'}, 0,
				"[".$_[0]->{'ip6'}."]");
			}
		&add_listen($_[0], $conf, $_[0]->{'web_port'});

		# Change the virtualhost IPs
		local $lref = &read_file_lines($virt->{'file'});
		$lref->[$virt->{'line'}] =
			"<VirtualHost ".
			&get_apache_vhost_ips($_[0], $nvstar, $nvstar6).
			">";
		&flush_file_lines($virt->{'file'});

		undef(@apache::get_config_cache);
		($virt, $vconf, $conf) = &get_apache_virtual($_[1]->{'dom'},
						      $_[1]->{'web_port'});
		$rv++;
		$need_restart = 1;
		&$second_print($text{'setup_done'});
		}
	if ($_[0]->{'home'} ne $_[1]->{'home'}) {
		# Home directory has changed .. update any directives that
		# referred to the old directory
		&$first_print($text{'save_apache3'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		&modify_web_home_directory($_[0], $_[1], $virt, $vconf, $conf);
		($virt, $vconf, $conf) = &get_apache_virtual($_[1]->{'dom'},
						      $_[1]->{'web_port'});
		$rv++;
		&find_html_cgi_dirs($_[0]);

		# Re-create wrapper scripts, which contain home
		if (defined(&create_php_wrappers) && !$_[0]->{'alias'}) {
			&create_php_wrappers($_[0]);
			}
		&$second_print($text{'setup_done'});
		}
	if (!$_[0]->{'subdom'} && $_[1]->{'subdom'}) {
		# No longer a sub-domain .. fix up any references to the old
		# HTML and CGI directories, and log files
		&$first_print($text{'save_apache11'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		local $phsrc = &public_html_dir($_[1]);
		local $phdst = &public_html_dir($_[0]);
		local $cgisrc = &cgi_bin_dir($_[1]);
		local $cgidst = &cgi_bin_dir($_[0]);
		local $lref = &read_file_lines($virt->{'file'});
		local $alogsrc = &get_apache_log($_[1]->{'dom'},
						 $_[1]->{'web_port'}, 0);
		local $elogsrc = &get_apache_log($_[1]->{'dom'},
						 $_[1]->{'web_port'}, 1);
		local $alogdst = &get_apache_template_log($_[0], 0);
		local $elogdst = &get_apache_template_log($_[0], 1);
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
		($virt, $vconf, $conf) = &get_apache_virtual($_[1]->{'dom'},
						      $_[1]->{'web_port'});
		&setup_apache_logs($_[0], $alogdst, $elogdst);
		&link_apache_logs($_[0], $alogdst, $elogdst);
		$rv++;
		&$second_print($text{'setup_done'});
		}
	if ($_[0]->{'alias'} && $_[2] && $_[2]->{'dom'} ne $_[3]->{'dom'}) {
		# This is an alias, and the domain it is aliased to has
		# changed .. update all Proxy* and Redirect directives
		&$first_print($text{'save_apache4'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		local $lref = &read_file_lines($virt->{'file'});
		for($i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
			if ($lref->[$i] =~
			    /^\s*(Proxy|Redirect\s|RedirectPermanent\s)/) {
				$lref->[$i] =~ s/$_[3]->{'dom'}/$_[2]->{'dom'}/g;
				}
			}
		&flush_file_lines($virt->{'file'});
		undef(@apache::get_config_cache);
		($virt, $vconf, $conf) = &get_apache_virtual($_[1]->{'dom'},
						      $_[1]->{'web_port'});
		$rv++;
		&$second_print($text{'setup_done'});
		}
	if ($_[0]->{'proxy_pass_mode'} == 1 &&
	    $_[1]->{'proxy_pass_mode'} == 1 &&
	    $_[0]->{'proxy_pass'} ne $_[1]->{'proxy_pass'}) {
		# This is a proxying forwarding website and the URL has
		# changed - update all Proxy* directives
		&$first_print($text{'save_apache6'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		local $lref = &read_file_lines($virt->{'file'});
		for($i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
			if ($lref->[$i] =~ /^\s*ProxyPass(Reverse)?\s/) {
				$lref->[$i] =~ s/$_[1]->{'proxy_pass'}/$_[0]->{'proxy_pass'}/g;
				}
			}
		&flush_file_lines($virt->{'file'});
		undef(@apache::get_config_cache);
		($virt, $vconf, $conf) = &get_apache_virtual($_[1]->{'dom'},
						      $_[1]->{'web_port'});
		$rv++;
		&$second_print($text{'setup_done'});
		}
	if ($_[0]->{'proxy_pass_mode'} != $_[1]->{'proxy_pass_mode'}) {
		# Proxy mode has been enabled or disabled .. remove all
		# ProxyPass / , ProxyPassReverse / and AliasMatch ^/$
		# directives, and create new ones as appropriate.
		local $mode = $_[0]->{'proxy_pass_mode'} ||
			      $_[1]->{'proxy_pass_mode'};
		&$first_print($mode == 2 ? $text{'save_apache8'}
					 : $text{'save_apache9'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}

		# Take out old proxy directives and block
		local $lref = &read_file_lines($virt->{'file'});
		local @lines = @$lref[$virt->{'line'}+1 .. $virt->{'eline'}-1];
		@lines = grep { !/^\s*ProxyPass\s+\/\s/ &&
				!/^\s*ProxyPassReverse\s+\/\s/ &&
				!/^\s*AliasMatch\s+\^\/\.\*\$\s/ &&
				!/^\s*SSLProxyEngine\s/ } @lines;
		for(my $i=0; $i<@lines; $i++) {
			if ($lines[$i] eq "<Proxy *>" &&
			    $lines[$i+2] eq "</Proxy>") {
				# Take out <Proxy *> block
				splice(@lines, $i, 3);
				last;
				}
			}

		# Add new directives
		local @ppdirs = &apache_proxy_directives($_[0]);
		push(@lines, @ppdirs);
		splice(@$lref, $virt->{'line'} + 1,
		       $virt->{'eline'} - $virt->{'line'} - 1, @lines);
		&flush_file_lines($virt->{'file'});
		undef(@apache::get_config_cache);
		($virt, $vconf, $conf) = &get_apache_virtual($_[1]->{'dom'},
						      $_[1]->{'web_port'});
		$rv++;
		&$second_print($text{'setup_done'});
		}
	if ($_[0]->{'user'} ne $_[1]->{'user'}) {
		# Username has changed .. update SuexecUserGroup and User
		&$first_print($text{'save_apache7'});
		&modify_web_user_group($_[0], $_[1], $virt, $vconf, $conf);
		$rv++;
		&$second_print($text{'setup_done'});

		# Set owner on log files
		local $web_user = &get_apache_user($_[0]);
		local $gid = $web_user && $web_user ne 'none' ? $web_user
							: $_[0]->{'gid'};
		local @ldv;
		foreach my $ld ("ErrorLog", "TransferLog", "CustomLog") {
			push(@ldv, &apache::find_directive($ld, $vconf, 1));
			}
		foreach my $ldv (@ldv) {
			if (&safe_domain_file($_[0], $ldv)) {
				&set_ownership_permissions(
					$_[0]->{'uid'}, $gid, undef, $ldv);
				}
			}
		&link_apache_logs($_[0]);

		# Add the Apache user to the group for the new domain
		local $tmpl = &get_template($_[0]->{'template'});
		if ($tmpl->{'web_user'} ne 'none' && $web_user) {
			&add_user_to_domain_group($_[0], $web_user,
						  'setup_webuser');
			}
		}
	if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
		# Domain name has changed .. update ServerName and ServerAlias,
		# and any log files that contain the domain name
		&$first_print($text{'save_apache2'});
		if (!$virt) {
			&$second_print($text{'delete_noapache'});
			goto VIRTFAILED;
			}
		&modify_web_domain($_[0], $_[1], $virt, $vconf, $conf, 1);
		$rv++;

		# If filename contains domain name, rename the Apache .conf file
		local $newfile = &get_website_file($_[0]);
		local $oldfile = &get_website_file($_[1]);
		if ($virt->{'file'} eq $oldfile &&
		    $newfile ne $oldfile &&
		    !-r $newfile) {
			&apache::delete_webfile_link($virt->{'file'});
			&rename_logged($virt->{'file'}, $newfile);
			&apache::create_webfile_link($newfile);
			undef(@apache::get_config_cache);
			($virt, $vconf, $conf) = &get_apache_virtual(
				$_[0]->{'dom'}, $_[0]->{'web_port'});
			}

		# Re-link Apache logs
		&link_apache_logs($_[0]);
		&$second_print($text{'setup_done'});
		}

	# If any other rename step fails becuase no <virtualhost> was found,
	# the code will jump to here.
	VIRTFAILED:
	if ($_[0]->{'home'} ne $_[1]->{'home'}) {
		# Update session dir and upload path in php.ini files
		local @fixes = (
		  [ "session.save_path", $_[1]->{'home'}, $_[0]->{'home'}, 1 ],
		  [ "upload_tmp_dir", $_[1]->{'home'}, $_[0]->{'home'}, 1 ],
		  );
		&fix_php_ini_files($_[0], \@fixes);
		}
	&release_lock_web($_[0]);
	&create_framefwd_file($_[0]);
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
						     $d->{'web_port'});
	return &text('validate_eweb', "<tt>$d->{'dom'}</tt>") if (!$pvirt);
	}
else {
	# Find real domain
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
						    $d->{'web_port'});
	return &text('validate_eweb', "<tt>$d->{'dom'}</tt>") if (!$virt);

	# Check IP addresses
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
	if (defined(&get_domain_php_mode)) {
		local $mode = &get_domain_php_mode($d);
		if ($mode ne "mod_php") {
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
		}

	# If there are suexec directives, validate them
	local ($suexec) = &apache::find_directive_struct(
		"SuexecUserGroup", $vconf);
	local ($suuser) = &apache::find_directive_struct(
		"User", $vconf);
	local ($sugroup) = &apache::find_directive_struct(
		"Group", $vconf);
	if ($suexec) {
		# Has new-style suexec
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
	elsif ($suuser && $sugroup) {
		# Has old style user and group
		if ($suuser->{'words'}->[0] ne $_[0]->{'user'} &&
		    $suuser->{'words'}->[0] ne '#'.$_[0]->{'uid'}) {
			return &text('validate_ewebuid',
			     $suexec->{'words'}->[0], $_[0]->{'uid'});
			}
		if ($sugroup->{'words'}->[1] ne $_[0]->{'group'} &&
		    $sugroup->{'words'}->[1] ne '#'.$_[0]->{'ugid'}) {
			return &text('validate_ewebgid',
			     $suexec->{'words'}->[1], $_[0]->{'ugid'});
			}
		}
	elsif ($need_suexec) {
		# Has neither, but needs them!
		return $text{'validate_ewebphpsuexec'};
		}

	# Make sure a <Directory> exists for the document root
	if (!$d->{'alias'}) {
		local $pdir = &public_html_dir($d);
		local ($dir) = grep { $_->{'words'}->[0] eq $pdir ||
				      $_->{'words'}->[0] eq $pdir."/" }
			    &apache::find_directive_struct("Directory", $vconf);
		if (!$dir) {
			return &text('validate_ewebdir', $pdir);
			}
		}
	}
return undef;
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
if ($virt) {
	&create_disable_directives($virt, $vconf, $_[0]);
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_apache);
	}
else {
	&$second_print($text{'delete_noapache'});
	}
&release_lock_web($_[0]);
}

# create_disable_directives(&virt, &vconf, &domain)
sub create_disable_directives
{
local ($virt, $vconf, $d) = @_;
local $tmpl = &get_template($d->{'template'});
local $conf = &apache::get_config();
if ($tmpl->{'disabled_url'} eq 'none') {
	# Disable is done via local HTML
	local @am = &apache::find_directive("AliasMatch", $vconf);
	local $dis = &disabled_website_html($d);
	&apache::save_directive("AliasMatch",
				[ "^/.*\$ $dis", @am ], $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	local $msg = $tmpl->{'disabled_web'} eq 'none' ?
		"<h1>Website Disabled</h1>\n" :
		join("\n", split(/\t/, $tmpl->{'disabled_web'}));
	$msg = &substitute_domain_template($msg, $d);
	&open_lock_tempfile(DISABLED, ">$dis");
	&print_tempfile(DISABLED, $msg);
	&close_tempfile(DISABLED);
	&set_ownership_permissions(undef, undef, 0644, $disabled_website);
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

# disabled_website_html(&domain)
# Returns the file for storing the disabled site file for some domain
sub disabled_website_html
{
if (!-d $disabled_website_dir) {
	mkdir($disabled_website_dir, 0755);
	&set_ownership_permissions(undef, undef, $disabled_website_dir, 0755);
	}
return "$disabled_website_dir/$_[0]->{'id'}.html";
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
if ($virt) {
	&remove_disable_directives($virt, $vconf, $_[0]);
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_apache);
	}
else {
	&$second_print($text{'delete_noapache'});
	}
&release_lock_web($_[0]);
}

# remove_disable_directives(&virt, &vconf, &domain)
sub remove_disable_directives
{
local ($virt, $vconf, $d) = @_;

# Remove local disables
local @am = &apache::find_directive("AliasMatch", $vconf);
local $dis = &disabled_website_html($d);
@am = grep { $_ ne "^/.*\$ $disabled_website" &&
	     $_ ne "^/.*\$ $dis" } @am;
local $conf = &apache::get_config();
&apache::save_directive("AliasMatch", \@am, $vconf, $conf);

# Remove remote disables
local @rm = &apache::find_directive("RedirectMatch", $vconf);
@rm = grep { substr($_, 0, 5) ne "^/.*\$" } @rm;
&apache::save_directive("RedirectMatch", \@rm, $vconf, $conf);

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
&cleanup_php_cgi_processes() if (defined(&cleanup_php_cgi_processes));
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
	return &extract_writelogs_path($log);
	}
else {
	return undef;
	}
}

# extract_writelogs_path(log-command)
# Given a log destination, which may be input to a command, return the
# real log file path.
sub extract_writelogs_path
{
local ($log) = @_;
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
local @dirs = &apache_template($tmpl->{'web'}, $dom, $tmpl->{'web_suexec'});
foreach my $l (@dirs) {
	if ($error && $l =~ /^\s*ErrorLog\s+(\S+)/) {
		$log = $1;
		}
	elsif (!$error && $l =~ /^\s*(TransferLog|CustomLog)\s+(\S+)/) {
		$log = $2;
		}
	}
if ($log !~ /^\//) {
	$log = "$dom->{'home'}/$log";
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

# apache_template(text, &domain, suexec)
# Returns a suitably substituted Apache template, as a list of directive
# text lines
sub apache_template
{
local $dirs = $_[0];
$dirs =~ s/\t/\n/g;
$dirs = &substitute_domain_template($dirs, $_[1]);
local @dirs = split(/\n/, $dirs);
local ($sudir, $ppdir);
foreach (@dirs) {
	$sudir++ if (/^\s*SuexecUserGroup\s/i || /^\s*User\s/i);
	$ppdir++ if (/^\s*ProxyPass\s/);
	}
local $tmpl = &get_template($_[1]->{'template'});
local $pdom = $_[1]->{'parent'} ? &get_domain($_[1]->{'parent'}) : $_[1];
if (!$sudir && $_[2] && $pdom->{'unix'}) {
	# Automatically add suexec directives if missing
	if ($apache::httpd_modules{'core'} >= 2.0) {
		if ($apache::httpd_modules{'mod_suexec'}) {
			unshift(@dirs, "SuexecUserGroup \"#$pdom->{'uid'}\" ".
				       "\"#$pdom->{'ugid'}\"");
			}
		}
	else {
		unshift(@dirs, "User \"#$pdom->{'uid'}\"",
			       "Group \"#$pdom->{'ugid'}\"");
		}
	}
if (!$ppdir && $_[1]->{'proxy_pass'}) {
	# Add proxy directives
	push(@dirs, &apache_proxy_directives($_[1]));
	}
if ($tmpl->{'web_writelogs'}) {
	# Fix any CustomLog or ErrorLog directives to write via writelogs.pl
	foreach $d (@dirs) {
		if ($d =~ /^\s*(CustomLog|ErrorLog)\s+(\S+)(\s*\S*)/) {
			$d = "$1 \"|$writelogs_cmd $_[1]->{'id'} $2\"$3";
			}
		}
	}
return @dirs;
}

# apache_proxy_directives(&domain)
# Returns text lines for proxy pass or frame forwarding directives
sub apache_proxy_directives
{
local ($d) = @_;
&require_apache();
local @dirs;
if ($d->{'proxy_pass_mode'} == 1) {
	# Proxy to another server
	push(@dirs, "ProxyPass / $d->{'proxy_pass'}",
		    "ProxyPassReverse / $d->{'proxy_pass'}");
	if ($d->{'proxy_pass'} =~ /^https:/ &&
	    $apache::httpd_modules{'core'} >= 2.0) {
		# SSL proxy mode
		push(@dirs, "SSLProxyEngine on");
		}
	if ($apache::httpd_modules{'core'} >= 2.0) {
		# Ensure that proxying works
		push(@dirs, "<Proxy *>",
			    "allow from all",
			    "</Proxy>");
		}
	}
elsif ($d->{'proxy_pass_mode'} == 2) {
	# Redirect to /framefwd.html
	local $ff = &framefwd_file($d);
	push(@dirs, "AliasMatch ^/.*\$ $ff");
	}
return @dirs;
}

# backup_web(&domain, file, &opts, home-format?, incremental?, as-owner,
# 	     &all-opts)
# Save the virtual server's Apache config as a separate file, except for 
# ServerAlias lines for alias domains
sub backup_web
{
local ($d, $file, $opts, $homefmt, $increment, $asd, $allopts) = @_;
if ($d->{'alias'} && $d->{'alias_mode'}) {
	# For an alias domain, just save the old ServerAlias entries
	&$first_print($text{'backup_apachecp2'});
	local $alias = &get_domain($d->{'alias'});
	local ($pvirt, $pconf) = &get_apache_virtual($alias->{'dom'},
						     $alias->{'web_port'});
	if (!$pvirt) {
		&$second_print($text{'setup_ewebalias'});
		return 0;
		}
	local @aliasnames;
	foreach my $sa (&apache::find_directive_struct("ServerAlias", $pconf)) {
		foreach my $w (@{$sa->{'words'}}) {
			if ($w eq $d->{'dom'} ||
			    $w =~ /^([^\.]+)\.(\S+)/ && $2 eq $d->{'dom'}) {
				push(@aliasnames, $w);
				}
			}
		}
	&open_tempfile(FILE, ">$file");
	foreach my $a (@aliasnames) {
		&print_tempfile(FILE, $a,"\n");
		}
	&close_tempfile(FILE);
	&$second_print($text{'setup_done'});
	return 1;
	}
&$first_print($text{'backup_apachecp'});
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
					    $d->{'web_port'});
if ($virt) {
	local $lref = &read_file_lines($virt->{'file'});
	local $l;
	local @adoms = &get_domain_by("alias", $d->{'id'});
	local %adoms = map { $_->{'dom'}, 1 } @adoms;
	&open_tempfile(FILE, ">$file");
	foreach $l (@$lref[$virt->{'line'} .. $virt->{'eline'}]) {
		if ($l =~ /^\s*ServerAlias\s+(.*)/i) {
			# Exclude ServerAlias entries for alias domains
			local @sa = split(/\s+/, $1);
			@sa = grep { !($adoms{$_} ||
				       /^([^\.]+)\.(\S+)/ && $adoms{$2}) } @sa;
			next if (!@sa);
			$l = "ServerAlias ".join(" ", @sa);
			}
		&print_tempfile(FILE, "$l\n");
		}
	&close_tempfile(FILE);
	&$second_print($text{'setup_done'});

	# If the Apache log is outside the home, back it up too
	local $alog = &get_apache_log($d->{'dom'}, $d->{'web_port'});
	if (!&is_under_directory($d->{'home'}, $alog) &&
	    !$allopts->{'dir'}->{'dirnologs'}) {
		&$first_print($text{'backup_apachelog'});
		&copy_source_dest($alog, $file."_alog");
		local $elog = &get_apache_log($d->{'dom'},
					      $d->{'web_port'}, 1);
		if (!&is_under_directory($d->{'home'}, $elog)) {
			&copy_source_dest($elog, $file."_elog");
			}
		&$second_print($text{'setup_done'});
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
if ($_[0]->{'alias'} && $_[0]->{'alias_mode'}) {
	# Just re-add ServerAlias entries if missing
	&$first_print($text{'restore_apachecp2'});
	local $alias = &get_domain($_[0]->{'alias'});
	local ($pvirt, $pconf) = &get_apache_virtual($alias->{'dom'},
						     $alias->{'web_port'});
	if (!$pvirt) {
		&$second_print($text{'setup_ewebalias'});
		return 0;
		}
	local @sa = &apache::find_directive("ServerAlias", $pconf);
	local $srclref = &read_file_lines($_[1], 1);
	push(@sa, @$srclref);
	&unflush_file_lines($_[1]);
	@sa = &unique(@sa);
	&apache::save_directive("ServerAlias", \@sa, $pconf, $conf);
	&flush_file_lines($pvirt->{'file'});
	&$second_print($text{'setup_done'});
	return 1;
	}
&$first_print($text{'restore_apachecp'});
&obtain_lock_web($_[0]);
local $rv;
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_port'});
local $tmpl = &get_template($_[0]->{'template'});
if ($virt) {
	local $srclref = &read_file_lines($_[1]);
	local $dstlref = &read_file_lines($virt->{'file'});

	# Extract old logging-based directives before we change them, so they
	# can be restored later to match *this* system
	local %lmap;
	foreach $i ($virt->{'line'} .. $virt->{'line'}+scalar(@$srclref)-1) {
		if ($dstlref->[$i] =~
		    /^\s*(CustomLog|ErrorLog|TransferLog)\s+(.*)/i) {
			$lmap{lc($1)} = $2;
			}
		}

	splice(@$dstlref, $virt->{'line'}+1, $virt->{'eline'}-$virt->{'line'}-1,
	       @$srclref[1 .. @$srclref-2]);

	if ($_[3]->{'reuid'}) {
		# Fix up any UID or GID in suexec lines
		local $i;
		foreach $i ($virt->{'line'} .. $virt->{'line'}+scalar(@$srclref)-1) {
			if ($dstlref->[$i] =~ /^\s*SuexecUserGroup\s/) {
				$dstlref->[$i] = "SuexecUserGroup \"#$_[0]->{'uid'}\" \"#$_[0]->{'ugid'}\"";
				}
			elsif ($dstlref->[$i] =~ /^\s*User\s/) {
				$dstlref->[$i] = "User \"#$_[0]->{'uid'}\"";
				}
			elsif ($dstlref->[$i] =~ /^\s*Group\s/) {
				$dstlref->[$i] = "Group \"#$_[0]->{'ugid'}\"";
				}
			}
		}
	if (!$tmpl->{'web_suexec'}) {
		# Remove suexec directives if not supported on this server
		foreach $i ($virt->{'line'} ..
			    $virt->{'line'}+scalar(@$srclref)-1) {
			if ($dstlref->[$i] =~ /^\s*(SuexecUserGroup|User|Group)\s/) {
				splice(@$dstlref, $i--, 1);
				}
			}
		}
	else {
		# Fix SuexecUserGroup or User/Group directives to match
		# Apache version
		local ($uline, $gline, $suline);
		foreach $i ($virt->{'line'} ..
			    $virt->{'line'}+scalar(@$srclref)-1) {
			local $l = $dstlref->[$i];
			$uline = $i if ($l =~ /^\s*User\s/);
			$gline = $i if ($l =~ /^\s*Group\s/);
			$suline = $i if ($l =~ /^\s*SuexecUserGroup\s/);
			}
		local $pdom = $_[0]->{'parent'} ?
				&get_domain($_[0]->{'parent'}) : $_[0];
		if ($apache::httpd_modules{'core'} >= 2.0 && $uline) {
			# Replace User and Group with SuexecUserGroup
			splice(@$dstlref, $uline, 1,
			       "SuexecUserGroup \"#$pdom->{'uid'}\" \"#$pdom->{'ugid'}\"");
			if ($gline) {
				splice(@$dstlref, $gline, 1);
				}
			}
		elsif ($apache::httpd_modules{'core'} < 2.0 && $suline) {
			# Replace SuexecUserGroup with User and Group
			splice(@$dstlref, $suline, 1,
			       "User \"#$pdom->{'uid'}\"",
			       "Group \"#$pdom->{'ugid'}\"");
			}
		}

	# Fix up any DocumentRoot or other file-related directives
	if ($_[5]->{'home'} && $_[5]->{'home'} ne $_[0]->{'home'}) {
		local $i;
		foreach $i ($virt->{'line'} ..
			    $virt->{'line'}+scalar(@$srclref)-1) {
			$dstlref->[$i] =~
				s/\Q$_[5]->{'home'}\E/$_[0]->{'home'}/g;
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
	local $i;
	foreach $i ($virt->{'line'} ..  $virt->{'line'}+scalar(@$srclref)-1) {
		if ($dstlref->[$i] =~ /^\s*\Q$oldn\E\s+(.*)$/) {
			$dstlref->[$i] = "$newn $1";
			}
		}

	&flush_file_lines($virt->{'file'});
	undef(@apache::get_config_cache);

	# Re-generate PHP wrappers to match this system
	if (defined(&create_php_wrappers) && !$_[0]->{'alias'}) {
		local $mode = &get_domain_php_mode($_[0]);
		&create_php_wrappers($_[0], $mode);
		}
	&$second_print($text{'setup_done'});

	# Make sure the PHP execution mode is valid
	local $mode;
	if (defined(&get_domain_php_mode) && !$_[0]->{'alias'}) {
		&$first_print($text{'restore_checkmode'});
		$mode = &get_domain_php_mode($_[0]);
		local @supp = &supported_php_modes($_[0]);
		if ($mode && &indexof($mode, @supp) < 0 && @supp) {
			# Need to fix
			local $fix = pop(@supp);
			&save_domain_php_mode($_[0], $fix);
			&$second_print(&text('restore_badmode', 
					$text{'phpmode_short_'.$mode},
					$text{'phpmode_short_'.$fix}));
			}
		else {
			# Looks good .. but re-save anyway, to update
			# compatible directives
			&save_domain_php_mode($_[0], $mode);
			&$second_print(&text('restore_okmode',
					$text{'phpmode_short_'.$mode}));
			}
		}

	# Correct system-specific entries in PHP config files
	if (!$_[0]->{'alias'} && $_[5]) {
		local $sock = &get_php_mysql_socket($_[0]);
		local @fixes = (
		  [ "session.save_path", $_[5]->{'home'}, $_[0]->{'home'}, 1 ],
		  [ "upload_tmp_dir", $_[5]->{'home'}, $_[0]->{'home'}, 1 ],
		  );
		if ($sock ne 'none') {
			push(@fixes, [ "mysql.default_socket", undef, $sock ]);
			}
		&fix_php_ini_files($_[0], \@fixes);
		}

	# Fix broken PHP extension_dir directives
	if (($mode eq "fcgid" || $mode eq "cgi") && !$_[0]->{'alias'}) {
		&fix_php_extension_dir($_[0]);
		}

	# Set new public_html and cgi-bin paths
	&find_html_cgi_dirs($_[0]);

	# Create empty log files if needed
	&setup_apache_logs($_[0]);

	# Copy back log files if they were in the backup
	if (-r $_[1]."_alog") {
		&$first_print($text{'restore_apachelog'});
		local $alog = &get_apache_log($_[0]->{'dom'},
					      $_[0]->{'web_port'});
		&copy_source_dest($_[1]."_alog", $alog);
		&set_apache_log_permissions($_[0], $alog);
		if (-r $_[1]."_elog") {
			local $elog = &get_apache_log($_[0]->{'dom'},
						      $_[0]->{'web_port'}, 1);
			&copy_source_dest($_[1]."_elog", $elog);
			&set_apache_log_permissions($_[0], $elog);
			}
		&$second_print($text{'setup_done'});
		}

	# Re-link Apache logs if needed
	&link_apache_logs($_[0]);

	# Fix Options lines
	my ($virt, $vconf, $conf) = &get_apache_virtual($_[0]->{'dom'},
							$_[0]->{'web_port'});
	if ($virt) {
		&fix_options_directives($vconf, $conf, 0);
		}

	&register_post_action(\&restart_apache);
	$rv = 1;
	}
else {
	&$second_print($text{'delete_noapache'});
	$rv = 0;
	}
&release_lock_web($_[0]);
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
local @logs = ( &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'}),
		&get_apache_log($_[0]->{'dom'}, $_[0]->{'web_sslport'}) );
return if ($_[0]->{'alias'} || $_[0]->{'subdom'}); # never accounted separately
local $l;
local $max_ltime = $_[1];
foreach $l (&unique(@logs)) {
	local $f;
	foreach $f (&all_log_files($l, $max_ltime)) {
		local $_;
		if ($f =~ /\.gz$/i) {
			open(LOG, "gunzip -c ".quotemeta($f)." |");
			}
		elsif ($f =~ /\.Z$/i) {
			open(LOG, "uncompress -c ".quotemeta($f)." |");
			}
		else {
			open(LOG, $f);
			}
		while(<LOG>) {
			if (/^(\S+)\s+(\S+)\s+(\S+)\s+\[(\d+)\/(\S+)\/(\d+):(\d+):(\d+):(\d+)\s+(\S+)\]\s+"([^"]*)"\s+(\S+)\s+(\S+)/ && $12 ne "206") {
				# Valid-looking log line .. work out the time
				local $ltime = timelocal($9, $8, $7, $4, $apache_mmap{lc($5)}, $6-1900);
				if ($ltime > $_[1]) {
					local $day = int($ltime / (24*60*60));
					$_[2]->{"web_".$day} += $13;
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
$_[0] =~ /^(.*)\/([^\/]+)$/;
local $dir = $1;
local $base = $2;
local ($f, @rv, %mtime);
opendir(DIR, $dir);
foreach $f (readdir(DIR)) {
	if ($f =~ /^\Q$base\E/ && -f "$dir/$f" && $f ne $base.".offset") {
		local @st = stat("$dir/$f");
		if ($f ne $base) {
			next if ($_[1] && $st[9] <= $_[1]);
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
if ($_[0]->{'proxy_pass_mode'} == 2) {
	local $template = &get_template($_[0]->{'template'});
	local $ff = &framefwd_file($_[0]);
	&unlink_file($ff);
	local $text = $template->{'frame'};
	$text =~ s/\t/\n/g;
	&open_tempfile_as_domain_user($d, FRAME, ">$ff");
	local %subs = %{$_[0]};
	$subs{'proxy_title'} ||= $tmpl{'owner'};
	$subs{'proxy_meta'} ||= "";
	$subs{'proxy_meta'} = join("\n", split(/\t/, $subs{'proxy_meta'}));
	&print_tempfile(FRAME, &substitute_domain_template($text, \%subs));
	&close_tempfile_as_domain_user($d, FRAME);

	# Create a blank HTML page too, used in the frameset
	local $bl = &frameblank_file($_[0]);
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
local ($d, $rel, $nosubdom) = @_;
# First check for cache in domain object
local $want = $rel ? 'public_html_dir' : 'public_html_path';
if ($d->{$want} && !$nosubdom) {
	return $d->{$want};
	}
if ($d->{'subdom'} && !$nosubdom) {
	# Under public_html of parent domain
	local $subdom = &get_domain($d->{'subdom'});
	local $phtml = &public_html_dir($subdom, $rel);
	if ($rel) {
		return "../../$phtml/$d->{'subprefix'}";
		}
	else {
		return "$phtml/$d->{'subprefix'}";
		}
	}
else {
	# Under own home
	local $tmpl = &get_template($d->{'template'});
	local ($hdir) = ($tmpl->{'web_html_dir'} || 'public_html');
	if ($hdir ne 'public_html') {
		$hdir = &substitute_domain_template($hdir, $d);
		}
	return $rel ? $hdir : "$d->{'home'}/$hdir";
	}
}

# set_public_html_dir(&domain, sub-dir)
# Sets the HTML directory for a virtual server, by updating the DocumentRoot
# and <Directory> block. Returns undef on success or an error message on
# failure.
sub set_public_html_dir
{
local ($d, $subdir) = @_;
local $p = &domain_has_website($d);
local $path = $d->{'home'}."/".$subdir;
local $oldpath = $d->{'public_html_path'};
if ($p ne "web") {
	my $err = &plugin_call($p, "feature_set_web_public_html_dir",
			       $d, $subdir);
	return $err if ($err);
	$d->{'public_html_dir'} = $subdir;
	$d->{'public_html_path'} = $path;
	return undef;
	}
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
foreach my $p (@ports) {
	local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	&apache::save_directive("DocumentRoot", [ $path ], $vconf, $conf);
	local @dirs = &apache::find_directive_struct("Directory", $vconf);
	local ($dir) = grep { $_->{'words'}->[0] eq $oldpath ||
			      $_->{'words'}->[0] eq $oldpath."/" } @dirs;
	$dir ||= $dirs[0];
	$dir || return "No existing Directory block found!";
	local $olddir = { %$dir };
	$dir->{'value'} = $path;
	&apache::save_directive_struct($olddir, $dir, $vconf, $conf, 1);
	&flush_file_lines($virt->{'file'});
	}
$d->{'public_html_dir'} = $subdir;
$d->{'public_html_path'} = $path;
&register_post_action(\&restart_apache);
return undef;
}

# cgi_bin_dir(&domain, [relative], [no-subdomain])
# Returns the CGI programs directory for a virtual server
sub cgi_bin_dir
{
local ($d, $rel, $nosubdom) = @_;
# First check for cache in domain object
local $want = $rel ? 'cgi_bin_dir' : 'cgi_bin_path';
if ($d->{$want} && !$nosubdom) {
	return $d->{$want};
	}
local $cdir = $d->{'cgi_bin_dir'} || "cgi-bin";
if ($d->{'subdom'} && !$nosubdom) {
	# Under cgi-bin of parent domain
	local $subdom = &get_domain($d->{'subdom'});
	local $pcgi = &cgi_bin_dir($subdom, $rel);
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
local $hdir = &public_html_dir($_[0]);
return "$hdir/framefwd.html";
}

# frameblank_file(&domain)
sub frameblank_file
{
local $hdir = &public_html_dir($_[0]);
return "$hdir/frameblank.html";
}

# check_depends_web(&dom)
# Ensure that a website has a home directory, if not proxying
sub check_depends_web
{
if (!$_[0]->{'parent'} && !$_[0]->{'unix'}) {
	# For a non-sub-server, we need a Unix user
	return $text{'setup_edepunix2'};
	}
if ($_[0]->{'alias'}) {
	# If this is an alias domain, then no home is needed
	return undef;
	}
elsif ($_[0]->{'proxy_pass_mode'} == 2) {
	# If proxying using frame forwarding, a home is needed
	return $_[0]->{'dir'} ? undef : $text{'setup_edepframe'};
	}
elsif ($_[0]->{'proxy_pass_mode'} == 1) {
	# If proxying using ProxyPass, no home is needed
	return undef;
	}
else {
	# For a normal website, we need a home
	return $_[0]->{'dir'} ? undef : $text{'setup_edepweb'};
	}
}

# frame_fwd_input(forwardto)
sub frame_fwd_input
{
local $rv;
local $label;
if ($config{'proxy_pass'} == 1) {
	$label = &hlink($text{'form_proxy'}, "proxypass");
	}
else {
	$label = &hlink($text{'form_framefwd'}, "framefwd");
	}
return &ui_table_row($label,
	&ui_opt_textbox("proxy", $_[0], 40,
			$text{'form_plocal'}, $text{'form_purl'}), 3);
}

# setup_writelogs(&domain)
# Creates the writelogs wrapper
sub setup_writelogs
{
&foreign_require("cron", "cron-lib.pl");
&cron::create_wrapper($writelogs_cmd, $module_name, "writelogs.pl");
if (&has_command("chcon")) {
	&execute_command("chcon -t httpd_sys_script_exec_t ".quotemeta($writelogs_cmd).
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
&require_apache();
local $conf = &apache::get_config();
local @ports = ( $_[0]->{'web_port'},
		 $_[0]->{'ssl'} ? ( $_[0]->{'web_sslport'} ) : ( ) );
local ($p, $any);
foreach $p (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'}, $p);
	local $ld;
	foreach $ld ("CustomLog", "ErrorLog") {
		local $custom = &apache::find_directive($ld, $vconf);
		if ($custom !~ /$writelogs_cmd/ && $custom =~ /(\S+)(\s*\S*)/) {
			# Fix logging directive
			&$first_print($text{'save_fix'.lc($ld)});
			$custom = "\"|$writelogs_cmd $_[0]->{'id'} $1\"$2";
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
&require_apache();
local $conf = &apache::get_config();
local @ports = ( $_[0]->{'web_port'},
		 $_[0]->{'ssl'} ? ( $_[0]->{'web_sslport'} ) : ( ) );
local ($p, $any);
foreach $p (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'}, $p);
	local $ld;
	foreach $ld ("CustomLog", "ErrorLog") {
		local $custom = &apache::find_directive($ld, $vconf);
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
local ($virt, $vconf) = &get_apache_virtual($_[0]->{'dom'},
					    $_[0]->{'web_port'});
local $custom = &apache::find_directive("CustomLog", $vconf);
return $custom =~ /^"\|$writelogs_cmd\s+(\S+)\s+(\S+)"(\s*\S*)/ ? 1 : 0;
}

# get_website_file(&domain)
# Returns the file to add a new website to, and optionally a flag indicating
# that this is a new file.
sub get_website_file
{
&require_apache();
local $vfile = $apache::config{'virt_file'} ?
	&apache::server_root($apache::config{'virt_file'}) :
	undef;
local ($rv, $newfile);
if ($vfile) {
	if (!-d $vfile) {
		$rv = $vfile;
		}
	else {
		local $tmpl = $apache::config{'virt_name'} || '${DOM}.conf';
		$rv = "$vfile/".&substitute_domain_template($tmpl, $_[0]);
		$newfile = 1;
		}
	}
else {
	local $vconf = &apache::get_virtual_config();
	$rv = $vconf->[0]->{'file'};
	}
$rv =~ s/\/+/\//g;	# Fix use of //
return wantarray ? ($rv, $newfile) : $rv;
}

# get_apache_user([&domain])
# Returns the Unix user that the Apache process runs as, such as www or httpd
sub get_apache_user
{
if ($_[0]) {
	local $tmpl = &get_template($_[0]->{'template'});
	return $tmpl->{'web_user'} if ($tmpl->{'web_user'} &&
				       defined(getpwnam($tmpl->{'web_user'})));
	}
foreach $u ("httpd", "apache", "www", "www-data", "wwwrun", "nobody") {
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
sub add_name_virtual
{
local ($d, $conf, $web_port, $no_star_match, $ip) = @_;
&require_apache();
if ($apache::httpd_modules{'core'} >= 2.4) {
	# Apache 2.4 doesn't need NameVirtualHost any more
	return 1;
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
foreach my $dip ($d->{'ip'}, $d->{'ip6'} ? ( $d->{'ip6'} ) : ( )) {
	local $defport = &apache::find_directive("Port", $conf) || 80;
	local @listen = &apache::find_directive("Listen", $conf);
	local $lfound;
	foreach my $l (@listen) {
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
local @rv;
local ($link, $slink);
if (&get_webmin_version() < 1.582) {
	&require_apache();
	local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'},
						     $d->{'web_port'});
	$link = &indexof($virt, @$conf);
	if ($d->{'ssl'}) {
		local ($svirt, $svconf) = &get_apache_virtual($d->{'dom'},
							$d->{'web_sslport'});
		$slink = &indexof($svirt, @$conf);
		}
	}
else {
	$link = $d->{'dom'}.":".$d->{'web_port'};
	$slink = $d->{'dom'}.":".$d->{'web_sslport'};
	}
# Link to configure virtual host
push(@rv, { 'mod' => 'apache',
	    'desc' => $text{'links_web'},
	    'page' => "virt_index.cgi?virt=".$link,
	    'cat' => 'services',
	  });
if ($d->{'ssl'}) {
	# Link to configure SSL virtual host
	push(@rv, { 'mod' => 'apache',
		    'desc' => $text{'links_ssl'},
		    'page' => "virt_index.cgi?virt=".$slink,
		    'cat' => 'services',
		  });
	}

# Links to logs
foreach my $log ([ 0, $text{'links_alog'} ],
		 [ 1, $text{'links_elog'} ]) {
	local $lf = &get_apache_log($d->{'dom'},
				    $d->{'web_port'}, $log->[0]);
	if ($lf) {
		local $param = &master_admin() ? "file"
					       : "extra";
		push(@rv, { 'mod' => 'syslog',
			    'desc' => $log->[1],
			    'page' => "save_log.cgi?view=1&".
				      "$param=".&urlize($lf),
			    'cat' => 'logs',
			  });
		}
	}

# Links to edit PHP configs
foreach my $ini (&find_domain_php_ini_files($d)) {
	push(@rv, { 'mod' => 'phpini',
		    'desc' => $ini->[0] ?
			&text('links_phpini2', $ini->[0]) :
			&text('links_phpini'),
		    'page' => 'list_ini.cgi?file='.
				&urlize($ini->[1]),
		    'cat' => 'services',
		  });
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
if ($apid) {
	return ( { 'status' => 1,
		   'name' => $text{'index_aname'},
		   'desc' => $text{'index_astop'},
		   'restartdesc' => $text{'index_arestart'},
		   'longdesc' => $text{'index_astopdesc'},
		   'links' => \@links } );
	}
else {
	return ( { 'status' => 0,
		   'name' => $text{'index_aname'},
		   'desc' => $text{'index_astart'},
		   'longdesc' => $text{'index_astartdesc'},
		   'links' => \@links } );
	}
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

# show_template_web(&tmpl)
# Outputs HTML for editing apache related template options
sub show_template_web
{
local ($tmpl) = @_;
local @allvers = &unique(map { $_->[0] } &list_available_php_versions());

# Work out fields to disable
local @webfields = ( "web", "suexec", "user_def",
		     $tmpl->{'writelogs'} ? ( "writelogs" ) : ( ),
		     "html_dir", "html_dir_def", "html_perms", "stats_mode",
		     "stats_dir", "stats_hdir", "statspass", "statsnoedit",
		     "alias_mode", "web_port", "web_sslport",
		     "web_webmin_ssl", "web_usermin_ssl", "web_ssi",
		     "web_ssi_suffix", );
push(@webfields, "webmail", "webmaildom", "webmaildom_def",
		 "admin", "admindom", "admindom_def");
push(@webfields, "web_php_suexec", "web_phpver",
		 "web_phpchildren", "web_php_noedit");
foreach my $phpver (@allvers) {
	push(@webfields, "web_php_ini_".$phpver,
			 "web_php_ini_".$phpver."_def");
	}
if (defined(&get_domain_ruby_mode)) {
	push(@webfields, "web_ruby_suexec");
	}

local $ndi = &none_def_input("web", $tmpl->{'web'}, $text{'tmpl_webbelow'}, 1,
			     0, undef, \@webfields);
print &ui_table_row(&hlink($text{'tmpl_web'}, "template_web"),
	$ndi."<br>\n".
	&ui_textarea("web", $tmpl->{'web'} eq "none" ? "" :
				join("\n", split(/\t/, $tmpl->{'web'})),
		     10, 60));

# Input for adding suexec directives
print &ui_table_row(&hlink($text{'newweb_suexec'}, "template_suexec"),
	&ui_yesno_radio("suexec", $tmpl->{'web_suexec'} ? 1 : 0));

# Input for logging via program. Deprecated, so don't show unless enabled
if ($tmpl->{'web_writelogs'}) {
	print &ui_table_row(&hlink($text{'newweb_writelogs'},
				   "template_writelogs"),
		&ui_yesno_radio("writelogs", $tmpl->{'web_writelogs'} ? 1 : 0));
	}

# Input for Apache user to add to domain's group
print &ui_table_row(&hlink($text{'newweb_user'}, "template_user_def"),
	&ui_radio("user_def", $tmpl->{'web_user'} eq 'none' ? 2 :
				   $tmpl->{'web_user'} ? 1 : 0,
	       [ [ 2, $text{'no'}."<br>" ],
		 [ 0, $text{'newweb_userdef'}."<br>" ],
		 [ 1, $text{'newweb_useryes'}." ".
		      &ui_user_textbox("user", $tmpl->{'web_user'} eq 'none' ?
						'' : $tmpl->{'web_user'}) ] ]));

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

# Webalizer stats sub-directory input
local $smode = $tmpl->{'web_stats_hdir'} ? 2 :
	       $tmpl->{'web_stats_dir'} ? 1 : 0;
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
print &ui_table_row(&hlink($text{'newweb_statspass'}, "template_statspass"),
	&ui_radio("statspass", $tmpl->{'web_stats_pass'} ? 1 : 0,
		  [ [ 1, $text{'yes'} ], [ 0, $text{'no'} ] ]));

# Allow editing of Webalizer report
print &ui_table_row(&hlink($text{'newweb_statsedit'}, "template_statsedit"),
	&ui_radio("statsnoedit", $tmpl->{'web_stats_noedit'} ? 1 : 0,
	          [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

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
print &ui_table_row(&hlink($text{'newweb_sslport'}, "template_web_sslport"),
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

# Setup matching Webmin/Usermin SSL cert
print &ui_table_row(&hlink($text{'newweb_webmin'},
			   "template_web_webmin_ssl"),
	&ui_radio("web_webmin_ssl",
		  $tmpl->{'web_webmin_ssl'} ? 1 : 0,
		  [ [ 1, $text{'yes'} ], [ 0, $text{'no'} ] ]));

print &ui_table_row(&hlink($text{'newweb_usermin'},
			   "template_web_usermin_ssl"),
	&ui_radio("web_usermin_ssl",
		  $tmpl->{'web_usermin_ssl'} ? 1 : 0,
		  [ [ 1, $text{'yes'} ], [ 0, $text{'no'} ] ]));

# Add rewrites for webmail and admin
print &ui_table_hr();
foreach my $r ('webmail', 'admin') {
	print &ui_table_row(&hlink($text{'newweb_'.$r},
				   "template_".$r),
		&ui_yesno_radio($r, $tmpl->{'web_'.$r} ? 1 : 0));

	# Domain name to use in webmail redirect
	print &ui_table_row(&hlink($text{'newweb_'.$r.'dom'},
				   "template_".$r."dom"),
		&ui_opt_textbox($r."dom",
				$tmpl->{'web_'.$r.'dom'}, 40,
				$text{'newweb_webmailsame'}));
	}

print &ui_table_hr();

# Run PHP scripts as user
print &ui_table_row(
    &hlink($text{'tmpl_phpmode'}, "template_phpmode"),
    &ui_radio("web_php_suexec", int($tmpl->{'web_php_suexec'}),
	      [ [ 0, $text{'phpmode_mod_php'}."<br>" ],
		[ 1, $text{'phpmode_cgi'}."<br>" ],
		[ 2, $text{'phpmode_fcgid'}."<br>" ] ]));

# Default PHP version to setup
print &ui_table_row(
    &hlink($text{'tmpl_phpver'}, "template_phpver"),
    &ui_select("web_phpver", $tmpl->{'web_phpver'},
	       [ [ "", $text{'tmpl_phpverdef'} ],
		 map { [ $_->[0] ] } &list_available_php_versions() ]));

# Default number of PHP child processes
print &ui_table_row(
    &hlink($text{'tmpl_phpchildren'}, "template_phpchildren"),
    &ui_opt_textbox("web_phpchildren", $tmpl->{'web_phpchildren'},
	    5, $text{'tmpl_phpchildrennone'}));

# Source php.ini files
foreach my $phpver (@allvers) {
	print &ui_table_row(
	    &hlink(&text('tmpl_php_iniv', $phpver), "template_php_ini"),
	    &ui_opt_textbox("web_php_ini_$phpver",
			    $tmpl->{'web_php_ini_'.$phpver},
			    40, $text{'default'}));
	}

# Allow editing of PHP configs
print &ui_table_row(
    &hlink($text{'tmpl_php_noedit'}, "template_php_noedit"),
    &ui_radio("web_php_noedit", $tmpl->{'web_php_noedit'},
	      [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

if (defined(&get_domain_ruby_mode)) {
	# Run ruby scripts as user
	print &ui_table_row(
	    &hlink($text{'tmpl_rubymode'}, "template_rubymode"),
	    &ui_radio("web_ruby_suexec", int($tmpl->{'web_ruby_suexec'}),
		      [ [ -1, $text{'phpmode_noruby'}."<br>" ],
			[ 0, $text{'phpmode_mod_ruby'}."<br>" ],
			[ 1, $text{'phpmode_cgi'}."<br>" ] ]));
	}

print &ui_table_hr();

# Webalizer template
print &ui_table_row(&hlink($text{'tmpl_webalizer'},
			   "template_webalizer"),
    &none_def_input("webalizer", $tmpl->{'webalizer'},
		    $text{'tmpl_webalizersel'}, 0, 0,
		    $text{'tmpl_webalizernone'}, [ "webalizer" ])."\n".
    &ui_textbox("webalizer", $tmpl->{'webalizer'} eq "none" ?
				"" : $tmpl->{'webalizer'}, 40));

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

print &ui_table_hr();

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
}

# parse_template_web(&tmpl)
# Updates apache related template options from %in
sub parse_template_web
{
local ($tmpl) = @_;

# Save web-related settings
$old_web_port = $web_port;
$old_web_sslport = $web_sslport;
$tmpl->{'web'} = &parse_none_def("web");
if ($in{"web_mode"} == 2) {
	$err = &check_apache_directives($in{"web"});
	&error($err) if ($err);
	$tmpl->{'web_suexec'} = $in{'suexec'};
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

	$tmpl->{'web_webmin_ssl'} = $in{'web_webmin_ssl'};
	$tmpl->{'web_usermin_ssl'} = $in{'web_usermin_ssl'};

	# Parse SSI setting
	$tmpl->{'web_ssi'} = $in{'web_ssi'};
	if ($in{'web_ssi'} == 1) {
		$in{'web_ssi_suffix'} =~ /^\.([a-z0-9\.\_\-]+)$/i ||
			&error($text{'phpmode_essisuffix'});
		$tmpl->{'web_ssi_suffix'} = $in{'web_ssi_suffix'};
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

	# Save PHP settings
	&require_apache();
	if ($in{'web_php_suexec'}) {
		$in{'suexec'} ||
			&error($text{'tmpl_ephpsuexec'});
		&has_command("php") ||
			&error($text{'tmpl_ephpcmd'});
		}
	$tmpl->{'web_php_suexec'} = $in{'web_php_suexec'};
	$tmpl->{'web_phpver'} = $in{'web_phpver'};
	if ($in{'web_phpchildren_def'} ||
	    !defined($in{'web_phpchildren_def'})) {
		$tmpl->{'web_phpchildren'} = undef;
		}
	else {
		if ($in{'web_phpchildren'} < 1 ||
		    $in{'web_phpchildren'} > $max_php_fcgid_children) {
			&error(&text('phpmode_echildren',
				     $max_php_fcgid_children));
			}
		$tmpl->{'web_phpchildren'} = $in{'web_phpchildren'};
		}
	foreach my $phpver (&unique(map { $_->[0] }
				    &list_available_php_versions())) {
		$in{'web_php_ini_'.$phpver.'_def'} ||
		  -r $in{'web_php_ini_'.$phpver} ||
			&error($text{'tmpl_ephpini'});
		$tmpl->{'web_php_ini_'.$phpver} =
			$in{'web_php_ini_'.$phpver.'_def'} ? undef
				       : $in{'web_php_ini_'.$phpver};
		}
	$tmpl->{'web_php_noedit'} = $in{'web_php_noedit'};

	# Save ruby settings
	if (defined(&get_domain_ruby_mode)) {
		if ($in{'web_ruby_suexec'} > 0) {
			&has_command("ruby") ||
				&error($text{'tmpl_erubycmd'});
			}
		$tmpl->{'web_ruby_suexec'} = $in{'web_ruby_suexec'};
		}
	}
$tmpl->{'webalizer'} = &parse_none_def("webalizer");
if ($in{"webalizer_mode"} == 2) {
	-r $in{'webalizer'} || &error($text{'tmpl_ewebalizer'});
	}
$tmpl->{'disabled_web'} = &parse_none_def("disabled_web");
if ($in{'disabled_url_mode'} == 2) {
	$in{'disabled_url'} =~ /^(http|https):\/\/\S+/ ||
		&error($text{'tmpl_edisabled_url'});
	}
$tmpl->{'disabled_url'} = &parse_none_def("disabled_url");

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

if ($config{'proxy_pass'} == 2) {
	# Save frame-forwarding settings
	$tmpl->{'frame'} = &parse_none_def("frame");
	}
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

# show_template_phpwrappers(&template)
# Outputs HTML for setting custom PHP wrapper scripts
sub show_template_phpwrappers
{
local ($tmpl) = @_;
foreach my $w (@php_wrapper_templates) {
	local $ndi = &none_def_input($w, $tmpl->{$w},
				     $text{'tmpl_wrapperbelow'}, 0, 0,
				     $text{'tmpl_wrappernone'}, [ $w ]);
	print &ui_table_row(&hlink($text{'tmpl_'.$w}, "template_".$w),
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
foreach my $w (@php_wrapper_templates) {
	if ($in{$w."_mode"} == 0) {
		$tmpl->{$w} = 'none';
		}
	elsif ($in{$w."_mode"} == 1) {
		delete($tmpl->{$w});
		}
	elsif ($in{$w."_mode"} == 2) {
		$in{$w} =~ s/\r//g;
		$in{$w} =~ /^\#\!/ || &error($text{'tmpl_e'.$w});
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
if ($apache::httpd_modules{'core'} >= 2.0) {
	# Look for SuexecUserGroup
	local $su = &apache::find_directive("SuexecUserGroup", $vconf);
	return $su ? 1 : 0;
	}
else {
	# Look for User and Group
	local $u = &apache::find_directive("User", $vconf);
	local $g = &apache::find_directive("Group", $vconf);
	return $u && $g ? 1 : 0;
	}
}

# save_domain_suexec(&domain, enabled)
# Enables or disables suexec for some virtual host
sub save_domain_suexec
{
local ($d, $mode) = @_;
&require_apache();
local @ports;
push(@ports, $d->{'web_port'}) if ($d->{'web'});
push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
foreach my $port (@ports) {
	local ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);
	local $pdom = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
	if ($apache::httpd_modules{'core'} >= 2.0) {
		# Add or remove SuexecUserGroup
		&apache::save_directive("SuexecUserGroup",
		    $mode ? [ "\"#$pdom->{'uid'}\" \"#$pdom->{'gid'}\"" ] : [],
		    $vconf, $conf);
		}
	else {
		# Add or remove User and Group directives
		&apache::save_directive("User",
		    $mode ? [ "\"#$pdom->{'uid'}\"" ] : [ ], $vconf, $conf);
		&apache::save_directive("Group",
		    $mode ? [ "\"#$pdom->{'gid'}\"" ] : [ ], $vconf, $conf);
		}
	&flush_file_lines($virt->{'file'});
	}
&register_post_action(\&restart_apache);
}

# add_script_language_directives(&domain, &tmpl, port)
# Adds directives needed to enable PHP, Ruby and other languages to the
# <virtualhost> for some new domain.
sub add_script_language_directives
{
local ($d, $tmpl, $port) = @_;

if (defined(&save_domain_php_mode)) {
	&require_apache();
	if ($tmpl->{'web_php_suexec'} == 1 ||
	    $tmpl->{'web_php_suexec'} == 2 &&
	     !$apache::httpd_modules{'mod_fcgid'}) {
		# Create cgi wrappers for PHP 4 and 5
		&save_domain_php_mode($d, "cgi", $port, 1);
		}
	elsif ($tmpl->{'web_php_suexec'} == 2) {
		# Add directives for FastCGId
		&save_domain_php_mode($d, "fcgid", $port, 1);
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
}

# add_proxy_allow_directives(&domain)
# Adds a <Proxy *> section to allow ProxyPass to work, in case it is overridden
# at a higher level (as seen on Ubuntu).
sub add_proxy_allow_directives
{
local ($d) = @_;
&require_apache();
return 0 if ($apache::httpd_modules{'core'} < 2);	# Not supported in 1.3
local @ports;
push(@ports, $d->{'web_port'}) if ($d->{'web'});
push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
local $added = 0;
foreach my $port (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);
	local @proxy = grep { $_ eq "*" }
			    &apache::find_directive("Proxy", $vconf);
	if (!@proxy) {
		local $lref = &read_file_lines($virt->{'file'});
		splice(@$lref, $virt->{'eline'}, 0,
		       "<Proxy *>",
		       "allow from all",
		       "</Proxy>");
		&flush_file_lines($virt->{'file'});
		undef(@apache::get_config_cache);
		$added++;
		}
	}
return $added;
}

# add_webmail_redirect_directives(&domain, &template)
# Add mod_rewrite directives to direct webmail.$DOM and admin.$DOM to
# Usermin and Webmin. Also updates the ServerAlias if needed.
sub add_webmail_redirect_directives
{
local ($d, $tmpl) = @_;
return 1 if ($d->{'alias'});	# Don't bother for alias domains, due to
				# Apache config clashes
$tmpl ||= &get_template($d->{'template'});
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_add_web_webmail_redirect", $d, $tmpl);
	}
&require_apache();

foreach my $r ('webmail', 'admin') {
	next if (!$tmpl->{'web_'.$r});

	# Get directives we will be changing
	local $conf = &apache::get_config();
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'},
						    $d->{'web_port'});
	next if (!$virt);
	local @reng = &apache::find_directive("RewriteEngine", $vconf);
	local @rcond = &apache::find_directive("RewriteCond", $vconf);
	local @rrule = &apache::find_directive("RewriteRule", $vconf);
	local @sa = &apache::find_directive("ServerAlias", $vconf);

	# Work out the URL to redirect to
	local $url = $tmpl->{'web_'.$r.'dom'};
	if ($url) {
		# Sub in any template
		$url = &substitute_domain_template($url, $d);
		}
	else {
		# Work out URL
		local ($port, $proto);
		if ($r eq 'webmail') {
			# From Usermin
			if (&foreign_installed("usermin")) {
				&foreign_require("usermin", "usermin-lib.pl");
				local %miniserv;
				&usermin::get_usermin_miniserv_config(
					\%miniserv);
				$proto = $miniserv{'ssl'} ? 'https' : 'http';
				$port = $miniserv{'port'};
				}
			# Fall back to standard defaults
			$proto ||= "http";
			$port ||= 20000;
			}
		else {
			# From Webmin
			($port, $proto) = &get_miniserv_port_proto();
			}
		$url = "$proto://$d->{'dom'}:$port/";
		}

	# Add the mod_rewrite directives
	local $rhost = "$r.$d->{'dom'}";
	local ($ron) = grep { lc($_) eq "on" } @ron;
	push(@ron, "on") if (!$ron);
	local $condv = "\%{HTTP_HOST} =$rhost";
	local ($rcond) = grep { $_ eq $condv } @rcond;
	push(@rcond, $condv) if (!$rcond);
	local $rulev = "^(.*) $url [R]";
	local $rrule = grep { $_ eq $rulev } @rrule;
	push(@rrule, $rulev) if (!$rrule);

	# Add the ServerAlias
	local $foundsa;
	foreach my $s (@sa) {
		$foundsa++ if (&indexof($rhost, split(/\s+/, $s)) >= 0);
		}
	push(@sa, $rhost) if (!$foundsa);

	# Update Apache config
	&apache::save_directive("RewriteEngine", \@ron, $vconf, $conf);
	&apache::save_directive("RewriteCond", \@rcond, $vconf, $conf);
	&apache::save_directive("RewriteRule", \@rrule, $vconf, $conf);
	&apache::save_directive("ServerAlias", \@sa, $vconf, $conf);

	# Fix the Apache config for the domain so that the last RewriteCond
	# appears just before last RewriteRule. This is needed until Webmin
	# 1.430, as older versions always put same-named directives after
	# each other.
	local $lref = &read_file_lines($virt->{'file'});
	local ($lcond, $lrule);
	for(my $i=$virt->{'line'}; $i <= $virt->{'eline'}; $i++) {
		if ($lref->[$i] =~ /^RewriteCond\s/) { $lcond = $i; }
		if ($lref->[$i] =~ /^RewriteRule\s/) { $lrule = $i; }
		}
	if ($lcond && $lrule && @rcond > 1 && @rrule > 1) {
		splice(@$lref, $lrule, 0, $lref->[$lcond]);
		splice(@$lref, $lcond, 1);
		}

	# Write out config
	&flush_file_lines($virt->{'file'});
	undef(@apache::get_config_cache);
	&register_post_action(\&restart_apache);
	}
}

# remove_webmail_redirect_directives(&domain)
# Take out webmail and admin redirects from the Apache config
sub remove_webmail_redirect_directives
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_remove_web_webmail_redirect", $d);
	}

# Get directives we will be changing
&require_apache();
local $conf = &apache::get_config();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return 0 if (!$virt);
local @rcond = &apache::find_directive("RewriteCond", $vconf);
local @rrule = &apache::find_directive("RewriteRule", $vconf);
local @sa = &apache::find_directive("ServerAlias", $vconf);

# Filter out redirect rules
for(my $i=0; $i<@rcond; $i++) {
	if ($rcond[$i] =~ /^\%{HTTP_HOST}\s+=(webmail|admin)\.$d->{'dom'}/) {
		splice(@rcond, $i, 1);
		if ($rrule[$i] =~ /^\^\(\.\*\)\s+(http|https):/) {
			splice(@rrule, $i, 1);
			}
		$i--;
		}
	}
&apache::save_directive("RewriteCond", \@rcond, $vconf, $conf);
&apache::save_directive("RewriteRule", \@rrule, $vconf, $conf);

# Fix up the ServerAlias
local @newsa;
foreach my $s (@sa) {
	local @sav = split(/\s+/, $s);
	@sav = grep { $_ ne "webmail.$d->{'dom'}" &&
		      $_ ne "admin.$d->{'dom'}" } @sav;
	if (@sav) {
		push(@newsa, join(" ", @sav));
		}
	}
&apache::save_directive("ServerAlias", \@newsa, $vconf, $conf);

&flush_file_lines($virt->{'file'});
&register_post_action(\&restart_apache);
return 1;
}

# get_webmail_redirect_directives(&domain)
# Returns the list of hostnames if a domain has webmail redirects configured
sub get_webmail_redirect_directives
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
	return &plugin_call($p, "feature_get_web_webmail_redirect", $d);
	}

&require_apache();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return ( ) if (!$virt);
local @rcond = &apache::find_directive("RewriteCond", $vconf);
local @rv;
foreach my $r (@rcond) {
	if ($r =~ /^\%{HTTP_HOST}\s+=(\S+)/) {
		push(@rv, $1);
		}
	}
return @rv;
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
	undef(@apache::get_config_cache);
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
# Returns the directory under which suexec will run binaries, or undef 
# if unknown
sub get_suexec_document_root
{
local $suexec = &get_suexec_path();
return undef if (!$suexec);
local $out = &backquote_command("$suexec -V 2>&1 </dev/null");
if ($out =~ /AP_DOC_ROOT="([^"]+)"/ ||
    $out =~ /AP_DOC_ROOT=(\S+)/) {
	return $1;
	}
# Try new Debian-style suexec config files
local $user = &get_apache_user();
if ($out =~ /SUEXEC_CONFIG_DIR="([^"]+)"/ ||
    $out =~ /SUEXEC_CONFIG_DIR=(\S+)/) {
	foreach my $cf ("$1/$user", "$1/www-data") {
		if (open(SUEXECCF, $cf)) {
			my $basedir = <SUEXECCF>;
			close(SUEXECCF);
			$basedir =~ s/\r|\n//g;
			return $basedir if ($basedir);
			}
		}
	}
return undef;
} 

# check_suexec_install(&template)
# Returns an error message if suexec does not appear to be installed properly.
sub check_suexec_install
{
local ($tmpl) = @_;
&require_useradmin();

# Make sure suexec is actually installed
local $suexec = &get_suexec_path();
local $suhome = &get_suexec_document_root();
local $suerr;
if ($tmpl->{'web_suexec'} && !$suexec) {
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

# Make sure home base is under base directory, or template CGI directory is
if ($tmpl->{'web_suexec'} && $suhome &&
    !&same_file($suhome, $home_base) &&
    !&is_under_directory($suhome, $home_base) &&
    (!$cgibase || !&is_under_directory($suhome, $cgibase))) {
	return &text('check_ewebsuexechome',
		     "<tt>$home_base</tt>", "<tt>$suhome</tt>");
	}
return undef;
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
	if ($v->{'words'}->[0] eq $virt->{'words'}->[0]) {
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
# If domain files are in a directory, sort by filename as older Webmin's
# dont do this for us
if ($apache::config{'virt_file'} && -d $apache::config{'virt_file'} &&
    &get_webmin_version() < 1.490) {
	@rv = sort { $a->[0]->{'file'} cmp $b->[0]->{'file'} } @rv;
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
local ($d, $nvstar, $nvstar6, $port) = @_;
local $parent = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;
$port ||= $d->{'web_port'};
&require_apache();
local $vip = $d->{'name'} &&
	     $apache::httpd_modules{'core'} >= 1.312 &&
	     &is_shared_ip($d->{'ip'}) &&
	     $nvstar ? "*" : $d->{'ip'};
local @vips = ( "$vip:$port" );
if ($d->{'ip6'}) {
	local $vip6 = $d->{'name'} &&
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
	local $oldlogfile = &extract_writelogs_path($oldlog);
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

# modify_web_home_directory(&domain, &old-domain, &virt, &vconf, &apache-config)
# Updates all directives that refer to the old home directory, by modifying
# the Apache config files directly. Also updates PHP config files. Invalidates
# the Apache config cache.
sub modify_web_home_directory
{
local ($d, $oldd, $virt, $vconf, $conf) = @_;
local $lref = &read_file_lines($virt->{'file'});
for(my $i=$virt->{'line'}; $i<=$virt->{'eline'}; $i++) {
	$lref->[$i] =~ s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
	}
&flush_file_lines($virt->{'file'});
undef(@apache::get_config_cache);

# Fix all php.ini files that use old path
if (defined(&list_domain_php_inis) && &foreign_check("phpini")) {
	&foreign_require("phpini", "phpini-lib.pl");
	my $mode = &get_domain_php_mode($d);
	$mode = "cgi" if ($mode eq "mod_php");
	foreach my $ini (&list_domain_php_inis($d, $mode)) {
		&lock_file($ini->[1]);
		my $conf = &phpini::get_config($ini->[1]);
		my $fixed = 0;
		foreach my $c (@$conf) {
			if ($c->{'value'} =~ /\Q$oldd->{'home'}\E/) {
				$c->{'value'} =~
				    s/\Q$oldd->{'home'}\E/$d->{'home'}/g;
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
local $user = &apache::find_directive_struct("User", $vconf);
if ($user && ($user->{'words'}->[0] eq $oldd->{'user'} ||
	      $user->{'words'}->[0] eq '#'.$oldd->{'uid'})) {
	&apache::save_directive("User", [ '#'.$d->{'uid'} ],
				$vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}
}

# fix_mod_php_security([&domains], [find-only])
# Goes through all virtual servers in non-mod_php mode, and adds the 
# php_admin_value directive to forcibly disable mod_php if missing
sub fix_mod_php_security
{
local ($doms, $findonly) = @_;
$doms ||= [ &list_domains() ];
local @flush;
&require_apache();
local @fixdoms;
local @lockdoms;
if (!$apache::httpd_modules{'mod_php4'} &&
    !$apache::httpd_modules{'mod_php5'}) {
	# mod_php not even enabled, so do nothing
	return ( );
	}
foreach my $d (@$doms) {
	next if (!$d->{'web'} || $d->{'alias'});
	my $mode = &get_domain_php_mode($d);
	if ($mode eq "cgi" || $mode eq "fcgid") {
		local @ports = ( $d->{'web_port'},
				 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
		local $domfixed;
		if (!$findonly) {
			&obtain_lock_web($d);
			&obtain_lock_ssl($d) if ($d->{'ssl'});
			push(@lockdoms, $d);
			}
		foreach my $p (@ports) {
			local ($virt, $vconf, $conf) = &get_apache_virtual(
				$d->{'dom'}, $p);
			next if (!$virt);
			local @admin = &apache::find_directive(
					"php_admin_value", $vconf);
			local ($engine) = grep { /engine\s+Off/i } @admin;
			if (!$engine) {
				push(@admin, "engine Off");
				&apache::save_directive(
					"php_admin_value", \@admin,
					$vconf, $conf);
				push(@flush, $virt->{'file'});
				$domfixed++;
				}
			}
		push(@fixdoms, $d) if ($domfixed);
		}
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
					push(@allow, "All ".$olist);
					$ofixed++;
					}
				elsif ($allow[0] !~ /$olist/) {
					$allow[0] .= " ".$olist;
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
	}
foreach my $dir (&apache::find_directive_struct("Directory", $pconf)) {
	$changed += &fix_options_directives($dir->{'members'}, $conf);
	}
return $changed;
}

$done_feature_script{'web'} = 1;

1;

