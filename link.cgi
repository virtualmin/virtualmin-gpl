#!/usr/local/bin/perl
# link.cgi
# Forward the URL from path_info on to another webmin server

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
if ($@) {
	do '../web-lib.pl';
	}

&init_config();
if ($ENV{'PATH_INFO'} =~ /^\/([0-9\.]+)\/(http|https):\/+([^:\/]+)(:(\d+))?(.*)$/) {
	# Version with IP and URL
	$ip = $1;
	$protocol = $2;
	$ssl = $protocol eq "https";
	$host = $3;
	$port = $5 || ($ssl ? 443 : 80);
	$path = $6;
	$path =~ s/ /%20/g;
	$openurl = "$2://$3$4$6";
	$baseurl = "$2://$3$4";
	}
elsif ($ENV{'PATH_INFO'} =~ /^\/(http|https):\/+([^:\/]+)(:(\d+))?(.*)$/) {
	# Version without IP, for offsite links
	$protocol = $1;
	$ssl = $protocol eq "https";
	$host = $2;
	$port = $4 || ($ssl ? 443 : 80);
	$path = $5;
	$path =~ s/ /%20/g;
	$openurl = "$1://$2$3$5";
	$baseurl = "$1://$2$3";
	$ip = &to_ipaddress($host);
	}
else {
	&error("Bad PATH_INFO : $ENV{'PATH_INFO'}");
	}
delete($ENV{'HTTP_REFERER'});	# So error page doesn't link to it
if ($ENV{'QUERY_STRING'}) {
	$path .= '?'.$ENV{'QUERY_STRING'};
	}
elsif (@ARGV) {
	$path .= '?'.join('+', @ARGV);
	}
$linkurl = "/$module_name/link.cgi/$ip/";
$url = "/$module_name/link.cgi/$ip/$openurl";
$noiplinkurl = "/$module_name/link.cgi/";
$| = 1;
$meth = $ENV{'REQUEST_METHOD'};

# Make sure the IP is on this system
open(IPCACHE, "$module_config_directory/localips");
chop(@localips = <IPCACHE>);
close(IPCACHE);
&indexof($ip, @localips) >= 0 ||
	&error("Connections to IP addresses not on this system are ".
	       "not allowed : $ip");

# Alternate host for redirects
if ($host =~ /^www\.(.*)$/) {
	$althost = $1;
	}
else {
	$althost = "www.$host";
	}

if ($config{'loginmode'} == 2) {
	# Login is variable .. check if we have it yet
	if ($ENV{'HTTP_COOKIE'} =~ /tunnel=([^\s;]+)/) {
		# Yes - set the login and password to use
		($user, $pass) = split(/:/, &decode_base64("$1"));
		}
	else {
		# No - need to display a login form
		&ui_print_header(undef, $text{'login_title'}, "");

		print "<center>",&text('login_desc', "<tt>$openurl</tt>"),
		      "</center><p>\n";
		print "<form action=/$module_name/login.cgi method=post>\n";
		print "<input type=hidden name=url value='",
			&html_escape($openurl),"'>\n";
		print "<center><table border>\n";
		print "<tr $tb> <td><b>$text{'login_header'}</b></td> </tr>\n";
		print "<tr $cb> <td><table cellpadding=2>\n";
		print "<tr> <td><b>$text{'login_user'}</b></td>\n";
		print "<td><input name=user size=20></td> </tr>\n";
		print "<tr> <td><b>$text{'login_pass'}</b></td>\n";
		print "<td><input name=pass size=20 type=password></td>\n";
		print "</tr> </table></td></tr></table>\n";
		print "<input type=submit value='$text{'login_login'}'>\n";
		print "<input type=reset value='$text{'login_clear'}'>\n";
		print "</center></form>\n";

		&ui_print_footer("", $text{'index_return'});
		exit;
		}
	}
elsif ($config{'loginmode'} == 1) {
	# Login is fixed
	$user = $config{'user'};
	$pass = $config{'pass'};
	}

# Connect to the server
local $oldproxy = $gconfig{'http_proxy'};	# Proxies mess up connection
$gconfig{'http_proxy'} = '';			# to the IP explicitly
$httphost = $host;
$con = &make_http_connection($ip, $port, $ssl, $meth, $path, undef, undef,
			     { 'host' => $host,
			       'checkhost' => $host });
if (!ref($con)) {
	# Maybe the alternate SSL hostname will work?
	$httphost = $althost;
	$con = &make_http_connection(
		$ip, $port, $ssl, $meth, $path, undef, undef,
		{ 'host' => $althost, 'checkhost' => $althost });
	}
$gconfig{'http_proxy'} = $oldproxy;
&error($con) if (!ref($con));

# Send request headers
&write_http_connection($con, "Host: $httphost\r\n");
&write_http_connection($con, "User-agent: Webmin\r\n");
if ($user) {
	$auth = &encode_base64("$user:$pass");
	$auth =~ s/\n//g;
	&write_http_connection($con, "Authorization: basic $auth\r\n");
	}
&write_http_connection($con, sprintf(
			"Webmin-servers: %s://%s:%d/$module_name/\n",
			$ENV{'HTTPS'} eq "ON" ? "https" : "http",
			$ENV{'SERVER_NAME'}, $ENV{'SERVER_PORT'}));
$cl = $ENV{'CONTENT_LENGTH'};
&write_http_connection($con, "Content-length: $cl\r\n") if ($cl);
&write_http_connection($con, "Content-type: $ENV{'CONTENT_TYPE'}\r\n")
	if ($ENV{'CONTENT_TYPE'});
&write_http_connection($con, "Cookie: $ENV{'HTTP_COOKIE'}\r\n")
	if ($ENV{'HTTP_COOKIE'});
&write_http_connection($con, "\r\n");
if ($cl) {
	if (defined(&read_fully)) {
		&read_fully(STDIN, \$post, $cl);
		}
	else {
		read(STDIN, $post, $cl);
		}
	&write_http_connection($con, $post);
	}

# read back the headers
$dummy = &read_http_connection($con);
while(1) {
	($headline = &read_http_connection($con)) =~ s/\r|\n//g;
	last if (!$headline);
	$headline =~ /^(\S+):\s+(.*)$/ || &error("Bad header");
	$header{lc($1)} = $2;
	$headers .= $headline."\n";
	}

# Fix up cookies using the old path
$headers =~ s/(Set-Cookie:.*path=)(\/\S+)/$1$linkurl$baseurl$2/gi;

# Output the headers, minus location which we mangle
$headers =~ s/Location:.*\n//gi;
print $headers;

$defport = $ssl ? 443 : 80;
if ($header{'location'} =~ /^(http|https):\/\/$host:$port$page(.*)$/ ||
    $header{'location'} =~ /^(http|https):\/\/$host$page(.*)/ &&
    $port == $defport ||
    $header{'location'} =~ /^(http|https):\/\/$althost:$port$page(.*)$/ ||
    $header{'location'} =~ /^(http|https):\/\/$althost$page(.*)/ &&
    $port == $defport) {
	# fix a redirect to the same site
        ($lproto, $lpage) = ($1, $2);
        if ($lproto ne $proto) {
                # to same host, but different protocol
                $url =~ s/\/(http|https)/\/$lproto/;
                }
	$url =~ s/\/$//;
        &redirect($linkurl.$header{'location'});
	exit;
	}
elsif ($header{'location'} =~ /^(\/\S+)$/) {
	# Fix a relative redirect
	&redirect($linkurl.$baseurl.$1);
	exit;
	}

# End of headers
print "\n";

# read back the rest of the page
if ($header{'content-type'} =~ /text\/html/ && !$header{'x-no-links'}) {
	while($_ = &read_http_connection($con)) {
		# Fix absolute image links like <img src=/foo.gif>
		s/src='(\/[^']*)'/src='$linkurl$baseurl$1'/gi;
		s/src="(\/[^"]*)"/src="$linkurl$baseurl$1"/gi;
		s/src=(\/[^ "'>]*)/src=$linkurl$baseurl$1/gi;

		# Fix full links to the same host, like 
		# <img src=http://mydomain.com/blah.gif>
		s/src='((http|https):\/\/(\Q$host\E|\Q$althost\E)[^']*)'/src='$linkurl$1'/gi;
		s/src="((http|https):\/\/(\Q$host\E|\Q$althost\E)[^"]*)"/src="$linkurl$1"/gi;
		s/src=((http|https):\/\/(\Q$host\E|\Q$althost\E)[^ "'>]*)/src=$linkurl$1/gi;

		# Fix absolute hrefs like <a href=/foo.html>
		s/href='(\/[^']*)'/href='$linkurl$baseurl$1'/gi;
		s/href="(\/[^"]*)"/href="$linkurl$baseurl$1"/gi;
		s/href=(\/[^ "'>]*)/href=$linkurl$baseurl$1/gi;

		# Fix full links to the same domain, like
		# <a href=http://mydomain.com/blah.html>
		s/href='((http|https):\/\/(\Q$host\E|\Q$althost\E)[^']*)'/href='$linkurl$1'/gi;
		s/href="((http|https):\/\/(\Q$host\E|\Q$althost\E)[^"]*)"/href="$linkurl$1"/gi;
		s/href=((http|https):\/\/(\Q$host\E|\Q$althost\E)[^ "'>]*)/href=$linkurl$1/gi;

		# Fix absolute form actions like <form action=/foo>
		s/action='(\/[^']*)'/action='$linkurl$baseurl$1'/gi;
		s/action="(\/[^"]*)"/action="$linkurl$baseurl$1"/gi;
		s/action=(\/[^ "'>]*)/action=$linkurl$baseurl$1/gi;

		# Fix full form form actions
		s/action='((http|https):\/\/(\Q$host\E|\Q$althost\E)[^']*)'/action='$linkurl$1'/gi;
		s/action="((http|https):\/\/(\Q$host\E|\Q$althost\E)[^"]*)"/action="$linkurl$1"/gi;
		s/action=((http|https):\/\/(\Q$host\E|\Q$althost\E)[^ "'>]*)/action=$linkurl$1/gi;

		# Fix CSS imports
		s/\@import '(\/[^']*)'/\@import '$linkurl$baseurl$1'/gi;
		s/\@import "(\/[^']*)"/\@import "$linkurl$baseurl$1"/gi;

		print;
		}
	}
else {
	while($buf = &read_http_connection($con, 1024)) {
		print $buf;
		}
	}
&close_http_connection($con);

