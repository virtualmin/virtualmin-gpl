#!/usr/local/bin/perl
# Actually move a virtual server under a new owner

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'move_err'});
$d = &get_domain($in{'dom'});
&can_move_domain($d) || &error($text{'move_ecannot'});
$oldd = { %$d };

if ($in{'parent'}) {
	# Get the selected parent domain object
	$parent = &get_domain($in{'parent'});
	if ($d->{'parent'}) {
		$parent->{'id'} ==$d->{'parent'} && &error($text{'move_esame'});
		}
	else {
		$parent->{'id'} == $d->{'id'} && &error($text{'move_eparent'});
		}
	&can_config_domain($parent) || &error($text{'move_ecannot2'});
	}
else {
	# Turning into a parent domain - check the username for clashes
	$in{'newuser'} =~ /^[^\t :]+$/ || &error($text{'setup_euser2'});
	$newd = { %$d };
	$newd->{'user'} = $in{'newuser'};
	$newd->{'group'} = $in{'newuser'};
	$derr = &virtual_server_clashes($newd, undef, 'user') ||
		&virtual_server_clashes($newd, undef, 'group');
	&error($derr) if ($derr);
	}

&ui_print_unbuffered_header(&domain_in($d), $text{'move_title'}, "");
if ($parent) {
	print "<b>",&text('move_doing', "<tt>$d->{'dom'}</tt>",
			  "<tt>$parent->{'dom'}</tt>"),"</b><p>\n";
	}
else {
	print "<b>",&text('move_doing2', "<tt>$d->{'dom'}</tt>"),"</b><p>\n";
	}

# Do the move
if ($in{'parent'}) {
	$ok = &move_virtual_server($d, $parent);
	}
else {
	$ok = &reparent_virtual_server($d, $in{'newuser'}, $in{'newpass'});
	}
if ($ok) {
	print "<b>$text{'setup_ok'}</b><p>\n";
	}
else {
	print "<b>$text{'move_failed'}</b><p>\n";
	}

&webmin_log("move", "domain", $d->{'dom'}, $d);

# Call any theme post command
if (defined(&theme_post_save_domain)) {
        &theme_post_save_domain($d, 'modify');
        }

&ui_print_footer(&domain_footer_link($d),
        "", $text{'index_return'});


