# -*- mode: Perl; -*-
package NewsClipper::Types;

# This package contains a set of useful functions for manipulating HTML.

use strict;
# For exporting of functions
use Exporter;

use vars qw( @ISA @EXPORT $VERSION );

@ISA = qw( Exporter );
@EXPORT = qw( MakeSubtype String Link Image Array Hash ArrayOfString
              ArrayOfLink ArrayOfImage HashOfString Table Thread );

$VERSION = 0.1;

BEGIN
{
  # We do this in the BEGIN block to get the DEBUG constant before the rest of
  # the code is compiled into bytecode.
  require NewsClipper::Globals;
  NewsClipper::Globals->import;
}

# ------------------------------------------------------------------------------

# This routine can be used to make a type a subtype of another
sub MakeSubtype
{
  my $subType = shift;
  my $baseType = shift;

  die "You have to specify both a base type and a subtype for MakeSubtype.\n"
    unless defined $subType && defined $baseType;

  eval "package $subType; use vars qw(\@ISA); \@ISA = \"$baseType\";";
}

# ------------------------------------------------------------------------------

package String;
NewsClipper::Types::MakeSubtype('Link','String');
NewsClipper::Types::MakeSubtype('Image','String');

package Array;

NewsClipper::Types::MakeSubtype('ArrayOfHash','Array');
NewsClipper::Types::MakeSubtype('ArrayOfString','Array');
NewsClipper::Types::MakeSubtype('ArrayOfLink','ArrayOfString');

package Hash;

NewsClipper::Types::MakeSubtype('HashOfString','Hash');

package Table;

package Thread;

1;
