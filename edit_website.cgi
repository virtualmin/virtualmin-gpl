#!/usr/local/bin/perl
# Show website options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
$can = &can_edit_phpmode($d);
$can || &error($text{'phpmode_ecannot'});
if (!$d->{'alias'}) {
	@modes = &supported_php_modes($d);
	$mode = &get_domain_php_mode($d);
	}
$p = &domain_has_website($d);

&ui_print_header(&domain_in($d), $text{'phpmode_title'}, "");

print &ui_form_start("save_website.cgi");
print &ui_hidden("dom", $d->{'id'}),"\n";
print &ui_table_start($text{'website_header'}, "width=100%", 2);

# HTML directory
if (!$d->{'alias'} && $d->{'public_html_dir'} !~ /\.\./) {
	print &ui_table_row(&hlink($text{'phpmode_htmldir'}, 'htmldir'),
		&ui_textbox("htmldir", $d->{'public_html_dir'}, 20)."<br>\n".
		&ui_checkbox("htmlrename", 1, $text{'phpmode_rename'}, 0));
	}

# Redirect non-SSL to SSL?
if (&domain_has_ssl($d) && &can_edit_redirect() && &has_web_redirects($d)) {
	my @redirects = map { &remove_wellknown_redirect($_) }
			    &list_redirects($d);
	my ($defredir) = grep { $_->{'path'} eq '/' &&
			        $_->{'http'} && !$_->{'https'} } @redirects;
	print &ui_table_row(&hlink($text{'phpmode_sslredir'}, 'sslredir'),
		&ui_yesno_radio("sslredir", $defredir ? 1 : 0));
	}

# Redirect www to non-www or vice-versa
if (!$d->{'alias'} && &can_edit_redirect() &&
    &has_web_redirects($d) && &has_web_host_redirects($d)) {
	my ($r) = grep { $_ } map { &is_www_redirect($d, $_) }
				  &list_redirects($d);
	$r ||= 0;
	print &ui_table_row(
		&hlink($text{'phpmode_wwwredir'}, "wwwredir"),
		&ui_radio("wwwredir", $r,
			  [ map { [ $_, &text('phpmode_wwwredir'.$_,
					$d->{'dom'})."<br>" ] } (0.. 3) ]));
	}

# Match all sub-domains
if ($p eq 'web' || &plugin_defined($p, "feature_get_web_domain_star")) {
	print &ui_table_row(&hlink($text{'phpmode_matchall'}, "matchall"),
		    &ui_yesno_radio("matchall", &get_domain_web_star($d)));
	}

# Server-side includes
if (&supports_ssi($d)) {
	($ssi, $suffix) = &get_domain_web_ssi($d);
	$suffix = ".shtml" if ($ssi != 1);
	print &ui_table_row(&hlink($text{'phpmode_ssi'}, "phpmode_ssi"),
	    &ui_radio("ssi", $ssi,
		      [ [ 1, &text('phpmode_ssi1',
				   &ui_textbox("suffix", $suffix, 6)) ],
			[ 0, $text{'no'} ],
			$ssi == 2 ? ( [ 2, $text{'phpmode_ssi2'} ] )
				  : ( ) ]));
	}

# Default website for its IP
if (!$d->{'alias'} || $d->{'alias_mode'} != 1 &&
    ($p eq 'web' || &plugin_defined($p, "feature_get_web_default_website"))) {
	$defweb = &is_default_website($d);
	$defd = &find_default_website($d);
	$defno = $defd ? &text('phpmode_defno', $defd->{'dom'}) : $text{'no'};
	if (&can_default_website($d) && !$defweb) {
		print &ui_table_row(&hlink($text{'phpmode_defweb'}, "defweb"),
			&ui_radio("defweb", $defweb,
				  [ [ 1, $text{'yes'} ], [ 0, $defno ] ]));
		}
	else {
		print &ui_table_row(&hlink($text{'phpmode_defweb'}, "defweb"),
			$defweb == 1 ? $text{'yes'} :
			$defweb == 2 ? $text{'phpmode_defwebsort'} :
				       $defno);
		}
	}

# Log file locations
if (!$d->{'alias'} && &can_log_paths() &&
    ($p eq 'web' || &plugin_defined($p, "feature_change_web_access_log"))) {
	$alog = &get_website_log($d, 0);
	if ($alog) {
		print &ui_table_row(&hlink($text{'phpmode_alog'}, 'accesslog'),
			&ui_textbox("alog", $alog, 60));
		}
	$elog = &get_website_log($d, 1);
	if ($elog) {
		print &ui_table_row(&hlink($text{'phpmode_elog'}, 'errorlog'),
			&ui_textbox("elog", $elog, 60));
		}
	}
# CGI execution mode
my @cgimodes = &has_cgi_support($d);
if (@cgimodes > 0) {
	print &ui_table_row(
		&hlink($text{'tmpl_web_cgimode'}, "web_cgimode"),
		&ui_radio_table("cgimode", &get_domain_cgi_mode($d),
			  [ [ '', $text{'tmpl_web_cgimodenone'} ],
			    map { [ $_, $text{'tmpl_web_cgimode'.$_} ] }
				reverse(@cgimodes) ]));
	}

# Ruby execution mode
if (defined(&supported_ruby_modes)) {
	@rubys = &supported_ruby_modes($d);
	if (!$d->{'alias'} && @rubys && $can &&
	    ($p eq 'web' || &plugin_defined($p, "feature_get_web_ruby_mode"))) {
		print &ui_table_row(
			&hlink($text{'phpmode_rubymode'}, "rubymode"),
			&ui_radio_table("rubymode", &get_domain_ruby_mode($d),
				  [ [ "", $text{'phpmode_noruby'} ],
				    map { [ $_, $text{'phpmode_'.$_} ] }
					@rubys ]));
		}
	}

# Write logs via program. Don't show unless enabled.
if ((!$d->{'alias'} || $d->{'alias_mode'} != 1) && $can == 2 &&
    &get_writelogs_status($d) && $p eq 'web') {
	print &ui_table_row(
		&hlink($text{'newweb_writelogs'}, "template_writelogs"),
		&ui_yesno_radio("writelogs", &get_writelogs_status($d)));
	}

# HTTP2 protocol support?
if (!$d->{'alias'}) {
	my $canprots = &get_domain_supported_http_protocols($d);
	my $prots = &get_domain_http_protocols($d);
	my $defprots = &get_default_http_protocols($d);
	if (&indexof("h2", @$canprots) >= 0 && ref($prots)) {
		if (@$defprots) {
			$def = &indexof("h2", @$defprots) >= 0 ? $text{'yes'}
							       : $text{'no'};
			$inp = &ui_radio("http2",
				@$prots == 0 ? 2 :
				&indexof("h2", @$prots) >= 0 ? 1 : 0,
				[ [ 2, $text{'newweb_http2_def'}." ($def)" ],
				  [ 1, $text{'yes'} ],
				  [ 0, $text{'no'} ] ]);
			}
		else {
			$inp = &ui_yesno_radio(
				"http2", &indexof("h2", @$prots) >= 0);
			}
		print &ui_table_row(
			&hlink($text{'phpmode_http2'}, "http2"), $inp);
		}
	}

print &ui_table_end();

print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

