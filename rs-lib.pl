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
if ($config{'rs_snet'}) {
	# Storage URL needs to be customized for the internal network
	$h->{'storage-url'} =~ s/^(http|https):\/\//$1:\/\/snet-/;
	}
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
my ($ok, $out, $headers) = &rs_api_call($h, "/$container", "PUT");
return $ok ? undef : $out;
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

# rs_delete_container(&handle, container, [recursive])
# Deletes some container from rackspace. Returns an error message on failure, or
# undef on success
sub rs_delete_container
{
my ($h, $container, $recursive) = @_;
if ($recursive) {
	my $files = &rs_list_objects($h, $container);
	return $files if (!ref($files));
	foreach my $f (@$files) {
		my $err = &rs_delete_object($h, $container, $f);
		return "$f : $err" if ($err);
		}
	}
my ($ok, $out, $headers) = &rs_api_call($h, "/$container", "DELETE");
return $ok ? undef : $out;
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

# rs_upload_object(&handle, container, file, source-file, [multipart],
# 		   [force-chunk-size])
# Uploads the contents of some local file to rackspace. Returns undef on success
# or an error message string if something goes wrong
sub rs_upload_object
{
my ($h, $container, $file, $src, $multipart, $chunk) = @_;
my $def_rs_chunk_size = $config{'rs_chunk'}*1024*10234 || 200*1024*1024;# 200 MB
$chunk ||= $def_rs_chunk_size;
my @st = stat($src);
@st || return "File $src does not exist";
if ($st[7] >= 2*1024*1024*1024 || $multipart) {
	# Large files have to be uploaded in parts
	my $pos = 0;
	my $pinheaders = { 'X-Object-Meta-PIN' => int(rand()*10000) };
	my $n = "00000000";
	while($pos < $st[7]) {
		# Upload a chunk
		my $want = $st[7] - $pos;
		if ($want > $chunk) {
			$want = $chunk;
			}
		my ($ok, $out);
		for(my $try=0; $try<3; $try++) {
			($ok, $out) = &rs_api_call($h, "/$container/$file.$n",
					"PUT", $pinheaders, undef, $src,
					$pos, $want);
			last if ($ok);
			}
		if (!$ok) {
			close(CHUNK);
			return "Upload failed at $pos : $out";
			}
		$pos += $want;
		$n++;
		}
	close(CHUNK);

	# Finally upload the manifest
	$pinheaders->{'X-Object-Manifest'} = "$container/$file";
	my ($ok, $out) = &rs_api_call($h, "/$container/$file", "PUT",
                                      $pinheaders, undef, "");
	return $ok ? undef : "Manifest upload filed : $out";
	}
else {
	# Can upload in a single API call
	my ($ok, $out) = &rs_api_call($h, "/$container/$file", "PUT",
				      undef, undef, $src);
	return $ok ? undef : $out;
	}
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
my $st = &rs_stat_object($h, $container, $file);
if (ref($st) && $st->{'X-Object-Manifest'}) {
	# Looks multi-part .. delete the parts first
	my ($mcontainer, $mprefix) = split(/\//, $st->{'X-Object-Manifest'});
	if ($mprefix !~ /\S/ || $mcontainer !~ /\S/) {
		return "X-Object-Manifest header on file $file does not ".
		       "contain a prefix : $st->{'X-Object-Manifest'}";
		}
	my $files = &rs_list_objects($h, $mcontainer);
	return "Failed to find parts : $files" if (!ref($files));
	foreach my $f (@$files) {
		if ($f =~ /^\Q$mprefix\E/ && $f ne $file) {
			my ($ok, $out) = &rs_api_call($h, "/$mcontainer/$f",
						      "DELETE");
			return "Failed to delete part $f : $out" if (!$ok);
			}
		}
	}
my ($ok, $out) = &rs_api_call($h, "/$container/$file", "DELETE");
return $ok ? undef : $out;
}

# rs_api_call(&handle, path, method, &headers, [save-to-file],
# 	      [read-from-file|data], [file-offset], [file-length])
# Calls the rackspace API, and returns an OK flag, response body or error
# message, and HTTP headers.
sub rs_api_call
{
my ($h, $path, $method, $headers, $dstfile, $srcfile, $offset, $length) = @_;
my ($host, $port, $page, $ssl) = &parse_http_url($h->{'storage-url'});
my $sendheaders = $headers ? { %$headers } : { };
$sendheaders->{'X-Auth-Token'} = $h->{'token'};
return &rs_http_call($h->{'storage-url'}.$path, $method, $sendheaders,
		     $dstfile, $srcfile, $offset, $length);
}

# rs_http_call(url, method, &headers, [save-to-file], [read-from-file|data],
# 	       [file-offset], [file-length])
# Makes an HTTP call and returns an OK flag, response body or error
# message, and HTTP headers.
sub rs_http_call
{
my ($url, $method, $headers, $dstfile, $srcfile, $offset, $length) = @_;
my ($host, $port, $page, $ssl) = &parse_http_url($url);

# Build headers
my @headers;
push(@headers, [ "Host", $host ]);
push(@headers, [ "User-agent", "Webmin" ]);
push(@headers, [ "Accept-language", "en" ]);
foreach my $hname (keys %$headers) {
	push(@headers, [ $hname, $headers->{$hname} ]);
	}
if ($srcfile =~ /^\// && -r $srcfile) {
	if ($length) {
		push(@headers, [ "Content-Length", $length ]);
		}
	else {
		my @st = stat($srcfile);
		push(@headers, [ "Content-Length", $st[7] ]);
		}
	}
elsif (defined($srcfile)) {
	push(@headers, [ "Content-Length", length($srcfile) ]);
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

if ($srcfile =~ /^\// && -r $srcfile) {
	# Send body contents from file
	my $buf;
	open(SRCFILE, $srcfile);
	if ($offset) {
		# Seek to some position
		seek(SRCFILE, $offset, 0);
		}
	if ($length) {
		# Only copy length bytes
		my $want = $length;
		while($want) {
			my $readlen = $want;
			if ($readlen > 1024*1024) {
				$readlen = 1024*1024;
				}
			my $got = read(SRCFILE, $buf, $readlen);
			&write_http_connection($h, $buf);
			$want -= $got;
			}
		}
	else {
		# Copy till the end of the file
		while(read(SRCFILE, $buf, 1024) > 0) {
			&write_http_connection($h, $buf);
			}
		}
	close(SRCFILE);
	}
elsif (defined($srcfile)) {
	# Send body contents from string
	&write_http_connection($h, $srcfile);
	}

my ($out, $error);

# Read headers
alarm(60);
my $line;
($line = &read_http_connection($h)) =~ tr/\r\n//d;
if ($line !~ /^HTTP\/1\..\s+(20[0-9])(\s+|$)/) {
	alarm(0);
	return (0, $line ? "Invalid HTTP response : $line"
			 : "Empty HTTP response");
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

