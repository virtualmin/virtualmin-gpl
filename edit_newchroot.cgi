#!/usr/local/bin/perl
# Show a list of ProFTPd chroot directories

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'chroot_ecannot'});
&has_ftp_chroot() || &error($text{'chroot_esupport'});
&ui_print_header(undef, $text{'newchroot_title'}, "", "newchroot");

# Get list of all domain groups
@gsel = map { [ $_->{'group'}, &show_domain_name($_) ] }
	    grep { !$_->{'parent'} } &list_domains();
@gsel = &unique(@gsel);

print $text{'newchroot_desc'},"<p>\n";

@chroots = &list_ftp_chroots();
$i = 0;
@table = ( );
foreach $chroot (@chroots, { 'dir' => '~' }) {
	$d = $chroot->{'group'} && !$chroot->{'neg'} ?
		&get_domain_by("group", $chroot->{'group'}, "parent", "") :
		undef;
	$mode = $chroot->{'dir'} eq '/' ? 2 :
		$chroot->{'dir'} eq '~' ? 1 :
		$d && $chroot->{'dir'} eq $d->{'home'} ? 3 : 0;
	push(@table, [
		{ 'type' => 'checkbox', 'name' => "enabled_$i",
		  'value' => 1,
		  'checked' => &indexof($chroot, @chroots) >= 0 },
		&ui_radio("all_$i", $chroot->{'group'} ? 0 : 1,
		  [ [ 1, $text{'chroot_all'}."<br>" ],
		    [ 0, &text('chroot_gsel',
			     &ui_select("group_$i", $chroot->{'group'}, \@gsel,
					1, 0, $chroot->{'group'} ? 1 : 0),
			     &ui_checkbox("neg_$i", 1, " ", $chroot->{'neg'}))
		    ] ]),
		&ui_radio("mode_$i", $mode,
			  [ [ 2, $text{'chroot_root'}."<br>" ],
			    [ 1, $text{'chroot_home'}."<br>" ],
			    [ 3, $text{'chroot_dom'}."<br>" ],
			    [ 0, &text('chroot_path',
				   &ui_textbox("dir_$i",
					$mode ? "" : $chroot->{'dir'}, 40)) ] ]),
		]);
		
	$i++;
	}

# Output the table
print &ui_form_columns_table(
	"save_newchroot.cgi",
	[ [ undef, $text{'save'} ] ],
	0,
	undef,
	undef,
	[ $text{'chroot_active'}, $text{'chroot_who'}, $text{'chroot_dir'} ],
	100,
	\@table,
	undef,
	1,
	);

&ui_print_footer("", $text{'index_return'});
