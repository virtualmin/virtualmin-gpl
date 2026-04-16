#!/usr/local/bin/perl
#
# login_phpmyadmin.cgi
#
# Auto-login to phpMyAdmin for a Virtualmin domain without changing any
# phpMyAdmin configuration.

require './virtual-server-lib.pl';
&ReadParse();

# Get domain and check permissions
my $d = &get_domain($in{'dom'});
&domain_has_website($d) && $d->{'dir'} ||
	&error($text{'databases_login_pma_eweb'});
&can_edit_databases($d) || &error($text{'databases_ecannot'});

# Find phpMyAdmin installation details for this domain or its subdomains
my @phpmyadmin = grep { $_->{'name'} eq 'phpmyadmin' } &list_domain_scripts($d);

# Perhaps a subdomain has it installed?
if (!@phpmyadmin && $d->{'parent'}) {
	$d = &get_domain($d->{'parent'});
	@phpmyadmin = grep { $_->{'name'} eq 'phpmyadmin' }
		&list_domain_scripts($d);
	}

# Perhaps global is available?
my $src_dom = $d;
if (!@phpmyadmin) {
	my @all_glob = &list_all_global_def_scripts_cached();
	@phpmyadmin = grep { $_->{'name'} eq 'phpmyadmin' } @all_glob;
	$src_dom = &get_domain($phpmyadmin[0]->{'dom_id'}) if (@phpmyadmin);
	}
@phpmyadmin || &error($text{'databases_login_pma_enopma'});
@phpmyadmin = sort { ($b->{'time'} || 0) <=> ($a->{'time'} || 0) } @phpmyadmin;
my $pma = $phpmyadmin[0];
my $pma_dir = $pma->{'opts'}->{'dir'} ||
	&error($text{'databases_login_pma_einfo'});
$pma_dir =~ /^\// || &error($text{'databases_login_pma_einfo'});

# Use the recorded canonical URL for this install
my $pma_url = $pma->{'url'} || &error($text{'databases_login_pma_eurl'});
$pma_url =~ /^https?:\/\/.+/ || &error($text{'databases_login_pma_badurl'});
$pma_url =~ s/\s+//g;
$pma_url =~ s/\/+$/\//;

# Require HTTPS by upgrading if possible, otherwise refuse to send credentials
if ($pma_url =~ /^http:\/\//) {
	if (&domain_has_ssl($src_dom)) {
		$pma_url =~ s/^http:/https:/;
		}
	else {
		&error($text{'databases_login_pma_enossl'});
		}
	}

# Domain MySQL credentials always come from the parent domain unless already
$d = &get_domain($d->{'parent'}) if ($d->{'parent'});
my $dbuser = $d->{'mysql_user'} || &error($text{'databases_login_pma_euser'});
my $dbpass = $d->{'mysql_pass'} || &error($text{'databases_login_pma_epass'});

# Optional database to open after login
my $dbname = $in{'dbname'} || '';
if ($dbname) {
	$dbname =~ /^[A-Za-z0-9_.-]+$/ ||
		&error(&text('databases_login_pma_baddb', $dbname));
	}

# Private directory under the domain home
my $home = $src_dom->{'home'} || &error($text{'databases_login_pma_ehome'});
$home =~ /^\// || &error($text{'databases_login_pma_ehome'});

my $privdir = "$home/.pma-login";
$privdir =~ s/([^:])\/\//$1\//g;

# Random helper filename and one-shot nonce
my $rid = &substitute_pattern('[a-f0-9]{40}');
my $non = &substitute_pattern('[a-f0-9]{40}');
my $php_filename = "pma-login-$rid.php";
my $php_fullpath = "$pma_dir/$php_filename";
$php_fullpath =~ s/([^:])\/\//$1\//g;
my $credfile = "$privdir/login-phpmyadmin-$rid.cred";
$credfile =~ s/([^:])\/\//$1\//g;

# Create the private directory as the domain user so PHP can traverse it
if (!-d $privdir) {
	&make_dir_as_domain_user($src_dom, $privdir, 0700) ||
		&error(&text('databases_login_pma_emkdirhome', $privdir));
	}

# Store credentials outside the web directory
my $u64 = &encode_base64($dbuser); $u64 =~ s/\s+//g;
my $p64 = &encode_base64($dbpass); $p64 =~ s/\s+//g;

# Write the credential file as the domain user so PHP can read it
eval { &write_as_domain_user($src_dom, sub {
		&write_file_contents($credfile, join("\n",
			"u64=$u64",
			"p64=$p64",
			"db=$dbname",
			"nonce=$non",
			"")."");
		chmod(0600, $credfile);
	});
};
$@ && &error($text{'databases_login_pma_ecredwrite'});

# One-shot PHP helper content
my $php = <<'EOF';
<?php
declare(strict_types=1);

/* Template placeholders */
const NONCE    = '__NONCE__';
const PMAURL   = '__PMAURL__';
const CREDFILE = '__CREDFILE__';

/* Write debug info into the standard PHP error log */
function log_msg(string $msg): void
{
	error_log('Virtualmin phpMyAdmin autologin: '.$msg);
}

/* Log the reason, return a status code, and exit */
function fail(int $code, string $msg): void
{
	log_msg($msg);
	http_response_code($code);
	exit;
}

/* Remove secrets and remove this helper file and its directory if empty */
function cleanup(): void
{
	@unlink(CREDFILE);
	@rmdir(dirname(CREDFILE));

	/* Remove this file and any stale pma-login-*.php helpers left behind
	   by previous runs (e.g. browser closed before cleanup could fire) */
	$dir = dirname(__FILE__);
	foreach (glob($dir.'/pma-login-*.php') ?: [] as $f) {
		@unlink($f);
	}
}

/* Build the phpMyAdmin index URL */
function pma_index_url(): string
{
	return rtrim(PMAURL, '/').'/index.php';
}

/* Pass through browser auth for setups protected by Basic Auth */
function incoming_auth_header(): string
{
	if (!empty($_SERVER['HTTP_AUTHORIZATION'])) {
		return trim((string)$_SERVER['HTTP_AUTHORIZATION']);
	}
	if (!empty($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
		return trim((string)$_SERVER['REDIRECT_HTTP_AUTHORIZATION']);
	}
	if (!empty($_SERVER['PHP_AUTH_USER'])) {
		$user = (string)$_SERVER['PHP_AUTH_USER'];
		$pass = (string)($_SERVER['PHP_AUTH_PW'] ?? '');
		return 'Basic '.base64_encode($user.':'.$pass);
	}
	return '';
}

/* Read key/value credentials from the credential file */
function read_creds(): array
{
	if (!is_file(CREDFILE)) {
		fail(500, 'credfile missing');
	}
	if (!is_readable(CREDFILE)) {
		fail(500, 'credfile not readable');
	}
	$mt = @filemtime(CREDFILE);
	if ($mt === false) {
		fail(500, 'failed to stat credfile');
	}
	if ($mt < time() - 30) {
		@unlink(CREDFILE);
		@rmdir(dirname(CREDFILE));
		fail(410, 'credential file expired');
	}

	$lines = @file(CREDFILE, FILE_IGNORE_NEW_LINES);
	if (!is_array($lines)) {
		fail(500, 'failed to read credfile');
	}
	@unlink(CREDFILE);
	@rmdir(dirname(CREDFILE));

	$vals = [];
	foreach ($lines as $ln) {
		$ln = rtrim($ln, "\r\n");
		$pos = strpos($ln, '=');
		if ($pos === false) {
			continue;
		}

		$key = substr($ln, 0, $pos);
		$val = substr($ln, $pos + 1);

		if ($key === 'u64' || $key === 'p64' ||
		    $key === 'db' || $key === 'nonce') {
			$vals[$key] = $val;
		}
	}

	if (empty($vals['u64']) || empty($vals['p64']) ||
	    empty($vals['nonce'])) {
		fail(500, 'credfile missing keys');
	}

	return $vals;
}

/* Create a cookie jar file for cURL */
function cookiejar_path(): string
{
	$fn = tempnam(sys_get_temp_dir(), 'pma_');
	if ($fn === false) {
		fail(500, 'failed to create temp file');
	}
	return $fn;
}

register_shutdown_function('cleanup');

/* Enforce the one-shot nonce to prevent guessing the helper URL */
$n = (string)($_GET['n'] ?? '');
if ($n === '' || !hash_equals(NONCE, $n)) {
	fail(403, 'bad nonce');
}

$vals = read_creds();

/* The cred file also contains the nonce, so a reused helper URL won't work */
if (!hash_equals($vals['nonce'], NONCE)) {
	fail(403, 'nonce mismatch against credfile');
}

/* Decode credentials derived from a temp file */
$user = base64_decode($vals['u64'], true);
$pass = base64_decode($vals['p64'], true);
if ($user === false || $pass === false) {
	fail(500, 'failed to decode credentials');
}

/* Optional database to open after login */
$db = isset($vals['db']) ? (string)$vals['db'] : '';

/* phpMyAdmin login URL */
$login_idx = pma_index_url();

/* After login, optionally open a database page */
$dest = $login_idx;
if ($db !== '') {
	$dest .= '?route=/database/structure&db='.rawurlencode($db);
}

/* phpMyAdmin login emulation needs cURL */
if (!function_exists('curl_init')) {
	fail(500, 'PHP ext-curl not available');
}

$cookiejar = cookiejar_path();
$auth = incoming_auth_header();
$curl_headers = [];
if ($auth !== '') {
	$curl_headers[] = 'Authorization: '.$auth;
}

/* Remove the cookie jar on exit */
register_shutdown_function(static function () use ($cookiejar): void {
	@unlink($cookiejar);
});

/* Fetch the phpMyAdmin login page so we get cookies and the CSRF token */
$ch = curl_init();
curl_setopt_array($ch, [
	CURLOPT_RETURNTRANSFER => true,
	CURLOPT_HEADER => true,
	CURLOPT_FOLLOWLOCATION => false,
	CURLOPT_COOKIEJAR => $cookiejar,
	CURLOPT_COOKIEFILE => $cookiejar,
	CURLOPT_TIMEOUT => 10,
	/* Loopback request to the same server — skip SSL peer verification
	   to handle self-signed certs or missing CA bundles in PHP */
	CURLOPT_SSL_VERIFYPEER => false,
	CURLOPT_SSL_VERIFYHOST => 0,
]);

curl_setopt($ch, CURLOPT_URL, $login_idx);
curl_setopt($ch, CURLOPT_HTTPGET, true);
if ($curl_headers) {
	curl_setopt($ch, CURLOPT_HTTPHEADER, $curl_headers);
}

$res = curl_exec($ch);
if ($res === false) {
	fail(502, 'GET failed: '.curl_error($ch));
}
$get_code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
if ($get_code === 401) {
	/* Basic Auth is blocking the server-side cURL request.  Fall back to a
	   browser-side login: the browser already holds cached Basic Auth
	   credentials (it needed them to reach this helper file). */
	curl_close($ch);
	log_msg('GET returned 401; falling back to browser-side login');
	header('Content-Type: text/html; charset=UTF-8');
	header('Cache-Control: no-store, no-cache, must-revalidate');
	$j_login = json_encode($login_idx, JSON_HEX_TAG | JSON_HEX_AMP);
	$j_dest  = json_encode($dest, JSON_HEX_TAG | JSON_HEX_AMP);
	$j_user  = json_encode($user, JSON_HEX_TAG | JSON_HEX_AMP);
	$j_pass  = json_encode($pass, JSON_HEX_TAG | JSON_HEX_AMP);
	echo <<<LOGINHTML
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>phpMyAdmin</title></head><body>
<script>
(async function() {
	try {
		const loginUrl = {$j_login},
		      dest     = {$j_dest};
		const resp = await fetch(loginUrl, {credentials: 'same-origin'});
		if (!resp.ok) throw new Error('HTTP ' + resp.status);
		const html = await resp.text(),
		      m = html.match(/name="token"\\s+value="([^"]+)"/);
		if (!m) throw new Error('token not found');
		const ta = document.createElement('textarea');
		ta.innerHTML = m[1];
		const token = ta.value,
		      form = document.createElement('form');
		form.method = 'POST';
		form.action = dest;
		form.style.display = 'none';
		const flds = {pma_username: {$j_user}, pma_password: {$j_pass},
		            server: '1', token: token};
		for (const k in flds) {
			const inp = document.createElement('input');
			inp.type = 'hidden'; inp.name = k; inp.value = flds[k];
			form.appendChild(inp);
		}
		document.body.appendChild(form);
		form.submit();
	} catch (e) {
		document.body.textContent = 'Auto-login failed: ' + e.message;
	}
})();
</script>
<noscript><p>JavaScript is required for phpMyAdmin auto-login.</p></noscript>
</body></html>
LOGINHTML;
	exit;
}
if ($get_code >= 400) {
	fail(502, 'GET blocked before phpMyAdmin login page (auth/proxy?)');
}

$hsz  = (int)curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$body = substr($res, $hsz);

if (!preg_match('/name="token"\s+value="([^"]+)"/', $body, $m)) {
	fail(502, 'CSRF token not found on login page');
}
$token = html_entity_decode($m[1], ENT_QUOTES | ENT_HTML5);

/* Submit the login form with the token and credentials */
$post = http_build_query([
	'pma_username' => $user,
	'pma_password' => $pass,
	'server'       => '1',
	'token'        => $token,
], '', '&');

curl_setopt_array($ch, [
	CURLOPT_URL => $login_idx,
	CURLOPT_POST => true,
	CURLOPT_POSTFIELDS => $post,
	CURLOPT_HTTPHEADER => array_merge(
		$curl_headers,
		[ 'Content-Type: application/x-www-form-urlencoded' ]
	),
]);

$res2 = curl_exec($ch);
if ($res2 === false) {
	fail(502, 'POST failed: '.curl_error($ch));
}
if ((int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE) >= 400) {
	fail(502, 'POST rejected by upstream auth/proxy');
}

/* Forward session cookies to the browser so it is actually logged in */
$hsz2 = (int)curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$hdrs = substr($res2, 0, $hsz2);

curl_close($ch);

foreach (preg_split("/\r\n|\n|\r/", $hdrs) as $h) {
	if (stripos($h, 'Set-Cookie:') === 0) {
		header($h, false);
	}
}

/* Enter phpMyAdmin */
header('Location: '.$dest);
exit;
EOF

# Escape a string for embedding in single-quoted PHP
my $php_sq = sub {
	my ($s) = @_;
	$s =~ s/\r|\n//g;
	$s =~ s/\\/\\\\/g;
	$s =~ s/'/\\'/g;
	return $s;
};

$php =~ s/__NONCE__/$non/g;
$php =~ s/__PMAURL__/$php_sq->($pma_url)/ge;
$php =~ s/__CREDFILE__/$php_sq->($credfile)/ge;

# Write helper inside the phpMyAdmin directory as the domain user
eval { &write_as_domain_user($src_dom, sub {
		&write_file_contents($php_fullpath, $php);
		chmod(0600, $php_fullpath); }) };
if ($@) {
	unlink($credfile);
	&error($text{'databases_login_pma_ephpwrite'});
	}

print "Location: $pma_url$php_filename?n=$non\n\n";
