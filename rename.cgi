#!/usr/local/bin/perl
# rename.cgi
# Actually rename a server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'rename_err'});
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_rename_domains() || &error($text{'rename_ecannot'});
%oldd = %$d;

# Validate inputs, starting with domain name
$dom = lc(&parse_domain_name($in{'new'}));
$err = &valid_domain_name($dom);
&error($err) if ($err);
$newdom = $dom ne $d->{'dom'} ? 1 : 0;

# User name
if (!$d->{'parent'} && &can_rename_domains() == 2 &&
    ($in{'user_mode'} == 2 || $newdom)) {
	if ($in{'user_mode'} == 1) {
		$user = 'auto';
		}
	elsif ($in{'user_mode'} == 2) {
		$in{'user'} || &error($text{'rename_euser'});
		$user = $in{'user'};
		}
	}

# Mailbox user prefix
if ($in{'prefix_mode'} == 0) {
	# Don't change
	$prefix = undef;
	}
elsif ($in{'prefix_mode'} == 1) {
	# Automatically compute
	$prefix = 'auto';
	}
elsif ($in{'prefix_mode'} == 2) {
	# Entered value
	$in{'prefix'} =~ /^[a-z0-9\.\-]+$/i || &error($text{'setup_eprefix'});
	$prefix = $in{'prefix'};
	}

if ($in{'home_mode'} == 1) {
	# Automatic home
	&can_rehome_domains() || &error($text{'rename_ehome'});
	$home = 'auto';
	}
elsif ($in{'home_mode'} == 2) {
	# User-selected home
	&can_rehome_domains() == 2 || &error($text{'rename_ehome'});
	$in{'home'} || &error($text{'rename_ehome2'});
	$home = $in{'home'};
	}

&ui_print_unbuffered_header(&domain_in(\%oldd), $text{'rename_title'}, "");

# Do the rename
$err = &rename_virtual_server($d, $dom, $user, $home, $prefix);
&error($err) if ($err);

&webmin_log("rename", "domain", $oldd{'dom'}, $d);

# Call any theme post command
if (defined(&theme_post_save_domain)) {
	&theme_post_save_domain($d, 'modify');
	}

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});
