#!/usr/local/bin/perl
# Show a form for editing or adding a website redirect

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_redirect() ||
	&error($text{'redirects_ecannot'});
&has_web_redirects($d) || &error($text{'redirects_eweb'});
if (!$in{'new'}) {
	($r) = grep { $_->{'id'} eq $in{'id'} } &list_redirects($d);
	$r || &error($text{'redirect_egone'});
	$r = &remove_wellknown_redirect($r);
	}
else {
	$r = { 'http' => 1, 'https' => 1 };
	}

&ui_print_header(&domain_in($d), $in{'new'} ? $text{'redirect_create'}
					    : $text{'redirect_edit'}, "");

print &ui_form_start("save_redirect.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("old", $in{'id'});
print &ui_table_start($text{'redirect_header'}, undef, 2);

# URL path
print &ui_table_row(&hlink($text{'redirect_path'}, 'redirect_path'),
	&ui_textbox("path", $r->{'path'}, 40, undef, undef,
		"placeholder=\"$text{'index_global_eg'} / or /old-path\""), );

# Destination
my ($mode, $dir, $url, $upath);
if ($r->{'alias'}) {
	# A directory on this server
	$mode = 1;
	$dir = $r->{'dest'};
	}
elsif ($r->{'dest'} &&
       $r->{'dest'} =~ /^(http|https):\/\/%\{HTTP_HOST\}(\/.*)$/) {
	# A URL on this website, but with a different protocol
	$mode = 2;
	$dproto = $1;
	$dpath = $2;
	}
elsif ($r->{'dest'} && $r->{'dest'} =~ /^(http|https):\/\//) {
	# A URL on a different website
	$mode = 0;
	$url = $r->{'dest'};
	}
else {
	# A URL on this website with the same protocol
	$mode = 3;
	$urlpath = $r->{'dest'};
	}
print &ui_table_row(&hlink($text{'redirect_dest'}, 'redirect_dest'),
	&ui_radio_table("mode", $mode,
		[ [ 0, $text{'redirect_url'},
		    &ui_textbox("url", $url, 34, undef, undef,
				"placeholder=\"$text{'index_global_eg'} ".
				"https://google.com\"") ],
		  [ 3, $text{'redirect_urlpath'},
		    &ui_textbox("urlpath", $urlpath, 35, undef, undef,
				"placeholder=\"$text{'index_global_eg'} ".
				"/new-path\"") ],
		  [ 2, $text{'redirect_dpath'},
		    &ui_select("dproto", $dproto,
			       [ [ 'http', 'HTTP' ],
			         [ 'https', 'HTTPS' ] ])." ".
		    &ui_textbox("dpath", $dpath, 29, undef, undef,
				"placeholder=\"$text{'index_global_eg'} ".
				"/new-path\"") ],
		  [ 1, $text{'redirect_dir'},
		    &ui_textbox("dir", $dir, 52, undef, undef,
			"placeholder=\"$text{'index_global_eg'} ".
			"$d->{'home'}/$d->{'public_html_dir'}/new-path\"") ],
		]));

# HTTP status code
print &ui_table_row(&hlink($text{'redirect_code'}, 'redirect_code'),
	&ui_select("code", $r->{'code'},
		   [ [ "", $text{'default'} ],
		     [ 301, $text{'redirect_301'} ],
		     [ 302, $text{'redirect_302'} ],
		     [ 303, $text{'redirect_303'} ] ], 1, 0, 1));

# Sub-paths mode
print &ui_table_row(&hlink($text{'redirect_regexp2'}, 'redirect_regexp2'),
	&ui_radio("regexp", $r->{'regexp'} ? 1 : $r->{'exact'} ? 2 : 0,
		  [ [ 0, $text{'redirect_regexp2no'}."<br>" ],
		    [ 1, $text{'redirect_regexp2yes'}."<br>" ],
		    [ 2, $text{'redirect_regexp2exact'}."<br>" ] ]));

# Protocols to include
if (&domain_has_ssl($d)) {
	print &ui_table_row(&hlink($text{'redirect_proto'}, 'redirect_proto'),
		&ui_checkbox("http", 1, $text{'redirect_http'}, $r->{'http'}).
		" ".
		&ui_checkbox("https", 1, $text{'redirect_https'}, $r->{'https'})
		);
	}
else {
	print &ui_hidden("http", 1);
	}

# Hostname to match
if (&has_web_host_redirects($d)) {
	print &ui_table_row(&hlink($text{'redirect_host'}, 'redirect_host'),
		&ui_opt_textbox("host", $r->{'host'}, 35,
				$text{'redirect_host_def'}, undef, 0, undef, 0,
				"placeholder=\"$text{'index_global_eg'} ".
				"www.$d->{'dom'}\"")."<br>\n".
		&ui_checkbox("hostregexp", 1, $text{'redirect_hostregexp'},
			     $r->{'hostregexp'}));
	}

print &ui_table_end();
print &ui_form_end(
    $in{'new'} ? [ [ undef, $text{'create'} ] ]
    	       : [ [ undef, $text{'save'} ], [ "delete", $text{'delete'} ] ]);

&ui_print_footer("list_redirects.cgi?dom=$in{'dom'}", $text{'redirects_return'},
		 &domain_footer_link($d), "", $text{'index_return'});
