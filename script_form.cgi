#!/usr/local/bin/perl
# Show options for installing some script

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'scripts_ierr'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
$d->{'web'} && $d->{'dir'} || &error($text{'scripts_eweb'});

if ($in{'upgrade'}) {
	# Upgrading
	@got = &list_domain_scripts($d);
	($sinfo) = grep { $_->{'id'} eq $in{'script'} } @got;
	$script = &get_script($sinfo->{'name'});
	$sname = $sinfo->{'name'};
	$ver = $in{'version'};
	&ui_print_header(&domain_in($d), $text{'scripts_uptitle'}, "");
	}
else {
	# Installing new
	$sname = $in{'script'};
	$sname || &error($text{'scripts_enosel'});
	$ver = $in{'ver_'.$sname};
	$script = &get_script($sname);
	$script->{'avail'} || &error($text{'scripts_eavail'});
	&can_script_version($script, $ver) || &error($text{'scripts_eavail'});
	&ui_print_header(&domain_in($d), $text{'scripts_intitle'}, "");
	}

# Check dependencies
$derr = &{$script->{'depends_func'}}($d, $ver);
$ok = 1;
if ($derr) {
	print &text('scripts_edep', $derr),"<p>\n";
	$ok = 0;
	}

# Check PHP version
$phpvfunc = $script->{'php_vers_func'};
if (defined(&$phpvfunc)) {
	@vers = &$phpvfunc($d, $ver);
	@gotvers = grep { local $_; &check_php_version($d, $_) } @vers;
	if (!@gotvers) {
		print &text('scripts_ephpvers', join(" ", @vers)),"\n";
		$ok = 0;
		}
	}

if ($ok) {
	# Show install options form
	print &ui_form_start("script_install.cgi", "post");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_hidden("script", $sname),"\n";
	print &ui_hidden("version", $ver),"\n";
	if ($in{'upgrade'}) {
		print &ui_hidden("upgrade", $in{'script'}),"\n";
		}
	print &ui_table_start($text{'scripts_iheader'}, undef, 2);

	# Show script description
	print &ui_table_row($text{'scripts_iname'}, $script->{'desc'});
	print &ui_table_row($text{'scripts_idesc'}, $script->{'longdesc'})
		if ($script->{'longdesc'});
	print &ui_table_row($text{'scripts_iversion'},
			    $script->{'vdesc'}->{$ver} || $ver);
	if ($sinfo) {
		print &ui_table_row($text{'scripts_upversion'},
				    $sinfo->{'version'});
		}

	# Show parameters
	$opts = &{$script->{'params_func'}}($d, $ver, $sinfo);
	print $opts;

	print &ui_table_end();
	print &ui_form_end([ [ "install", $text{'scripts_iok'} ] ]);
	}

&ui_print_footer("list_scripts.cgi?dom=$in{'dom'}", $text{'scripts_return'},
		 &domain_footer_link($d));

