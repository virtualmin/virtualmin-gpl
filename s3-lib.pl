# Functions for talking to Amazon's S3 service

@s3_perl_modules = ( "S3::AWSAuthConnection", "S3::QueryStringAuthGenerator" );

# check_s3()
# Returns an error message if S3 cannot be used
sub check_s3
{
foreach my $m ("XML::Simple", "Crypt::SSLeay", @s3_perl_modules) {
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
	die $@ if ($@);
	}
}

# init_s3_bucket(access-key, secret-key, bucket)
# Connect to S3 and create a bucket (if needed). Returns undef on success or
# an error message on failure.
sub init_s3_bucket
{
&require_s3();
local ($akey, $skey, $bucket) = @_;
local $conn = S3::AWSAuthConnection->new($akey, $skey);
return $text{'s3_econn'} if (!$conn);
local $response = $conn->list_all_my_buckets();
if ($response->http_response->code != 200) {
	return &text('s3_elist', &extract_s3_message($response));
	}
local ($got) = grep { $_->{'Name'} eq $bucket } @{$response->entries};
if (!$got) {
	# Create the bucket
	$response = $conn->create_bucket($bucket);
	if ($response->http_response->code != 200) {
		return &text('s3_ecreate', &extract_s3_message($response));
		}
	}
return undef;
}

sub extract_s3_message
{
local ($response) = @_;
if ($response->body() =~ /<Message>(.*)<\/Message>/i) {
	return $1;
	}
return undef;
}

# s3_upload(access-key, secret-key, bucket, source-file, dest-filename, [&info])
# Upload some file to S3, and return undef on success or an error message on
# failure. Unfortunately we cannot simply use S3's put method, as it takes
# a scalar for the content, which could be huge.
sub s3_upload
{
local ($akey, $skey, $bucket, $sourcefile, $destfile, $info) = @_;
&require_s3();
local $conn = S3::AWSAuthConnection->new($akey, $skey);
return $text{'s3_econn'} if (!$conn);
local $object = S3::S3Object->new("");

# Delete any .info file first, as it will no longer be valid
$conn->delete($bucket, $destfile.".info");

# Use the S3 library to create a request object, but use Webmin's HTTP
# function to open it.
my $path = "$bucket/$destfile";
local $req = &s3_make_request($conn, $path, "PUT", "dummy");
local ($host, $port, $page, $ssl) = &parse_http_url($req->uri);
local $h = &make_http_connection($host, $port, $ssl, $req->method, $page);
local @st = stat($sourcefile);
&write_http_connection($h, "Content-length: $st[7]\r\n");
foreach my $hfn ($req->header_field_names) {
	&write_http_connection($h, $hfn.": ".$req->header($hfn)."\r\n");
	}
&write_http_connection($h, "\r\n");

# Send the backup file contents
local $buf;
open(BACKUP, $sourcefile);
while(read(BACKUP, $buf, 1024) > 0) {
	&write_http_connection($h, $buf);
	}
close(BACKUP);

# Read back response
local ($out, $err);
&complete_http_download($h, \$out, \$err);
&close_http_connection($h);

if (!$err && $info) {
	# Write out the info file, if given
	local $response = $conn->put($bucket, $destfile.".info",
				     &serialise_variable($info));
	if ($response->http_response->code != 200) {
		return &text('s3_einfo', &extract_s3_message($response));
		}
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
local $conn = S3::AWSAuthConnection->new($akey, $skey);
return $text{'s3_econn'} if (!$conn);

local $response = $conn->list_bucket($bucket);
if ($response->http_response->code != 200) {
	return &text('s3_elist2', &extract_s3_message($response));
	}
local $rv = { };
foreach my $f (@{$response->entries}) {
	if ($f->{'Key'} =~ /^(\S+)\.info$/ && (!$path || $path eq $1)) {
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

# s3_list_buckets(access-key, secret-key)
# Returns an array ref of all buckets under some account, or an error message.
# Each is a hash ref with keys 'Name' and 'CreationDate'
sub s3_list_buckets
{
&require_s3();
local ($akey, $skey, $bucket) = @_;
local $conn = S3::AWSAuthConnection->new($akey, $skey);
return $text{'s3_econn'} if (!$conn);
local $response = $conn->list_all_my_buckets();
if ($response->http_response->code != 200) {
	return &text('s3_elist', &extract_s3_message($response));
	}
return $response->entries;
}

# s3_list_files(access-key, secret-key, bucket)
# Returns a list of all files in an S3 bucket as an array ref, or an error
# message string. Each is a hash ref with keys like 'Key', 'Size', 'Owner'
# and 'LastModified'
sub s3_list_files
{
local ($akey, $skey, $bucket) = @_;
&require_s3();
local $conn = S3::AWSAuthConnection->new($akey, $skey);
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
local $conn = S3::AWSAuthConnection->new($akey, $skey);
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
if ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/) {
	local $rv = eval { timelocal($6, $5, $4, $3, $2-1, $1-1900); };
	return $@ ? undef : $rv;
	}
return undef;
}

# s3_delete_bucket(access-key, secret-key, bucket)
# Deletes an S3 bucket and all contents
sub s3_delete_bucket
{
local ($akey, $skey, $bucket) = @_;
&require_s3();
local $conn = S3::AWSAuthConnection->new($akey, $skey);
return $text{'s3_econn'} if (!$conn);

# Get and delete files first
local $files = &s3_list_files($akey, $skey, $bucket);
return $files if (!ref($files));
foreach my $f (@$files) {
	local $err = &s3_delete_file($akey, $skey, $bucket, $f->{'Key'});
	return $err if ($err);
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
local ($akey, $skey, $bucket, $file, $destfile) = @_;
&require_s3();
local $conn = S3::AWSAuthConnection->new($akey, $skey);
return $text{'s3_econn'} if (!$conn);

# Use the S3 library to create a request object, but use Webmin's HTTP
# function to open it.
my $path = "$bucket/$file";
local $req = &s3_make_request($conn, $path, "GET", "");
local ($host, $port, $page, $ssl) = &parse_http_url($req->uri);
local $h = &make_http_connection($host, $port, $ssl, $req->method, $page);
local @st = stat($sourcefile);
foreach my $hfn ($req->header_field_names) {
	&write_http_connection($h, $hfn.": ".$req->header($hfn)."\r\n");
	}
&write_http_connection($h, "\r\n");

# Read back response
local ($out, $err);
&complete_http_download($h, $destfile, \$err);
&close_http_connection($h);

return $err;
}

# s3_make_request(conn, path, method, data)
# Create a HTTP::Request object for talking to S3, 
sub s3_make_request
{
local ($conn, $path, $method, $data) = @_;
my $object = S3::S3Object->new($data);
my $headers = { };
my $metadata = $object->metadata;
my $http_headers = $conn->merge_meta($headers, $metadata);
$conn->_add_auth_header($http_headers, $method, $path);
my $protocol = $conn->{IS_SECURE} ? 'https' : 'http';
my $url = "$protocol://$conn->{SERVER}:$conn->{PORT}/$path";

local $req = HTTP::Request->new($method, $url, $http_headers);
$req->content($object->data);
return $req;
}

1;

