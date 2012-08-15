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
my $headers = { 'X-Auth-User' => $user,
		'X-Auth-Key' => $key };
my ($ok, $out, $rs_headers) = &rs_http_call($url, "GET", $headers);
return "Authentication at $url failed : $out" if (!$ok);
if (!$rs_headers->{'X-Auth-Token'}) {
	return "No authentication token received : $out";
	}
my $h = { 'url' => $url,
	  'storage-url' => $rs_headers->{'X-Storage-Url'},
	  'cdn-url' => $rs_headers->{'X-Cdn-Management-Url'},
	  'token' => $rs_headers->{'X-Auth-Token'},
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
# XXX
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
my ($ok, $out, $headers) = &rs_api_call($h, "/$container", "HEAD");
return $out if (!$ok);
return $headers;
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
my ($ok, $out, $headers) = &rs_api_call($h, "/$container", "GET");
return $out if (!$ok);
return [ split(/\r?\n/, $out) ];
}

# rs_upload_object(&handle, container, file, source-file)
# Uploads the contents of some local file to rackspace. Returns undef on success
# or an error message string if something goes wrong
sub rs_upload_object
{
my ($h, $container, $file, $src) = @_;
# XXX large files
my ($ok, $out) = &rs_api_call($h, "/$container/$file", "PUT",
			      undef, undef, $src);
return $ok ? undef : $out;
}

# rs_download_object(&handle, container, file, dest-file)
# Downloads the contents of rackspace file to local. Returns undef on success
# or an error message string if something goes wrong
sub rs_download_object
{
my ($h, $container, $file, $dst) = @_;
my ($ok, $out) = &rs_api_call($h, "/$container/$file", "GET",
			      undef, $dst);
return $ok ? undef : $out;
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
my ($ok, $out, $headers) = &rs_api_call($h, "/$container/$file", "HEAD");
return $out if (!$ok);
return $headers;
}

# rs_delete_object(&handle, container, file)
# Deletes some file from a container. Returns an error message on failure, or
# undef on success
sub rs_delete_object
{
my ($h, $container, $file) = @_;
}

# rs_api_call(&handle, path, method, &headers, [save-to-file], [read-from-file])
# Calls the rackspace API, and returns an OK flag, response body or error
# message, and HTTP headers.
sub rs_api_call
{
my ($h, $path, $method, $headers, $dstfile, $srcfile) = @_;
my ($host, $port, $page, $ssl) = &parse_http_url($h->{'storage-url'});
my $sendheaders = $headers ? { %$headers } : { };
$sendheaders->{'X-Auth-Token'} = $h->{'token'};
return &rs_http_call($h->{'storage-url'}.$path, $method, $sendheaders,
		     $dstfile, $srcfile);
}

# rs_http_call(url, method, &headers, [save-to-file], [read-from-file])
# Makes an HTTP call and returns an OK flag, response body or error
# message, and HTTP headers.
sub rs_http_call
{
my ($url, $method, $headers, $dstfile, $srcfile) = @_;
my ($host, $port, $page, $ssl) = &parse_http_url($url);
!$srcfile || -r $srcfile || return (0, "Source file $srcfile does not exist");

# Build headers
my @headers;
push(@headers, [ "Host", $host ]);
push(@headers, [ "User-agent", "Webmin" ]);
push(@headers, [ "Accept-language", "en" ]);
foreach my $hname (keys %$headers) {
	push(@headers, [ $hname, $headers->{$hname} ]);
	}
if ($srcfile) {
	my @st = stat($srcfile);
	push(@headers, [ "Content-Length", $st[7] ]);
	}

# Make the HTTP connection
$main::download_timed_out = undef;
local $SIG{ALRM} = \&download_timeout;
alarm(60);
my $h = &make_http_connection($host, $port, $ssl, $method, $page, \@headers);
alarm(0);
$h = $main::download_timed_out if ($main::download_timed_out);
if (!ref($h)) {
	return (0, $error);
	}

if ($srcfile) {
	# Send body contents
	my $buf;
	open(SRCFILE, $srcfile);
	while(read(SRCFILE, $buf, 1024) > 0) {
		&write_http_connection($h, $buf);
		}
	close(SRCFILE);
	}

my ($out, $error);

# Read headers
alarm(60);
my $line;
($line = &read_http_connection($h)) =~ tr/\r\n//d;
if ($line !~ /^HTTP\/1\..\s+(20[0-9])(\s+|$)/) {
	alarm(0);
	return (0, "Invalid HTTP response : $line");
	}
my $rcode = $1;
my %header;
while(1) {
	$line = &read_http_connection($h);
	$line =~ tr/\r\n//d;
	$line =~ /^(\S+):\s+(.*)$/ || last;
	$header{$1} = $2;
	}
alarm(0);
if ($main::download_timed_out) {
	return (0, $main::download_timed_out);
	}

# Read data
my $out;
if (!$dstfile) {
	# Append to a variable
	while(defined($buf = &read_http_connection($h, 1024))) {
		$out .= $buf;
		}
	}
else {
	# Write to a file
	my $got = 0;
	if (!&open_tempfile(PFILE, ">$dstfile", 1)) {
		return (0, "Failed to write to $dstfile : $!");
		}
	binmode(PFILE);		# For windows
	while(defined($buf = &read_http_connection($h, 1024))) {
		&print_tempfile(PFILE, $buf);
		$got += length($buf);
		}
	&close_tempfile(PFILE);
	if ($header{'content-length'} &&
	    $got != $header{'content-length'}) {
		return (0, "Download incomplete");
		}
	}
&close_http_connection($h);

return (1, $out, \%header);
}

1;

