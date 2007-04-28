#!/usr/local/bin/perl
# Display all virtual server templates

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newtmpl_ecannot'});
&ui_print_header(undef, $text{'newtmpl_title'}, "");

# Show list of templates
@tmpls = &list_templates();
print &ui_form_start("delete_tmpls.cgi");
@clinks = ( "<a href='edit_tmpl.cgi?new=1&cp=1'>$text{'newtmpl_add2'}</a>",
	    "<a href='edit_tmpl.cgi?new=1'>$text{'newtmpl_add1'}</a>" );
print &ui_links_row(\@clinks);
@tds = ( "width=5" );
print &ui_columns_start([ "",
			  $text{'newtmpl_name'},
			  $text{'newtmpl_skel'},
			  $text{'newtmpl_web'},
			  $text{'newtmpl_dns'},
			  $text{'newtmpl_ftp'},
			  $text{'newtmpl_logrotate'},
			  $text{'newtmpl_mail'},
			  $virtualmin_pro ? ( $text{'newtmpl_scripts'} )
					  : ( ), ]);
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
	local @cols = (
		"<a href='edit_tmpl.cgi?id=$t->{'id'}'>$t->{'name'}</a>",
		$t->{'skel'} eq "none" ? $text{'newtmpl_none'} :
		$t->{'skel'} eq "" ? $text{'default'} :
				     "<tt>$t->{'skel'}</tt>",
		@fcs );
	if ($t->{'standard'}) {
		print &ui_columns_row([ &ui_checkbox("d", $t->{'id'}, "", 0,
						     undef, 1), @cols ], \@tds);
		}
	else {
		print &ui_checked_columns_row(\@cols, \@tds, "d", $t->{'id'});
		$deletable++;
		}
	}
print &ui_columns_end();
print &ui_links_row(\@clinks);
print &ui_form_end($deletable ? [ [ "delete", $text{'newtmpl_delete'} ] ] : []);

&ui_print_footer("", $text{'index_return'});
