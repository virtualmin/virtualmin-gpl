# Functions for talking to Amazon's S3 service

@s3_perl_modules = ( "S3::AWSAuthConnection", "S3::QueryStringAuthGenerator" );

# check_s3()
# Returns an error message if S3 cannot be used
sub check_s3
{
foreach my $m ("XML::Simple", "Crypt::SSLeay", "Digest::HMAC_SHA1", @s3_perl_modules) {
	eval "use $m";
	if ($@) {
		return &text('s3_emodule', "<tt>$m</tt>");
		}
	}
return undef;
}

# require_s3()
# Load Perl modules needed by S3 (which are included in Virtualmin)
sub require_s3
{
foreach my $m (@s3_perl_modules) {
	eval "use $m";
	die "$@" if ($@);
	}
}

# init_s3_bucket(access-key, secret-key, bucket, attempts, [location])
# Connect to S3 and create a bucket (if needed). Returns undef on success or
# an error message on failure.
sub init_s3_bucket
{
&require_s3();
local ($akey, $skey, $bucket, $tries, $location) = @_;
$tries ||= 1;
my $err;
local $data;
if ($location) {
	$data = "<CreateBucketConfiguration>".
		"<LocationConstraint>".
		$location.
		"</LocationConstraint>".
		"</CreateBucketConfiguration>";
	}
for(my $i=0; $i<$tries; $i++) {
	$err = undef;
	local $conn = &make_s3_connection($akey, $skey);
	if (!$conn) {
		$err = $text{'s3_econn'};
		sleep(10);
		next;
		}

	# Check if the bucket already exists, by trying to list it
	local $response = $conn->list_bucket($bucket);
	if ($response->http_response->code == 200) {
		last;
		}

	# Try to fetch my buckets
	local $response = $conn->list_all_my_buckets();
	if ($response->http_response->code != 200) {
		$err = &text('s3_elist', &extract_s3_message($response));
		sleep(10);
		next;
		}

	# Re-open the connection, as sometimes it times out
	$conn = &make_s3_connection($akey, $skey);

	# Check if given bucket is in the list
	local ($got) = grep { $_->{'Name'} eq $bucket } @{$response->entries};
	if (!$got) {
		# Create the bucket
		$response = $conn->create_bucket($bucket, undef, $data);
		if ($response->http_response->code != 200) {
			$err = &text('s3_ecreate',
				     &extract_s3_message($response));
			sleep(10);
			next;
			}
		}
	last;
	}
return $err;
}

sub extract_s3_message
{
local ($response) = @_;
if ($response->body() =~ /<Message>(.*)<\/Message>/i) {
	return $1;
	}
return undef;
}

# s3_upload(access-key, secret-key, bucket, source-file, dest-filename, [&info],
#           [&domains], attempts, [reduced-redundancy])
# Upload some file to S3, and return undef on success or an error message on
# failure. Unfortunately we cannot simply use S3's put method, as it takes
# a scalar for the content, which could be huge.
sub s3_upload
{
local ($akey, $skey, $bucket, $sourcefile, $destfile, $info, $dom, $tries, $rrs) = @_;
$tries ||= 1;
&require_s3();
local @st = stat($sourcefile);
my $can_use_write = &get_webmin_version() >= 1.451;
my $headers = { 'Content-Length' => $st[7] };
if ($rrs) {
	$headers->{'x-amz-storage-class'} = 'REDUCED_REDUNDANCY';
	}

my $err;
my $endpoint = undef;
for(my $i=0; $i<$tries; $i++) {
	local $newendpoint;
	$err = undef;
	local $conn = &make_s3_connection($akey, $skey, $endpoint);
	if (!$conn) {
		$err = $text{'s3_econn'};
		next;
		}
	my $path = $endpoint ? $destfile : "$bucket/$destfile";
	my $authpath = "$bucket/$destfile";

	# Delete any .info or .dom file first, as it will no longer be valid.
	# Only needs to be done the first time.
	if (!$endpoint) {
		$conn->delete($bucket, $destfile.".info");
		$conn->delete($bucket, $destfile.".dom");
		}

	# Use the S3 library to create a request object, but use Webmin's HTTP
	# function to open it.
	local $req = &s3_make_request($conn, $path, "PUT", "dummy",
				      $headers, $authpath);
	local ($host, $port, $page, $ssl) = &parse_http_url($req->uri);
	local $h = &make_http_connection(
		$host, $port, $ssl, $req->method, $page);
	if (!ref($h)) {
		$err = "HTTP connection to ${host}:${port} ".
		       "for $page failed : $h";
		next;
		}
	foreach my $hfn ($req->header_field_names) {
		&write_http_connection($h, $hfn.": ".$req->header($hfn)."\r\n");
		}
	&write_http_connection($h, "\r\n");

	# Send the backup file contents
	local $SIG{'PIPE'} = 'IGNORE';
	local $buf;
	local $writefailed;
	open(BACKUP, $sourcefile);
	while(read(BACKUP, $buf, 1024) > 0) {
		if (!&write_http_connection($h, $buf) && $can_use_write) {
			$writefailed = $!;
			last;
			}
		}
	close(BACKUP);

	# Read back response .. this needs to be our own code, as S3 does
	# some wierd redirects
	local $line = &read_http_connection($h);
	$line =~ s/\r|\n//g;

	# Read the headers
	local %rheader;
	while(1) {
		local $hline = &read_http_connection($h);
		$hline =~ s/\r\n//g;
		$hline =~ /^(\S+):\s+(.*)$/ || last;
		$rheader{lc($1)} = $2;
		}

	# Read the body
	local $out;
	while(defined($buf = &read_http_connection($h, 1024))) {
		$out .= $buf;
		}
	&close_http_connection($out);

	if ($line !~ /^HTTP\/1\..\s+(200|30[0-9])(\s+|$)/) {
		$err = "Upload failed : $line";
		}
	elsif ($1 >= 300 && $1 < 400) {
		# Follow the SOAP redirect
		if ($out =~ /<Endpoint>([^<]+)<\/Endpoint>/) {
			if ($endpoint ne $1) {
				$endpoint = $1;
				$err = "Redirected to $endpoint";
				$newendpoint = 1;
				$i--;	# Doesn't count as a try
				}
			else {
				$err = "Redirected to same endpoint $endpoint";
				}
			}
		else {
			$err = "Missing new endpoint in redirect : ".
				&html_escape($out);
			}
		}
	elsif ($writefailed) {
		$err = "HTTP transfer failed : $writefailed";
		}

	if (!$err && $info) {
		# Write out the info file, if given
		local $iconn = &make_s3_connection($akey, $skey);
		local $response = $iconn->put($bucket, $destfile.".info",
					     &serialise_variable($info));
		if ($response->http_response->code != 200) {
			$err = &text('s3_einfo',
                                     &extract_s3_message($response));
			}
		}
	if (!$err && $dom) {
		# Write out the .dom file, if given
		local $iconn = &make_s3_connection($akey, $skey);
		local $response = $iconn->put($bucket, $destfile.".dom",
		     &serialise_variable(&clean_domain_passwords($dom)));
		if ($response->http_response->code != 200) {
			$err = &text('s3_edom',
                                     &extract_s3_message($response));
			}
		}
	if ($err) {
		# Wait a little before re-trying
		sleep(10) if (!$newendpoint);
		}
	else {
		# Worked .. end of the job
		last;
		}
	}

# If it worked, save the info file too
if (!$err && $info) {
	local $itemp = &transname();
	&open_tempfile(ITEMP, ">$itemp", 0, 1);
	&print_tempfile(ITEMP, &serialise_variable($info));
	&close_tempfile(ITEMP);
	$err = &s3_upload($akey, $skey, $bucket, $itemp,
			  $destfile.".info", undef, $tries, $rrs);
	}

return $err;
}

# s3_list_backups(access-key, secret-key, bucket, [file])
# Returns a hash reference from domain names to lists of features, or an error
# message string on failure.
sub s3_list_backups
{
local ($akey, $skey, $bucket, $path) = @_;
&require_s3();
local $conn = &make_s3_connection($akey, $skey);
return $text{'s3_econn'} if (!$conn);

local $response = $conn->list_bucket($bucket);
if ($response->http_response->code != 200) {
	return &text('s3_elist2', &extract_s3_message($response));
	}
local $rv = { };
foreach my $f (@{$response->entries}) {
	if ($f->{'Key'} =~ /^(\S+)\.info$/ && (!$path || $path eq $1) ||
	    $f->{'Key'} =~ /^((\S+)\/([^\/]+))\.info$/ && $path && $path eq $2){
		# Found a valid info file .. get it
		local $bfile = $1;
		local ($bentry) = grep { $_->{'Key'} eq $bfile }
				  @{$response->entries};
		next if (!$bentry);	# No actual backup file found!
		local $gresponse = $conn->get($bucket, $f->{'Key'});
		if ($gresponse->http_response->code == 200) {
			local $info = &unserialise_variable(
				$gresponse->object->data);
			foreach my $dname (keys %$info) {
				$rv->{$dname} = {
					'file' => $bfile,
					'features' => $info->{$dname},
					};
				}
			}
		}
	}
return $rv;
}

# s3_list_domains(access-key, secret-key, bucket, [file])
# Returns a hash reference from domain names to domain hashes, or an error
# message string on failure.
sub s3_list_domains
{
local ($akey, $skey, $bucket, $path) = @_;
&require_s3();
local $conn = &make_s3_connection($akey, $skey);
return $text{'s3_econn'} if (!$conn);

local $response = $conn->list_bucket($bucket);
if ($response->http_response->code != 200) {
	return &text('s3_elist2', &extract_s3_message($response));
	}
local $rv = { };
foreach my $f (@{$response->entries}) {
	if ($f->{'Key'} =~ /^(\S+)\.dom$/ && (!$path || $path eq $1) ||
	    $f->{'Key'} =~ /^((\S+)\/([^\/]+))\.dom$/ && $path && $path eq $2){
		# Found a valid .dom file .. get it
		local $bfile = $1;
		local ($bentry) = grep { $_->{'Key'} eq $bfile }
				  @{$response->entries};
		next if (!$bentry);	# No actual backup file found!
		local $gresponse = $conn->get($bucket, $f->{'Key'});
		if ($gresponse->http_response->code == 200) {
			local $dom = &unserialise_variable(
				$gresponse->object->data);
			foreach my $dname (keys %$dom) {
				$rv->{$dname} = $dom->{$dname};
				}
			}
		}
	}
return $rv;
}

# s3_list_buckets(access-key, secret-key)
# Returns an array ref of all buckets under some account, or an error message.
# Each is a hash ref with keys 'Name' and 'CreationDate'
sub s3_list_buckets
{
&require_s3();
local ($akey, $skey, $bucket) = @_;
local $conn = &make_s3_connection($akey, $skey);
return $text{'s3_econn'} if (!$conn);
local $response = $conn->list_all_my_buckets();
if ($response->http_response->code != 200) {
	return &text('s3_elist', &extract_s3_message($response));
	}
return $response->entries;
}

# s3_get_bucket(access-key, secret-key, bucket)
# Returns a hash ref with details of a bucket. Keys are :
# location - A location like us-west-1, if any is set
sub s3_get_bucket
{
&require_s3();
local ($akey, $skey, $bucket) = @_;
local %rv;
local $conn = &make_s3_connection($akey, $skey);
local $response = $conn->get_bucket_location($bucket);
if ($response->http_response->code == 200) {
	$rv{'location'} = $response->{'LocationConstraint'};
	}
$response = $conn->get_bucket_logging($bucket);
if ($response->http_response->code == 200) {
	$rv{'logging'} = $response->{'BucketLoggingStatus'};
	}
$response = $conn->get_bucket_acl($bucket);
if ($response->http_response->code == 200) {
	$rv{'acl'} = $response->{'AccessControlPolicy'};
	}
return \%rv;
}

# s3_list_files(access-key, secret-key, bucket)
# Returns a list of all files in an S3 bucket as an array ref, or an error
# message string. Each is a hash ref with keys like 'Key', 'Size', 'Owner'
# and 'LastModified'
sub s3_list_files
{
local ($akey, $skey, $bucket) = @_;
&require_s3();
local $conn = &make_s3_connection($akey, $skey);
return $text{'s3_econn'} if (!$conn);
local $response = $conn->list_bucket($bucket);
if ($response->http_response->code != 200) {
	return &text('s3_elistfiles', &extract_s3_message($response));
	}
return $response->entries;
}

# s3_delete_file(access-key, secret-key, bucket, file)
# Delete one file from an S3 bucket
sub s3_delete_file
{
local ($akey, $skey, $bucket, $file) = @_;
&require_s3();
local $conn = &make_s3_connection($akey, $skey);
return $text{'s3_econn'} if (!$conn);
local $response = $conn->delete($bucket, $file);
if ($response->http_response->code < 200 ||
    $response->http_response->code >= 300) {
        return &text('s3_edeletefile', &extract_s3_message($response));
        }
return undef;
}

# s3_parse_date(string)
# Converts an S3 date string like 2007-09-30T05:58:39.000Z into a Unix time
sub s3_parse_date
{
local ($str) = @_;
if ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)\.000Z/) {
	local $rv = eval { timegm($6, $5, $4, $3, $2-1, $1-1900); };
	return $@ ? undef : $rv;
	}
elsif ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/) {
	local $rv = eval { timelocal($6, $5, $4, $3, $2-1, $1-1900); };
	return $@ ? undef : $rv;
	}
return undef;
}

# s3_delete_bucket(access-key, secret-key, bucket, [bucket-only])
# Deletes an S3 bucket and all contents
sub s3_delete_bucket
{
local ($akey, $skey, $bucket, $norecursive) = @_;
&require_s3();
local $conn = &make_s3_connection($akey, $skey);
return $text{'s3_econn'} if (!$conn);

if (!$norecursive) {
	# Get and delete files first
	local $files = &s3_list_files($akey, $skey, $bucket);
	return $files if (!ref($files));
	foreach my $f (@$files) {
		local $err = &s3_delete_file($akey, $skey,
					     $bucket, $f->{'Key'});
		return $err if ($err);
		}
	}

local $response = $conn->delete_bucket($bucket);
if ($response->http_response->code < 200 ||
    $response->http_response->code >= 300) {
        return &text('s3_edelete', &extract_s3_message($response));
        }
return undef;
}

# s3_download(access-key, secret-key, bucket, file, destfile)
# Download some file for S3 into the given destination file. Returns undef on
# success or an error message on failure.
sub s3_download
{
local ($akey, $skey, $bucket, $file, $destfile, $tries) = @_;
$tries ||= 1;
&require_s3();

my $err;
my $endpoint = undef;
for(my $i=0; $i<$tries; $i++) {
	local $newendpoint;
	$err = undef;

	# Connect to S3
	local $conn = &make_s3_connection($akey, $skey, $endpoint);
	if (!$conn) {
		$err = $text{'s3_econn'};
		next;
		}

	# Use the S3 library to create a request object, but use Webmin's HTTP
	# function to open it.
	my $path = $endpoint ? $file : "$bucket/$file";
	my $authpath = "$bucket/$file";
	local $req = &s3_make_request($conn, $path, "GET", "dummy",
				      undef, $authpath);
	local ($host, $port, $page, $ssl) = &parse_http_url($req->uri);
	local $h = &make_http_connection(
		$host, $port, $ssl, $req->method, $page);
	local @st = stat($sourcefile);
	foreach my $hfn ($req->header_field_names) {
		&write_http_connection($h, $hfn.": ".$req->header($hfn)."\r\n");
		}
	&write_http_connection($h, "\r\n");

	# Read back response .. this needs to be our own code, as S3 does
	# some wierd redirects
	local $line = &read_http_connection($h);
	$line =~ s/\r|\n//g;

	# Read the headers
	local %rheader;
	while(1) {
		local $hline = &read_http_connection($h);
		$hline =~ s/\r\n//g;
		$hline =~ /^(\S+):\s+(.*)$/ || last;
		$rheader{lc($1)} = $2;
		}

	if ($line !~ /^HTTP\/1\..\s+(200|30[0-9])(\s+|$)/) {
		$err = "Download failed : $line";
		}
	elsif ($1 >= 300 && $1 < 400) {
		# Read the body for the redirect
		local $out;
		while(defined($buf = &read_http_connection($h, 1024))) {
			$out .= $buf;
			}
		if ($out =~ /<Endpoint>([^<]+)<\/Endpoint>/) {
			if ($endpoint ne $1) {
				$endpoint = $1;
				$err = "Redirected to $endpoint";
				$newendpoint = 1;
				$i--;	# Doesn't count as a try
				}
			else {
				$err = "Redirected to same endpoint $endpoint";
				}
			}
		else {
			$err = "Missing new endpoint in redirect : ".
				&html_escape($out);
			}
		}
	else {
		# Read the actual data to the file
		&open_tempfile(S3SAVE, ">$destfile");
		while(defined($buf = &read_http_connection($h, 1024))) {
			&print_tempfile(S3SAVE, $buf);
			}
		&close_tempfile(S3SAVE);
		}
	&close_http_connection($h);

	if ($err) {
		# Wait a little before re-trying
		sleep(10) if (!$newendpoint);
		}
	else {
		# Worked .. end of the job
		last;
		}
	}

return $err;
}

# s3_make_request(conn, path, method, data, [&headers], [authpath])
# Create a HTTP::Request object for talking to S3, 
sub s3_make_request
{
local ($conn, $path, $method, $data, $headers, $authpath) = @_;
my $object = S3::S3Object->new($data);
$headers ||= { };
$authpath ||= $path;
my $metadata = $object->metadata;
my $merged = S3::merge_meta($headers, $metadata);
$conn->_add_auth_header($merged, $method, $authpath);
my $protocol = $conn->{IS_SECURE} ? 'https' : 'http';
my $url = "$protocol://$conn->{SERVER}:$conn->{PORT}/$path";

my @http_headers;
foreach my $h ($merged->header_field_names()) {
	push(@http_headers, lc($h), $merged->header($h));
	}
local $req = HTTP::Request->new($method, $url, \@http_headers);
$req->content($object->data);
return $req;
}

# make_s3_connection(access-key, secret-key, [endpoint])
# Returns an S3::AWSAuthConnection connection object
sub make_s3_connection
{
local ($akey, $skey, $endpoint) = @_;
$endpoint ||= $config{'s3_endpoint'};
&require_s3();
return S3::AWSAuthConnection->new($akey, $skey, undef, $endpoint);
}

1;

