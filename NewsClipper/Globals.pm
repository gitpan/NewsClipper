# -*- mode: Perl; -*-
package NewsClipper::Globals;

# This package contains a set of globals used by all News Clipper modules.

use strict;
# For exporting of functions
use Exporter;

use vars qw( @ISA @EXPORT $VERSION );

@ISA = qw( Exporter );
@EXPORT = qw( DEBUG reformat dprint dequote %errors %config %opts);

$VERSION = 0.22;

# ------------------------------------------------------------------------------

# We'll use a global DEBUG constant, which is set by the -d flag on the
# command line. (Be sure to "require" this module after doing getopt in main.
# Debug mode doesn't put a time limit on the script, outputs some
# <!--DEBUG:...--> commentary, and doesn't write to the output file (instead
# it dumps to screen).

use constant DEBUG => $main::opts{d} || 0;

# ------------------------------------------------------------------------------

# We will alias this variable to the one in main so that it will be easily
# accessible by all modules. We don't simply put this variable here because it
# is used in main before this module is loaded.

*config = \%main::config;

# ------------------------------------------------------------------------------

# We will alias this variable to the one in main so that it will be easily
# accessible by all modules. We don't simply put this variable here because it
# is used in main before this module is loaded.

*opts = \%main::opts;

# ------------------------------------------------------------------------------

# This variable will hold error messages from various parts of the system.
# These messages will be stored according to their location, and then printed
# as News Clipper commands execute. The contents are cleared at the end of
# each sequence of News Clipper commands.

my %errors;

# ------------------------------------------------------------------------------

# The user's home directory (Initialized in main::SetupConfig)
my $home;

# The cache. There is only one. (Initialized in main::SetupConfig)
my $cache;

# The News Clipper state. There is only one. (Initialized in main::SetupConfig)
my $state;

# The handler factory. There is only one. (Initialized in main::SetupConfig)
my $handlerFactory;

# ------------------------------------------------------------------------------

use Text::Wrap;

# Reformats the input to 80 columns, or the number specified by the first
# argument. Retains any empty lines at the end.

sub reformat(@)
{
  my $columns;

  if ($#_ > 0 && $_[0] =~ /^\d+$/)
  {
    $columns = shift;
  }
  else
  {
    $columns = 80;
  }

  my $text = join '\n',@_;

  my ($ending_newlines) = $text =~ /(\n*)$/s;
  $ending_newlines = '' unless defined $ending_newlines;
  $text =~ s/\n*$//;

  # Change all the newlines to spaces in preparation of reformatting.
  $text =~ s/\n/ /g;
  $Text::Wrap::columns = $columns;

  my $formatted = wrap('','',$text);

  # Tack a newline on the end if the original had one.

  $formatted .= $ending_newlines;

  return $formatted;
}

# ------------------------------------------------------------------------------

# Prints debug messages in the form "<!--DEBUG: ... -->" if the DEBUG constant
# is true.

sub dprint(@)
{
  return 1 unless DEBUG;

  my $message = join '',@_;

  my @lines = split /\n/, $message;
  foreach my $line (@lines)
  {
    printf "<!--DEBUG: %-64s -->\n",$line;
  }

  return 1;
}

# ------------------------------------------------------------------------------

# Allows indented here documents. Modified from the Perl Cookbook. The first
# argument can be a prefix string to start each line with.

sub dequote($;$)
{
  my $prefix;
  $prefix = shift if $#_ == 1;

  local $_ = shift;

  my ($white, $leader);

  if (/^\s*(?:([^\w\s<>!@#\$\%^&*()]+)(\s*).*\n)(?:\s*\1\2?.*\n)+$/)
  {
    ($white, $leader) = ($2, quotemeta($1));
  }
  else
  {
    ($white, $leader) = (/^(\s*)/,'');
  }

  s/^\n/$white\n/gm;
  s/^\s*?$leader(?:$white)//gm;

  # Put the prefix on if one was specified
  $_ =~ s/^/$prefix/gm if $prefix;

  return $_;
}

# ------------------------------------------------------------------------------

1;
