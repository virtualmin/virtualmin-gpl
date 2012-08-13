# Functions for accessing the Rackspace cloud files API

# rs_connect(url, user, key)
# Connect to rackspace and get an authentication token. Returns a hash ref for
# a connection handle on success, or an error message on failure.
sub rs_connect
{
my ($url, $user, $key) = @_;
my ($host, $port, $page, $ssl) = &parse_http_url($url);
$host || return "Invalid URL : $url";
my $apiver;
if ($url =~ /(v[0-9\.]+)$/) {
	$apiver = $1;
	}
else {
	return "URL does not end with an API version : $url";
	}
my ($out, $err);
my $headers = { 'X-Auth-User' => $user,
		'X-Auth-Key' => $key };
$rs_headers = undef;
&http_download($host, $port, $page, \$out, \$error,
	       \&rs_capture_headers_callback, $ssl, undef, undef, 30, 0, 1,
	       $headers);
return "Authentication at $url failed : $error" if ($error);
if (!$rs_headers->{'x-auth-token'}) {
	return "No authentication token received : $out";
	}
my $h = { 'url' => $url,
	  'storage-url' => $rs_headers->{'x-storage-url'},
	  'cdn-url' => $rs_headers->{'x-cdn-management-url'},
	  'token' => $rs_headers->{'x-auth-token'},
	  'user' => $user,
	  'key' => $key,
	  'api' => $apiver,
	};
return $h;
}

# rs_list_containers(&handle)
# Returns a list of containers owned by the user, as an array ref. On error 
# returns the error message string
sub rs_list_containers
{
my ($h) = @_;
my ($ok, $out, $headers) = &rs_api_call($h, "", "GET");
return $out if (!$ok);
return [ split(/\r?\n/, $out) ];
}

# rs_create_container(&handle, container)
# Creates a container with the given name. Returns undef on success, or an
# error message on failure.
sub rs_create_container
{
my ($h, $container) = @_;
}

# rs_stat_container(&handle, container)
# Returns a hash ref with metadata information about some container, or an error
# message on failure. Available keys are like :
# X-Container-Object-Count: 7
# X-Container-Bytes-Used: 413
# X-Container-Meta-InspectedBy: JackWolf
sub rs_stat_container
{
my ($h, $container) = @_;
}

# rs_delete_container(&handle, container)
# Deletes some container from rackspace. Returns an error message on failure, or
# undef on success
sub rs_delete_container
{
my ($h, $container) = @_;
}

# rs_list_objects(&handle, container)
# Returns a list of object filenames in some container, as an array ref. On 
# error returns the error message string
sub rs_list_objects
{
my ($h, $container) = @_;
}

# rs_upload_object(&handle, container, file, source-file)
# Uploads the contents of some local file to rackspace. Returns undef on success
# or an error message string if something goes wrong
sub rs_upload_object
{
my ($h, $container, $file, $src) = @_;
}

# rs_download_object(&handle, container, file, dest-file)
# Downloads the contents of rackspace file to local. Returns undef on success
# or an error message string if something goes wrong
sub rs_download_object
{
my ($h, $container, $file, $dst) = @_;
}

# rs_stat_object(&handle, container, file)
# Returns a hash ref with metadata information about some object, or an error
# message on failure. Available keys are like :
# Last-Modified: Fri, 12 Jun 2007 13:40:18 GMT
# ETag: 8a964ee2a5e88be344f36c22562a6486
# Content-Length: 512000
# Content-Type: text/plain; charset=UTF-8
# X-Object-Meta-Meat: Bacon
sub rs_stat_object
{
my ($h, $container, $file) = @_;
}

# rs_delete_object(&handle, container, file)
# Deletes some file from a container. Returns an error message on failure, or
# undef on success
sub rs_delete_object
{
my ($h, $container, $file) = @_;
}

# rs_capture_headers_callback(mode)
# For passing to http_download to get back headers
sub rs_capture_headers_callback
{
my ($mode) = @_;
if ($mode == 2) {
	$rs_headers = $WebminCore::header;
	}
}

# rs_api_call(&handle, path, method, &headers)
# Calls the rackspace API, and returns an OK flag, response body or error
# message, and HTTP headers.
sub rs_api_call
{
my ($h, $path, $method, $headers) = @_;
my ($host, $port, $page, $ssl) = &parse_http_url($h->{'storage-url'});
my $sendheaders = $headers ? { %$headers } : { };
$sendheaders->{'X-Auth-Token'} = $h->{'token'};
return &rs_http_call($h->{'storage-url'}.$path, $method, $sendheaders);
}

# rs_http_call(url, method, &headers)
# Makes an HTTP call and returns an OK flag, response body or error
# message, and HTTP headers.
sub rs_http_call
{
my ($url, $method, $headers) = @_;
my ($host, $port, $page, $ssl) = &parse_http_url($url);

# Build headers
my @headers;
push(@headers, [ "Host", $host ]);
push(@headers, [ "User-agent", "Webmin" ]);
push(@headers, [ "Accept-language", "en" ]);
foreach my $hname (keys %$headers) {
	push(@headers, [ $hname, $headers->{$hname} ]);
	}

# Actually download it
$main::download_timed_out = undef;
local $SIG{ALRM} = \&download_timeout;
alarm(60);
my $h = &make_http_connection($host, $port, $ssl, $method, $page, \@headers);
alarm(0);
$h = $main::download_timed_out if ($main::download_timed_out);
if (!ref($h)) {
	return (0, $error);
	}

# XXX doesn't handle 204 status
my ($out, $error);
&complete_http_download($h, \$out, \$error, \&rs_capture_headers_callback,
			0, $host, $port, $headers, $ssl, 1);
return (1, $out, $rs_headers);
}

1;

