# -*- mode: Perl; -*-

package NewsClipper::Parser;

# This package contains a parser for News Clipper "enabled" HTML files. It
# basically passes all tags except ones like <!--newsclipper ...-->, which are
# parsed for commands which are then executed.

use strict;
use HTML::Parser;
use NewsClipper::TagParser;

use vars qw( @ISA $VERSION );
@ISA = qw(HTML::Parser);

BEGIN
{
  # We do this in the BEGIN block to get the DEBUG constant before the rest of
  # the code is compiled into bytecode.
  require NewsClipper::Globals;
  NewsClipper::Globals->import;
}

$VERSION = 0.62;

my $span_active = 0;

# ------------------------------------------------------------------------------

# Basically pass everything through except the special tags.
sub text
{
  return if $span_active;
  print "$_[1]";
}

sub declaration
{
  return if $span_active;
  print "<!$_[1]>";
}

sub process
{
  return if $span_active;
  print pop @_;
}

sub start
{
  return if $span_active;
  print pop @_;
}

# ------------------------------------------------------------------------------

sub end
{
  my $self = shift;
  my $tagname = shift;
  my $originalText = shift;

  return if $span_active;

  # Print a generator message so we can use the search engines to get a feel
  # for how popular News Clipper is...
  if ($tagname eq 'head')
  {
    print "<meta name=generator content=\"News Clipper ",
      "$main::VERSION $config{product}\">\n";
  }

  print $originalText;
}

# ------------------------------------------------------------------------------

# We embed News Clipper commands in comments.

sub comment
{
  my $self = shift;
  my $originalText = pop @_;

  if ($originalText =~ /^\s*newsclipper\s+startcomment\b/is)
  {
    $span_active = 1;
  }
  elsif ($originalText =~ /^\s*newsclipper\s+endcomment\b/is)
  {
    $span_active = 0;
  }
  elsif ($originalText =~ /^\s*newsclipper\b/is)
  {
    return if $span_active;

    dprint "Found newsclipper tag:";

    # Clear out the %errors log
    undef %errors;

    dprint "<!--$originalText-->";

    # Take off the newsclipper stuff
    my ($commandText) = $originalText =~ /^\s*newsclipper\s*(.*)\s*$/is;

    # Get the commands
    my $parser = new NewsClipper::TagParser;
    my @commands = $parser->parse($commandText);

    if ($#commands == -1)
    {
      $errors{'parser'} .=
        "A News Clipper comment was found, but no valid commands.\n";
      return;
    }
    else
    {
      # Now execute the commands
      require NewsClipper::Interpreter;
      my $interpreter = new NewsClipper::Interpreter;

      # The trial version puts a nag in the output
      if ($config{product} eq 'Trial')
      {
        print dequote <<"        EOF";
          <table border=1>
          <tr>
          <td>
        EOF
      }

      $interpreter->Execute(@commands);

      # The trial version puts a nag in the output
      if ($config{product} eq 'Trial')
      {
        print dequote <<"        EOF";
          <p>
          <a href="http://www.newsclipper.com">
          <img src="http://www.newsclipper.com/images/ncnow.gif" align=left>
          </a>
          This dynamic content brought to you by
          <a href="http://www.newsclipper.com">News Clipper</a>. The registered
          version does not have this message.
          </p>

          </td>
          </tr>
          </table>
        EOF
      }
    }
    
    PrintErrors($originalText);
    undef %errors;
  }
  # If it's not a special tag, just print it out.
  else
  {
    return if $span_active;

    print "<!--$originalText-->";
  }

}

# ------------------------------------------------------------------------------

# Print out any errors that occured while executing a sequence of News Clipper
# commands

sub PrintErrors
{
  my $commands = shift;

  my $expandedCommands = $errors{'expanded commands'} || undef;
  delete $errors{'expanded commands'};

  return unless keys %errors;

  # Localize %errors since we're going to change it.
  local %errors = %errors;

  print "<!-- News Clipper error message:\n";

  my $wereErrors = 0;
  $wereErrors = 1 if keys %errors;

  if (exists $errors{'tagparser'})
  {
    print reformat dequote <<"    EOF";
      The following errors occurred while processing this
      sequence of commands: $errors{'tagparser'}
    EOF
  }

  if (exists $errors{'parser'})
  {
    print reformat dequote <<"    EOF";
      The following errors occurred while processing this
      News Clipper comment: $errors{'parser'}
    EOF
  }

  if (exists $errors{'acquisition'})
  {
    print reformat dequote <<"    EOF";
      The following errors occurred while attempting to
      acquire the data from the remote server: $errors{'acquisition'}
    EOF
  }

  if (exists $errors{'interpreter'} && !exists $errors{'acquisition'})
  {
    print reformat dequote <<"    EOF";
      The following errors occurred while attempting to execute the
      News Clipper commands: $errors{'interpreter'}
    EOF
  }

  foreach my $key (keys %errors)
  {
    if ($key =~ /^handler#(.*)/)
    {
      print reformat dequote <<"      EOF";
        The following errors occurred while executing the handler "$1"
        with this sequence of commands: $errors{$key}
      EOF
      delete $errors{$key};
    }
  }

  # Delete the error types we know of, since we're now done processing them.
  delete $errors{'tagparser'};
  delete $errors{'acquisition'};
  delete $errors{'interpreter'};

  foreach my $key (keys %errors)
  {
    delete $errors{$key} if ($key =~ /^handler#(.*)/);
  }

  # Now print any remaining, unknown, errors.
  foreach my $key (keys %errors)
  {
    print reformat dequote <<"    EOF";
      Unrecognized error: $errors{$key}

    EOF
    delete $errors{$key};
  }

  if ($wereErrors)
  {
    $commands =~ s/^.*?\n*(\s*<)/$1/s;
    $commands =~ s/\s*$//s;
    print "\nThe sequence of commands was:\n$commands\n";

    if (($commands !~ /<\s*output/i) && (defined $expandedCommands))
    {
      $expandedCommands =~ s/\s*$//s;
      print <<"      EOF";
This input command was expanded using the default filter and output commands
for the handler, which resulted in:
$commands
$expandedCommands
      EOF
    }
  }

  print "-->\n\n";
}

1;
