#!/usr/local/bin/perl
# rename_form.cgi
# Display server rename form

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_rename_domains() || &error($text{'rename_ecannot'});
&ui_print_header(&domain_in($d), $text{'rename_title'}, "", "rename");

print &ui_form_start("rename.cgi", "post");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_table_start($text{'rename_header'}, "width=100%", 2);

# Old and new domain name
print &ui_table_row($text{'rename_domain'},
		    "<tt>$d->{'dom'}</tt>");
$dname = &show_domain_name($d);
if ($dname ne $d->{'dom'}) {
	print &ui_table_row($text{'rename_xndomain'},
			    "<tt>$dname</tt>");
	}
print &ui_table_row($text{'rename_new'},
		    &ui_textbox("new", $dname, 30));

if ($d->{'unix'} && &can_rename_domains() == 2) {
	# Rename user option
	print &ui_table_row($text{'rename_user'},
	    &ui_radio("user_mode", 1,
		      [ [ 0, &text('rename_user0',
				   "<tt>$d->{'user'}</tt>")."<br>" ],
			[ 1, $text{'rename_user1'}."<br>" ],
			[ 2, $text{'rename_user2'}." ".
			     &ui_textbox("user", undef, 20) ] ]));
	}

$rh = &can_rehome_domains();
if (!$rh) {
	# Cannot change home at all
	print &ui_hidden("home_mode", 0),"\n";
	}
elsif ($d->{'dir'}) {
	# Change home dir option
	print &ui_table_row($text{'rename_home'},
	    &ui_radio("home_mode", 1,
		      [ [ 0, &text('rename_home0',
				   "<tt>$d->{'home'}</tt>")."<br>" ],
			[ 1, $text{'rename_home1'}."<br>" ],
			$rh == 2 ? ( [ 2, &text('rename_home2',
				&ui_textbox("home", undef, 30)) ] ) : ( ),
		      ]));
	}
else {
	# Always change home, since there is none!
	print &ui_hidden("home_mode", 1),"\n";
	}

# Rename mailboxes option
@users = &list_domain_users($d, 1, 1, 1, 1);
print &ui_table_row($text{'rename_group'},
		    &ui_yesno_radio("group_mode", @users ? 0 : 1));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'rename_ok'} ] ]);

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});

