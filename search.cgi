#!/usr/local/bin/perl
# search.cgi
# Display domains matching some search

require './virtual-server-lib.pl';
&ReadParse();

# If search is by parent, look it up
$oldwhat = $in{'what'};
if (($in{'field'} eq "parent" || $in{'field'} eq "alias") &&
    $in{'what'} !~ /^\d+$/) {
	# Convert domain name to ID
	$pd = &get_domain_by("dom", $in{'what'});
	$in{'what'} = $pd->{'id'} if ($pd);
	}
elsif ($in{'field'} eq "template" && $in{'what'} !~ /^\d+$/) {
	# Convert template name to ID
	($tmpl) = grep { $_->{'name'} =~ /\Q$in{'what'}\E/i } &list_templates();
	$in{'what'} = $tmpl->{'id'} if ($tmpl);
	}

# Do the search
foreach $d (&list_domains()) {
	next if (!&can_edit_domain($d));
	if ($d->{$in{'field'}} =~ /\Q$in{'what'}\E/i) {
		push(@doms, $d);
		}
	}

&ui_print_header(undef, $text{'search_title'}, "");
$isfeat = &indexof($in{'field'}, @features) >= 0;
if ($isfeat) {
	$fname = $text{'feature_'.$in{'field'}};
	}

if (!@doms) {
	if ($in{'nonemsg'}) {
		print "<b>$in{'nonemsg'}</b><p>\n";
		}
	elsif ($isfeat) {
		print "<b>",&text('search_nonef', $fname),"</b><p>\n";
		}
	else {
		print "<b>",&text('search_none',
				  "<tt>$oldwhat</tt>"),"</b><p>\n";
		}
	}
else {
	if ($in{'msg'}) {
		print "<b>$in{'msg'}</b><p>\n";
		}
	elsif ($isfeat) {
		print "<b>",&text('search_resultsf', $fname,
				  scalar(@doms)),"</b><p>\n";
		}
	else {
		print "<b>",&text('search_results', "<tt>$oldwhat</tt>",
				  scalar(@doms)),"</b><p>\n";
		}
	print &ui_form_start("domain_form.cgi");
	@links = ( );
	if ($virtualmin_pro) {
		push(@links, &select_all_link("d"),
			     &select_invert_link("d") );
		}
	print &ui_links_row(\@links);
	&domains_table(\@doms, $virtualmin_pro, 0,
           $in{'field'} eq 'parent' ? [ 'user', 'quota', 'squota', 'uquota' ]
				    : [ ]);
	print &ui_links_row(\@links);
	if ($virtualmin_pro && &can_config_domain($doms[0])) {
		print &ui_submit($text{'index_delete'}, "delete"),"\n";
		print &ui_submit($text{'index_mass'}, "mass"),"\n";
		if (&can_disable_domain($doms[0])) {
			print "&nbsp;&nbsp;\n";
			print &ui_submit($text{'index_disable'},"disable"),"\n";
			print &ui_submit($text{'index_enable'}, "enable"),"\n";
			}
		}
	print &ui_form_end();
	}

&ui_print_footer("", $text{'index_return'});

