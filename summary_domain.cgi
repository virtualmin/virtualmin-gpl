#!/usr/local/bin/perl
# Quickly show overview information about a domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
if ($d->{'parent'}) {
	$parentdom = &get_domain($d->{'parent'});
	}
if ($d->{'alias'}) {
	$aliasdom = &get_domain($d->{'alias'});
	}
if ($d->{'subdom'}) {
	$subdom = &get_domain($d->{'subdom'});
	}
$tmpl = &get_template($d->{'template'});

&ui_print_header(&domain_in($d), $aliasdom ?  $text{'summary_title3'} :
                                 $subdom ?    $text{'summary_title4'} :
                                 $parentdom ? $text{'summary_title2'} :
                                              $text{'summary_title'}, "");

print &ui_table_start($text{'edit_header'}, "width=100%", 4);

# Domain name (with link), user and group
if (&domain_has_website($d)) {
	my $url = &get_domain_url($d, 1);
	print &ui_table_row($text{'edit_domain'},
	    "<tt>".&ui_link($url, $d->{'dom'}, undef, "target=_blank")."</tt>");
	}
else {
	print &ui_table_row($text{'edit_domain'},
			    "<tt>$d->{'dom'}</tt>");
	}

# Creator
print &ui_table_row($text{'edit_created'},
	$d->{'creator'} ? &text('edit_createdby', &make_date($d->{'created'},1),
						  $d->{'creator'})
			: &make_date($d->{'created'}));

# Last login
if ($config{'show_domains_lastlogin'}) {
	print &ui_table_row($text{'users_ll'},
		&human_readable_time($d->{'last_login_timestamp'}) ||
		$text{'users_ll_never'});
	}

# Owner
my $owner = "<tt title='$d->{'user'} ($d->{'uid'})'>$d->{'user'}</tt>";
if (&can_edit_domain($d) && &can_rename_domains()) {
	$owner = "<a href='rename_form.cgi?dom=$d->{'id'}'>$owner</a>"
	}
print &ui_table_row($text{'edit_user'}, $owner);
if (!$d->{'parent'}) {
	my $gr = $d->{'unix'} &&
	          $d->{'group'} ? "<tt title='$d->{'group'} ($d->{'gid'})'>$d->{'group'}</tt>" : $text{'edit_nogroup'};
	if (&can_edit_domain($d) && &can_rename_domains()) {
		$gr = "<a href='rename_form.cgi?dom=$d->{'id'}'>$gr</a>"
		}
	print &ui_table_row($text{'edit_group'}, $gr);
	}

# Show user and group quotas
if (&has_home_quotas() && !$parentdom) {
	my $uq = $d->{'quota'} ? &quota_show($d->{'quota'}, "home")
			  : $text{'form_unlimit'};
	if (&can_config_domain($d)) {
		$uq = "<a href='edit_domain.cgi?dom=$d->{'id'}'>$uq</a>"
		}
	print &ui_table_row($text{'edit_quota'}, $uq);

	my $uuq = $d->{'uquota'} ? &quota_show($d->{'uquota'}, "home")
			   : $text{'form_unlimit'};
	if (&can_config_domain($d)) {
		$uuq = "<a href='edit_domain.cgi?dom=$d->{'id'}'>$uuq</a>"
		}
	print &ui_table_row($text{'edit_uquota'}, $uuq);
	}


# IP-related options
if (!$aliasdom) {
	if (defined(&get_reseller)) {
		foreach $r (split(/\s+/, $d->{'reseller'})) {
			$resel = &get_reseller($r);
			if ($resel && $resel->{'acl'}->{'defip'}) {
				$reselip = $resel->{'acl'}->{'defip'};
				$reselip6 = $resel->{'acl'}->{'defip6'};
				}
			}
		}
	my $ip = "<tt>$d->{'ip'}</tt>";
	if (&can_change_ip($d) && &can_edit_domain($d)) {
		$ip = "<a href='newip_form.cgi?dom=$d->{'id'}'>$ip</a>"
		}
	print &ui_table_row($text{'edit_ip'},
		   "$ip ".($d->{'virt'} ? $text{'edit_private'} :
		   $d->{'ip'} eq $reselip ? &text('edit_rshared',
						  "<tt>$resel->{'name'}</tt>") :
					    $text{'edit_shared'}));
	}
if ($d->{'ip6'} && !$aliasdom) {
	my $ipv6 = "<tt>$d->{'ip6'}</tt>";
	if (&can_change_ip($d) && &can_edit_domain($d)) {
		$ipv6 = "<a href='newip_form.cgi?dom=$d->{'id'}'>$ipv6</a>"
		}
	print &ui_table_row($text{'edit_ip6'},
		"$ipv6 ".($d->{'virt6'} ? $text{'edit_private'} :
		 $d->{'ip6'} eq $reselip6 ? &text('edit_rshared',
						  "<tt>$resel->{'name'}</tt>") :
			       		    $text{'edit_shared'}));
	}

# Plan, if any
if (!$parentdom && $d->{'plan'} ne '') {
	my $plan = &get_plan($d->{'plan'});
	my $plan_name = $plan->{'name'};
	if (&can_config_domain($d)) {
		$plan_name = "<a href='edit_domain.cgi?dom=$d->{'id'}'>$plan_name</a>"
		}
	print &ui_table_row($text{'edit_plan'}, $plan_name);
	}

if ($aliasdom) {
	# Alias destination
	print &ui_table_row($text{'edit_aliasto'},
	   "<a href='view_domain.cgi?dom=$d->{'alias'}'>".
	    &show_domain_name($aliasdom)."</a>");
	}
elsif (!$parentdom) {
	# Contact email address
	my $domemail = &html_escape($d->{'emailto'});
	if (&can_config_domain($d)) {
		$domemail = "<a href='edit_domain.cgi?dom=$d->{'id'}'>$domemail</a>"
		}
	print &ui_table_row($text{'edit_email'}, $domemail);
	}
else {
	# Show link to parent domain
	print &ui_table_row($text{'edit_parent'},
	    "<a href='view_domain.cgi?dom=$d->{'parent'}'>".
	     &show_domain_name($parentdom)."</a>");
	}

# PHP mode and version
my $showphp = !$aliasdom && &domain_has_website($d);
if ($showphp) {
	my $phpmode = &get_domain_php_mode($d);
	if ($phpmode && $phpmode ne "none") {
		my ($phpdir) = &list_domain_php_directories($d);
		my $phpver = $phpdir->{'version'};
		$phpmode = $text{"phpmode_$phpmode"};
		my $phpinfo = &text('summary_phpvermode', $phpver, $phpmode);
		if (&can_edit_phpmode($d) && &can_edit_phpver($d)) {
			$phpinfo = "<a href='edit_phpmode.cgi?dom=$d->{'id'}'>$phpinfo</a>"
			}
		print &ui_table_row($text{'scripts_iphpver'}, $phpinfo.
			&get_php_info_link($d->{'id'}, 'label'));
		}
	}

# Home directory
if ((!$aliasdom && $d->{'dir'}) ||
    ($aliasdom && -d $d->{'home'})) {
	my $domhome = "<tt>$d->{'home'}</tt>";
	if (&domain_has_website($d) && $d->{'dir'} &&
          !$d->{'proxy_pass_mode'} && &foreign_available("filemin")) {
		my $ophd;
		my $phd = $ophd = &public_html_dir($d);
		my $hd = $d->{'home'};
		my %faccess = &get_module_acl(undef, 'filemin');
		my @ap = split(/\s+/, $faccess{'allowed_paths'});
		if (@ap == 1) {
			if ($ap[0] eq '$HOME' &&
			    $base_remote_user eq $d->{'user'}) {
				$ap[0] = $d->{'home'};
				}
			$phd =~ s/^\Q$ap[0]\E//;
			$hd =~ s/^\Q$ap[0]\E//;
			$hd = '/' if (!$hd);
			}
		my $dompath = -d $ophd ? &urlize($phd) : &urlize($hd);
		$domhome = "<a href=\"@{[&get_webprefix_safe()]}/filemin/index".
				".cgi?path=$dompath\">$domhome</a>";
		}
	print &ui_table_row($text{'edit_home'}, $domhome, 3);
	}

# Description
if ($d->{'owner'}) {
	my $owner = &html_escape($d->{'owner'});
	if (&can_config_domain($d)) {
		$owner = &ui_link("edit_domain.cgi?dom=$d->{'id'}", $owner);
		}
	print &ui_table_row($text{'edit_owner'}, $owner, 3);
	}

# Show domain ID
if (&master_admin()) {
	my $domid = "<tt>$d->{'id'}</tt>";
	if (&foreign_available('filemin')) {
		my $efile = &urlize("$domains_dir/$d->{'id'}");
		my $qfile = &quote_escape("$domains_dir/$d->{'id'}");
		$domid = "<a data-dom-file=\"$qfile\" href=\"@{[&get_webprefix_safe()]}/filemin/edit_file.cgi?file=$efile\">$domid</a>";
		}
	print &ui_table_row($text{'edit_id'}, $domid);
	my $now = time();

	# Show SSL cert expiry date and add color based on time
	if ($exptime = &get_ssl_cert_expiry($d)) {
		my $exp = &make_date($exptime);
		if ($now > $exptime) {
			$exp = &ui_text_color($exp, 'danger');
			}
		elsif ($now > $exptime - 7*24*60*60) {
			$exp = &ui_text_color($exp, 'warn');
			}
		if (&can_edit_domain($d) && &can_edit_ssl()) {
			$exp = "<a class=\"no-color\" href='cert_form.cgi?dom=$d->{'id'}'>$exp</a>"
			}
		print &ui_table_row($text{'edit_ssl_exp'}, $exp);
		}

	# Show domain registration expiry date and add color based on time
	if ($d->{'whois_expiry'}) {
		my $exp = &make_date($d->{'whois_expiry'});
		if ($now > $d->{'whois_expiry'}) {
			$exp = &ui_text_color($exp, 'danger');
			}
		elsif ($now > $d->{'whois_expiry'} - 7*24*60*60) {
			$exp = &ui_text_color($exp, 'warn');
			}
		print &ui_table_row($text{'edit_whois_exp'}, $exp);
		}
	}

# Domain auto disable state
if ($d->{'disabled_auto'}) {
	print &ui_table_row($text{'disable_autodisable2'},
		&make_date($d->{'disabled_auto'}));
	}

print &ui_table_end();

# Make sure the left menu is showing this domain
if (defined(&theme_select_domain)) {
	&theme_select_domain($d);
	}

&ui_print_footer("", $text{'index_return'});

