# -*- mode: Perl; -*-

# This is a small parser for the newsclipper tags. The main parser is below.

package NewsClipper::Parser::_TagParser;

use strict;
use HTML::Parser;

use vars qw( @ISA $VERSION );
@ISA = qw(HTML::Parser);

BEGIN
{
  # We do this in the BEGIN block to get the DEBUG constant before the rest of
  # the code is compiled into bytecode.
  require NewsClipper::Globals;
  NewsClipper::Globals->import;
}

# ------------------------------------------------------------------------------

sub new
{
  my $proto = shift;

  # We take the ref if "new" was called on an object, and the class ref
  # otherwise.
  my $class = ref($proto) || $proto;

  # Create an "object"
  my $self = {};

  # Make the object a member of the class
  bless ($self, $class);

  return $self;
}

# ------------------------------------------------------------------------------

sub start
{
  my $self = shift @_;
  my $originalText = pop @_;

  my ($tag, $attributeList) = @_;

  # Make sure all the attributes are lower case
  foreach my $attribute (keys %$attributeList)
  {
    if (lc($attribute) ne $attribute)
    {
      $attributeList->{lc($attribute)} = $attributeList->{$attribute};
      delete $attributeList->{$attribute};
    }
  }

  print "<!--News Clipper message:\n",
        "A News Clipper command must have a \"name\" attribute.\n",
        "-->\n" and return
    unless defined $attributeList->{name};

  if ($tag =~ /(input|filter|output)/)
  {
    push @NewsClipper::Parser::_commandList,[$tag,$attributeList];
  }
  else
  {
    print "<!--News Clipper message:\n",
          "Invalid News Clipper command '$tag' seen in input file.\n",
          "-->\n";
  }
}

################################################################################

package NewsClipper::Parser;

# This package contains a parser for News Clipper "enabled" HTML files. It
# basically passes all tags except ones like <!--newsclipper ...-->, which are
# parsed for commands which are then executed.

use strict;
use HTML::Parser;

use vars qw( @ISA $VERSION $_commandList );
@ISA = qw(HTML::Parser);

# The little parser above fills this with parsed commands.
my @_commandList;

$VERSION = 0.6;

# DEBUG for this package is the same as the main.
use constant DEBUG => main::DEBUG;

sub dprint;
*dprint = \&main::dprint;

# ------------------------------------------------------------------------------

sub new
{
  my $proto = shift;

  # We take the ref if "new" was called on an object, and the class ref
  # otherwise.
  my $class = ref($proto) || $proto;

  # Create an "object"
  my $self = {};

  # Make the object a member of the class
  bless ($self, $class);

  return $self;
}

# ------------------------------------------------------------------------------

# Basically pass everything through except the special tags.
sub text { print "$_[1]"; }
sub declaration { print "<!$_[1]>"; }
sub start { print pop @_; }

# ------------------------------------------------------------------------------

sub end
{
  my $self = shift @_;
  my $tagname = shift @_;
  my $originalText = shift @_;

  # Print a generator message so we can use the search engines to get a feel
  # for how popular News Clipper is...
  if ($tagname eq 'head')
  {
    print "<meta name=generator content=\"News Clipper ",
      "$main::VERSION $main::config{product}\">\n";
  }

  print $originalText;
}

# ------------------------------------------------------------------------------

sub comment
{
  my $self = shift @_;
  my $originalText = pop @_;

  if ($originalText =~ /^\s*newsclipper\b/is)
  {
    dprint "Found newsclipper tag:";

    dprint "<!--$originalText-->";

    # Take off the newsclipper stuff
    my ($commandText) = $originalText =~ /^\s*newsclipper\s*(.*)\s*$/is;

    # Clear out the old commands, if there are any
    undef @NewsClipper::Parser::_commandList;

    # Get the commands
    my $parser = new NewsClipper::Parser::_TagParser;
    $parser->parse($commandText);

    # Now execute the commands
    require NewsClipper::Interpreter;
    my $interpreter = new NewsClipper::Interpreter;

    # The trial version puts a nag in the output
    if ($main::config{product} eq 'Trial')
    {
      print dequote <<"      EOF";
        <table border=1>
        <tr>
        <td>
      EOF
    }

    $interpreter->Execute(@NewsClipper::Parser::_commandList);

    # The trial version puts a nag in the output
    if ($main::config{product} eq 'Trial')
    {
      print dequote <<"      EOF";
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
  # If it's not a special tag, just print it out.
  else
  {
    print "<!--$originalText-->";
  }

}

1;
