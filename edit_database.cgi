#!/usr/local/bin/perl
# Show one DB

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});
$tmpl = &get_template($d->{'template'});

if ($in{'new'}) {
	&ui_print_header(&domain_in($d), $text{'database_title1'}, "");
	}
else {
	&ui_print_header(&domain_in($d), $text{'database_title2'}, "");
	}

print &ui_form_start("save_database.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
if (!$in{'new'}) {
	print &ui_hidden("name", $in{'name'}),"\n";
	print &ui_hidden("type", $in{'type'}),"\n";
	}
else {
	print &ui_hidden("new", 1),"\n";
	}
print &ui_table_start($text{'database_header'}, undef, 2, [ "width=30%" ]);

# Database name
if ($in{'new'} && $tmpl->{'mysql_suffix'} ne "none") {
	$prefix = &substitute_domain_template($tmpl->{'mysql_suffix'}, $d);
	$prefix =~ s/-/_/g;
	$prefix =~ s/\./_/g;
	}
print &ui_table_row($text{'database_name'},
    $in{'new'} ? $prefix.&ui_textbox("name", undef, 30) : "<tt>$in{'name'}</tt>");

# Database type
@types = ( );
push(@types, [ "mysql", $text{'databases_mysql'} ]) if ($d->{'mysql'});
push(@types, [ "postgres", $text{'databases_postgres'} ]) if ($d->{'postgres'});
foreach $p (@database_plugins) {
	push(@types, [ $p, &plugin_call($p, "database_name") ]) if ($d->{$p});
	}
print &ui_table_row($text{'database_type'},
    $in{'new'} ? &ui_select("type", $types[0]->[0], \@types) :
    &indexof($in{'type'}, @database_plugins) >= 0 ?
	&plugin_call($in{'type'}, "database_name") :
	       $text{'databases_'.$in{'type'}});

if (!$in{'new'}) {
	# Show database size and tables
	if (&indexof($in{'type'}, @database_plugins) >= 0) {
		($size, $tables) = &plugin_call($in{'type'}, "database_size",
						$d, $in{'name'});
		}
	else {
		$szfunc = $in{'type'}."_size";
		($size, $tables) = &$szfunc($d, $in{'name'});
		}
	if ($size ne "") {
		print &ui_table_row($text{'database_size'}, &nice_size($size));
		}
	if ($tables ne "") {
		print &ui_table_row($text{'database_tables'}, $tables);
		}
	}

# Type-specific creation options
foreach $t ('mysql', 'postgres') {
	$ofunc = "creation_form_$t";
	if ($in{'new'} && $d->{$t} && defined(&$ofunc)) {
		print &$ofunc($d);
		}
	}
foreach $p (@database_plugins) {
	if ($in{'new'} && $d->{$p} && &plugin_defined($p, "creation_form")) {
		print &plugin_call($p, "creation_form", $d);
		}
	}

print &ui_table_end();

if ($in{'new'}) {
	print &ui_form_end([ [ "create", $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ "delete", $text{'database_delete'} ],
	     &can_import_servers() ? ( [ "disc", $text{'database_disc'} ] )
			     : ( ) ]);
	}

&ui_print_footer("list_databases.cgi?dom=$in{'dom'}", $text{'databases_return'},
		 &domain_footer_link($d),
		 "", $text{'index_return'});
