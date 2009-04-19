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
&copy_source_dest($d->{'ssl_cert'}, $certfile);
if ($d->{'ssl_key'}) {
	$keyfile = "$dir/$d->{'dom'}.key";
	&copy_source_dest($d->{'ssl_key'}, $keyfile);
	}
if ($d->{'ssl_chain'}) {
	$chainfile = "$dir/$d->{'dom'}.chain";
	&copy_source_dest($d->{'ssl_chain'}, $chainfile);
	}
&$second_print($text{'setup_done'});

if ($in{'usermin'}) {
	# Configure Usermin to use it
	&$first_print($text{'copycert_userminconfig'});
	&usermin::get_usermin_miniserv_config(\%miniserv);
	$miniserv{'certfile'} = $certfile;
	$miniserv{'keyfile'} = $keyfile;
	$miniserv{'extracas'} = $chainfile;
	&usermin::put_usermin_miniserv_config(\%miniserv);
	&usermin::restart_miniserv();
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
	&get_miniserv_config(\%miniserv);
	$miniserv{'certfile'} = $certfile;
	$miniserv{'keyfile'} = $keyfile;
	$miniserv{'extracas'} = $chainfile;
	&put_miniserv_config(\%miniserv);
	&restart_miniserv();
	&$second_print($text{'setup_done'});

	# Tell the user if not in SSL mode
	if (!$miniserv{'ssl'}) {
		&$second_print(&text('copycert_webminnot',
				     "../webmin/edit_ssl.cgi"));
		}
	}

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

