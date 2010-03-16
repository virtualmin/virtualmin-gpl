#!/usr/local/bin/perl
# Copy this domain's cert to Webmin or Usermin

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() && &can_webmin_cert() ||
	&error($text{'copycert_ecannot'});
$d->{'ssl_pass'} && &error($text{'copycert_epass'});

&ui_print_header(&domain_in($d), $text{'copycert_title'}, "");

# Copy to appropriate config dir
if ($in{'usermin'}) {
	&foreign_require("usermin");
	$dir = $usermin::config{'usermin_dir'};
	}
else {
	$dir = $config_directory;
	}
&$first_print(&text('copycert_webmindir', "<tt>$dir</tt>"));
$certfile = "$dir/$d->{'dom'}.cert";
&lock_file($certfile);
&copy_source_dest($d->{'ssl_cert'}, $certfile);
&unlock_file($certfile);
if ($d->{'ssl_key'}) {
	$keyfile = "$dir/$d->{'dom'}.key";
	&lock_file($keyfile);
	&copy_source_dest($d->{'ssl_key'}, $keyfile);
	&unlock_file($keyfile);
	}
if ($d->{'ssl_chain'}) {
	$chainfile = "$dir/$d->{'dom'}.chain";
	&lock_file($chainfile);
	&copy_source_dest($d->{'ssl_chain'}, $chainfile);
	&unlock_file($chainfile);
	}
&$second_print($text{'setup_done'});

if ($in{'usermin'}) {
	# Configure Usermin to use it
	&$first_print($text{'copycert_userminconfig'});
	&lock_file($usermin::usermin_miniserv_config);
	&usermin::get_usermin_miniserv_config(\%miniserv);
	$miniserv{'certfile'} = $certfile;
	$miniserv{'keyfile'} = $keyfile;
	$miniserv{'extracas'} = $chainfile;
	&usermin::put_usermin_miniserv_config(\%miniserv);
	&unlock_file($usermin::usermin_miniserv_config);
	&usermin::restart_usermin_miniserv();
	&$second_print($text{'setup_done'});

	# Tell the user if not in SSL mode
	if (!$miniserv{'ssl'}) {
		&$second_print(&text('copycert_userminnot',
				     "../usermin/edit_ssl.cgi"));
		}
	}
else {
	# Configure Webmin to use it
	&$first_print($text{'copycert_webminconfig'});
	&lock_file($ENV{'MINISERV_CONFIG'});
	&get_miniserv_config(\%miniserv);
	$miniserv{'certfile'} = $certfile;
	$miniserv{'keyfile'} = $keyfile;
	$miniserv{'extracas'} = $chainfile;
	&put_miniserv_config(\%miniserv);
	&unlock_file($ENV{'MINISERV_CONFIG'});
	&restart_miniserv();
	&$second_print($text{'setup_done'});

	# Tell the user if not in SSL mode
	if (!$miniserv{'ssl'}) {
		&$second_print(&text('copycert_webminnot',
				     "../webmin/edit_ssl.cgi"));
		}
	}

&webmin_log("copycert", $in{'usermin'} ? "usermin" : "webmin");

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

