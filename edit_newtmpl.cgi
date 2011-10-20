#!/usr/local/bin/perl
# Display all virtual server templates

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newtmpl_ecannot'});
&ui_print_header(undef, $text{'newtmpl_title'}, "");

# Build list of templates
@tmpls = &list_templates();
foreach $t (@tmpls) {
	next if ($t->{'deleted'});
	local @fcs;
	foreach $w ('web', 'dns', 'ftp', 'logrotate', 'mail_on') {
		($sw = $w) =~ s/_on$//;
		push(@fcs, $t->{$w} eq "none" ? $text{'newtmpl_none'} :
			   $t->{$w} eq "" ? $text{'default'} :
			"<a href='edit_tmpl.cgi?id=$t->{'id'}&editmode=$sw'>".
			"$text{'newtmpl_cust'}</a>");
		}
	$scripts = &list_template_scripts($t);
	$smesg = $scripts eq "none" ? $text{'newtmpl_none'} :
		 @$scripts ? scalar(@$scripts) :
	         $t->{'default'} ? $text{'newtmpl_none'} :
			     $text{'default'};
	if ($virtualmin_pro) {
		push(@fcs, "<a href='edit_tmpl.cgi?id=$t->{'id'}&".
			   "editmode=scripts'>$smesg</a>");
		}
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $t->{'id'}, 'disabled' => $t->{'standard'} },
		"<a href='edit_tmpl.cgi?id=$t->{'id'}'>$t->{'name'}</a>",
		$t->{'skel'} eq "none" ? $text{'newtmpl_none'} :
		$t->{'skel'} eq "" ? $text{'default'} :
				     "<tt>$t->{'skel'}</tt>",
		@fcs,
	        $t->{'created'} ? &make_date($t->{'created'}, 1)
				: "<i>$text{'newtmpl_init'}</i>" ]);
	$deletable++ if (!$t->{'standard'});
	}

# Show the table of templates
print &ui_form_columns_table(
	"delete_tmpls.cgi",
	$deletable ? [ [ "delete", $text{'newtmpl_delete'} ] ] : [ ],
	0,
	[ [ "edit_tmpl.cgi?new=1&cp=1", $text{'newtmpl_add2'} ],
	  [ "edit_tmpl.cgi?new=1", $text{'newtmpl_add1'} ] ],
	undef,
	[ "", $text{'newtmpl_name'}, $text{'newtmpl_skel'},
	  $text{'newtmpl_web'}, $text{'newtmpl_dns'},
	  $text{'newtmpl_ftp'}, $text{'newtmpl_logrotate'},
	  $text{'newtmpl_mail'},
	  $virtualmin_pro ? ( $text{'newtmpl_scripts'} ) : ( ),
	  $text{'newtmpl_created'} ],
	100,
	\@table);

&ui_print_footer("", $text{'index_return'});
