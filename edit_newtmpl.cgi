#!/usr/local/bin/perl
# Display all virtual server templates

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newtmpl_ecannot'});
&ui_print_header(undef, $text{'newtmpl_title'}, "");

# Build list of templates
@tmpls = &list_templates();
@doms = &list_domains();
foreach $t (@tmpls) {
	next if ($t->{'deleted'});

	# Find domains on the template
	my @tdoms = grep { $_->{'template'} eq $t->{'id'} } @doms;

	my @uses;
	foreach my $f ("parent", "sub", "alias") {
		if ($t->{"for_".$f}) {
			push(@uses, $text{'tmpl_for_'.$f});
			}
		}

	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $t->{'id'} },
		ui_link("edit_tmpl.cgi?id=$t->{'id'}",
			&html_escape($t->{'name'})) . (
				$t->{'id'} == &get_init_template(0) ||
		  		$t->{'id'} == &get_init_template(1) ?
				    &vui_inline_label('newtmpl_def', 1) : ""),
		join(", ", @uses),
		&ui_link("search.cgi?field=template&what=$t->{'id'}",
			 scalar(@tdoms)),
	        $t->{'created'} ? &make_date($t->{'created'}, 1)
				: "<i>$text{'newtmpl_init'}</i>" ]);
	$deletable++ if (!$t->{'standard'});
	}

# Show the table of templates
print &ui_form_columns_table(
	"delete_tmpls.cgi",
	[ $deletable ? ( [ "delete", $text{'newtmpl_delete'} ] ) : ( ),
	  [ 'default', $text{'newtmpl_setdef'} ],
	  [ 'defaultsub', $text{'newtmpl_setdefsub'} ],
	],
	0,
	[ [ "edit_tmpl.cgi?new=1&cp=1", $text{'newtmpl_add2'} ],
	  [ "edit_tmpl.cgi?new=1", $text{'newtmpl_add1'} ] ],
	undef,
	[ "",
	  $text{'newtmpl_name'},
	  $text{'newtmpl_useby'},
	  $text{'newtmpl_tdoms'},
	  $text{'newtmpl_created'} ],
	100,
	\@table);

&ui_print_footer("", $text{'index_return'});
