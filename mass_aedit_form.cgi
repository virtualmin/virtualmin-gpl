#!/usr/local/bin/perl
# Show a form for manually editing all simple aliases in a text box

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'aliases_ecannot'});
&ui_print_header(&domain_in($d), $text{'aedit_title'}, "", "aedit");

print $text{'aedit_help'};
print "<br><tt>$text{'amass_format'}</tt><p>\n";
print &ui_form_start("mass_aedit.cgi", "form-data");

# Find aliases we can edit
@aliases = &list_domain_aliases($d, 1);
foreach my $alias (@aliases) {
	my $simple = &get_simple_alias($d, $alias);
	if ($simple && !$simple->{'auto'}) {
		push(@canaliases, [ $alias, $simple ]);
		print &ui_hidden("orig", $alias->{'from'});
		}
	}
if (scalar(@canaliases) != scalar(@aliases)) {
	print &text('aedit_missing',
		    scalar(@aliases)-scalar(@canaliases)),"<p>\n";
	}

# Make them into a string
$aliases = "";
foreach $can (@canaliases) {
	($alias, $simple) = @$can;

	# Alias name
	$name = $alias->{'from'};
	$name =~ s/\@\S+$//;
	if ($name eq "") {
		$aliases .= "*";
		}
	else {
		$aliases .= $name;
		}

	# Comment
	$aliases .= ":".$alias->{'cmt'};

	# Forward, local and bounce destinations
	$dname = $d->{'dom'};
	foreach $f (@{$simple->{'forward'}}) {
		$f =~ s/\@\Q$dname\E$//;	# Remove domain
		$aliases .= ":".$f;
		}
	if ($simple->{'local'}) {
		$aliases .= ":local ".$simple->{'local'};
		}
	if ($simple->{'bounce'}) {
		$aliases .= ":bounce";
		}

	$aliases .= "\n";
	}

# Show them in a text box
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_textarea("aliases", $aliases, 10, 80),"<br>\n";
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("list_aliases.cgi?dom=$in{'dom'}", $text{'aliases_return'},
		 "", $text{'index_return'});

