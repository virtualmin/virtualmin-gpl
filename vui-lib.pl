# UI functions specific to Virtualmin

# virtualmin_ui_rating_selector(name, value, max, cgi)
# Returns HTML for a field for selecting a rating for something. When chosen,
# submits to the given CGI.
# XXX AJAX theme can override
# XXX just * links
sub virtualmin_ui_rating_selector
{
return &theme_virtualmin_ui_rating_selector(@_)
	if (defined(&theme_virtualmin_ui_rating_selector));
local ($name, $value, $max, $cgi) = @_;
local $rv;
for($i=1; $i<=$max; $i++) {
	local $img = $i <= $value ? "starover.gif" : "staroff.gif";
	if ($cgi) {
		local $cgiv = $cgi;
		$cgiv .= ($cgi =~ /\?/ ? "&" : "?");
		$cgiv .= $name."=".$i;
		$rv .= "<a href='$cgiv' id=$name$i>".
		       "<img src=images/$img border=0></a>";
		}
	else {
		$rv .= "<img src=images/$img>";
		}
	}
return $rv;
}

1;

