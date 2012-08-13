# Functions for accessing the Rackspace cloud files API

# rs_connect(url, user, key)
# Connect to rackspace and get an authentication token. Returns a hash ref for
# a connection handle on success, or an error message on failure.
sub rs_connect
{
my ($url, $user, $key) = @_;
}

# rs_list_containers(&handle)
# Returns a list of containers owned by the user, as an array ref. On error 
# returns the error message string
sub rs_list_containers
{
my ($h) = @_;
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

1;

