# -*- mode: Perl; -*-
package NewsClipper::Cache;

use strict;
# For mkpath
use File::Path;
# To parse dates
use Time::CTime;
use Time::ParseDate;

use vars qw( $VERSION );

$VERSION = 0.2;

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

# Removes data from the cache, if there is any
sub _RemoveFromCache
{
  my $url = shift;

  my $newRegistry = '';
  my $found = 0;

  open REGISTRY,"$main::config{cachelocation}/registry.txt" or return;
  while (defined(my $line = <REGISTRY>))
  {
    chomp $line;
    my ($cacheUrl,$filename,$size,$time) = split / /,$line;

    if ($cacheUrl eq $url)
    {
      dprint "Removing cached data for URL:\n  $url";

      unlink "$main::config{cachelocation}/$filename";
      $found = 1;
    }
    else
    {
      $newRegistry .= $line."\n";
    }
  }
  close REGISTRY;

  if ($found)
  {
    open REGISTRY,">$main::config{cachelocation}/registry.txt"
      or die "Can't open cache registry file: $!";
    print REGISTRY $newRegistry;
    close REGISTRY;
  }
}

# ------------------------------------------------------------------------------

sub _Outdated
{
  # Get the times that the user has specified, or the default times.
  my @relativeUpdateTimes = @{shift @_};
  my $lastUpdated = shift;

  # Iterate over the times to find out which is the most recent time we should
  # have updated.
  my $mostRecentUpdateTime = 0;
  foreach my $timeSpec (@relativeUpdateTimes)
  {
    # Extract the day and timezone from the time specification from the
    # handler. Replace $timeSpec with the middle, which should be the hours.
    my ($day,$timezone);
    ($day,$timeSpec,$timezone) =
      $timeSpec =~ /^([a-z]*)\D*([\d ,]*)\s*([a-z]*)/i;

    # Move all the hours from 2,3,4,5 form into an array.
    my @hours = split /\D+/,$timeSpec;

    # chop off extra characters on the day, just in case they did thurs
    # instead of thu.
    $day =~ s/^(...).*/$1/;

    # If they didn't specify a day, it's today
    $day = 'today'
      if $day eq '' || lc(strftime("%a",localtime(time))) eq lc($day);

    # If they didn't specify a timezone, it's pacific (in recognition of the
    # multitude of internet companies in California)
    $timezone = 'PST' if $timezone eq '';

    # Now iterate through each hour in the list, looking for the most recent
    # update hour
    foreach my $hour (@hours)
    {
      my $tempDate = parsedate("$day $hour:00", ZONE => $timezone);

      # Correct apparently future times. Basically, they meant "last Friday at
      # 2pm", not "this Friday at 2pm" and "yesterday at 2pm" not "today at
      # 2pm"
      if ($tempDate > parsedate('now'))
      {
        if ($day eq 'today')
        {
          $day = 'yesterday';
        }
        else
        {
          $day = "last $day";
        }
      }

      # Parse the date again, in case we corrected the day.
      my $parsedDate = parsedate("$day $hour:00", ZONE => $timezone);

      $mostRecentUpdateTime = $parsedDate
        if $parsedDate > $mostRecentUpdateTime;
    }
  }

  dprint ("Comparing dates:");
  dprint ("  Last Updated: $lastUpdated");
  dprint ("  Most Recent Update Time: $mostRecentUpdateTime");
  dprint ("  Now: ",parsedate('now'));

  if ($lastUpdated < $mostRecentUpdateTime)
  {
    dprint "Update is needed";
    return 1;
  }
  else
  {
    dprint "Update is not needed";
    return 0;
  }
}

# ------------------------------------------------------------------------------

# Checks the cache for the url's data.  One of three return values are
# possible:
# valid: The data exists and isn't old
# stale: The data is exists but is old
# not found: The data is not in the cache
sub _IsStillValid
{
  my $url = shift;
  my @updateTimes = @_;

  dprint "Checking cache for data for URL:\n  $url";

  my ($cacheUrl,$filename,$size,$lastUpdated) = (undef,undef,undef,undef);

  open REGISTRY,"$main::config{cachelocation}/registry.txt"
    or dprint "No registry file found" and return 'not found';
  while (defined(my $line = <REGISTRY>))
  {
    chomp $line;
    ($cacheUrl,$filename,$size,$lastUpdated) = split / /,$line;

    last if $cacheUrl eq $url;
  }
  close REGISTRY;

  # Return 'not found' if we couldn't find it in the cache.
  dprint "Couldn't find cached data " if $cacheUrl ne $url;
  return 'not found' unless $cacheUrl eq $url;


  if (_Outdated(\@updateTimes,$lastUpdated))
  {
    dprint "Data is stale";
    return 'stale';
  }
  else
  {
    dprint "Reusing cached data";
    return 'valid';
  }
}

# ------------------------------------------------------------------------------

sub _ReduceCacheSize
{
  my $amountToReduce = shift;

  dprint "Reducing cache size by $amountToReduce";

  my @cacheInfo = ();

  open REGISTRY,"$main::config{cachelocation}/registry.txt" or return;
  while (defined(my $line = <REGISTRY>))
  {
    chomp $line;
    my ($cacheUrl,$filename,$size,$time) = split / /,$line;

    push @cacheInfo,[$cacheUrl,$filename,$size,$time];
  }
  close REGISTRY;

  # Sort by timestamp
  @cacheInfo = sort { $a->[3] <=> $b->[3] } @cacheInfo;

  while (($#cacheInfo > -1) && ($amountToReduce > 0))
  {
    my ($cacheUrl,$filename,$size,$time) = @{shift @cacheInfo};

    $amountToReduce -= $size;
    _RemoveFromCache($cacheUrl);
  }
}

# ------------------------------------------------------------------------------

# Precondition: the data must not be in the cache.
sub _PutInCache
{
  my $url = shift;
  my $data = shift;

  dprint "Storing data in cache for URL:\n  $url";

  # Generate a new filename
  my $filename;
  do
  {
    $filename = sprintf('%d.html',rand()*100000);
  } while -e "$main::config{cachelocation}/$filename";

  mkpath ($main::config{cachelocation})
    unless -e "$main::config{cachelocation}";

  open REGISTRY,">>$main::config{cachelocation}/registry.txt"
    or die "Can't open cache registry file: $!";
  print REGISTRY "$url $filename ",length($data)," ",time,"\n";
  close REGISTRY;

  open CACHEFILE,">$main::config{cachelocation}/$filename"
    or die "Can't write to cache file ($main::config{cachelocation}/$filename): $!";
  print CACHEFILE $data;
  close CACHEFILE;

  return;
}

# ------------------------------------------------------------------------------

# Returns data from the cache, for a given URL. Returns undef if the data is
# not available.

sub _GetFromCache
{
  my $url = shift;

  my ($cacheUrl,$filename,$size,$time) = (undef,undef,undef,undef);

  open REGISTRY,"$main::config{cachelocation}/registry.txt" or return undef;
  while (defined(my $line = <REGISTRY>))
  {
    chomp $line;
    ($cacheUrl,$filename,$size,$time) = split / /,$line;

    last if $cacheUrl eq $url;
  }
  close REGISTRY;

  return undef unless $cacheUrl eq $url;

  open CACHEDDATA,"$main::config{cachelocation}/$filename"
    or die "Can't locate file $filename in the cache, even though it's".
           " listed\n  in the registry.\n";
  my $data = join '',<CACHEDDATA>;
  close CACHEDDATA;

  return $data;
}

# ------------------------------------------------------------------------------

# Gets the data from the cache, if it is available, as well as the status. The
# possible return combinations are:
# DATA, valid: Data is in cache and not stale
# DATA, stale: Data is in cache but stale
# undef, not found: Data is not in cache

sub GetData
{
  my $self = shift;
  my $url = shift;
  my @updateTimes = @_;

  return (_GetFromCache($url),_IsStillValid($url,@updateTimes));
}

# ------------------------------------------------------------------------------

sub CacheData
{
  my $self = shift;
  my $url = shift;
  my $data = shift;

  _RemoveFromCache($url);

  if (-e "$main::config{cachelocation}/registry.txt")
  {
    # Get the current cache size.
    my $cacheSize = 0;

    open REGISTRY,"$main::config{cachelocation}/registry.txt"
      or die "Can't open cache registry file: $!";

    while (defined(my $line = <REGISTRY>))
    {
      chomp $line;
      my ($cacheUrl,$filename,$size,$time) = split / /,$line;

      $cacheSize += $size;
    }
    close REGISTRY;

    # Reduce the cache size if necessary
    _ReduceCacheSize(length $data)
      if $cacheSize + length $data > $main::config{maxcachesize};
  }


  # Cache it!
  _PutInCache($url,$data);
}

1;
