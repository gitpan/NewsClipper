# -*- mode: Perl; -*-
package NewsClipper::HTMLTools;

# This package contains a set of useful functions for manipulating HTML.

use strict;
# Used to make relative URLs absolute
use URI;
# For exporting of functions
use Exporter;

use vars qw( @ISA @EXPORT $VERSION );

@ISA = qw( Exporter );
@EXPORT = qw( ExtractText MakeLinksAbsolute StripTags EscapeHTMLChars 
              StripAttributes HTMLsubstr TrimOpenTags );

$VERSION = 0.5;

BEGIN
{
  # We do this in the BEGIN block to get the DEBUG constant before the rest of
  # the code is compiled into bytecode.
  require NewsClipper::Globals;
  NewsClipper::Globals->import;
}

# ------------------------------------------------------------------------------

# Takes a bunch of html in the first argument (as one long string). Uses the
# remaining arguments to strip out attributes. By default, these are taken to
# be alt,class
sub StripAttributes
{
  my $html = shift @_;
  my @tags = @_;

  my $type = ref $html || 'String';

  if ($type ne 'String')
  {
    die reformat dequote<<"    EOF";
      You've tried to call StripAttributes with a value of type "$type", but
      it only takes values of type "String".
    EOF
  }

  @tags = qw(alt class)
    if $#tags == -1;

  # Make the pattern from @tags
  my $temp = $";
  $" = '|';
  my $pattern = "@tags";
  $" = $temp;

  # Strip out anything that matches the pattern inside a tag with ' quotes
  $html =~ s#(<[^>]+?)\s*\b($pattern)\b\s*=\s*'[^']+'([^>]*>)#$1$3#sig;

  # Strip out anything that matches the pattern inside a tag with " quotes
  $html =~ s#(<[^>]+?)\s*\b($pattern)\b\s*=\s*"[^"]+"([^>]*>)#$1$3#sig;

  # Strip out anything that matches the pattern inside a tag without quotes
  $html =~ s#(<[^>]+?)\s*\b($pattern)\b\s*=\s*\S+([^>]*>)#$1$3#sig;

  return $html;
}

# ------------------------------------------------------------------------------

# Takes a bunch of html in the first argument (as one long string). Uses the
# remaining arguments to strip out tags. By default, these are taken to be
# strong,h1,h2,h3,h4,h5,h6,b,i,u,tt,font,big,small,strike,
# which (hopefully) strips out the formatting.
sub StripTags
{
  my $html = shift @_;
  my @tags = @_;

  my $type = ref $html || 'String';

  if ($type ne 'String')
  {
    die reformat dequote <<"    EOF";
      You've tried to call StripAttributes with a value of type "$type", but
      it only takes values of type "String".
    EOF
  }

  @tags = qw(strong em h1 h2 h3 h4 h5 h6 b i u tt font big small strike)
    if $#tags == -1;

  # Make the pattern from @tags
  my $temp = $";
  $" = '|';
  my $pattern = "@tags";
  $" = $temp;

  # Strip out anything that matches the pattern
  $html =~ s#<\s*/?\b($pattern)\b[^>]*>##sig;

  return $html;
}

# ------------------------------------------------------------------------------

# Extracts all text between the starting and ending patterns. '^' and '$' can
# be used for the starting and ending patterns to signify start of text and
# end of text.
sub ExtractText
{
  my $html = shift;
  my $startPattern = shift;
  my $endPattern = shift;

  my $type = ref $html || 'String';

  if ($type ne 'String')
  {
    die <<"    EOF";
      You've tried to call StripAttributes with a value of type "$type", but
      it only takes values of type "String".
    EOF
  }

  # Makes things a lot faster
  return if $startPattern ne '^' && $html !~ /$startPattern/s;

  if (($startPattern eq '^') && ($endPattern eq '$'))
  {
    return $html;
  }
  if (($startPattern ne '^') && ($endPattern ne '$'))
  {
    $html =~ s/.*?$startPattern(.*?)$endPattern.*/$1/s;
    return '' if $1 eq '';
    return $html;
  }
  if (($startPattern ne '^') && ($endPattern eq '$'))
  {
    $html =~ s/.*?$startPattern(.*)/$1/s;
    return '' if $1 eq '';
    return $html;
  }
  if (($startPattern eq '^') && ($endPattern ne '$'))
  {
    $html =~ s/(.*?)$endPattern.*/$1/s;
    return '' if $1 eq '';
    return $html;
  }

  return $html;
}

# ------------------------------------------------------------------------------

# Takes a bunch of html in the first argument (as one long string). Uses the
# remaining arguments to trim unclosed tags from the beginning and end of the
# html. By default, these are taken to be every possible enclosing-style tag.
sub TrimOpenTags
{
  my $html = shift @_;
  my @tags = @_;

 my $type = ref $html || 'String';

  if ($type ne 'String')
  {
    die <<"    EOF";
      You've tried to call StripAttributes with a value of type "$type", but
      it only takes values of type "String".
    EOF
  }

  @tags = qw(strong em h1 h2 h3 h4 h5 h6 b i u tt font big small strike a html
                title head body div span blockquote q code samp kbd var dfn
                address ins del acronym abbr s sub sup pre center blink marquee
                multicol layer ilayer nolayer map object nobr ul ol dl menu form
                button label select optgroup textarea fieldset legend table tr
                td th tfoot thead caption col colgroup frameset noframes iframe
                script noscript applet server style bdo)
    if $#tags == -1;

  foreach my $tag (@tags)
  {
    # If we see a starting tag...
    if ($html =~ /^(.*)(<\s*\b$tag\b[^>]*>)(.*?)$/si)
    {
      my ($start,$tagtext,$end) = ($1,$2,$3);
      # If there isn't a closing tag...
      if ($end !~ /<\s*\/\s*\b$tag\b[^>]*>/si)
      {
        $html = $start.$end;
      }
    }

    # If we see an ending tag...
    if ($html =~ /^(.*?)(<\s*\/\s*\b$tag\b[^>]*>)(.*)$/si)
    {
      my ($start,$tagtext,$end) = ($1,$2,$3);
      # If there isn't a starting tag...
      if ($start !~ /<\s*\b$tag\b[^>]*>/si)
      {
        $html = $start.$end;
      }
    }
  }

  return $html;
}

# ------------------------------------------------------------------------------

# Takes a substring from HTML, but only counts the non-tag characters. It also
# tries to remove starting HTML tags that have been trimmed off...
# Arguments are the text, an offset, and the length.
sub HTMLsubstr
{
  my $html = shift;
  my $offset = shift;
  my $length = shift || 32700;

  my $type = ref $html || 'String';

  if ($type ne 'String')
  {
    die <<"    EOF";
      You've tried to call StripAttributes with a value of type "$type", but
      it only takes values of type "String".
    EOF
  }

  # First make a copy of the html
  my $pattern = $html;

  # Turn every tag and its contents into ZZZs
  $pattern =~ s/<([^>]+)>/my $temp = $1;$temp =~ s#.#Z#sg;"Z$temp\Z"/esg;

  # Turn newlines into ZZZs
  $pattern =~ s/\n/Z/sg;

  # Count all the non-Zs, ignoring sequences of Zs. ({0,200} in case they
  # specified a number larger than our string.)
  $pattern =~ /^([^Z]Z*){0,$offset}(Z*([^Z]Z*){0,$length})/;

  my $substring = $2;

  # Translate all the Zs to .'s, which will match everything.
  $substring =~ s/Z/./g;

  # Translate all the \ to \\'s, which will match everything.
  $substring =~ s#\\#\\\\#g;

  # Escape all the metacharacters
  $substring = quotemeta($substring);

  # Now match our munged substring against the real thing, and extract the match
  my ($returnval) = $html =~ /($substring)/s;

  # But wait! What if we chopped off a starting <font>, <tt> etc from the
  # beginning, or an ending </font>, </tt>, etc from the end?
  $returnval = TrimOpenTags($returnval);

  return $returnval;
}

# ------------------------------------------------------------------------------

# Escapes & < and > in text. Note that this should only be used on non-HTML
# text. ('&lt;' gets turned into '&amp;lt;')
sub EscapeHTMLChars
{
  my $html = shift @_;

  my $type = ref $html || 'String';

  if ($type ne 'String')
  {
    die <<"    EOF";
      You've tried to call StripAttributes with a value of type "$type", but
      it only takes values of type "String".
    EOF
  }

  # Escape HTML characters
  $html =~ s/&/&amp;/sg;
  $html =~ s/</&lt;/sg;
  $html =~ s/>/&gt;/sg;

  return $html;
}

# ------------------------------------------------------------------------------

# Searches text for "a href" or "img src" tags and makes them absolute. We
# should probably be doing this with HTML::Parser. Note that this function
# erroneously recognizes stuff like <a href='XXX">. This is pretty rare, and
# doing it this way is faster than recognizing two quotes and no quotes
# separately.
sub MakeLinksAbsolute
{
  my $url = shift;
  my $html = shift;

  my $type = ref $html || 'String';

  if ($type ne 'String')
  {
    die <<"    EOF";
      You've tried to call StripAttributes with a value of type "$type", but
      it only takes values of type "String".
    EOF
  }

  $html =~ s/
      # First look for an a, img, or area, followed later by an href or src
      (<\s*(?:a|img|area)\b[^>]*(?:href|src)\s*=\s*
      # Then an optional quote
      ['"]?)
      # Then the interesting part
      ([^'"> ]+)
      # Then another optional quote
      (['"]?
      # And the left-overs
      [^>]*>)
    /
      # Then construct the new link from the prefix and suffix
      $1.sprintf("%s",URI->new($2)->abs($url)).$3
    /segix;

  return $html;
}

1;
