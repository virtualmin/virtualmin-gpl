#!/usr/local/bin/perl
# list_aliases.cgi
# Display users and aliases in a domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_aliases() || &error($text{'aliases_ecannot'});
@aliases = &list_domain_aliases($d, 1);
&ui_print_header(&domain_in($d), $text{'aliases_title'}, "");

# Create select / add links
($mleft, $mreason, $mmax, $mhide) = &count_feature("aliases");
@links = ( &select_all_link("d"),
	   &select_invert_link("d") );
if ($mleft != 0) {
	push(@links, "<a href='edit_alias.cgi?new=1&dom=$in{'dom'}'>".
		     "$text{'aliases_add'}</a>");
	}
if ($virtualmin_pro && $mleft != 0) {
	push(@rlinks, "<a href='mass_acreate_form.cgi?dom=$in{'dom'}'>".
		      "$text{'aliases_mass'}</a>");
	}

if (@aliases) {
	print &ui_form_start("delete_aliases.cgi");
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print "<table cellpadding=0 cellspacing=0 width=100%><tr><td>\n";
	if ($mleft != 0 && $mleft != -1 && !$mhide) {
		print "<b>",&text('aliases_canadd'.$mreason,$mleft),"</b><p>\n";
		}
	elsif ($mleft == 0) {
		print "<b>",&text('aliases_noadd'.$mreason, $mmax),"</b><p>\n";
		}
	print &ui_links_row(\@links);
	print "</td> <td align=right>\n";
	print &ui_links_row(\@rlinks);
	print "</td> </tr></table>\n";
	if ($can_alias_comments) {
		($anycmt) = grep { $_->{'cmt'} } @aliases;
		}
	print &ui_columns_start([ "", $text{'aliases_name'},
				      $text{'aliases_domain'},
				      $text{'aliases_dests'},
				      $anycmt ? ( $text{'aliases_cmt'} ) : ( )
				], 100, 0,
				[ "width=5" ]);
	foreach $a (sort { $a->{'from'} cmp $b->{'from'} } @aliases) {
		$name = $a->{'from'};
		$name =~ s/\@\S+$//;
		$name = "<i>$text{'alias_catchall'}</i>" if ($name eq "");
		$alines = "";
		$simple = $virtualmin_pro ? &get_simple_alias($d, $a) : undef;
		foreach $v (@{$a->{'to'}}) {
			($anum, $astr) = &alias_type($v);
			if ($anum == 5 && $simple) {
				$msg = $simple->{'autotext'};
				$msg = substr($msg, 0, 100)." ..."
					if (length($msg) > 100);
				$alines .= &text('aliases_reply',
					"<i>".&html_escape($msg)."</i>");
				}
			else {
				$alines .= &text("aliases_type$anum",
				   "<tt>".&html_escape($astr)."</tt>")."<br>\n";
				}
			}
		if (!@{$a->{'to'}}) {
			$alines = "<i>$text{'aliases_dnone'}</i>\n";
			}
		print &ui_checked_columns_row([
			"<a href='edit_alias.cgi?dom=$in{'dom'}&".
			"alias=$a->{'from'}'>$name</a>",
			$d->{'dom'},
			$alines,
			$anycmt ? ( $a->{'cmt'} ) : ( ) ],
			[ "width=5", "valign=top", "valign=top" ],
			"d", $a->{'from'});
		}
	print &ui_columns_end();
	}
else {
	print "<b>$text{'aliases_none'}</b><p>\n";
	shift(@links); shift(@links);
	}
print "<table cellpadding=0 cellspacing=0 width=100%><tr><td>\n";
print &ui_links_row(\@links);
print "</td> <td align=right>\n";
print &ui_links_row(\@rlinks);
print "</td> </tr></table>\n";
if (@aliases) {
	print &ui_form_end([ [ "delete", $text{'aliases_delete'} ] ]);
	}

if ($single_domain_mode) {
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return2'});
	}
else {
	&ui_print_footer(&domain_footer_link($d),
		"", $text{'index_return'});
	}

