# -*- mode: Perl; -*-
package NewsClipper::Handler;

# This package contains the Handler class, from which all handlers derive.  To
# use it, subclass it and redefine the Get, Filter, and Output methods. 

use strict;
use Carp;

use vars qw( $VERSION );

$VERSION = 0.4;

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

# This should be overridden by data acquisition handlers. (Filter and output
# handlers can safely ignore it.)
sub Get
{
  my $self = shift;
  my $attributes = shift;

  my $type = ref($self);
  croak "$type does not have the ability to do data acquisition.\n";
}

# ------------------------------------------------------------------------------

# This function is used to filter out some of the data acquired using Get.
# Currently it does nothing, but subclasses can override this behavior.
sub Filter
{
  my $self = shift;
  my $attributes = shift;
  my $grabbedData = shift;

  # Return a reference to the data.
  return $grabbedData;
}

# ------------------------------------------------------------------------------

# This should be overridden by data acquisition handlers. (Filter and output
# handlers can safely ignore it.)
sub Output
{
  my $self = shift;
  my $attributes = shift;
  my $grabbedData = shift;
}

# ------------------------------------------------------------------------------

# Overriding this method is optional.
sub GetUpdateTimes
{
  my $self = shift;

  return ['2,5,8,11,14,17,20,23'];
}

# ------------------------------------------------------------------------------

# Overriding this method is optional, but recommended.
sub GetDefaultHandlers
{
  my $self = shift;

  # Sometimes we have to know how the input is called in order to choose a
  # handler.
  my $inputAttributes = shift;

  # The format should be an array, where the last item is an output filter
  # description, and the others are filter descriptions. The descriptions
  # should be in the form of a hash, with the 'name' key containing the name
  # of the filter or output handler. For example:
  # my @returnVal = (
  #   {'name' => 'highlight', 'words' => 'linux,wine,mitnick'},
  #   {'name' => 'string'}
  # );

  return ();
}

1;
