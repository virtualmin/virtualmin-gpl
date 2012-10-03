#!/usr/local/bin/perl
# DUplicate a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'clone_err'});
$d = &get_domain($in{'dom'});
$oldd = { %$d };

# Check limits
if ($d->{'parent'} && !&can_create_sub_servers() ||
    !$d->{'parent'} && !&can_create_master_servers()) {
	&error($text{'clone_ecannot'});
	}
($dleft, $dreason, $dmax) = &count_domains($d->{'alias'} ? "aliasdoms"
							 : "realdoms");
&error(&text('setup_emax', $dmax)) if ($dleft == 0);

# Validate inputs
$in{'newdomain'} = lc(&parse_domain_name($in{'newdomain'}));
$err = &valid_domain_name($in{'newdomain'});
&error($err) if ($err);
$clash = &get_domain_by("dom", $in{'newdomain'});
$clash && &error($text{'clone_eclash'});
if (!$d->{'parent'}) {
	$in{'newuser'} =~ /^[^\t :]+$/ || &error($text{'setup_euser2'});
	$in{'newpass_def'} || $in{'newpass'} || &error($text{'clone_epass'});
	$clash = &get_domain_by("user", $in{'newuser'});
	$clash && &error($text{'clone_eclash2'});
	}

# Check for allowed domain name
$parent = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;
$derr = &allowed_domain_name($parent, $in{'newdomain'});
&error($derr) if ($derr);

# Validate IP address
if ($d->{'virt'} && &can_select_ip() && !$in{'ip_def'}) {
	$ip = $in{'ip'};
	$virtalready = $in{'virtalready'};
	&check_ipaddress($ip) || &error($text{'setup_eip'});
	$clash = &check_virt_clash($ip);
	if ($virtalready) {
		# Fail if the IP isn't yet active, or if claimed by another
		# virtual server
                $clash || &error(&text('setup_evirtclash2', $ip));
		$already = &get_domain_by("ip", $ip);
		$already && &error(&text('setup_evirtclash4',
                                         $already->{'dom'}));
		}
	else {
		# Fail if the IP *is* already activ
		$clash && &error(&text('setup_evirtclash'));
		}
	}

&ui_print_unbuffered_header(&domain_in($d), $text{'clone_title'}, "");

if ($d->{'parent'}) {
	&$first_print(&text('clone_doing',
			    $d->{'dom'}, $in{'newdomain'}));
	}
else {
	&$first_print(&text('clone_doing2',
			    $d->{'dom'}, $in{'newdomain'}, $in{'newuser'}));
	}
$ok = &clone_virtual_server($d, $in{'newdomain'}, $in{'newuser'},
			    $in{'newpass_def'} ? undef : $in{'newpass'},
			    $ip, $virtalready);
if ($ok) {
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'clone_failed'});
	}

# Refresh Webmin user
&refresh_webmin_user($d, 1);

&run_post_actions();
&webmin_log("clone", "domain", $d->{'dom'}, $d);

# Call any theme post command
$clone = &get_domain_by("dom", $in{'newdomain'});
if (defined(&theme_post_save_domain) && $clone) {
	&theme_post_save_domain($clone, 'create');
	}

&ui_print_footer(&domain_footer_link($d),
        	 "", $text{'index_return'});


