# -*- mode: Perl; -*-

package NewsClipper::Interpreter;

use strict;
use NewsClipper::Types;

use vars qw( $VERSION );

$VERSION = 0.3;

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

sub _GetInput
{
  my $handlerName = shift;
  my $handler = shift;
  my $attributeList = shift;

  dprint "Calling Get function for handler $handlerName.";

  # Get the data
  my $data = $handler->Get($attributeList);

  if ((!defined $data)||
      ((ref($data) eq "ARRAY") && (!defined @$data)) ||
      ((ref($data) eq "SCALAR") && (!defined $$data)))
  {
    return undef;
  }

  dprint $#{$data}+1," lines acquired" if ref($data) eq "ARRAY";
  dprint length $$data," characters acquired." if ref($data) eq "SCALAR";

  return $data;
}

# ------------------------------------------------------------------------------

sub _FilterData
{
  my $handlerName = shift;
  my $handler = shift;
  my $attributeList = shift;
  my $data = shift;

  dprint "Calling Filter function for handler $handlerName.";

  # Filter the data
  $data = $handler->Filter($attributeList,$data);

  if ((!defined $data)||
      ((ref($data) eq "ARRAY") && (!defined @$data)) ||
      ((ref($data) eq "SCALAR") && (!defined $$data)))
  {
    dprint "Couldn't get data. Handler's Filter function returned nothing.";
    print "<!--News Clipper message:\n",
          "<!--  Couldn't get data. Handler's Filter function returned nothing.\n",
          "-->\n";
    return undef;
  }

  dprint $#{$data}+1," lines filtered." if ref($data) eq "ARRAY";
  dprint length $$data," characters filtered." if ref($data) eq "SCALAR";

  return $data;
}

# ------------------------------------------------------------------------------

sub _OutputData
{
  my $handlerName = shift;
  my $handler = shift;
  my $attributeList = shift;
  my $data = shift;

  dprint "Calling Output function for handler $handlerName.";

  $handler->Output($attributeList,$data);
}

# ------------------------------------------------------------------------------

sub _GetDefaultCommands
{
  my @commands = @_;

  # We only try to fill in defaults if the user only specified an input
  # command.
  return @commands if $#commands > 0 || $commands[0][0] ne 'input';

  my ($type,$attributeList) = @{$commands[0]};

  my $handlerName = $attributeList->{name};

  # Create a handler factory to give us a suitable handler
  require NewsClipper::HandlerFactory;
  my $handlerFactory = new NewsClipper::HandlerFactory;

  # Ask the HandlerFactory to create a handler for us, based on the name.
  my $handler = $handlerFactory->Create($handlerName);

  if (defined $handler)
  {
    my @temp = $handler->GetDefaultHandlers($attributeList);

    dprint "Adding default filter and output handlers" if $#temp != -1;

    for(my $i=0;$i <= $#temp;$i++)
    {
      if ($i != $#temp)
      {
        push @commands,['filter',$temp[$i]];
      }
      else
      {
        push @commands,['output',$temp[$i]];
      }
    }
  }
  else
  {
    @commands = ();
  }

  return @commands;
}

# ------------------------------------------------------------------------------

sub _CheckTypes
{
  my $data = shift;
  my $handler = shift;
  my $handlerName = shift;
  my $type = shift;

  my $dataType = ref $data || 'String';

  my $expectedTypes;
  
  $expectedTypes = $handler->FilterType() if $type eq 'filter';
  $expectedTypes = $handler->OutputType() if $type eq 'output';

  dprint "Comparing data type \"$dataType\" to expected types ",
         "\"$expectedTypes\".";

  my @validTypes = split /\s*,\s*/, $expectedTypes;

  my $isValid = 0;

  foreach my $validType (@validTypes)
  {
    if ($dataType->isa($validType))
    {
      dprint "\"$dataType\" is a subtype of \"$validType\".";

      $isValid = 1;
      last;
    }
  }

  unless ($isValid)
  {
    die reformat dequote <<"    EOF";
      The data expected by "$handlerName" is supposed to be of type
      "$expectedTypes", but it's actually of type "$dataType". This normally
      means that your sequence of News Clipper commands is broken. Try
      changing "$handlerName" to a more suitable handler, or use a filter to
      convert the data from "$dataType" to "$expectedTypes".
    EOF
  }
}

# ------------------------------------------------------------------------------

sub Execute
{
my $self = shift;
my @commands = @_;

dprint "Executing ",$#commands+1," commands.";

# Fill in any defaults
@commands = _GetDefaultCommands(@commands);

my $data = undef;

foreach my $command (@commands)
{
  my ($type,$attributeList) = @$command;
  my $handlerName = $attributeList->{name};

  delete $attributeList->{name};

  # Create a handler factory to give us a suitable handler
  require NewsClipper::HandlerFactory;
  my $handlerFactory = new NewsClipper::HandlerFactory;

  # Ask the HandlerFactory to create a handler for us, based on the name.
  my $handler = $handlerFactory->Create($handlerName);

  # Now have the handler handle it!
  if (defined $handler)
  {
    if ($type eq 'input')
    {
      $data = _GetInput($handlerName,$handler,$attributeList)
    }

    if (defined $data && $type eq 'filter')
    {
      _CheckTypes($data,$handler,$handlerName,$type);
      $data = _FilterData($handlerName,$handler,$attributeList,$data)
    }

    if (defined $data && $type eq 'output')
    {
      _CheckTypes($data,$handler,$handlerName,$type);
      _OutputData($handlerName,$handler,$attributeList,$data)
    }
  }

  # If the get function failed, or everything was filtered out, quit
  dprint "Aborting execution for this News Clipper tag."
    if !defined $data || $data eq '';
  print "<!--News Clipper message:\n",
        "      Aborting execution for this News Clipper tag.\n",
        "-->\n" and last
    if !defined $data || $data eq '';
}

}

1;
