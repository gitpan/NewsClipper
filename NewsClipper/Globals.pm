# -*- mode: Perl; -*-
package NewsClipper::Globals;

# This package contains a set of globals used by all News Clipper modules.

use strict;
# For exporting of functions
use Exporter;

use vars qw( @ISA @EXPORT $VERSION );

@ISA = qw( Exporter );
@EXPORT = qw( DEBUG reformat dprint dequote );

$VERSION = 0.10;

# ------------------------------------------------------------------------------

# We'll use a global DEBUG constant, which is set by the -d flag on the
# command line. (Be sure to "require" this module after doing getopt in main.
# Debug mode doesn't put a time limit on the script, outputs some
# <!--DEBUG:...--> commentary, and doesn't write to the output file (instead
# it dumps to screen).

use constant DEBUG => $main::opts{d} || 0;

# ------------------------------------------------------------------------------

use Text::Wrap;

# Reformats the input to 80 columns.

sub reformat
{
  my $text = join '\n',@_;

  # Change all the newlines to spaces in preparation of reformatting.
  $text =~ s/\n/ /g;
  $Text::Wrap::columns = 80;

  my $formatted = wrap '','',$text;

  # Tack a newline on the end if the original had one.
  $formatted .= "\n" if $_[-1] =~ /\n$/s;

  return $formatted;
}

# ------------------------------------------------------------------------------

# Prints debug messages in the form "<!--DEBUG: ... -->" if the DEBUG constant
# is true.

sub dprint
{
  return unless DEBUG;

  my $message = join '',@_;

  my @lines = split /\n/, $message;
  foreach my $line (@lines)
  {
    print "<!--DEBUG: $line";
    print " "x(65-length $line) if length $line < 65;
    print "-->\n";
  }

  return 1;
}

# ------------------------------------------------------------------------------

# Allows indented here documents. Modified from the Perl Cookbook. The first
# argument can be a prefix string to start each line with.

sub dequote
{
  my $prefix;
  $prefix = shift if $#_ == 1;

  local $_ = shift;

  my ($white, $leader);

  if (/^\s*(?:([^\w\s]+)(\s*).*\n)(?:\s*\1\2?.*\n)+$/)
  {
    ($white, $leader) = ($2, quotemeta($1));
  }
  else
  {
    ($white, $leader) = (/^(\s+)/,'');
  }

  s/^\n/$white\n/gm;
  s/^\s*?$leader(?:$white)?//gm;

  # Put the prefix on if one was specified
  $_ =~ s/^/$prefix/gm if $prefix;

  return $_;
}

# ------------------------------------------------------------------------------

1;
