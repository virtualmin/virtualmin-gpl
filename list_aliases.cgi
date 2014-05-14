#!/usr/local/bin/perl
# list_aliases.cgi
# Display users and aliases in a domain

$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) && &can_edit_aliases() || &error($text{'aliases_ecannot'});
@aliases = &list_domain_aliases($d, !$in{'show'});
$msg = &text('aliases_indom', scalar(@aliases),
	     "<tt>".&show_domain_name($d)."</tt>");
&ui_print_header($msg, $text{'aliases_title'}, "");

# Create add links
($mleft, $mreason, $mmax, $mhide) = &count_feature("aliases");
if ($mleft != 0) {
	push(@links, [ "edit_alias.cgi?new=1&dom=".&urlize($in{'dom'}).
			"&show=".&urlize($in{'show'}),
		       $text{'aliases_add'} ]);
	}
push(@links, [ "mass_aedit_form.cgi?dom=".&urlize($in{'dom'}),
	       $text{'aliases_emass'}, 'right' ]);
if ($in{'show'}) {
	push(@links, [ "list_aliases.cgi?dom=".&urlize($in{'dom'})."&show=0",
		       $text{'aliases_hide'}, 'right' ]);
	}
else {
	push(@links, [ "list_aliases.cgi?dom=".&urlize($in{'dom'})."&show=1",
		       $text{'aliases_show'}, 'right' ]);
	}

# Show reason why aliases cannot be added
if ($mleft != 0 && $mleft != -1 && !$mhide) {
	print "<b>",&text('aliases_canadd'.$mreason,$mleft),"</b><p>\n";
	}
elsif ($mleft == 0) {
	print "<b>",&text('aliases_noadd'.$mreason, $mmax),"</b><p>\n";
	}

# Make the table data
@table = ( );
if ($can_alias_comments) {
	($anycmt) = grep { $_->{'cmt'} } @aliases;
	}
foreach $a (sort { $a->{'from'} cmp $b->{'from'} } @aliases) {
	$name = $a->{'from'};
	$name =~ s/\@\S+$//;
	$name = "<i>$text{'alias_catchall'}</i>" if ($name eq "");
	$alines = "";
	$simple = &get_simple_alias($d, $a);
	foreach $v (@{$a->{'to'}}) {
		($anum, $astr) = &alias_type($v);
		if ($anum == 5 && $simple) {
			# Show shortened autoreply message
			$msg = $simple->{'autotext'};
			$msg = substr($msg, 0, 100)." ..."
				if (length($msg) > 100);
			$alines .= &text('aliases_reply',
				"<i>".&html_escape($msg)."</i>")."<br>\n";
			}
		elsif ($anum == 13) {
			# Show everyone domain
			$ed = &get_domain($astr);
			$alines .= &text("aliases_type$anum",
			   "<tt>".&show_domain_name($ed)."</tt>")."<br>\n";
			}
		else {
			$alines .= &text("aliases_type$anum",
			   "<tt>".&html_escape($astr)."</tt>")."<br>\n";
			}
		}
	if (!@{$a->{'to'}}) {
		$alines = "<i>$text{'aliases_dnone'}</i>\n";
		}
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $a->{'from'} },
		"<a href='edit_alias.cgi?dom=".&urlize($in{'dom'})."&".
		"alias=".&urlize($a->{'from'})."&show=".&urlize($in{'show'})."'>$name</a>",
		$alines,
		$anycmt ? ( $a->{'cmt'} ) : ( ),
		]);
	}

# Generate the table
print &ui_form_columns_table(
	"delete_aliases.cgi",
	[ [ "delete", $text{'aliases_delete'} ] ],
	1,
	\@links,
	[ [ "dom", $in{'dom'} ],
	  [ "show", $in{'show'} ] ],
	[ "", $text{'aliases_name'},
	  $text{'aliases_dests'},
          $anycmt ? ( $text{'aliases_cmt'} ) : ( ) ],
	100,
	\@table,
	undef, 0, undef,
	$text{'aliases_none'});

# Make sure the left menu is showing this domain
if (defined(&theme_select_domain)) {
	&theme_select_domain($d);
	}

if ($single_domain_mode) {
	&ui_print_footer(&domain_footer_link($d),
			 "", $text{'index_return2'});
	}
else {
	&ui_print_footer(&domain_footer_link($d),
		"", $text{'index_return'});
	}

