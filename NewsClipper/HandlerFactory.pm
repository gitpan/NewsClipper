# -*- mode: Perl; -*-
package NewsClipper::HandlerFactory;

# This package implements a "Handler Factory", which is used to find and
# return handler objects.

use strict;
use Carp;
# For UserAgent
use LWP::UserAgent;
# For mkpath
use File::Path;
# For find
use File::Find;

use vars qw( $VERSION );

$VERSION = 0.83;

use NewsClipper::Globals;

my $userAgent = new LWP::UserAgent;

my $TIME_BETWEEN_FUNCTIONAL_UPDATES = 24 * 60 * 60;
my $TIME_BETWEEN_BUGFIX_UPDATES = 8 * 60 * 60;
my $HANDLER_SERVER = 'handlers.newsclipper.com';
#my $HANDLER_SERVER = '192.168.0.1';
my $COMPATIBLE_NEWS_CLIPPER_VERSION = 1.18;

# Used to avoid unnecessary processing of handlers
my @updatedHandlers;
my @allowedHandlers;
my @compatibleHandlers;

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

# Finds and creates a handler object for the given name. Be careful here that
# you don't actually load the handler until you are sure that it is compatible
# with this version of News Clipper.

sub Create
{
  my $self = shift;
  my $handlerName = shift;

  croak "You must supply a handler name to HandlerFactory\n"
    unless defined $handlerName;

  $handlerName = lc($handlerName);

  _CheckRegistrationRestriction($handlerName);

  {
    my $handler_version_compatibility_result = 
      _HandlerVersionIsCompatible($handlerName);
    return undef if defined $handler_version_compatibility_result &&
      $handler_version_compatibility_result == 0;
  }

  # Download the handler if we need to, either because ours is
  # out of date, or because we don't have it installed.
  my $update_result = _DoHandlerUpdate($handlerName);

  my $loadResult;

  # Be sure to "unload" the handler by deleting it from %INC
  if ($update_result eq 'updated')
  {
    # Try to reload the handler
    $loadResult = _LoadHandler($handlerName,1);
  }
  else
  {
    # Try to load the handler
    $loadResult = _LoadHandler($handlerName,0);
  }

  if ($loadResult =~ /^Found/)
  {
    dprint "Creating handler \"$handlerName\"";
    my ($fullHandler) = $loadResult =~ /Found as (.*)/;
    return "$fullHandler"->new;
  }
  elsif ($loadResult eq 'Not found')
  {
    warn "Can not find handler \"$handlerName\", and can not download it.\n";
    return undef;
  }
}

# ------------------------------------------------------------------------------

# Updates from the remote the handler if necessary. Returns 'updated' if the
# handler was updated, and 'not updated' otherwise. Updates are necessary if:
# the handler isn't anywhere on the system
# auto_download_bugfix_updates is 'yes' and there is a bugfix version
# -n was specified and a functional or bugfix version is available.

sub _DoHandlerUpdate
{
  my $handlerName = shift;

  dprint "Checking if handler \"$handlerName\" needs to be updated.";

  # Skip this handler if we've already processed it.
  if (grep { /^$handlerName$/i } @updatedHandlers)
  {
    dprint "Skipping already checked handler \"$handlerName\".";
    return 'not updated';
  }

  push @updatedHandlers,$handlerName;

  # First check if the handler isn't on the system.
  if (_LoadHandler($handlerName,0) eq 'Not found')
  {
    dprint "Handler isn't installed, " .
      "so we need to download a functional update.";

    my ($versionStatus,$newVersion,$updateType) =
      _GetNewHandlerVersion($handlerName,0);

    if ($versionStatus eq 'okay')
    {
      dprint "There is a remote handler available.";
    }
    elsif ($versionStatus eq 'not found' || $versionStatus eq 'no update')
    {
      return 'not updated';
    }
    # failed, so we check next time too instead of waiting
    else
    {
      dprint "News Clipper could not get version information for handler " .
        "$handlerName. Maybe the server is down.";
      return 'not updated';
    }

    my $download_result = _DownloadHandler($handlerName,$newVersion);

    return 'updated' if $download_result eq 'okay';
    return 'not updated' if $download_result ne 'okay';
  }

  my $update_status;

  $update_status = _DoHandlerFunctionalUpdate($handlerName);
  return 'updated' if $update_status eq 'updated';

  $update_status = _DoHandlerBugfixUpdate($handlerName);
  return $update_status;
}

# ------------------------------------------------------------------------------

# Checks for and does a functional update for a handler. Returns 'updated' or
# 'not updated'.

sub _DoHandlerFunctionalUpdate
{
  my $handlerName = shift;

  # Functional updates are only prompted by -n
  unless ($opts{n})
  {
    dprint "Skipping functional update check -- -n not specified";
    return 'not updated';
  }

  # Check if we've already done a functional check in the last time period
  {
    my $lastCheck =
      $NewsClipper::Globals::state->get("last_functional_check_$handlerName");

    if (defined $lastCheck &&
             (time - $lastCheck < $TIME_BETWEEN_FUNCTIONAL_UPDATES))
    {
      dprint "Don't need to check for a functional update yet.";
      return 'not updated';
    }
  }

  # Now do the check
  my ($versionStatus,$newVersion,$updateType) =
    _GetNewHandlerVersion($handlerName,0);

  if ($versionStatus eq 'okay')
  {
    dprint "There is a new " . $updateType . " version.";
    $NewsClipper::Globals::state->set("last_functional_check_$handlerName",time);
    $NewsClipper::Globals::state->set("last_bugfix_check_$handlerName",time);
  }
  elsif ($versionStatus eq 'not found' || $versionStatus eq 'no update')
  {
    $NewsClipper::Globals::state->set("last_functional_check_$handlerName",time);
    $NewsClipper::Globals::state->set("last_bugfix_check_$handlerName",time);
    return 'not updated';
  }
  # failed, so we check next time too instead of waiting
  else
  {
    return 'not updated';
  }

  # Do automatic download if it's a bugfix and auto_download_bugfix_updates is
  # specified, or if -a was specified.
  if ($opts{a} || ($updateType eq 'bugfix' && 
        $main::config{auto_download_bugfix_updates} =~ /^y/i))
  {
    dprint "Doing automatic download for handler \"$handlerName\"";
  }
  # Prompt the user if run interactively, and the user didn't specify one of
  # the auto download options
  elsif (-t STDIN)
  {
    warn "There is a newer version of handler \"$handlerName\".\n";
    warn "Would you like News Clipper to attempt to download it? [y/n]\n";
    my $response = <STDIN>;

    return 'not updated' if $response !~ /^y/i;
  }
  # Otherwise we just warn the user we can't do a download
  elsif ($updateType eq 'bugfix')
  {
    warn reformat dequote <<"    EOF";
      A bugfix update to handler "$handlerName" is available, but it can't be
      downloaded because auto_download_bugfix_updates is not "yes" in your
      configuration file, and since News Clipper can't ask you interactively.
    EOF
    return 'not updated';
  }
  elsif ($updateType eq 'functional')
  {
    warn reformat dequote <<"    EOF";
      A functional update to handler "$handlerName" is available, but it can't
      be downloaded because the -a flag was not specified, and since News
      Clipper can't ask you interactively.
    EOF
    return 'not updated';
  }
  else
  {
    die "News Clipper encountered an unknown input scenario";
  }

  my $download_result = _DownloadHandler($handlerName,$newVersion);

  return 'updated' if $download_result eq 'okay';
  return 'not updated' if $download_result ne 'okay';
}

# ------------------------------------------------------------------------------

# Checks for and does a bugfix update for a handler. Returns 'updated' or
# 'not updated'.

sub _DoHandlerBugfixUpdate
{
  my $handlerName = shift;

  # Bugfix updates are only prompted by -n or auto_download_bugfix_updates
  unless ($opts{n} || $main::config{auto_download_bugfix_updates} =~ /^y/i)
  {
    dprint "Skipping bugfix update check -- neither -n nor " .
      "auto_download_bugfix_updates was specified";
    return 'not updated';
  }

  # Check if we've already done a bugfix check in the last time period
  {
    my $lastCheck =
      $NewsClipper::Globals::state->get("last_bugfix_check_$handlerName");

    if (defined $lastCheck &&
             (time - $lastCheck < $TIME_BETWEEN_BUGFIX_UPDATES))
    {
      dprint "Don't need to check for a bugfix update yet.";
      return 'not updated';
    }
  }

  # Now do the check
  my ($versionStatus,$newVersion,$updateType) =
    _GetNewHandlerVersion($handlerName,1);

  if ($versionStatus eq 'okay')
  {
    dprint "There is a new bugfix version.";
    $NewsClipper::Globals::state->set("last_bugfix_check_$handlerName",time);
  }
  elsif ($versionStatus eq 'not found' || $versionStatus eq 'no update')
  {
    $NewsClipper::Globals::state->set("last_bugfix_check_$handlerName",time);
    return 'not updated';
  }
  # failed, so we check next time too instead of waiting
  else
  {
    return 'not updated';
  }

  # Do automatic download if it's a bugfix and auto_download_bugfix_updates is
  # specified, or if -a was specified.
  if ($opts{a} || ($updateType eq 'bugfix' && 
        $main::config{auto_download_bugfix_updates} =~ /^y/i))
  {
    dprint "Doing automatic download for handler \"$handlerName\"";
  }
  # Prompt the user if run interactively, and the user didn't specify one of
  # the auto download options
  elsif (-t STDIN)
  {
    warn "There is a newer version of handler \"$handlerName\".\n";
    warn "Would you like News Clipper to attempt to download it? [y/n]\n";
    my $response = <STDIN>;

    return 'not updated' if $response !~ /^y/i;
  }
  # Otherwise we just warn the user we can't do a download
  elsif ($updateType eq 'bugfix')
  {
    warn reformat dequote <<"    EOF";
      A bugfix update to handler "$handlerName" is available, but it can't be
      downloaded because auto_download_bugfix_updates is not "yes" in your
      configuration file, and since News Clipper can't ask you interactively.
    EOF
  }
  elsif ($updateType eq 'functional')
  {
    warn reformat dequote <<"    EOF";
      A functional update to handler "$handlerName" is available, but it can't
      be downloaded because the -a flag was not specified, and since News
      Clipper can't ask you interactively.
    EOF
  }
  else
  {
    die "News Clipper encountered an unknown input scenario";
  }

  my $download_result = _DownloadHandler($handlerName,$newVersion);

  return 'updated' if $download_result eq 'okay';
  return 'not updated' if $download_result ne 'okay';
}

# ------------------------------------------------------------------------------

# This function finds the News Clipper compatible version of the locally
# installed handler. Returns the version number or undef if the handler could
# not be found.

sub _GetLocalHandlerNCVersion($)
{
  my $handlerName = shift;

  # Find the handler
  my $foundDirectory = _GetHandlerPath($handlerName);

  return undef unless defined $foundDirectory;

  open LOCALHANDLER, "$foundDirectory/$handlerName.pm";
  my $handler_code = join '',<LOCALHANDLER>;
  close LOCALHANDLER;

  # Really there should be underscores between the words, but there are a few
  # handlers out there with the wrong thing.
  my ($for_news_clipper_version) =
    $handler_code =~ /'For.News.Clipper.Version'} *= *'(.*?)' *;/s;

  my $nc_version;

  # Ug. Pre "For_News_Clipper_Version" days...
  if (!defined $for_news_clipper_version)
  {
    return '1.00';
  }
  else
  {
    return $for_news_clipper_version;
  }
}

# ------------------------------------------------------------------------------

# This function finds the version of the locally installed handler. Returns
# the version number or undef if the handler could not be found.

sub _GetLocalHandlerVersion($)
{
  my $handlerName = shift;

  # Load the handler if we need to.
  my $loadResult = _LoadHandler($handlerName,0);

  if ($loadResult eq 'Not found')
  {
    dprint "Handler \"$handlerName\" not found locally.";
    return undef;
  }

  my $foundDirectory = _GetHandlerPath($handlerName);

  dprint "Found local copy of handler in:\n  $foundDirectory";

  open LOCALHANDLER, "$foundDirectory/$handlerName.pm";
  my $localHandler = join '',<LOCALHANDLER>;
  close LOCALHANDLER;

  my ($versionCode) = $localHandler =~ /\$VERSION\s*=\s*(.*?);[ ]*$/m;
  my $localVersion = eval "$versionCode";

  dprint "Local version for handler \"$handlerName\" is: $localVersion";

  return $localVersion;
}

# ------------------------------------------------------------------------------

# This routine restricts the personal version to 5 built-in handlers and 5
# optional ones.

sub _CheckRegistrationRestriction($)
{
  my $handlerName = shift;

  dprint "Checking if handler \"$handlerName\" is okay to use.";

  # Skip this handler if we've already processed it.
  if (grep { /^$handlerName$/i } @allowedHandlers)
  {
    dprint "Skipping already checked handler \"$handlerName\".";
    return;
  }

  push @allowedHandlers,$handlerName;

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

  # Yell if they have the trial version and are doing any acquisition handler
  # other than yahootopstories
  if ($config{product} eq 'Trial')
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
  if ($#installedHandlers+1 > $config{numberhandlers})
  {
    local $" = "\n";
    warn reformat dequote <<"    EOF";

      You currently have more than the allowed number of handlers on your
      system.  This personal version of News Clipper is only registered to
      used $config{numberhandlers} handlers.

      Please delete one or more of the following files:
    EOF
    die "@installedHandlers\n";
  }

  # Yell if they have the registered number of handlers on their system, and
  # the current handler isn't one of them.
  if (($#installedHandlers+1 == $config{numberhandlers}) &&
      (!grep {/$handlerName.pm$/} @installedHandlers))
  {
    local $" = "\n";
    warn reformat dequote <<"    EOF";
      You currently have $config{numberhandlers} handlers on your
      system, and are trying to use a handler that is not one of these five
      ($handlerName). This personal version of News Clipper is only registered
      to use $config{numberhandlers} handlers.

      Please delete one or more of the following files if you want to be able
      to use this handler:
    EOF
    die "@installedHandlers\n";
  }
}

# ------------------------------------------------------------------------------

# This routine checks that a handler on the system is for the current version
# of News Clipper. Returns 1 if the handler is compatible, 0 if it is not, and
# undef if it wasn't found.

sub _HandlerVersionIsCompatible($)
{
  my $handlerName = shift;

  dprint "Checking if handler \"$handlerName\" is okay to use.";

  # Skip this handler if we've already processed it.
  if (grep { /^$handlerName$/i } @compatibleHandlers)
  {
    dprint "Skipping handler \"$handlerName\" (already checked compatibility.";
    return;
  }

  push @compatibleHandlers,$handlerName;

  my $local_handler_nc_version = _GetLocalHandlerNCVersion($handlerName);

  return undef unless defined $local_handler_nc_version;

  dprint "Handler \"$handlerName\" was written for News Clipper version " .
    "$local_handler_nc_version, and";
  dprint "  this version of News Clipper is compatible with version " .
    "$COMPATIBLE_NEWS_CLIPPER_VERSION.";

  if ($local_handler_nc_version != $COMPATIBLE_NEWS_CLIPPER_VERSION)
  {
    $errors{"handler#$handlerName"} =
      "Handler is incompatible. (Compatible with News Clipper versions that " .
      "take handlers from version $local_handler_nc_version, but this " .
      "version of News Clipper uses handlers from version " .
      "$COMPATIBLE_NEWS_CLIPPER_VERSION).";
    return 0;
  }
  else
  {
    return 1;
  }
}

# ------------------------------------------------------------------------------

my @acquisitionHandlers;
sub _GetAcquisitionHandlers
{
  if (@acquisitionHandlers)
  {
    dprint "Reusing cached list of acquisition handlers.";
    return @acquisitionHandlers;
  }

  dprint "Downloading list of acquisition handlers.\n";

  my $url = "http://" . $HANDLER_SERVER . "/cgi-bin/getinfo?field=Type&string=Acquisition&print=Name&ncversion=$main::VERSION";

  my $data = _DownloadURL($url);

  die "Couldn't download the list of acquisition handlers. Maybe".
         " the server is down.\n"
    unless defined $data;

  my (@handlers) = $$data =~ /Name +: (.*)/g;
  @acquisitionHandlers = @handlers;
  return @handlers;
}

# ------------------------------------------------------------------------------

# Figure out where the handler is in the file system. (This function does not
# load the handler.)

sub _GetHandlerPath($)
{
  my $handlerName = shift;

  my @dirs = qw(Acquisition Filter Output);

  foreach my $dir (@INC)
  {
    return "$dir/NewsClipper/Handler/Acquisition"
      if -e "$dir/NewsClipper/Handler/Acquisition/$handlerName.pm";
    return "$dir/NewsClipper/Handler/Filter"
      if -e "$dir/NewsClipper/Handler/Filter/$handlerName.pm";
    return "$dir/NewsClipper/Handler/Output"
      if -e "$dir/NewsClipper/Handler/Output/$handlerName.pm";
  }

  return undef;
}

# ------------------------------------------------------------------------------

# Loads or reloads a handler, depending on whether the second argument is
# nonzero.

sub _LoadHandler($$)
{
  my $handlerName = shift;
  my $reload = shift;

  if ($reload)
  {
    dprint "Trying to reload handler \"$handlerName\"";

    delete $INC{"NewsClipper/Handler/Acquisition/$handlerName.pm"};
    delete $INC{"NewsClipper/Handler/Filter/$handlerName.pm"};
    delete $INC{"NewsClipper/Handler/Output/$handlerName.pm"};
  }
  else
  {
    dprint "Trying to load handler \"$handlerName\"";
  }

  my @dirs = qw(Acquisition Filter Output);

  # Return if it has already been loaded before. This helps speed things up.
  foreach my $dir (@dirs)
  {
    if (defined $INC{"NewsClipper/Handler/$dir/$handlerName.pm"})
    {
      dprint "Handler \"$handlerName\" already loaded";
      return "Found as NewsClipper::Handler::${dir}::$handlerName" 
    }
  }

  foreach my $dir (@dirs)
  {
    # Try to load it in $dir
    dprint "Looking for handler as NewsClipper::Handler::$dir\::$handlerName";

    # Here we need to store errors.
    my $errors;
    {
      local $SIG{__WARN__} =
        sub
        {
          # We ignore redefined messages during reload
          return if $reload && $_[0] =~ /Subroutine (\w+) redefined/;

          $errors .= $_[0]
        };

      eval "require NewsClipper::Handler::${dir}::$handlerName";
    }

# At this point, the possibilities are:
# $errors     empty, $@ non-empty, $INC{} non-empty: impossible
# $errors non-empty, $@ non-empty, $INC{} non-empty: compile error on eval
# $errors     empty, $@     empty, $INC{} non-empty: winner!
# $errors non-empty, $@     empty, $INC{} non-empty: $errors holds warnings
# $errors     empty, $@ non-empty, $INC{}     empty: handler not found, etc.
# $errors non-empty, $@ non-empty, $INC{}     empty: $errors holds errors?
# $errors     empty, $@     empty, $INC{}     empty: impossible
# $errors non-empty, $@     empty, $INC{}     empty: eval had syntax error

    # Something went wrong
    if ($@)
    {
      # We'll skip can't locate messages, but stop on everything else
      if ($@ !~ /Can't locate NewsClipper.Handler.$dir.$handlerName/)
      {
        $@ =~ s/Compilation failed in require at \(eval.*?\n//s;

        warn "Handler $handlerName was found in:\n";
        warn "  ",$INC{"NewsClipper/Handler/$dir/$handlerName.pm"},"\n";
        warn "  but could not be loaded because of the following error:\n\n";
        warn "$errors\n" if defined $errors;
        die "$@\n";
      }
    }

    if (defined $INC{"NewsClipper/Handler/$dir/$handlerName.pm"})
    {
      dprint "Found handler as:\n ",
                  $INC{"NewsClipper/Handler/$dir/$handlerName.pm"};

      # If there's anything in $errors, it must be warnings. Store them
      # for later printing.
      $errors{"handler#$handlerName"} = $errors if defined $errors;

      return "Found as NewsClipper::Handler::$dir\::$handlerName"
    }

    # We can get here if the eval has a syntax error. (e.g. if someone tries
    # to use handler.pm as the handler name)
    if ($errors)
    {
      warn "Handler $handlerName could not be loaded. The error was:\n";
      die "$errors\n";
    }
  }

  # Darn. Couldn't find it anywhere!
  dprint "Couldn't find handler";
  return "Not found";

}

# ------------------------------------------------------------------------------

# This function downloads and saves a remote handler, if one exists. Returns
# 'okay' or 'failed'

sub _DownloadHandler($$)
{
  my $handlerName = shift;
  my $version = shift;

  dprint "Downloading handler $handlerName, version $version";

  # Try to load the handler so we can figure out where to put the replacement
  my $loadResult = _LoadHandler($handlerName,0);

  my ($getResult,$code) = _GetHandlerCode($handlerName,$version);

  return 'failed' if $getResult ne 'okay';

  my $foundDirectory = _GetHandlerPath($handlerName);

  # Remove the outdated one.
  unlink "$foundDirectory/$handlerName.pm" if defined $foundDirectory;

  # Use the old directory, or create a new one based on what the handler calls
  # itself.
  my $destDirectory;
  if (defined $foundDirectory)
  {
    dprint "Replacing handler located in\n  $foundDirectory";
    $destDirectory = $foundDirectory;
  }
  else
  {
    my ($subDir) = $code =~ /package NewsClipper::Handler::([^:]*)::/;
    $destDirectory =
      "$config{handlerlocations}[0]/NewsClipper/Handler/$subDir";

    dprint "Saving new handler to $destDirectory";
  }

  mkpath $destDirectory unless -e $destDirectory;

  # Write the handler.
  open HANDLER,">$destDirectory/$handlerName.pm"
    or return 'failed';
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

  return 'okay';
}

# ------------------------------------------------------------------------------

# This function downloads a new handler from the handler database.  The first
# argument is the name of the handler. The second argument is the version
# number of the current handler. You should call _GetNewHandlerVersion before
# calling this function.

# This function returns two values:
# - an error code: (okay, Download failed)
# - the handler (if the error code is okay)

# Cache downloaded code for this run.
my %downloadedCode;

sub _GetHandlerCode($$)
{
  my $handlerName = shift;
  my $version = shift;

  dprint "Downloading code for handler \"$handlerName\"";

  if (defined $downloadedCode{$handlerName})
  {
    dprint "Reusing already downloaded code.";
    return ('okay',$downloadedCode{$handlerName});
  }

  my $url;

  $url = "http://" . $HANDLER_SERVER . "/cgi-bin/gethandler?tag=$handlerName&ncversion=$main::VERSION&version=$version";

  my $data = _DownloadURL($url);

  if (defined $data && $$data =~ /^Handler not found/)
  {
    warn "Server reports that handler \"$handlerName\" doesn't exist.\n";
    return ('Handler not found',undef);
  }

  # If either the download failed, or the thing we got back doesn't look like
  # a handler...
  if ((!defined $data) || ($$data !~ /package NewsClipper/))
  {
    warn "Couldn't download handler \"$handlerName\"." .
      " Maybe the server\n  is down.\n";

    warn "Message from server is:\n\n$$data\n" if defined $data;

    return ('Download failed',undef);
  }

  $downloadedCode{$handlerName} = $$data;

  return ('okay',$$data);
}

# ------------------------------------------------------------------------------

# Checks if a new version of the handler is available, taking consideration of
# -n flag into account.
# Params:
# 1) the handler name
# 2) whether you want only a bugfix update, not a functional update too
# Returns:
# 1) status: okay, failed, not found, no update
# 2) the version
# 3) type of update it is ("bugfix" or "functional")
#    if $needBugfix == 0, type can be either bugfix or functional.
#    if $needBugfix == 1, type can be only bugfix.

sub _GetNewHandlerVersion($$)
{
  my $handlerName = shift;
  my $needBugfix = shift;

  dprint "Checking for a new version for handler \"$handlerName\"";

  # A version of undef means that we want whatever the newest version is,
  # regardless of functional compatibility.
  my $localVersion = _GetLocalHandlerVersion($handlerName);

  my $url = "http://" . $HANDLER_SERVER .
    "/cgi-bin/checkversion?tag=$handlerName&ncversion=$main::VERSION";

  # Server assumes no version param means get most recent version
  $url .= "&version=$localVersion" if defined $localVersion;

  if ($needBugfix)
  {
    $url .= "&debug=1";
  }
  else
  {
    $url .= "&debug=0";
  }

  dprint "Checking for new version for handler \"$handlerName\"";
  my $data = _DownloadURL($url);

  # If the download failed...
  unless (defined $data)
  {
    warn "Couldn't download handler version information for \"$handlerName\"." .
      " Maybe the server\n  is down.\n";
    return 'failed';
  }

  if ($$data =~ /^Handler not found/)
  {
    dprint "Server reports that handler \"$handlerName\" doesn't exist.\n";
    return 'not found';
  }

  if ($$data =~ /^No new version available/)
  {
    dprint "No new version is available";
    return 'no update';
  }

  # We actually got a version
  my $updateType;

  my ($newVersion) = $$data =~ /(\S+)/;

  if (defined $localVersion)
  {
    if (int($newVersion * 100) == int($localVersion * 100))
    {
      $updateType = 'bugfix';
    }
    else
    {
      $updateType = 'functional';
    }

    dprint "A new version is available.\n  New version:$newVersion " .
      "Old version: $localVersion Update type: $updateType\n";
  }
  else
  {
    $updateType = 'functional';

    dprint "A new version is available.\n  New version:$newVersion " .
      "Old version: <NONE FOUND> Update type: $updateType\n";
  }

  return ('okay',$newVersion,$updateType);
}

# ------------------------------------------------------------------------------

# Gets the entire content from a URL. file:// supported

sub _DownloadURL($)
{
  my $url = shift;

  $userAgent->timeout($config{socketTimeout});
  $userAgent->proxy(['http', 'ftp'], $config{proxy})
    if $config{proxy} ne '';
  my $request = new HTTP::Request GET => "$url";
  if ($config{proxy_username} ne '')
  {
    $request->proxy_authorization_basic($config{proxy_username},
                     $config{proxy_password});
  }

  my $result;
  my $numTriesLeft = $config{socketTries};

  do
  {
    $result = $userAgent->request($request);
    $numTriesLeft--;
  } until ($numTriesLeft == 0 || $result->is_success);

  return undef unless $result->is_success;

  my $content = $result->content;

  # Strip linefeeds off the lines
  $content =~ s/\r//gs;

  return \$content;
}

1;
