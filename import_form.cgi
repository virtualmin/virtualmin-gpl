#!/usr/local/bin/perl
# import_form.cgi
# Display a form for importing an existing mail domain, dns zone, apache
# virtual host and mysql database so that they can be controlled by this module.

require './virtual-server-lib.pl';
&can_import_servers() || &error($text{'import_ecannot'});

&ui_print_header(undef, $text{'import_title'}, "");

print "$text{'import_desc1'}<p>\n";
print "$text{'import_desc2'}<p>\n";
print "$text{'import_desc3'}<p>\n";

# Script to disable some inputs when in parent mode
print <<EOF;
<script>
function pchange(form)
{
dis = form.parent_def[1].checked;
form.user.disabled = dis;
form.user_def[0].disabled = dis;
form.user_def[1].disabled = dis;
form.group.disabled = dis;
form.group_def[0].disabled = dis;
form.group_def[1].disabled = dis;
form.pass.disabled = dis;
form.webmin[0].disabled = dis;
form.webmin[1].disabled = dis;
form.quota.disabled = dis;
form.quota_units.disabled = dis;
}
</script>
EOF
$onch = "onChange='pchange(form)'";

print &ui_form_start("import.cgi", "post");
print &ui_table_start($text{'import_header'}, "width=100%", 4);

# Domain name
print &ui_table_row($text{'import_dom'},
		    &ui_textbox("dom", undef, 40), 3);

# Parent virtual server
@doms = sort { $a->{'user'} cmp $b->{'user'} }
	     grep { $_->{'unix'} } &list_domains();
if (@doms) {
	print &ui_table_row($text{'migrate_parent'},
			    &ui_radio("parent_def", 1,
			      [ [ 1, $text{'migrate_parent1'}, $onch ],
				[ 0, $text{'migrate_parent0'}, $onch ] ])."\n".
			    &ui_select("parent", undef,
				       [ map { [ $_->{'user'} ] } @doms ]), 3);
	}
else {
	print &ui_hidden("parent_def", 1);
	}

print &ui_table_row($text{'import_user'},
    &ui_radio("user_def", 0, [ [ 1, $text{'import_ucr'} ],
			       [ 0, $text{'import_uex'} ] ])."\n".
    &unix_user_input("user"), 3);

# New or existing group
print &ui_table_row($text{'import_group'},
    &ui_radio("group_def", 0, [ [ 1, $text{'import_gdf'} ],
			       [ 0, $text{'import_gex'} ] ])."\n".
    &unix_group_input("group"), 3);

# Pattern for mailbox users
print &ui_table_row($text{'import_regexp'},
	    &ui_opt_textbox("regexp", undef, 20, $text{'import_regexpg'},
						 $text{'import_regexpr'}));

# Home directory
print &ui_table_row($text{'import_home'},
    &ui_opt_textbox("home", undef, 40, $text{'import_auto'}), 3);

# Domain prefix
print &ui_table_row($text{'migrate_prefix'},
	   &ui_opt_textbox("prefix", undef, 20, $text{'migrate_auto'}), 3);

# Password
print &ui_table_row($text{'import_pass'},
		    &ui_password("pass", undef, 20));

# Create Webmin user
print &ui_table_row($text{'import_webmin'},
		    &ui_yesno_radio("webmin", 1));

# IP address and virtual options
$defip = &get_default_ip();
print &ui_table_row($text{'import_ip'},
		    &ui_textbox("ip", $defip, 15));

print &ui_table_row($text{'import_hasvirt'},
		    &ui_yesno_radio("virt", 0));

if (&has_home_quotas()) {
	print &ui_table_row($text{'form_quota'},
		    &quota_input("quota", $config{'defquota'}, "home"), 3);
	}

if ($config{'mysql'}) {
	print &ui_table_row($text{'import_db_mysql'},
			    &ui_textbox("db_mysql", undef, 40), 3);
	}
if ($config{'postgres'}) {
	print &ui_table_row($text{'import_db_postgres'},
			    &ui_textbox("db_postgres", undef, 40), 3);
	}

print &ui_table_end();
print &ui_form_end([ [ "show", $text{'import_show'} ] ]);

&ui_print_footer("", $text{'index_return'});

