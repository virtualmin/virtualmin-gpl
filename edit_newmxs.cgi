#!/usr/local/bin/perl
# Show a form for selecting Webmin servers to use as secondary MXs for mail

require './virtual-server-lib.pl';
&foreign_require("servers");
&can_edit_templates() || &error($text{'newmxs_ecannot'});
&ui_print_header(undef, $text{'newmxs_title'}, "", "newmxs");

# Make the table data
@servers = grep { $_->{'user'} } &servers::list_servers();
%mxs = map { $_->{'id'}, $_ } &list_mx_servers();
foreach $s (sort { $a->{'host'} cmp $b->{'host'} } @servers) {
	$mx = $mxs{$s->{'id'}};
	push(@table, [
	  { 'type' => 'checkbox', 'name' => 'servers',
	    'value' => $s->{'id'}, 'checked' => $mx },
	  $s->{'desc'} ? $s->{'host'}." (".$s->{'desc'}.")"
		       : $s->{'host'},
	  &ui_opt_textbox("mxname_".$s->{'id'},
			  $mx ? $mx->{'mxname'} : undef, 30,
			  $text{'newmxs_same'}),
	  ]);
	}

# Render the table
print &ui_form_columns_table(
	"save_newmxs.cgi",
	[ [ "save", $text{'save'} ],
	  [ "addexisting", $text{'newmxs_saveadd'} ] ],
	0,
	undef,
	undef,
	[ "", $text{'newmxs_server'}, $text{'newmxs_mxname'} ],
	100,
	\@table,
	undef,
	1,
	undef,
	&foreign_available("servers") ?
		&text('newmxs_none2', "../servers/") :
		$text{'newmxs_none'},
	);

&ui_print_footer("", $text{'index_return'});

