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
print &ui_table_row(&hlink($text{'redirect_from'}, 'redirect_path'),
	&ui_textbox("path", $r->{'path'}, 32, undef, undef,
		"placeholder=\"$text{'index_global_eg'} / or /old-path\""), );

# Destination
my $dest;
if ($r->{'alias'}) {
	# A directory on this server
	$dest = $r->{'dest'};
	}
elsif ($r->{'dest'} &&
       $r->{'dest'} =~ /^(http|https):\/\/%\{HTTP_HOST\}(\/.*)$/) {
	# A URL on this website, but with a different protocol
	$dest = $1.'://%{HTTP_HOST}'.$2;
	}
else {
	$dest = $r->{'dest'};
	}
# Convert punycode hostname to unicode for display
if ($dest && $dest =~ /^https?:\/\// && !$r->{'alias'}) {
	my ($phost) = &parse_http_url($dest);
	if ($phost) {
		my $dhost = &show_domain_name($phost, 2);
		$dest =~ s/\Q$phost\E/$dhost/ if ($dhost ne $phost);
		}
	}
print &ui_table_row(&hlink($text{'redirect_to'}, 'redirect_dest'),
	&ui_textbox("dest", $dest, 65, undef, undef,
		"placeholder=\"$text{'index_global_eg'} ".
		"/new-path, https://dom.tld/new-path, or ".
		"/home/user/public_html/dir/\""));

print &ui_table_hr();

# HTTP status code
print &ui_table_row(&hlink($text{'redirect_code'}, 'redirect_code'),
	&ui_select("code", $r->{'code'} || 302,
		   [ [ 301, $text{'redirect_301'} ],
		     [ 302, $text{'redirect_302'} ],
		     [ 303, $text{'redirect_303'} ] ], 1, 0, 1));

# Sub-paths mode
print &ui_table_row(&hlink($text{'redirect_regexp2'}, 'redirect_regexp2'),
	&ui_select("regexp", $r->{'regexp'} ? 1 : $r->{'exact'} ? 2 : 0,
		   [ [ 0, $text{'redirect_regexp2no'} ],
		     [ 1, $text{'redirect_regexp2yes'} ],
		     [ 2, $text{'redirect_regexp2exact'} ] ]));

# Protocols to include
if (&domain_has_ssl($d)) {
	my $pmode = $r->{'http'} && $r->{'https'} ? "both" :
		    $r->{'https'} ? "https" : "http";
	print &ui_table_row(&hlink($text{'redirect_proto'}, 'redirect_proto'),
		&ui_select("proto_mode", $pmode,
			   [ [ "both", $text{'redirect_proto_both'} ],
			     [ "http", $text{'redirect_proto_http'} ],
			     [ "https", $text{'redirect_proto_https'} ] ]));
	}
else {
	print &ui_hidden("proto_mode", "http");
	}

# Hostname filter with any, selected website hostname, or manual pattern.
if (&has_web_host_redirects($d)) {
	my @hosts = &get_website_hostnames($d);
	my $inpick = @hosts && $r->{'host'} && !$r->{'hostregexp'} &&
		     grep { $_ eq $r->{'host'} } @hosts;
	my $hmode = !$r->{'host'} ? 0 :
		    $inpick ? 1 : 2;
	my $htexti = @hosts ? 2 : 1;
	my $htext = &ui_textbox("host", $hmode == 2 ? $r->{'host'} : undef,
		35, undef, undef,
		"onfocus=\"if (this.form.host_mode && ".
			"this.form.host_mode.length > $htexti) { ".
			"this.form.host_mode[$htexti].checked = true; }\" ".
		"placeholder=\"$text{'index_global_eg'} ".
		"dom.tld or ^regex\$\"");
	my @hmode_opts = ( [ 0, $text{'redirect_host_def'} ] );
	if (@hosts) {
		my @hopts = ( [ undef, $text{'redirect_host_pick'} ],
			      map { [ $_, &show_domain_name($_) ] } @hosts );
		my $hsel = &ui_select("host_pick",
			$hmode == 1 ? $r->{'host'} : undef,
			\@hopts, undef, undef, undef, undef,
			"onchange=\"if (this.form.host_mode && ".
				"this.form.host_mode.length > 2) { ".
				"this.form.host_mode[1].checked = true; }\"");
		push(@hmode_opts,
			[ 1, $text{'redirect_host_pick_mode'}."&nbsp;".$hsel ]);
		}
	else {
		print &ui_hidden("host_pick", "");
		}
	push(@hmode_opts, [ 2, $text{'redirect_host_spec'}."&nbsp;".$htext ]);
	print &ui_table_row(&hlink($text{'redirect_host'}, 'redirect_host'),
		&ui_radio("host_mode", $hmode, \@hmode_opts));
	}

print &ui_table_end();
print &ui_form_end(
    $in{'new'} ? [ [ undef, $text{'create'} ] ]
    	       : [ [ undef, $text{'save'} ], [ "delete", $text{'delete'} ] ]);

&ui_print_footer("list_redirects.cgi?dom=$in{'dom'}", $text{'redirects_return'},
		 &domain_footer_link($d), "", $text{'index_return'});
