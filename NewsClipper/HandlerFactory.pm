# -*- mode: Perl; -*-
package NewsClipper::HandlerFactory;

use strict;
use Carp;
# For UserAgent
use LWP::UserAgent;
# For mkpath
use File::Path;
# For find
use File::Find;

use vars qw( $VERSION );

$VERSION = 0.73;

BEGIN
{
  # We do this in the BEGIN block to get the DEBUG constant before the rest of
  # the code is compiled into bytecode.
  require NewsClipper::Globals;
  NewsClipper::Globals->import;
}

my $userAgent = new LWP::UserAgent;

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

# Gets the entire content from a URL. file:// supported
sub _DownloadURL
{
  my $url = shift;

  $userAgent->timeout($main::config{socketTimeout});
  $userAgent->proxy(['http', 'ftp'], $main::config{proxy})
    if $main::config{proxy} ne '';
  my $request = new HTTP::Request GET => "$url";
  if ($main::config{proxy_username} ne '')
  {
    $request->proxy_authorization_basic($main::config{proxy_username},
                     $main::config{proxy_password});
  }

  my $result = $userAgent->request($request);

  return undef unless $result->is_success;

  my $content = $result->content;

  # Strip linefeeds off the lines
  $content =~ s/\r//gs;

  return \$content;
}

# ------------------------------------------------------------------------------

sub _LoadHandler
{
  my $handlerName = shift;

  my @dirs = qw(Acquisition Filter Output);

  # Return if it has already been loaded before. This helps speed things up.
  foreach my $dir (@dirs)
  {
    return "Found as NewsClipper::Handler::$dir\::$handlerName" 
      if defined $INC{"NewsClipper/Handler/$dir/$handlerName.pm"};
  }

  foreach my $dir (@dirs)
  {
    # Try to load it in $dir
    dprint "Looking for handler as NewsClipper::Handler::$dir\::$handlerName";

    # Here we need to supress the warning about DEBUG being redefined. 
    {
      local $SIG{__WARN__} =
        sub { print STDERR $_[0] unless $_[0] =~ /DEBUG redefined/};
      eval "require NewsClipper::Handler::$dir\::$handlerName";
    }

    dprint "Found handler as:\n ",
                  $INC{"NewsClipper/Handler/$dir/$handlerName.pm"}
      if !$@;

    # No error message means we found it
    return "Found as NewsClipper::Handler::$dir\::$handlerName"
      if !$@;

    # We'll skip can't locate messages, but stop on everything else
    if ($@ !~ /^Can't locate NewsClipper.Handler.$dir.$handlerName/)
    {
      warn "Handler $handlerName was found in:\n";
      warn "  ",$INC{"NewsClipper/Handler/$dir/$handlerName.pm"},"\n";
      die "  but could not be loaded because of the following error:\n\n$@";
    }
  }

  # Darn. Couldn't find it anywhere!
  dprint "Couldn't find handler";
  return "Not found";
}

# ------------------------------------------------------------------------------

sub _GetHandlerCode
{
  my $handlerName = shift;

  my $url = "http://handlers.newsclipper.com/cgi-bin/gethandler?tag=$handlerName";
#  my $url = "http://192.168.0.1/cgi-bin/gethandler?tag=$handlerName";

  dprint "Downloading code for handler \"$handlerName\"";
  my $data = _DownloadURL($url);

  # If either the download failed, or the thing we got back doesn't look like
  # a handler...
  if ((!defined $data) || ($$data !~ /package NewsClipper/))
  {
    warn "Couldn't download handler \"$handlerName\". Maybe the server\n  is down.\n";

    warn "Message from server is:\n\n$$data\n" if defined $data;

    return 'Download failed';
  }

  if ($$data =~ /^Handler not found/)
  {
    warn "Server reports that handler \"$handlerName\" doesn't exist.\n";
  }

  return $$data;
}

# ------------------------------------------------------------------------------

sub _GetHandlerVersion
{
  my $handlerName = shift;

  my $url = "http://handlers.newsclipper.com/cgi-bin/getinfo?field=Name&string=^$handlerName\$&print=Version";
#  my $url = "http://192.168.0.1/cgi-bin/getinfo?field=Name&string=$handlerName&print=Version";

  dprint "Downloading version info for handler \"$handlerName\"";
  my $data = _DownloadURL($url);

  if (!defined $data)
  {
    warn "Couldn't download handler \"$handlerName\" maybe the server is down.\n";
    return 'Download failed';
  }

  if ($$data =~ /^Handler not found/)
  {
    warn "Server reports that handler \"$handlerName\" doesn't exist.\n";
  }

  $$data =~ s/.*Version *: (\S+).*/$1/s;

  return $$data;
}

# ------------------------------------------------------------------------------

# Precondition: you have to load the handler if it's already on the system, so
# that this routine will know where to put the replacement.
sub _DownloadHandler
{
  my $handlerName = shift;

  # See if it already exists on our system by checking where we already loaded
  # it from.
  my $foundDirectory =
    $INC{"NewsClipper/Handler/Acquisition/$handlerName.pm"} ||
    $INC{"NewsClipper/Handler/Filter/$handlerName.pm"} ||
    $INC{"NewsClipper/Handler/Output/$handlerName.pm"} || undef;

  $foundDirectory =~ s#/[^/]*$##;

  dprint "Downloading handler $handlerName";

  my $code = _GetHandlerCode($handlerName);

  return if $code =~ /^(Handler not found|Download failed)/;

  # Remove the outdated one.
  unlink "$foundDirectory/$handlerName.pm" if defined $foundDirectory;

  # Use the old directory, or create a new one based on what the handler calls
  # itself.
  my $destDirectory;
  if (defined $foundDirectory)
  {
    dprint "Replacing handler located in $foundDirectory";
    $destDirectory = $foundDirectory;
  }
  else
  {
    my ($subDir) = $code =~ /package NewsClipper::Handler::([^:]*)::/;
    $destDirectory =
      "$main::config{handlerlocations}[0]/NewsClipper/Handler/$subDir";

    mkpath $destDirectory unless -e $destDirectory;
  }

  # Write the handler.
  open HANDLER,">$destDirectory/$handlerName.pm";
  print HANDLER $code;
  close HANDLER;

  warn "The $handlerName handler has been downloaded and saved as\n";
  warn "  $destDirectory/$handlerName.pm\n";

  # Figure out if the handler needs any other modules.
  my @uses = $code =~ /\nuse (.*?);/g;

  @uses = grep {!/(vars|constant|NewsClipper|strict)/} @uses;

  if ($#uses != -1)
  {
    warn "The handler uses the following modules:\n";
    $" = "\n  ";
    warn "  @uses\n";
    warn "Make sure you have them installed.\n";
  }
}

# ------------------------------------------------------------------------------

# Precondition: you have to load the handler if it's already on the system, so
# that this routine will know where to put the replacement.

# This variable is a "static local" used to remember which handlers have
# already been checked.
my %alreadyCheckedVersion;
sub _HandlerOutdated
{
  my $handlerName = shift;

  dprint "Checking version of handler $handlerName";

  if (defined $alreadyCheckedVersion{$handlerName})
  {
    dprint "$handlerName has already been checked to see if it is outdated.";
    return 0;
  }

  $alreadyCheckedVersion{$handlerName} = 1;

  # See if it already exists on our system by checking where we already loaded
  # it from.
  my $foundDirectory =
    $INC{"NewsClipper/Handler/Acquisition/$handlerName.pm"} ||
    $INC{"NewsClipper/Handler/Filter/$handlerName.pm"} ||
    $INC{"NewsClipper/Handler/Output/$handlerName.pm"} || undef;

  $foundDirectory =~ s#/[^/]*$##;

  unless (defined $foundDirectory)
  {
    dprint "Handler $handlerName not found locally.";
    return 1;
  }

  my $remoteVersion = _GetHandlerVersion($handlerName);

  return 0 if $remoteVersion =~ /^(Handler not found|Download failed)/;

  dprint "Found local copy of handler in: $foundDirectory";

  open LOCALHANDLER, "$foundDirectory/$handlerName.pm";
  my $localHandler = join '',<LOCALHANDLER>;
  close LOCALHANDLER;
  my ($localVersion) = $localHandler =~ /\$VERSION *= *(.*?);/s;

  dprint "Comparing local version ($localVersion) to".
           " remote version ($remoteVersion)";

  if (($localVersion cmp $remoteVersion) == -1)
  {
    # Remote is newer. Need to download handler.
    dprint "Remote version is newer.";
    return 1;
  }
  else
  {
    # Local is newer. No need to download handler.
    dprint "Local version is newer.";
    return 0;
  }
}

# ------------------------------------------------------------------------------

my @acquisitionHandlerInfo;
sub _GetAcquisitionHandlers
{
  if (defined @acquisitionHandlerInfo)
  {
    dprint "Reusing cached information about available acquisition handlers.";
    return @acquisitionHandlerInfo;
  }

  my $url = "http://handlers.newsclipper.com/cgi-bin/getinfo?field=Type&string=Acquisition&print=Name";
#  my $url = "http://192.168.0.1/cgi-bin/getinfo?field=Type&string=Acquisition&print=Name";

  dprint "Downloading list of acquisition handlers.\n";
  my $data = _DownloadURL($url);

  die "Couldn't download information about the handler database. Maybe".
         " the server is down.\n"
    unless defined $data;

  my (@handlers) = $$data =~ /Name +: (.*)/g;
  @acquisitionHandlerInfo = @handlers;
  return @handlers;
}

# ------------------------------------------------------------------------------

# This routine restricts the personal version to 5 built-in handlers and 5
# optional ones.
sub _CheckHandlerOkay
{
  my $handlerName = shift;

  return if ($main::config{product} ne 'Personal') &&
            ($main::config{product} ne 'Trial');

  # Non-acquisition handlers are always okay to use.
  {
    my @acquisitionHandlers = _GetAcquisitionHandlers();
    unless (grep {/^$handlerName$/i} @acquisitionHandlers)
    {
      dprint "$handlerName isn't an acquisition handler -- okay to use.";
      return;
    }
  }

  dprint "Checking if handler \"$handlerName\" is okay to use.";

  # Yell if they have the trial version and are doing any acquisition handler
  # other than yahootopstories
  if ($main::config{product} eq 'Trial')
  {
    if ($handlerName ne 'yahootopstories')
    {
      die reformat dequote <<"      EOF";
        You can not use the "$handlerName" handler. The trial version of News
        Clipper only allows you to use the yahootopstories handler.
      EOF
    }

    return;
  }

  my @installedHandlers;

  dprint "Counting number of installed handlers.";

  foreach my $dir (@INC)
  {
    if (-d "$dir/NewsClipper/Handler/Acquisition")
    {
      # Gets all .pm files in $dir. Puts them in @handlers
      my @handlers;
      find(sub {push @handlers,"$File::Find::name"
          if /\.pm$/i},"$dir/NewsClipper/Handler/Acquisition");

      foreach my $handler (@handlers)
      {
        push @installedHandlers, $handler;
      }
    }
  }

  dprint $#installedHandlers+1," total acquisition handlers found.";

  # Yell if they have more than the registered number of handlers on their
  # system.
  if ($#installedHandlers+1 > $main::config{numberhandlers})
  {
    local $" = "\n";
    die reformat dequote <<"    EOF";

      You currently have more than the allowed number of handlers on your
      system.  This personal version of News Clipper is only registered to
      used $main::config{numberhandlers} handlers.

      Please delete one or more of the following files:
    EOF
    print "@installedHandlers\n";
  }

  # Yell if they have the registered number of handlers on their system, and
  # the current handler isn't one of them.
  if (($#installedHandlers+1 == $main::config{numberhandlers}) &&
      (!grep {/$handlerName.pm$/} @installedHandlers))
  {
    local $" = "\n";
    die reformat dequote <<"    EOF";
      You currently have $main::config{numberhandlers} handlers on your
      system, and are trying to use a handler that is not one of these five
      ($handlerName). This personal version of News Clipper is only registered
      to use $main::config{numberhandlers} handlers.

      Please delete one or more of the following files if you want to be able
      to use this handler:
    EOF
    print "@installedHandlers";
  }
}

# ------------------------------------------------------------------------------

sub Create
{
  my $self = shift;
  my $handlerName = shift;

  croak "You must supply a handler name to HandlerFactory\n"
    unless defined $handlerName;

  $handlerName = lc($handlerName);

  _CheckHandlerOkay($handlerName);

  # Try to load the handler
  my $loadResult = _LoadHandler($handlerName);

  # Figure out if we need to download the handler, either because ours is out
  # of date, or because we don't have it installed.
  if ($loadResult =~ /^Found/)
  {
    # Do a version check if the user wants it.
    if (exists $main::opts{n} and _HandlerOutdated($handlerName))
    {
      warn "There is a newer version of handler '$handlerName'.\n",
    }
    # Otherwise, we're done!
    else
    {
      my ($fullHandler) = $loadResult =~ /Found as (.*)/;
      return "$fullHandler"->new
    }
  }
  elsif ($loadResult eq 'Not found')
  {
    warn "Can not find handler '$handlerName'\n";
  }

  my $downloadedHandler = 0;

  # If we've made it this far, we must need to do a download.
  dprint "Download of new handler needed.";

  if (exists $main::opts{a})
  {
    warn "Doing automatic download.\n";
    _DownloadHandler($handlerName);
  }
  else
  {
    warn "Would you like News Clipper to attempt to download it? [y/n]\n";
    my $response = <STDIN>;

    if ($response =~ /^y/i)
    {
      _DownloadHandler($handlerName);
    }
    # If they don't want a download, but we have a local version, use it.
    elsif ($loadResult =~ /^Found/)
    {
      my ($fullHandler) = $loadResult =~ /Found as (.*)/;
      return "$fullHandler"->new
    }
  }

  # If we made it this far, we have just downloaded a new handler.

  # Delete any cached information from a previous load.
  if ($loadResult =~ /^Found/)
  {
    # Clear out the cached require information
    delete $INC{"NewsClipper/Handler/Acquisition/$handlerName.pm"};
    delete $INC{"NewsClipper/Handler/Filter/$handlerName.pm"};
    delete $INC{"NewsClipper/Handler/Output/$handlerName.pm"};
  }

  # Reload the handler
  $loadResult = _LoadHandler($handlerName);

  if ($loadResult =~ /^Found/)
  {
    my ($fullHandler) = $loadResult =~ /Found as (.*)/;
    return "$fullHandler"->new
  }

  # If we got this far, we must not have been able to load the handler.
  return undef;
}

1;
