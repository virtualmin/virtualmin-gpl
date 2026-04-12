#!/usr/local/bin/perl
# link.cgi
# Serve a read-only preview of a locally hosted website inside Webmin.

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
if ($@) {
	do '../web-lib.pl';
	}

# parse_preview_request(pathinfo)
# Parse PATH_INFO into a normalized preview or proxy request hash.
sub parse_preview_request
{
my ($pathinfo) = @_;
my %req = ( 'mode' => 'preview' );
$pathinfo ||= '';
$req{'mode'} = 'proxy' if ($pathinfo =~ s/^\/proxy(?=\/)//);

if ($pathinfo =~ /^\/([0-9\.]+)\/(http|https):\/+([^:\/]+)(:(\d+))?(.*)$/) {
	# Preview a local site by explicit IP and URL.
	$req{'ip'} = $1;
	$req{'protocol'} = $2;
	$req{'ssl'} = $2 eq "https";
	$req{'host'} = $3;
	$req{'port'} = $5 || ($req{'ssl'} ? 443 : 80);
	$req{'path'} = $6;
	$req{'path'} =~ s/ /%20/g;
	$req{'openurl'} = "$2://$3$4$6";
	$req{'baseurl'} = "$2://$3$4";
	}
elsif ($pathinfo =~ /^\/(http|https):\/+([^:\/]+)(:(\d+))?(.*)$/) {
	# Keep support for older off-site style URLs.
	$req{'protocol'} = $1;
	$req{'ssl'} = $1 eq "https";
	$req{'host'} = $2;
	$req{'port'} = $4 || ($req{'ssl'} ? 443 : 80);
	$req{'path'} = $5;
	$req{'path'} =~ s/ /%20/g;
	$req{'openurl'} = "$1://$2$3$5";
	$req{'baseurl'} = "$1://$2$3";
	$req{'ip'} = &to_ipaddress($2);
	}
else {
	&error("Bad PATH_INFO : $pathinfo");
	}

if ($ENV{'QUERY_STRING'}) {
	$req{'path'} .= '?'.$ENV{'QUERY_STRING'};
	}
elsif (@ARGV) {
	$req{'path'} .= '?'.join('+', @ARGV);
	}

if ($req{'host'} =~ /^www\.(.*)$/) {
	$req{'althost'} = $1;
	}
else {
	$req{'althost'} = "www.$req{'host'}";
	}

$req{'linkurl'} = "/$module_name/link.cgi/proxy/$req{'ip'}/";
$req{'url'} = $req{'linkurl'}.$req{'openurl'};
$req{'url'} .= '?'.$ENV{'QUERY_STRING'} if ($ENV{'QUERY_STRING'});
$req{'url'} .= '?'.join('+', @ARGV)
	if (!$ENV{'QUERY_STRING'} && @ARGV);

return \%req;
}

# require_local_preview_ip(ip)
# Reject preview targets that are not bound to a local system IP.
sub require_local_preview_ip
{
my ($ip) = @_;
open(my $fh, "<$module_config_directory/localips") ||
	&error("Failed to read local IP addresses");
chop(my @localips = <$fh>);
close($fh);
&indexof($ip, @localips) >= 0 ||
	&error("Connections to IP addresses not on this system are ".
	       "not allowed : $ip");
}

# open_target_connection(req, method)
# Open the upstream site connection, with a fallback to the alternate host.
sub open_target_connection
{
my ($req, $method) = @_;
local $oldproxy = $gconfig{'http_proxy'};
local $con;
local $httphost = $req->{'host'};
$gconfig{'http_proxy'} = '';
$con = &make_http_connection(
	$req->{'ip'}, $req->{'port'}, $req->{'ssl'}, $method,
	$req->{'path'}, undef, undef,
	{ 'host' => $req->{'host'},
		'checkhost' => $req->{'host'} });
if (!ref($con)) {
	# Some sites answer only on the www/non-www alternate host.
	$httphost = $req->{'althost'};
	$con = &make_http_connection(
		$req->{'ip'}, $req->{'port'}, $req->{'ssl'}, $method,
		$req->{'path'}, undef, undef,
		{ 'host' => $req->{'althost'},
		  'checkhost' => $req->{'althost'} });
	}
$gconfig{'http_proxy'} = $oldproxy;
return ($con, $httphost);
}

# send_target_request(con, httphost, body)
# Forward the browser request metadata and optional body upstream.
sub send_target_request
{
my ($con, $httphost, $body) = @_;
my $cl = length($body);
&write_http_connection($con, "Host: $httphost\r\n");
&write_http_connection($con, "User-agent: Webmin\r\n");
&write_http_connection($con, sprintf(
			"Webmin-servers: %s://%s:%d/$module_name/\r\n",
			$ENV{'HTTPS'} eq "ON" ? "https" : "http",
			$ENV{'SERVER_NAME'}, $ENV{'SERVER_PORT'}));
&write_http_connection($con, "Content-length: $cl\r\n") if ($cl);
&write_http_connection($con, "Content-type: $ENV{'CONTENT_TYPE'}\r\n")
	if ($ENV{'CONTENT_TYPE'});
&write_http_connection($con, "\r\n");
&write_http_connection($con, $body) if ($cl);
}

# read_target_headers(con)
# Read the upstream status line and response headers.
sub read_target_headers
{
my ($con) = @_;
my $status = &read_http_connection($con);
my (%header, $headers);
while (1) {
	(my $line = &read_http_connection($con)) =~ s/\r|\n//g;
	last if (!$line);
	$line =~ /^(\S+):\s+(.*)$/ || &error("Bad header");
	$header{lc($1)} = $2;
	$headers .= $line."\n";
	}
return ($status, \%header, $headers);
}

# read_browser_request_body()
# Read the incoming browser request body, if one was sent.
sub read_browser_request_body
{
my $cl = $ENV{'CONTENT_LENGTH'} || 0;
my $body = '';
if ($cl) {
	if (defined(&read_fully)) {
		&read_fully(STDIN, \$body, $cl);
		}
	else {
		read(STDIN, $body, $cl);
		}
	}
return $body;
}

# is_basic_auth_challenge(status, header)
# Return true when the upstream response requests HTTP Basic Authentication.
sub is_basic_auth_challenge
{
my ($status, $header) = @_;
return $status =~ /\s401(?:\s|$)/ &&
       $header->{'www-authenticate'} =~ /basic/i;
}

# preflight_preview_request(req)
# Probe the target before rendering the wrapper so early errors reach the user.
sub preflight_preview_request
{
my ($req) = @_;
my ($con, $httphost) = &open_target_connection($req, "GET");
&error($con) if (!ref($con));
&send_target_request($con, $httphost, '');
my ($status, $header) = &read_target_headers($con);
&close_http_connection($con);
&error(&text('links_preview_basic'))
	if (&is_basic_auth_challenge($status, $header));
}

# print_preview_wrapper(req)
# Render the simple preview page with a banner and sandboxed iframe.
sub print_preview_wrapper
{
my ($req) = @_;
my $style = ':root { color-scheme: light dark; --preview-bg: #fff; } '.
	    '@media (prefers-color-scheme: dark) { '.
	    ':root { --preview-bg: #111; } } '.
	    'html, body { margin: 0; padding: 0; height: 100%; '.
	    'background: var(--preview-bg); } '.
	    'body { font-family: sans-serif; display: grid; '.
	    'grid-template-rows: 30px 1fr; } '.
	    '.preview-banner { height: 30px; padding: 0 14px; '.
	    'background: #961602; font-weight: bold; color: #fff4f5; '.
	    'font-size: 12px; line-height: 30px; text-align: center; '.
	    'white-space: nowrap; overflow: hidden; text-overflow: ellipsis; } '.
	    'iframe { display: block; width: 100%; height: 100%; border: 0; '.
	    'background: var(--preview-bg); min-height: 0; }';

print "Content-type: text/html; charset=UTF-8\n";
print "X-Content-Type-Options: nosniff\n";
print "Content-Security-Policy: default-src 'none'; style-src ".
      "'unsafe-inline'; frame-src 'self'; frame-ancestors 'self'; ".
      "base-uri 'none'; form-action 'none'\n\n";
print &ui_tag('html',
	&ui_tag('head',
		&ui_tag('meta', undef, { 'charset' => 'utf-8' }).
		&ui_tag('meta', undef, {
			'name' => 'viewport',
			'content' => 'width=device-width, initial-scale=1',
		  }).
		&ui_tag('title', &html_escape($text{'links_website'})).
		&ui_tag('style', $style)
	).
	&ui_tag('body',
		&ui_tag('div',
			&html_escape($text{'links_preview_note'}),
			{ 'class' => 'preview-banner' }).
		&ui_tag('iframe', undef, {
			'src' => $req->{'url'},
			'title' => $text{'links_website'},
			'sandbox' => 'allow-scripts',
			'loading' => 'eager',
		  })
	));
}

# rewrite_proxy_redirect(req, header)
# Translate upstream redirects back into preview proxy URLs when possible.
sub rewrite_proxy_redirect
{
my ($req, $header) = @_;
my $location = $header->{'location'} || return undef;
my $defport = $req->{'ssl'} ? 443 : 80;

if ($location =~ /^(http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E):\Q$req->{'port'}\E(.*)$/) {
	return $req->{'linkurl'}.$location;
	}
if ($req->{'port'} == $defport &&
    $location =~ /^(http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)(\/.*)$/) {
	return $req->{'linkurl'}.$location;
	}
if ($location =~ /^(\/\S+)$/) {
	return $req->{'linkurl'}.$req->{'baseurl'}.$1;
	}
return undef;
}

# sanitize_proxy_headers(headers, header)
# Drop or replace upstream headers that are unsafe or no longer accurate.
sub sanitize_proxy_headers
{
my ($headers, $header) = @_;
# Drop headers that do not make sense once Webmin owns the response.
$headers =~ s/^Set-Cookie:.*\n//gmi;
$headers =~ s/^Location:.*\n//gmi;
if ($header->{'content-type'} =~ /text\/html/i) {
	$headers =~ s/^Content-Length:.*\n//gmi;
	$headers =~ s/^X-Frame-Options:.*\n//gmi;
	$headers .= "Content-Security-Policy: sandbox allow-scripts\n";
	}
return $headers;
}

# preview_blocker_markup()
# Return the injected CSS and JS that keeps preview content non-interactive.
sub preview_blocker_markup
{
return qq|<style>a, area, button, input[type=submit], input[type=button], input[type=image] { cursor: not-allowed !important; }</style>| .
       qq~<script>(function(){function block(event){var target = event.target && event.target.closest ? event.target.closest('a, area, button, input[type="submit"], input[type="button"], input[type="image"]') : null;if(target){event.preventDefault();event.stopPropagation();}}document.addEventListener('click', block, true);document.addEventListener('submit', function(event){event.preventDefault();event.stopPropagation();}, true);document.addEventListener('keydown', function(event){if ((event.key === 'Enter' || event.key === ' ') && event.target && event.target.closest && event.target.closest('a, area, button')) { event.preventDefault(); event.stopPropagation(); }}, true);})();</script>~;
}

# rewrite_html_chunk(req, chunk, injected_ref)
# Rewrite local asset URLs and inject the preview blocker into HTML once.
sub rewrite_html_chunk
{
my ($req, $chunk, $injected_ref) = @_;
if (!$$injected_ref) {
	# Inject once into the document body or head, without disturbing doctype.
	my $blocker = &preview_blocker_markup();
	if ($chunk =~ s/(<head\b[^>]*>)/$1$blocker/i ||
	    $chunk =~ s/(<body\b[^>]*>)/$1$blocker/i) {
		$$injected_ref = 1;
		}
	}

	$chunk =~ s/src='(\/[^']*)'/src='$req->{'linkurl'}$req->{'baseurl'}$1'/gi;
	$chunk =~ s/src="(\/[^"]*)"/src="$req->{'linkurl'}$req->{'baseurl'}$1"/gi;
	$chunk =~ s/src=(\/[^ "'>]*)/src=$req->{'linkurl'}$req->{'baseurl'}$1/gi;

	$chunk =~ s/src='((http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)[^']*)'/src='$req->{'linkurl'}$1'/gi;
	$chunk =~ s/src="((http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)[^"]*)"/src="$req->{'linkurl'}$1"/gi;
	$chunk =~ s/src=((http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)[^ "'>]*)/src=$req->{'linkurl'}$1/gi;

	$chunk =~ s/href='(\/[^']*)'/href='$req->{'linkurl'}$req->{'baseurl'}$1'/gi;
	$chunk =~ s/href="(\/[^"]*)"/href="$req->{'linkurl'}$req->{'baseurl'}$1"/gi;
	$chunk =~ s/href=(\/[^ "'>]*)/href=$req->{'linkurl'}$req->{'baseurl'}$1/gi;

	$chunk =~ s/href='((http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)[^']*)'/href='$req->{'linkurl'}$1'/gi;
	$chunk =~ s/href="((http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)[^"]*)"/href="$req->{'linkurl'}$1"/gi;
	$chunk =~ s/href=((http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)[^ "'>]*)/href=$req->{'linkurl'}$1/gi;

	$chunk =~ s/action='(\/[^']*)'/action='$req->{'linkurl'}$req->{'baseurl'}$1'/gi;
	$chunk =~ s/action="(\/[^"]*)"/action="$req->{'linkurl'}$req->{'baseurl'}$1"/gi;
	$chunk =~ s/action=(\/[^ "'>]*)/action=$req->{'linkurl'}$req->{'baseurl'}$1/gi;

	$chunk =~ s/action='((http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)[^']*)'/action='$req->{'linkurl'}$1'/gi;
	$chunk =~ s/action="((http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)[^"]*)"/action="$req->{'linkurl'}$1"/gi;
	$chunk =~ s/action=((http|https):\/\/(\Q$req->{'host'}\E|\Q$req->{'althost'}\E)[^ "'>]*)/action=$req->{'linkurl'}$1/gi;

	$chunk =~ s/\@import '(\/[^']*)'/\@import '$req->{'linkurl'}$req->{'baseurl'}$1'/gi;
	$chunk =~ s/\@import "(\/[^']*)"/\@import "$req->{'linkurl'}$req->{'baseurl'}$1"/gi;

return $chunk;
}

&init_config();
delete($ENV{'HTTP_REFERER'});
$| = 1;

my $req = &parse_preview_request($ENV{'PATH_INFO'});
&require_local_preview_ip($req->{'ip'});

if ($req->{'mode'} eq 'preview') {
	# Fail early in the main request before printing any wrapper HTML.
	&preflight_preview_request($req);
	&print_preview_wrapper($req);
	exit;
	}

my $body = &read_browser_request_body();
my ($con, $httphost) = &open_target_connection($req, $ENV{'REQUEST_METHOD'});
&error($con) if (!ref($con));
&send_target_request($con, $httphost, $body);

my ($status, $header, $headers) = &read_target_headers($con);
if (&is_basic_auth_challenge($status, $header)) {
	&close_http_connection($con);
	&error(&text('links_preview_basic'));
	}

if (my $redirect = &rewrite_proxy_redirect($req, $header)) {
	&close_http_connection($con);
	&redirect($redirect);
	exit;
	}

$headers = &sanitize_proxy_headers($headers, $header);
print $headers;
print "\n";

if ($header->{'content-type'} =~ /text\/html/ && !$header->{'x-no-links'}) {
	my $injected = 0;
	while (defined(my $chunk = &read_http_connection($con))) {
		print &rewrite_html_chunk($req, $chunk, \$injected);
		}
	}
else {
	while (my $chunk = &read_http_connection($con, 1024)) {
		print $chunk;
		}
	}
&close_http_connection($con);

