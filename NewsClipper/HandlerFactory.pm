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

$VERSION = 0.89;

use NewsClipper::Globals;

my $userAgent = new LWP::UserAgent;

my $TIME_BETWEEN_FUNCTIONAL_UPDATES = 24 * 60 * 60;
my $TIME_BETWEEN_BUGFIX_UPDATES = 8 * 60 * 60;
my $HANDLER_SERVER = 'handlers.newsclipper.com';
#my $HANDLER_SERVER = '192.168.0.1';
my $COMPATIBLE_NEWS_CLIPPER_VERSION = 1.18;

# Caches used to avoid unnecessary processing of handlers
my @updatedHandlers;
my @allowedHandlers;
my @compatibleHandlers;
my %handler_type;
my %downloadedCode;

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

# Finds and creates a handler object for the given name. Downloads a new
# handler from the server if the handler is not installed on the system, or if
# an update is needed. Returns undef if the handler can not be loaded and
# created.

sub Create
{
  my $self = shift;
  my $handler_name = shift;

  croak "You must supply a handler name to HandlerFactory\n"
    unless defined $handler_name;

  $handler_name = lc($handler_name);

  # First see if the handler is okay to use given the trial/personal
  # restrictions.
  _CheckRegistrationRestriction($handler_name);

  # Check that the handler version is compatible
  {
    my $handler_version_compatibility_result = 
      _HandlerVersionIsCompatible($handler_name);

    if (defined $handler_version_compatibility_result &&
      $handler_version_compatibility_result == 0)
    {
      return undef;
    }
  }

  # Download the handler if we need to, either because ours is
  # out of date, or because we don't have it installed.
  my $update_result = _DoHandlerUpdate($handler_name);

  my $loadResult;

  # Try to load the handler
  $loadResult = _LoadHandler($handler_name);

  if ($loadResult =~ /^found/)
  {
    dprint "Creating handler \"$handler_name\"";
    my ($fullHandler) = $loadResult =~ /found as (.*)/;
    return "$fullHandler"->new;
  }
  elsif ($loadResult eq 'not found')
  {
    return undef;
  }
}

# ------------------------------------------------------------------------------

# Downloads or updates from the remote the handler if necessary. Returns
# 'updated' if the handler was updated, 'not updated' if it wasn't, and
# 'failed' if something when wrong. Updates are necessary if:
# * the handler isn't anywhere on the system
# * auto_download_bugfix_updates is 'yes' and there is a bugfix version
# * -n was specified and a functional or bugfix version is available.

sub _DoHandlerUpdate
{
  my $handler_name = shift;

  dprint "Checking if handler \"$handler_name\" needs to be updated.";

  # Skip this handler if we've already processed it.
  if (grep { /^$handler_name$/i } @updatedHandlers)
  {
    dprint "Skipping already checked handler \"$handler_name\".";
    return 'not updated';
  }

  push @updatedHandlers,$handler_name;

  # First check if the handler isn't on the system.
  if (_LoadHandler($handler_name) eq 'not found')
  {
    dprint "Handler isn't installed, so we need to download it.";

    my ($versionStatus,$newVersion,$updateType) =
      _GetNewHandlerVersion($handler_name,'functional');

    if ($versionStatus eq 'not found')
    {
      warn reformat dequote <<"      EOF";
        The handler server reports that the handler $handler_name is not in
        the database.
      EOF
      return 'failed';
    }

    if ($versionStatus eq 'no update')
    {
      die "News Clipper encountered a \"no update\" when there is no local " .
        "version of handler $handler_name";
    }

    if ($versionStatus eq 'failed')
    {
      warn reformat dequote <<"      EOF";
        Couldn't determine which version of the handler $handler_name to
        download because the server is down. Try again in a while, and send
        email to bugreport\@newsclipper.com if the problem persists.
      EOF
      return 'failed';
    }
    elsif ($versionStatus ne 'okay')
    {
      die "News Clipper encountered an unknown \$versionStatus";
    }

    dprint "There is a remote handler available.";

    my $download_result = _DownloadHandler($handler_name,$newVersion);
    return 'updated' if $download_result eq 'okay';

    if ($download_result eq 'not found')
    {
      warn reformat dequote <<"      EOF";
        Couldn't install the handler $handler_name. The handler server reports
        that the handler is not in the database.
      EOF
      return 'failed';
    }
    elsif ($download_result =~ /failed: (.*)/s)
    {
      warn reformat dequote $1;
      return 'failed';
    }
  }
  # The handler is on the system, so do an update if we need to.
  else
  {
    my $update_status;

    $update_status = _DoHandlerFunctionalUpdate($handler_name);

    if ($update_status eq 'updated')
    {
      _UnLoadHandler($handler_name);
      return 'updated';
    }
    elsif ($update_status eq 'failed')
    {
      return 'failed';
    }
    elsif ($update_status ne 'not updated')
    {
      die "News Clipper encountered an unknown \$update_status";
    }

    $update_status = _DoHandlerBugfixUpdate($handler_name);

    if ($update_status eq 'updated')
    {
      _UnLoadHandler($handler_name);
      return 'updated';
    }
    elsif ($update_status eq 'not updated')
    {
      return 'not updated';
    }
    elsif ($update_status eq 'failed')
    {
      return 'failed';
    }
    else
    {
      die "News Clipper encountered an unknown \$update_status";
    }
  }
}

# ------------------------------------------------------------------------------

# Checks for and does a functional update for a handler. Returns 'updated',
# 'not updated', or 'failed'. Handles any error messages to the user.

sub _DoHandlerFunctionalUpdate
{
  my $handler_name = shift;

  # Functional updates are only prompted by -n
  unless ($opts{n})
  {
    dprint "Skipping functional update check -- -n not specified";
    return 'not updated';
  }

  # Check if we've already done a functional check in the last time period
  {
    my $lastCheck =
      $NewsClipper::Globals::state->get("last_functional_check_$handler_name");

    if (defined $lastCheck &&
             (time - $lastCheck < $TIME_BETWEEN_FUNCTIONAL_UPDATES))
    {
      dprint "Don't need to check for a functional update yet.";
      return 'not updated';
    }
  }

  # Now do the check
  my ($versionStatus,$newVersion,$updateType) =
    _GetNewHandlerVersion($handler_name,'functional');

  if ($versionStatus eq 'not found')
  {
    dprint reformat (65,dequote <<"    EOF");
      Can't do functional update of handler $handler_name.
      Handler server reports that handler $handler_name is not in the database.
    EOF
    $NewsClipper::Globals::state->set("last_functional_check_$handler_name",time);
    $NewsClipper::Globals::state->set("last_bugfix_check_$handler_name",time);
    return 'not updated';
  }
  elsif ($versionStatus eq 'no update')
  {
    dprint "There is a no new functional or bugfix update version.";
    $NewsClipper::Globals::state->set("last_functional_check_$handler_name",time);
    $NewsClipper::Globals::state->set("last_bugfix_check_$handler_name",time);
    return 'not updated';
  }
  # failed, so we check next time too instead of waiting
  elsif ($versionStatus eq 'failed')
  {
    $errors{"handler#$handler_name"} = reformat dequote <<"    EOF";
      Couldn't determine if there is a newer functional update version of
      $handler_name available because the server is down. Try again in a while,
      and send email to bugreport\@newsclipper.com if the problem persists.
    EOF
    return 'failed';
  }
  elsif ($versionStatus ne 'okay')
  {
    die "News Clipper encountered an unknown \$versionStatus";
  }

  dprint "There is a new " . $updateType . " version.";
  $NewsClipper::Globals::state->set("last_functional_check_$handler_name",time);
  $NewsClipper::Globals::state->set("last_bugfix_check_$handler_name",time);

  # Do automatic download if it's a bugfix and auto_download_bugfix_updates is
  # specified, or if -a was specified.
  if ($opts{a} || ($updateType eq 'bugfix' && 
        $main::config{auto_download_bugfix_updates} =~ /^y/i))
  {
    dprint "Doing automatic download for handler \"$handler_name\"";
  }
  # Prompt the user if run interactively, and the user didn't specify one of
  # the auto download options
  elsif (-t STDIN)
  {
    warn "There is a newer version of handler \"$handler_name\".\n";
    warn "Would you like News Clipper to attempt to download it? [y/n]\n";
    my $response = <STDIN>;

    return 'not updated' if $response !~ /^y/i;
  }
  # Otherwise we just warn the user we can't do a download
  elsif ($updateType eq 'bugfix')
  {
    $errors{"handler#$handler_name"} = reformat dequote <<"    EOF";
      A bugfix update to handler "$handler_name" is available, but it can't be
      downloaded because auto_download_bugfix_updates is not "yes" in your
      configuration file, and since News Clipper can't ask you interactively.
    EOF
    return 'not updated';
  }
  elsif ($updateType eq 'functional')
  {
    $errors{"handler#$handler_name"} = reformat dequote <<"    EOF";
      A functional update to handler "$handler_name" is available, but it can't
      be downloaded because the -a flag was not specified, and since News
      Clipper can't ask you interactively.
    EOF
    return 'not updated';
  }
  else
  {
    die "News Clipper encountered an unknown input scenario";
  }

  my $download_result = _DownloadHandler($handler_name,$newVersion);
  return 'updated' if $download_result eq 'okay';

  if ($download_result eq 'not found')
  {
    $errors{"handler#$handler_name"} = reformat dequote <<"    EOF";
      Couldn't do a functional update of the handler $handler_name. The handler
      server reports that the handler is not in the database.
    EOF
    return 'failed';
  }
  elsif ($download_result =~ /failed: (.*)/s)
  {
    $errors{"handler#$handler_name"} = reformat dequote $1;
    return 'failed';
  }
}

# ------------------------------------------------------------------------------

# Checks for and does a bugfix update for a handler. Returns 'updated',
# 'not updated', or 'failed'. Handles any error messages to the user.

sub _DoHandlerBugfixUpdate
{
  my $handler_name = shift;

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
      $NewsClipper::Globals::state->get("last_bugfix_check_$handler_name");

    if (defined $lastCheck &&
             (time - $lastCheck < $TIME_BETWEEN_BUGFIX_UPDATES))
    {
      dprint "Don't need to check for a bugfix update yet.";
      return 'not updated';
    }
  }

  # Now do the check
  my ($versionStatus,$newVersion,$updateType) =
    _GetNewHandlerVersion($handler_name,'bugfix');

  if ($versionStatus eq 'not found')
  {
    dprint reformat (65,dequote <<"    EOF");
      Can't do bugfix update of handler $handler_name.
      Handler server reports that handler $handler_name is not in the database.
    EOF
    $NewsClipper::Globals::state->set("last_bugfix_check_$handler_name",time);
    return 'not updated';
  }
  elsif ($versionStatus eq 'no update')
  {
    dprint "There is a no new bugfix update version.";
    $NewsClipper::Globals::state->set("last_bugfix_check_$handler_name",time);
    return 'not updated';
  }
  elsif ($versionStatus eq 'failed')
  {
    $errors{"handler#$handler_name"} = reformat dequote <<"    EOF";
      Couldn't determine if there is a newer bugfix update version of
      $handler_name available because the server is down. Try again in a while,
      and send email to bugreport\@newsclipper.com if the problem persists.
    EOF
    return 'failed';
  }
  elsif ($versionStatus ne 'okay')
  {
    die "News Clipper encountered an unknown \$versionStatus";
  }

  die "Non-bugfix update type encountered for a bugfix update check"
    if $updateType ne 'bugfix';

  dprint "There is a new bugfix version.";
  $NewsClipper::Globals::state->set("last_bugfix_check_$handler_name",time);

  # Do automatic download if auto_download_bugfix_updates is specified, or if
  # -a was specified.
  if ($opts{a} || $main::config{auto_download_bugfix_updates} =~ /^y/i)
  {
    dprint "Doing automatic download for handler \"$handler_name\"";
  }
  # Prompt the user if run interactively, and the user didn't specify one of
  # the auto download options
  elsif (-t STDIN)
  {
    warn "There is a newer version of handler \"$handler_name\".\n";
    warn "Would you like News Clipper to attempt to download it? [y/n]\n";
    my $response = <STDIN>;

    return 'not updated' if $response !~ /^y/i;
  }
  # Otherwise we just warn the user we can't do a download
  else
  {
    $errors{"handler#$handler_name"} = reformat dequote <<"    EOF";
      A bugfix update to handler "$handler_name" is available, but it can't be
      downloaded because auto_download_bugfix_updates is not "yes" in your
      configuration file, and since News Clipper can't ask you interactively.
    EOF
    return 'not updated';
  }

  my $download_result = _DownloadHandler($handler_name,$newVersion);
  return 'updated' if $download_result eq 'okay';

  if ($download_result eq 'not found')
  {
    $errors{"handler#$handler_name"} = reformat dequote <<"    EOF";
      Couldn't do a bugfix update of the handler $handler_name. The handler
      server reports that the handler is not in the database.
    EOF
    return 'failed';
  }
  elsif ($download_result =~ /failed: (.*)/s)
  {
    $errors{"handler#$handler_name"} = reformat dequote $1;
    return 'failed';
  }
}

# ------------------------------------------------------------------------------

# This function finds the News Clipper compatible version of the locally
# installed handler. Returns the version number or undef if the handler could
# not be found.

sub _GetLocalHandlerNCVersion($)
{
  my $handler_name = shift;

  # Find the handler
  my $foundDirectory = _GetHandlerPath($handler_name);
  return undef unless defined $foundDirectory;

  open LOCALHANDLER, "$foundDirectory/$handler_name.pm";
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
  my $handler_name = shift;

  my $foundDirectory = _GetHandlerPath($handler_name);
  return undef unless defined $foundDirectory;

  dprint "Found local copy of handler in:\n  $foundDirectory";

  open LOCALHANDLER, "$foundDirectory/$handler_name.pm";
  my $localHandler = join '',<LOCALHANDLER>;
  close LOCALHANDLER;

  my ($versionCode) = $localHandler =~ /\$VERSION\s*=\s*do\s*({.*?});/;
  my $localVersion = eval "$versionCode";

  dprint "Local version for handler \"$handler_name\" is: $localVersion";

  return $localVersion;
}

# ------------------------------------------------------------------------------

# This routine restricts the personal version to 5 built-in handlers and 5
# optional ones. It dies if the user is trying to use more than their
# registration allows.

sub _CheckRegistrationRestriction($)
{
  my $handler_name = shift;

  dprint "Checking if handler \"$handler_name\" is okay to use.";

  return if ($main::config{product} ne 'Personal') &&
            ($main::config{product} ne 'Trial');

  # Skip this handler if we've already processed it.
  if (grep { /^$handler_name$/i } @allowedHandlers)
  {
    dprint "Skipping already checked handler \"$handler_name\".";
    return;
  }

  push @allowedHandlers,$handler_name;

  unless (_IsAcquisitionHandler($handler_name))
  {
    dprint "$handler_name isn't an acquisition handler -- okay to use.";
    return;
  }

  # Yell if they have the trial version and are doing any acquisition handler
  # other than yahootopstories
  if ($config{product} eq 'Trial')
  {
    if ($handler_name ne 'yahootopstories')
    {
      die reformat dequote <<"      EOF";
        You can not use the "$handler_name" handler. The trial version of News
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
      (!grep {/$handler_name.pm$/} @installedHandlers))
  {
    local $" = "\n";
    warn reformat dequote <<"    EOF";
      You currently have $config{numberhandlers} handlers on your
      system, and are trying to use a handler that is not one of these five
      ($handler_name). This personal version of News Clipper is only registered
      to use $config{numberhandlers} handlers.

      Please delete one or more of the following files if you want to be able
      to use this handler:
    EOF
    die "@installedHandlers\n";
  }
}

# ------------------------------------------------------------------------------

# Checks to see if a handler is an acquisition handler. First it looks
# locally, then checks the list of remote acquisition handlers. Dies (in
# _GetRemoteHandlerType) if the handler is not installed locally and the
# handler type can not be determined from the server.

sub _IsAcquisitionHandler
{
  my $handler_name = shift;

  # First look locally
  my $loadResult = _LoadHandler($handler_name);

  my $is_acquisition_handler = 0;

  if ($loadResult =~ /(Acquisition|Filter|Output)/s)
  {
    $is_acquisition_handler = 1 if $1 eq 'Acquisition';
  }
  else
  {
    $is_acquisition_handler = 1
      if _GetRemoteHandlerType($handler_name) eq 'Acquisition';
  }

  return $is_acquisition_handler;
}

# ------------------------------------------------------------------------------

# This routine checks that a handler on the system is for the current version
# of News Clipper. Returns 1 if the handler is compatible, 0 if it is not, and
# undef if it wasn't found.

sub _HandlerVersionIsCompatible($)
{
  my $handler_name = shift;

  dprint "Checking if handler \"$handler_name\" is of a compatible version.";

  # Skip this handler if we've already processed it.
  if (grep { /^$handler_name$/i } @compatibleHandlers)
  {
    dprint reformat (65,
      "Skipping handler \"$handler_name\" (already checked compatibility).");
    return;
  }

  push @compatibleHandlers,$handler_name;

  my $local_handler_nc_version = _GetLocalHandlerNCVersion($handler_name);
  return undef unless defined $local_handler_nc_version;

  dprint reformat (65,dequote <<"  EOF");
    Handler "$handler_name" was written for News Clipper version 
    $local_handler_nc_version, and this version of News Clipper is
    compatible with version $COMPATIBLE_NEWS_CLIPPER_VERSION.
  EOF

  if ($local_handler_nc_version != $COMPATIBLE_NEWS_CLIPPER_VERSION)
  {
    $errors{"handler#$handler_name"} = reformat dequote <<"    EOF";
       Handler $handler_name is incompatible with this version of News Clipper.
       (The handler is compatible with News Clipper versions that take handlers
       from version $local_handler_nc_version, but this version of News Clipper
       uses handlers from version $COMPATIBLE_NEWS_CLIPPER_VERSION).
    EOF
    return 0;
  }
  else
  {
    return 1;
  }
}

# ------------------------------------------------------------------------------

# Download the handler type from the remote server, caching it locally in
# %handler_type. Dies with a message if the server can't be contacted, or the
# returned data can't be parsed.

sub _GetRemoteHandlerType
{
  my $handler_name = shift;

  if (exists $handler_type{$handler_name})
  {
    dprint "Reusing cached handler type information " .
      "($handler_name is $handler_type{$handler_name})";
    return $handler_type{$handler_name};
  }

  dprint "Downloading handler type information.\n";

  my $url = "http://" . $HANDLER_SERVER .
    "/cgi-bin/getinfo?field=Name&string=$handler_name&" .
    "print=Type&ncversion=$main::VERSION";

  my $data = _DownloadURL($url);

  die reformat dequote <<"  EOF"
    Couldn't download the handler type for handler $handler_name. Maybe
    the server is down. This version of News Clipper can only use a limited
    number of acquisition handlers, and must contact the server to determine
    if the handler is an acquisition handler. Try again in a while, and send
    email to bugreport\@newsclipper.com if the problem persists.
  EOF
    unless defined $data;

  if ($$data =~ /Type +: (.*)/)
  {
    $handler_type{$handler_name} = $1;
    return $handler_type{$handler_name};
  }
  else
  {
    die reformat dequote <<"    EOF";
ERROR: Couldn't parse handler type information fetched from server. Please
send email to bugreport\@newsclipper.com describing this message. Fetched
content was:
$$data
    EOF
  }
}

# ------------------------------------------------------------------------------

# Figure out where the handler is in the file system. Returns undef if not
# found.

sub _GetHandlerPath($)
{
  my $handler_name = shift;

  # Try to load the handler so we can figure out where to put the replacement
  my $loadResult = _LoadHandler($handler_name);

  if ($loadResult eq 'not found')
  {
    dprint "Handler \"$handler_name\" not found locally. Can't get path.";
    return undef;
  }

  my @dirs = qw(Acquisition Filter Output);

  foreach my $dir (@INC)
  {
    return "$dir/NewsClipper/Handler/Acquisition"
      if -e "$dir/NewsClipper/Handler/Acquisition/$handler_name.pm";
    return "$dir/NewsClipper/Handler/Filter"
      if -e "$dir/NewsClipper/Handler/Filter/$handler_name.pm";
    return "$dir/NewsClipper/Handler/Output"
      if -e "$dir/NewsClipper/Handler/Output/$handler_name.pm";
  }

  return undef;
}

# ------------------------------------------------------------------------------

# "Unloads" a handler by deleting the entry in %INC and undefining any
# subroutines.

sub _UnLoadHandler($)
{
  my $handler_name = shift;

  dprint "Unloading handler \"$handler_name\"";

  my $handler_type = undef;

  # Find out what kind of handler it is
  $handler_type = 'Acquisition'
    if exists $INC{"NewsClipper/Handler/Acquisition/$handler_name.pm"};
  $handler_type = 'Filter'
    if exists $INC{"NewsClipper/Handler/Filter/$handler_name.pm"};
  $handler_type = 'Output'
    if exists $INC{"NewsClipper/Handler/Output/$handler_name.pm"};

  die "_UnLoadHandler called on $handler_name, but $handler_name is not " .
    "in %INC\n"
    unless defined $handler_type;

  # Delete it from %INC
  delete $INC{"NewsClipper/Handler/$handler_type/$handler_name.pm"};

  # Now undef the package
  no strict 'refs';
  my %oldconfig =
    %{"NewsClipper::Handler::${handler_type}::${handler_name}::handlerconfig"};
  Symbol::delete_package("NewsClipper::Handler::${handler_type}::${handler_name}::");
  %{"NewsClipper::Handler::${handler_type}::${handler_name}::handlerconfig"} =
    %oldconfig;
}

# ------------------------------------------------------------------------------

# Loads a handler.  Returns "found as
# NewsClipper::Handler::${dir}::$handler_name" if the handler is found on the
# system, and "not found" if it can't be found.  Dies if the handler is found
# but has errors.

sub _LoadHandler($)
{
  my $handler_name = shift;

  my @dirs = qw(Acquisition Filter Output);

  dprint "Trying to load handler \"$handler_name\"";

  # Return if it has already been loaded before. This helps speed things up.
  foreach my $dir (@dirs)
  {
    if (defined $INC{"NewsClipper/Handler/$dir/$handler_name.pm"})
    {
      dprint "Handler \"$handler_name\" already loaded";
      return "found as NewsClipper::Handler::${dir}::$handler_name" 
    }
  }

  foreach my $dir (@dirs)
  {
    # Try to load it in $dir
    dprint "Looking for handler as:";
    dprint "  NewsClipper::Handler::${dir}::$handler_name";

    # Here we need to store errors.
    my $errors;
    {
      local $SIG{__WARN__} = sub { $errors .= $_[0] };

      eval "require NewsClipper::Handler::${dir}::$handler_name";
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
      if ($@ !~ /Can't locate NewsClipper.Handler.$dir.$handler_name/)
      {
        $@ =~ s/Compilation failed in require at \(eval.*?\n//s;

        warn "Handler $handler_name was found in:\n";
        warn "  ",$INC{"NewsClipper/Handler/$dir/$handler_name.pm"},"\n";
        warn "  but could not be loaded because of the following error:\n\n";
        warn "$errors\n" if defined $errors;
        die "$@\n";
      }
    }

    if (defined $INC{"NewsClipper/Handler/$dir/$handler_name.pm"})
    {
      dprint "Found handler as:\n ",
                  $INC{"NewsClipper/Handler/$dir/$handler_name.pm"};

      # If there's anything in $errors, it must be warnings. Store them
      # for later printing.
      $errors{"handler#$handler_name"} = $errors if defined $errors;

      return "found as NewsClipper::Handler::${dir}::$handler_name"
    }

    # We can get here if the eval has a syntax error. (e.g. if someone tries
    # to use handler.pm as the handler name)
    if ($errors)
    {
      warn "Handler $handler_name could not be loaded. The error was:\n";
      die "$errors\n";
    }
  }

  # Darn. Couldn't find it anywhere!
  dprint "Couldn't find handler";
  return 'not found';
}

# ------------------------------------------------------------------------------

# This function downloads and saves a remote handler, if one exists. Returns
# 'okay', 'not found', or 'failed: error message'

sub _DownloadHandler($$)
{
  my $handler_name = shift;
  my $version = shift;

  dprint "Downloading handler $handler_name, version $version";

  my ($getResult,$code) = _GetHandlerCode($handler_name,$version);
  return $getResult if $getResult ne 'okay';

  my $foundDirectory = _GetHandlerPath($handler_name);

  # Use the old directory, or create a new one based on what the handler calls
  # itself.
  my $destDirectory;
  if (defined $foundDirectory)
  {
    dprint "Replacing handler located in\n  $foundDirectory";

    # Remove the outdated one.
    unlink "$foundDirectory/$handler_name.pm";

    $destDirectory = $foundDirectory;
  }
  else
  {
    my ($subDir) = $code =~ /package NewsClipper::Handler::([^:]*)::/;
    $destDirectory =
      "$config{handler_locations}[0]/NewsClipper/Handler/$subDir";

    dprint "Saving new handler to $destDirectory";
  }

  mkpath $destDirectory unless -e $destDirectory;

  # Write the handler.
  open HANDLER,">$destDirectory/$handler_name.pm"
    or return "failed: Handler $handler_name was downloaded, but could " .
      " not be saved. The message from the operating system is:\n\n$!";
  print HANDLER $code;
  close HANDLER;

  warn "The $handler_name handler has been downloaded and saved as\n";
  warn "  $destDirectory/$handler_name.pm\n";

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
# - an error code: (okay, not found, failed: error message)
# - the handler (if the error code is okay)

sub _GetHandlerCode($$)
{
  my $handler_name = shift;
  my $version = shift;

  dprint "Downloading code for handler \"$handler_name\"";

  if (defined $downloadedCode{$handler_name})
  {
    dprint "Reusing already downloaded code.";
    return ('okay',$downloadedCode{$handler_name});
  }

  my $url;

  $url = "http://" . $HANDLER_SERVER .
         "/cgi-bin/gethandler?tag=$handler_name&" .
         "ncversion=$main::VERSION&version=$version";

  my $data = _DownloadURL($url);

  if (defined $data && $$data =~ /^Handler not found/)
  {
    return ('not found',undef);
  }

  # If either the download failed, or the thing we got back doesn't look like
  # a handler...
  if ((!defined $data) || ($$data !~ /package NewsClipper/))
  {
    my $error_message = reformat dequote <<"    EOF";
      failed: Couldn't download handler $handler_name. Maybe the server is
      down. Try again in a while, and send email to bugreport\@newsclipper.com
      if the problem persists.
    EOF

    $error_message .= " Message from server is: $$data\n" if defined $data;

    return ($error_message,undef);
  }

  $downloadedCode{$handler_name} = $$data;

  return ('okay',$$data);
}

# ------------------------------------------------------------------------------

my $dbh = undef;

# Connect to the database, storing the DB connection in $dbh for the
# duration of the run

sub ConnectToDB
{
  return $dbh if defined $dbh;

  require DBI;

  local $SIG{ALRM} = sub { die "database timeout" };

  my $numTriesLeft = $config{socket_tries};

  do
  {
    eval
    {
      alarm($config{socket_tries});

      $dbh = DBI->connect('DBI:mysql:handlers:handlers.newsclipper.com','webuser')
        || die "Can't connect to database: $DBI::errstr";

      alarm(0);
    };

    $numTriesLeft--;
  } until ($numTriesLeft == 0 || defined $dbh);

  alarm(0);
}

# ------------------------------------------------------------------------------

# Disconnect from the database.

sub DisconnectFromDB
{
  $dbh->disconnect() if defined $dbh;
}

# ------------------------------------------------------------------------------

sub _GetTable
{
  my $version = shift;

  my $table = $version;
  $table =~ s/\./_/g;

  return $table;
}

# ------------------------------------------------------------------------------

# Computes the most recent version number for a working handler.
# Returns undef if the handler can't be found.

sub _GetLatestWorkingHandlerVersion
{
  my $handler_name = shift;
  my $ncversion = shift;

  my $table = _GetTable($ncversion);

  my $query = qq{ SELECT Version FROM $table WHERE Name like '$handler_name'
    and Status like 'Working'
    ORDER BY Version DESC };

dprint "_GetLatestWorkingHandlerVersion is doing query:";
dprint "  ".$query;
  return scalar $dbh->selectrow_array($query);
}

# ------------------------------------------------------------------------------

# Computes the most recent guaranteed-compatible version number for a
# workinghandler.  Returns undef if the handler can't be found.

sub _GetCompatibleWorkingHandlerVersion
{
  my $handler_name = shift;
  my $ncversion = shift;
  my $version = shift;

  my $table = _GetTable($ncversion);

  # Truncate to two decimal places, and increment the hundredths place so we
  # can query for < $version
  my $lower_version = sprintf("%0.2f",int($version * 100)/100);
  my $upper_version = sprintf("%0.2f",int($version * 100)/100 + .01);

  my $query = qq{ SELECT Version FROM $table WHERE Name like '$handler_name'
    and Status like 'Working'
    and Version < $upper_version and Version >= $lower_version
    ORDER BY Version DESC };

  return scalar $dbh->selectrow_array($query);
}

# ------------------------------------------------------------------------------

# Checks if a new version of the handler is available, taking consideration of
# -n flag into account.
# Params:
# 1) the handler name
# 2) whether you want only a bugfix update, not a functional update too
#    ('bugfix','functional')
# Returns:
# 1) status: okay, failed, not found, no update
# 2) the version
# 3) type of update it is ("bugfix" or "functional")
#    if $needBugfix == 0, type can be either bugfix or functional.
#    if $needBugfix == 1, type can be only bugfix.

my $alreadyFailed = 0;

sub _GetNewHandlerVersion($$)
{
  my $handler_name = shift;
  my $needBugfix = shift;

  return 'failed' if $alreadyFailed;

  dprint "Checking for a new version for handler \"$handler_name\"";

  # A version of undef means that we want whatever the newest version is,
  # regardless of functional compatibility.
  my $localVersion = _GetLocalHandlerVersion($handler_name);


  ConnectToDB();

  unless (defined $dbh)
  {
    $alreadyFailed = 1;
    return 'failed';
  }

  unless (defined _GetLatestWorkingHandlerVersion($handler_name,$COMPATIBLE_NEWS_CLIPPER_VERSION))
  {
    dprint "Server reports that handler \"$handler_name\" doesn't exist.\n";
    return 'not found';
  }

  my $newVersion;

  if ($needBugfix eq 'bugfix')
  {
    $newVersion = _GetCompatibleWorkingHandlerVersion($handler_name,
      $COMPATIBLE_NEWS_CLIPPER_VERSION, $localVersion);
  }
  else
  {
    $newVersion = _GetLatestWorkingHandlerVersion($handler_name,$COMPATIBLE_NEWS_CLIPPER_VERSION);
  }

  if (!defined $newVersion ||
     ( defined $localVersion && $newVersion <= $localVersion))
  {
    dprint "No new version is available";
    return 'no update';
  }

  # We actually got a version
  my $updateType;

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

  dprint "Downloading URL:";
  dprint "  $url";

  $userAgent->timeout($config{socket_timeout});
  $userAgent->proxy(['http', 'ftp'], $config{proxy})
    if $config{proxy} ne '';
  my $request = new HTTP::Request GET => "$url";
  if ($config{proxy_username} ne '')
  {
    $request->proxy_authorization_basic($config{proxy_username},
                     $config{proxy_password});
  }

  my $result;
  my $numTriesLeft = $config{socket_tries};

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

END
{
  DisconnectFromDB();
}

1;
