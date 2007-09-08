#!/usr/local/bin/perl
# Migrate some virtual server backup file
# XXX allow specification of parent when migrating/importing

require './virtual-server-lib.pl';
&can_migrate_servers() || &error($text{'migrate_ecannot'});
&error_setup($text{'migrate_err'});
&ReadParseMime();
&require_migration();

# Validate inputs
if ($in{'mode'} == 0) {
	$in{'upload'} || &error($text{'migrate_eupload'});
	$file = &transname();
	open(FILE, ">$file");
	print FILE $in{'upload'};
	close(FILE);
	}
else {
	-r $in{'file'} || &error($text{'migrate_efile'});
	$file = $in{'file'};
	}
$in{'dom'} =~ /^[a-z0-9\.\-\_]+$/i || &error($text{'migrate_edom'});
&get_domain_by("dom", $in{'dom'}) && &error($text{'migrate_eclash'});
if (!$in{'user_def'}) {
	$in{'user'} =~ /^[a-z0-9\.\-\_]+$/i || &error($text{'migrate_euser'});
	$user = $in{'user'};
	defined(getpwnam($in{'user'})) && &error($text{'migrate_euserclash'});
	}
if (!$in{'pass_def'}) {
	$pass = $in{'pass'};
	}
$tmpl = &get_template($in{'template'});
if (!$in{'parent_def'}) {
	$parent = &get_domain_by("user", $in{'parent'}, "parent", "");
	}
($ip, $virt, $virtalready) = &parse_virtual_ip($tmpl,
			$parent ? $parent->{'reseller'} :
			&reseller_admin() ? $base_remote_user : undef);
if (!$in{'prefix_def'}) {
	$in{'prefix'} =~ /^[a-z0-9\.\-]+$/i ||
		&error($text{'setup_eprefix'});
	$prefix = $in{'prefix'};
	}
$in{'email_def'} || $in{'email'} =~ /\S/ || &error($text{'setup_eemail'});

# Validate the file
$vfunc = "migration_$in{'type'}_validate";
$err = &$vfunc($file, $in{'dom'}, $user, $parent, $prefix, $pass);
&error($err) if ($err);

&ui_print_header(undef, $text{'migrate_title'}, "");

# Call the migration function
&lock_domain_name($in{'dom'});
&$first_print($in{'mode'} == 0 ?
		&text('migrate_doing0', "<tt>$in{'dom'}</tt>") :
		&text('migrate_doing1', "<tt>$in{'dom'}</tt>",
		      "<tt>$in{'file'}</tt>"));
&$indent_print();
$mfunc = "migration_$in{'type'}_migrate";
@doms = &$mfunc($file, $in{'dom'}, $user, $in{'webmin'}, $in{'template'},
		$ip, $virt, $pass, $parent, $prefix,
		$virtalready, $in{'email_def'} ? undef : $in{'email'});
&run_post_actions();
&$outdent_print();
if (@doms) {
	$d = $doms[0];
	&$second_print(&text('migrate_ok', "edit_domain.cgi?dom=$d->{'id'}", scalar(@doms)));

	# Call any theme post command
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain(\%dom, 'create');
		}
	}
else {
	&$second_print(&text('migrate_failed'));
	}

&ui_print_footer("", $text{'index_return'});

