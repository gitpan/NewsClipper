# -*- mode: Perl; -*-
package NewsClipper::AcquisitionFunctions;

# This package contains a set of useful functions for grabbing data from the
# internet. It is used by the handlers' Get functions.

use strict;
# For some HTML manipulation functions
use NewsClipper::HTMLTools;
# For UserAgent
use LWP::UserAgent;
# For exporting of functions
use Exporter;

use vars qw( @ISA @EXPORT_OK $VERSION );

@ISA = qw( Exporter );
@EXPORT_OK = qw( GetUrl GetHtml GetImages GetLinks GetText);

$VERSION = 0.61;

BEGIN
{
  # We do this in the BEGIN block to get the DEBUG constant before the rest of
  # the code is compiled into bytecode.
  require NewsClipper::Globals;
  NewsClipper::Globals->import;
}

use NewsClipper::Cache;
my $cache = NewsClipper::Cache->new;

my $userAgent = new LWP::UserAgent;

# ------------------------------------------------------------------------------

# I wish there was a way to get the actual reference to the calling object, so
# we don't have to create a temporary.
sub _GetUpdateTimes
{
  # Walk up the call chain until we find who called us
  my $callersClass = undef;
  my $depth = 0;
  do
  {
    my $tempCaller = (caller($depth))[0];
    $callersClass = $tempCaller if $tempCaller =~ /Handler/;
    $depth++;
  } until defined $callersClass;

  my $tempHandler = "$callersClass"->new;

  my ($baseTagName) = $callersClass =~ /^(\S*)/;

  my @updateTimes = @{$tempHandler->GetUpdateTimes};

  if (DEBUG)
  {
    my $temp = $";
    $" = ',';
    dprint "Update times are: @updateTimes";
    $" = $temp;
  }

  return @updateTimes;
}

# ------------------------------------------------------------------------------

# Gets the entire content from a URL. This function *does not* escape & < and
# >. Use "GetHtml($url,'^','$')" if you wan this behavior.
sub GetUrl
{
  my $url = shift;

  dprint "GetUrl is getting URL: $url";

  # Try to get the cached data if it's available and still valid
  my @updateTimes = _GetUpdateTimes();

  # If the user specified "always", there's no need to check the time.
  dprint "\"Always\" specified. Skipping cache check"
    if lc($updateTimes[0]) eq 'always';

  my ($cachedData,$cacheStatus) = $cache->GetData($url,@updateTimes);

  # If the data is still valid for the @updateTimes, we can return it
  # immediately
  if ((lc($updateTimes[0]) ne 'always') && ($cacheStatus eq 'valid'))
  {
    my $tempRef = \$cachedData;
    bless $tempRef,"String";
    return $tempRef;
  }


  # Otherwise we'll have to fetch it.
  $userAgent->timeout($main::config{socketTimeout});
  $userAgent->proxy(['http', 'ftp'], $main::config{proxy})
    if $main::config{proxy} ne '';
  my $request = new HTTP::Request GET => "$url";

  # Reload content if the user wants it
  $request->push_header("Pragma" => "no-cache") if exists $main::opts{r};

  if ($main::config{proxy_username} ne '')
  {
    $request->proxy_authorization_basic($main::config{proxy_username},
                     $main::config{proxy_password});
  }

  my $result = $userAgent->request($request);

  if (!$result->is_success)
  {
    dprint "Couldn't get data. Error on HTTP request: ".$result->message;
    print "<!--News Clipper message:\n",
          "<!-- Couldn't get data. Error on HTTP request: ".$result->message.".\n",
          "-->\n"
      if defined $result;

    # Use the cached data if there is any available
    if ($cacheStatus eq 'stale')
    {
      dprint "HTTP request failed, but there is cached data available";
      my $tempRef = \$cachedData;
      bless $tempRef,"String";
      return $tempRef;
    }
    else
    {
      dprint "HTTP request failed, and there is no cached data available";
      print "<!--News Clipper message:\n",
            "<!-- HTTP request failed, and there is no cached data available.\n",
            "-->\n";

      return undef;
    }
  }

  my $content = $result->content;

  # Strip linefeeds off the lines
  $content =~ s/\r//gs;

  # Cache it for later use unless it's an "always"
  $cache->CacheData($url,$content) if lc($updateTimes[0]) ne 'always';

  my $tempRef = \$content;
  bless $tempRef,"String";
  return $tempRef;
}

# ------------------------------------------------------------------------------

# Gets all the text from a URL, stripping out all HTML tags between the
# starting pattern and the ending pattern. This function escapes & < >.
sub GetText
{
  my ($url,$startPattern,$endPattern) = @_;

  my $html = GetUrl($url);

  return unless defined $html;

  $html = $$html;

  # Strip off all the stuff before and after the start and end patterns
  $html = &ExtractText($html,$startPattern,$endPattern);

  # Remove pieces of tags at the ends
  $html =~ s/^[^<]*>//s;
  $html =~ s/<[^>]*$//s;

  # Wrap in HTML to help TreeBuilder.
  $html = "<body>$html" unless $html =~ /<body/i;
  $html = "$html</body>" unless $html =~ /<\/body>/i;
  $html = "</head>$html" unless $html =~ /<\/head>/i;
  $html = "<head>$html" unless $html =~ /<head/i;
  $html = "<html>$html" unless $html =~ /<html/i;
  $html = "$html</html>" unless $html =~ /<\/html>/i;

  # FormatText seems to have a problem with &nbsp;
  $html =~ s/&nbsp;/ /sg;

  # Convert to text
  require HTML::FormatText;
  require HTML::TreeBuilder;

  my $f = HTML::FormatText->new(leftmargin=>0);
  $html = $f->format(HTML::TreeBuilder->new->parse($html));
  $html =~ s/\n*$//sg;

  # Escape HTML characters
  $html = EscapeHTMLChars($html);

  if ($html ne '')
  {
    my $tempRef = \$html;
    bless $tempRef,"String";
    return $tempRef;
  }
  else
  {
    return undef;
  }
}

# ------------------------------------------------------------------------------

# Extracts HTML between startPattern and endPattern. 

# startPattern and endPattern can be '^' or '$' to match the beginning of the
# file or the end of the file.
sub GetHtml
{
  my ($url,$startPattern,$endPattern) = @_;

  my $html = &GetUrl($url);

  return unless defined $html;

  $html = $$html;

  # Strip off all the stuff before and after the start and end patterns
  $html = &ExtractText($html,$startPattern,$endPattern);

  $html = &MakeLinksAbsolute($url,$html);

  if ($html ne '')
  {
    my $tempRef = \$html;
    bless $tempRef,"String";
    return $tempRef;
  }
  else
  {
    return undef;
  }
}

#-------------------------------------------------------------------------------

# Extracts all <img...> tags at a given url between startPattern
# and endPattern.
# Handles '^' and '$' to signify start and end of file.
# Thanks to Tanner Lovelace <lovelace@cs.unc.edu> for writing this
sub GetImages
{
  my ($url,$startPattern,$endPattern) = @_;

  my $html = &GetUrl($url);

  return unless defined $html;

  $html = $$html;

  # Strip off all the stuff before and after the start and end patterns
  $html = &ExtractText($html,$startPattern,$endPattern);

  require HTML::TreeBuilder;
  my $tree = HTML::TreeBuilder->new;
  $tree->parse($html);

  my @imgTags;

  foreach my $linkpair (@{$tree->extract_links('img')})
  {
    # Extract the link from the HTML element.
    my $elem = ${$linkpair}[1];
    my $link = $elem->as_HTML();
    chomp $link;

    # Remove any formatting
    $link = StripTags($link);

    # change relative tags to absolute
    $link = &MakeLinksAbsolute($url,$link);
    push @imgTags, $link;
  }

  if ($#imgTags != -1)
  {
    my $tempRef = \@imgTags;
    bless $tempRef,"ArrayOfImage";
    return $tempRef;
  }
  else
  {
    return undef;
  }
}

# ------------------------------------------------------------------------------

# Extracts all <a href...>...</a> links at a given url between startPattern
# and endPattern. Removes all text formatting, and makes relative links
# absolute. Puts quotes around attribute values in stuff like <a href=blah> and
# <img src=blah>.

# Now handles '^' and '$' to signify start and end of file.
sub GetLinks
{
  my ($url,$startPattern,$endPattern) = @_;

  my $html = &GetUrl($url);

  return unless defined $html;

  $html = $$html;

  # Strip off all the stuff before and after the start and end patterns
  $html = &ExtractText($html,$startPattern,$endPattern);

  require HTML::TreeBuilder;
  my $tree = HTML::TreeBuilder->new;
  $tree->parse($html);

  my @links;

  foreach my $linkpair (@{$tree->extract_links('a')})
  {
    # Extract the link from the HTML element.
    my $elem = ${$linkpair}[1];
    my $link = $elem->as_HTML();
    chomp $link;

    # Remove any formatting
    $link = StripTags($link);

    # change relative tags to absolute
    $link = &MakeLinksAbsolute($url,$link);
    push @links, $link;
  }

  if ($#links != -1)
  {
    my $tempRef = \@links;
    bless $tempRef,"ArrayOfLink";
    return $tempRef;
  }
  else
  {
    return undef;
  }
}

1;
