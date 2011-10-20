#!/usr/local/bin/perl
# Show a form for creating or editing one extra admin

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_admins($d) || &error($text{'admins_ecannot'});

if ($in{'new'}) {
	&ui_print_header(&domain_in($d), $text{'admin_title1'}, "");
	$admin = { 'norename' => 1 };
	}
else {
	&ui_print_header(&domain_in($d), $text{'admin_title2'}, "");
	@admins = &list_extra_admins($d);
	($admin) = grep { $_->{'name'} eq $in{'name'} } @admins;
	$admin || &error($text{'admin_egone'});
	}
$tmpl = &get_template($d->{'template'});

print &ui_form_start("save_admin.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_hidden("new", $in{'new'}),"\n";
print &ui_hidden("old", $in{'name'}),"\n";
print &ui_hidden_table_start($text{'admin_header'}, "width=100%", 2, "main", 1);

# Show general user information
if ($tmpl->{'extra_prefix'} ne "none") {
	$pfx = &substitute_domain_template($tmpl->{'extra_prefix'}, $d);
	if ($in{'new'} || $admin->{'name'} =~ /^\Q$pfx\E(.*)/) {
		# Show input for suffix only
		print &ui_table_row(&hlink($text{'admin_name'}, "admin_name"),
				    $pfx.&ui_textbox("name", $1, 20), 2);
		}
	elsif (&master_admin()) {
		# A prefix is set but the user doesn't match .. allow editing
		# of the whole name
		print &ui_table_row(&hlink($text{'admin_name'}, "admin_name"),
			    &ui_textbox("name", $admin->{'name'}, 20), 2);
		}
	else {
		# A prefix is set but the user doesn't match it! Don't allow
		# editing of the name
		print &ui_table_row(&hlink($text{'admin_name'}, "admin_name"),
				    "<tt>$admin->{'name'}</tt>");
		print &ui_hidden("name", $admin->{'name'}),"\n";
		}
	}
else {
	# Username can be anything
	print &ui_table_row(&hlink($text{'admin_name'}, "admin_name"),
			    &ui_textbox("name", $admin->{'name'}, 20), 2);
	}

# Password
print &ui_table_row(&hlink($text{'admin_pass'}, "admin_pass"),
    $in{'new'} ? &ui_textbox("pass", undef, 20)
	       : &ui_opt_textbox("pass", undef, 20, $text{'resel_leave'}), 2);

# Description
print &ui_table_row(&hlink($text{'admin_desc'}, "admin_desc"),
		    &ui_textbox("desc", $admin->{'desc'}, 40), 2);

# Contact email address
print &ui_table_row(&hlink($text{'admin_email'}, "admin_email"),
		    &ui_opt_textbox("email", $admin->{'email'}, 40,
				    $text{'admin_none'}), 2);

print &ui_hidden_table_end();
print &ui_hidden_table_start($text{'admin_header2'}, "width=100%", 2, "can", 1);

# Can edit
print &ui_table_row(&hlink($text{'admin_create'}, "admin_create"),
		    &ui_yesno_radio("create", int($admin->{'create'})));

# Can rename domains
print &ui_table_row(&hlink($text{'limits_norename'}, "admin_norename"),
	&ui_radio("norename", $admin->{'norename'} ? 1 : 0,
	       [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));

# Can use feature modules
print &ui_table_row(&hlink($text{'admin_features'}, "admin_features"),
		    &ui_yesno_radio("features", int($admin->{'features'})));

# Can use other modules
print &ui_table_row(&hlink($text{'admin_modules'}, "admin_modules"),
		    &ui_yesno_radio("modules", int($admin->{'modules'})));

# Capabilities when editing a server
@grid = ( );
foreach $ed (@edit_limits) {
	push(@grid, &ui_checkbox("edit", $ed, $text{'limits_edit_'.$ed} || $ed,
				 $admin->{"edit_$ed"}, undef,
				 !$d->{'edit_'.$ed}));
	}
$etable .= &ui_grid_table(\@grid, 2);
print &ui_table_row(&hlink($text{'limits_edit'}, "admin_edit"), $etable);

print &ui_hidden_table_end();
print &ui_hidden_table_start($text{'admin_header3'}, "width=100%", 2, "dom", 0);

# Allowed domains
@doms = &get_domain_by("user", $d->{'user'});
@aids = split(/\s+/, $admin->{'doms'});
print &ui_table_row(&hlink($text{'admin_doms'}, "admin_doms"),
		    &ui_radio("doms_def", $admin->{'doms'} ? 0 : 1,
			      [ [ 1, $text{'admin_doms1'} ],
				[ 0, $text{'admin_doms0'} ] ])."<br>\n".
		    &servers_input("doms", \@aids, \@doms));

print &ui_hidden_table_end();
if ($in{'new'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ "save", $text{'save'} ],
			     [ "delete", $text{'delete'} ],
			     &can_switch_user($d, $admin->{'name'}) ?
			       ( [ "switch", $text{'admin_switch'} ] ) : ( ) ]);
	}

&ui_print_footer("list_admins.cgi?dom=$d->{'id'}", $text{'admins_return'},
		 "", $text{'index_return'});
