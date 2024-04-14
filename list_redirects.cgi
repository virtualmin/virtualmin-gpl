#!/usr/local/bin/perl
# Display aliases and redirects in some domain

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_redirect() ||
	&error($text{'redirects_ecannot'});
&has_web_redirects($d) || &error($text{'redirects_eweb'});
&ui_print_header(&domain_in($d), $text{'redirects_title'}, "", "redirects");

# Build table data
@redirects = map { &remove_wellknown_redirect($_) } &list_redirects($d);
$canhost = &has_web_host_redirects($d);
foreach $r (@redirects) {
	my @protos;
	push(@protos, "HTTP") if ($r->{'http'});
	push(@protos, "HTTPS") if ($r->{'https'});
	my $dest = $r->{'dest'};
	if (!$r->{'alias'} &&
	    $dest =~ /^(http|https):\/\/%\{HTTP_HOST\}(\/.*)$/) {
		$dest = &text('redirects_with', "$2", uc($1));
		}
	my $iswebmail = &is_webmail_redirect($d, $r);
	my $iswww = &is_www_redirect($d, $r);
	my $canedit = !$iswebmail && !$iswww;
	push(@table, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $r->{'id'}, 'disabled' => !$canedit },
		$canedit ? 
			&ui_link("edit_redirect.cgi?dom=$in{'dom'}&".
				 "id=$r->{'id'}", $r->{'path'}) :
			$r->{'path'},
		$iswebmail == 2 ? $text{'redirects_webmin'} :
		$iswebmail == 1 ? $text{'redirects_usermin'} :
		$iswww ? $text{'redirects_canon'} :
		$r->{'alias'} ? $text{'redirects_alias'}
			      : $text{'redirects_redirect'},
		join(", ", @protos),
		$canhost ? ( $r->{'host'} || $text{'redirects_any'} ) : ( ),
		$dest,
		]);
	}

# Generate the table
print &ui_form_columns_table(
	"delete_redirects.cgi",
	[ [ undef, $text{'redirects_delete'} ] ],
	1,
	[ [ "edit_redirect.cgi?new=1&dom=$in{'dom'}",
	    $text{'redirects_add'} ] ],
	[ [ "dom", $in{'dom'} ] ],
	[ "", $text{'redirects_path'},
          $text{'redirects_type'},
          $text{'redirects_protos'},
	  $canhost ? ( $text{'redirects_host'} ) : ( ),
          $text{'redirects_dest'},
	],
	100,
	\@table,
	undef,
	0,
	undef,
	$text{'redirects_none'},
	);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});
