#!/usr/bin/perl

# For bare-bones documentation, do "perldoc NewsClipper.pl". A user's manual
#   is included with the purchase of one of the commercial versions.
# To subscribe to the News Clipper mailing list, visit
#   http://www.NewsClipper.com/techsup.htm#MailingList
# Send bug reports or enhancements to bugs@newsclipper.com. Send in a
#   significant enhancement and you'll get a free license for News Clipper.

# Visit the News Clipper homepage at http://www.newsclipper.com/ for more
# information.

#------------------------------------------------------------------------------

# Written by: David Coppit http://coppit.org/ <david@coppit.org>

# This code is distributed under the GNU General Public License (GPL). See
# http://www.opensource.org/gpl-license.html and http://www.opensource.org/.

# ------------------------------------------------------------------------------

use Getopt::Std;
use FileHandle;

use vars qw( %config %opts $commandLine );

# These need to be predeclared so that this code can be parsed and run until
# we load the NewsClipper::Globals module. WARNING! Be careful to not use
# these until NewsClipper::Globals has been imported!
sub DEBUG();
sub dprint;
sub reformat;
sub dequote;

#------------------------------------------------------------------------------

require 5.004;
use strict;

# $home is used in the config file sometimes
use vars qw( $VERSION $home );

$VERSION = do {my @r=(q$Revision: 1.1.7 $=~/\d+/g);sprintf"%d."."%1d"x$#r,@r};

# ------------------------------------------------------------------------------

sub print_usage
{
  my $exeName = $0;
  # Fix the $exeName if it's the compiled version.
  ($exeName) = $ENV{SOURCEEXE} =~ /([^\/\\]*)$/ if defined $ENV{SOURCEEXE};

  my $version = "$VERSION, $config{product}";

  if ($config{product} eq "Personal")
  {
    $version .= " ($config{numberpages} page";
    $version .= "s" if $config{numberpages} > 1;
    $version .= ", $config{numberhandlers} handlers)";
  }

  print dequote<<"  EOF";
    This is News Clipper version $version

    usage: $exeName [-adnrv] [-i inputfile] [-o outputfile] [-c configfile]

    -i The template file to use as input (overrides value in configuration file)
    -o The output file (overrides value in configuration file)
    -c The configuration file to use
    -a Automatically download handlers as needed
    -n Check for new versions of the handlers
    -r Forces caching proxies to reload data
    -d Enable debug mode
    -v Output to STDOUT in addition to the file. (Unix only.)
  EOF
}

# ------------------------------------------------------------------------------

sub _LoadSysConfig
{
  $config{'sysconfigfile'} = 'Not specified';

  return if !exists $ENV{'NEWSCLIPPER'} || $^O eq 'MSWin32' || $^O eq 'dos';

  my $configFile = "$ENV{'NEWSCLIPPER'}/NewsClipper.cfg";
  my $doResult;
  my $warnings = '';

  # Hide any warnings that occur from parsing the config file.
  {
    local $SIG{__WARN__} = sub { };
    $doResult = do $configFile;
  }

  # No error message means we found it
  if ($doResult)
  {
    $config{sysconfigfile} = $configFile;
    return;
  }

  if ($@)
  {
    die <<"    EOF";
News Clipper found your configuration file at $configFile, but it could not
be processed because of the following error:
$warnings $@
    EOF
  }

  unless (defined $doResult)
  {
    die <<"    EOF";
News Clipper could not load your system-wide configuration file
"$configFile". Make sure your NEWSCLIPPER environment variable is
set correctly. The error is:
$warnings $!
    EOF
  }

  unless ($doResult)
  {
    die <<"    EOF";
News Clipper found your configuration file at
"$configFile", but could not process it.
$warnings
    EOF
  }
}

# ------------------------------------------------------------------------------

sub _LoadUserConfig
{
  $config{userconfigfile} = 'Not found';

  my $configFile = $opts{c} || "$home/.NewsClipper/NewsClipper.cfg";

  # Make sure $configFile specifies a specific directory, so the the do
  # command below doesn't start searching the Perl include path.
  $configFile = "./$configFile" unless $configFile =~ /[\/\\]/;
  
  my $doResult;

  my $warnings = '';

  # Hide any warnings that occur from parsing the config file.
  {
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };

    # This is kinda tricky. We don't want the %config in $configFile to
    # totally redefine %main::config, so we wrap the "do" in a package
    # declaration, which will put the config file's %config in the
    # NewsClipper::config package for later use.
    my $currentPackage = __PACKAGE__;
    package NewsClipper::config;
    use vars qw ($home);
    *home = \$main::home;
    $doResult = do $configFile;
    eval "package $currentPackage";
  }

  # No error message means we found it
  if ($doResult)
  {
    $config{userconfigfile} = $configFile;

    # Now override main's %config
    while (my ($key,$value) = each %NewsClipper::config::config)
    {
      $main::config{$key} = $value;
    }

    undef %NewsClipper::config::config;
    return;
  }

  if ($@)
  {
    die <<"    EOF";
News Clipper found your personal configuration file at
$configFile, but could not be processed because of the following
error:
$warnings $@
    EOF
  }

  unless (defined $doResult)
  {
    # On Windows we croak if we can't load the config file.
    if ($^O eq 'MSWin32' || $^O eq 'dos')
    {
      die <<"      EOF";
News Clipper couldn't load your configuration file "$configFile".
Your registry value for "InstallDir" in
"HKEY_LOCAL_MACHINE\\SOFTWARE\\Spinnaker Software\\News
Clipper\\$VERSION" (or your HOME environment variable) may not be
correct. Here is the error: $warnings $!
      EOF
    }
    # If the person explicitely set the config file, we'd better croak.
    elsif ($opts{c})
    {
      die reformat dequote<<"      EOF";
News Clipper couldn't load your configuration file "$configFile".
Here is the error: $warnings $!
      EOF
    }
    # Otherwise just emit a warning on the debug output.
    else
    {
      warn <<"      EOF";
News Clipper could not load personal configuration file "$configFile"
because of the following error: $warnings $!
      EOF
      return;
    }
  }

  unless ($doResult)
  {
    die <<"    EOF";
News Clipper found your configuration file at
"$configFile", but could not process it.
$warnings
    EOF
  }
}

# ------------------------------------------------------------------------------

sub LoadConfig
{
  _LoadSysConfig;
  _LoadUserConfig;

  # Put the News Clipper module file location, if it is specified
  push @INC,$config{modulepath};

  # Now we slurp in the global functions and constants.
  require NewsClipper::Globals;
  NewsClipper::Globals->import;

  dprint "System-wide configuration file found as:\n  $config{sysconfigfile}\n";
  dprint "Personal configuration file found as:\n  $config{userconfigfile}\n";

  dprint "Configuration is:";
  while (my ($k,$v) = each %config)
  {
    my $keyVal = "  $k:\n";
    if (ref $v eq 'ARRAY')
    {
      grep { $keyVal .= "    $_\n" } @$v;
    }
    else
    {
      if (defined $v && $v ne '')
      {
        $keyVal .= "    $v\n";
      }
      else
      {
        $keyVal .= "    <NOT SPECIFIED>\n";
      }
    }
    dprint $keyVal;
  }

}

# ------------------------------------------------------------------------------

sub CheckRegistration
{
  # Set the default product type
  $config{product} = "Trial";
  $config{numberpages} = 1;
  $config{numberhandlers} = 1;

  # Extract the date, license type, and crypt'd code from the key
  my ($date,$license,$numPages,$numHandlers,$code) =
    $config{regKey} =~ /^(.*?)#(.*?)#(.*?)#(.*)#(.*)$/;

  my $licensestring =
    "$date#$license#$^O#$config{email}#$numPages#$numHandlers";

  # Mash groups of eight together to help hash the string for crypt, which can
  # only use up to eight characters
  my $hashed = "";
  foreach ($licensestring =~ /(.{1,8})/gs) { $hashed ^= $_ }

  # Now check the key
  if (crypt ($hashed,$code) eq $code)
  {
    if ($license eq 'p')
    {
      $config{product} = "Personal";
      $config{numberpages} = $numPages;
      $config{numberhandlers} = $numHandlers;
    }

    if ($license eq 'c')
    {
      $config{product} = "Corporate";
    }
  }
  elsif ($config{regKey} ne 'YOUR_REG_KEY_HERE')
  {
    print STDERR reformat dequote<<"    EOF";
      ERROR: Your registration key appears to be incorrect. Here is the
      information News Clipper was able to determine:
    EOF
    die dequote '  ',<<"    EOF";
      System-wide configuration file: $config{sysconfigfile}
      Personal configuration file: $config{userconfigfile}
      Email: $config{email}
      Key: $config{regKey}
      Operating System: $^O
      Date Issued: $date
      License Type: $license
      Number of pages: $numPages
      Number of Handlers: $numHandlers
    EOF
  }

  # Override the product type in the Open Source version. We use SOURCEEXE to
  # detect if this is the compiled version (the compiler sets this).
  $config{product} = "Open Source";
}

# ------------------------------------------------------------------------------

sub GetHomeDirectory
{
  # Get the user's home directory. First try the password info, then the
  # registry (if it's a Windows machine), then any HOME environment variable.
  my $home = eval { (getpwuid($>))[7] } || GetWinInstallDir() || $ENV{HOME};

  # "s cause problems in Windows. Sometimes people set their home variable as
  # "c:\Program Files\NewsClipper", which causes when the path is therefore
  # "c:\Program Files\NewsClipper"\.NewsClipper\Handler\Acquisition
  $home =~ s/"//g;

  die reformat dequote <<"  EOF"
    News Clipper could not determine your home directory. On non-Windows
    machines, News Clipper attempts to get your home directory using getpwuid,
    then the HOME environment variable. On Windows machines, it attempts to
    read the registry entry "HKEY_LOCAL_MACHINE\\SOFTWARE\\Spinnaker
    Software\\News Clipper\\$VERSION" then tries the HOME environment
    variable.
  EOF
    unless defined $home;

    return $home;
}

# ------------------------------------------------------------------------------

sub SetupConfig
{
  $home = GetHomeDirectory;

  LoadConfig;

  # Translate the cache size into bytes from megabytes, and the maximum image
  # age into seconds from days.
  $config{maxcachesize} = $config{maxcachesize}*1048576;
  $config{maximgcacheage} = $config{maximgcacheage}*86400;

  die "\"handlerlocations\" in NewsClipper.cfg must be non-empty.\n"
    if $#{$config{handlerlocations}} == -1;

  # Put the handler locations on the include search path
  unshift @INC,@{$config{handlerlocations}};

  CheckRegistration;

  dprint "Operating system:\n  $^O";
  dprint "Version:\n  $VERSION, $config{product}";
  dprint "Command line was:\n  $commandLine";

  # Check that the user isn't trying to use the -i and -o flags for the Trial
  # and Personal versions
  if (($config{product} eq "Trial" ||
       $config{product} eq "Personal") &&
      (defined $opts{i} || defined $opts{o}))
  {
    die reformat dequote<<"    EOF";
      The -i and -o flags are disabled in the Trial and Personal versions of
      News Clipper. Please specify your input and output files in the
      NewsClipper.cfg file.
    EOF
  }

  # Override the config values if the user specified -i or -o.
  $config{inputFiles} = ["$opts{i}"] if defined $opts{i};
  $config{outputFiles} = ["$opts{o}"] if defined $opts{o};

  # Check that the input files and output files match
  if ($#{$config{inputFiles}} != $#{$config{outputFiles}})
  {
    die reformat dequote <<"    EOF";
      Your input and output files are not correctly specified. Check your
      configuration file NewsClipper.cfg.
    EOF
  }

  # Check that the user isn't trying to process more than one input file for
  # the Trial version
  if ($#{$config{inputFiles}} > 0 && $config{product} eq "Trial")
  {
    die reformat dequote <<"    EOF";
      Sorry, but the Trial version of News Clipper can only process one input
      file.
    EOF
  }

  # Check that the user isn't trying to process more than the registered
  # number of files for the Personal version
  if ($config{product} eq "Personal" &&
      $#{$config{inputFiles}}+1 > $config{numberpages} )
  {
    die reformat dequote<<"    EOF";
      Sorry, but this Personal version of News Clipper is only registered to
      process $config{numberpages} input files.
    EOF
  }

  die "No input files specified.\n" if $#{$config{inputFiles}} == -1;

  # Check that they specified cachelocation and maxcachesize
  die "cachelocation not specified in NewsClipper.cfg"
    unless defined $config{cachelocation} &&
           $config{cachelocation} ne '';
  die "maxcachesize not specified in NewsClipper.cfg"
    unless defined $config{maxcachesize} &&
           $config{maxcachesize} != 0;
}

# ------------------------------------------------------------------------------

sub HandleProxyPassword
{
  # Handle the proxy password, if a username was given but not a password, and
  # a tty is available.
  if (($config{proxy_username} ne '') &&
      (($config{proxy_password} eq '') && (-t)))
  {
    unless (eval "require Term::ReadKey")
    {
      die reformat dequote<<"      EOF";
        You need Term::ReadKey for password authorization.\nGet it from
        CPAN.\n";
      EOF
    }

    # Make unbuffered
    my $oldBuffer = $|;
    $|=1;

    print "Please enter your proxy password: ";
    my $DEV_TTY = new FileHandle("</dev/tty")
      or die "Unable to open /dev/tty: $!\n";

    # Temporarily disable strict subs so this will compile even though we
    # haven't require'd Term::ReadKey yet.
    no strict "subs";

    # Turn off echo to read in password
    Term::ReadKey::ReadMode (2, $DEV_TTY);
    $config{proxy_password} = Term::ReadKey::ReadLine (0, $DEV_TTY);

    # Turn echo back on
    Term::ReadKey::ReadMode (0, $DEV_TTY);

    # Restore strict subs
    use strict "subs";

    # Give the user a visual cue that their password has been entered
    print "\n";

    chomp($config{proxy_password});
    close($DEV_TTY) || warn "Unable to close /dev/tty: $!\n";
    $| = $oldBuffer;
  }
}

# ------------------------------------------------------------------------------

# This function attempts to grab the installation from the registry for
# Windows machines. It returns nothing if anything goes wrong, otherwise the
# installation path.
sub GetWinInstallDir
{
  return if ($^O ne 'MSWin32') && ($^O ne 'dos');

  require Win32::Registry;

  my $key = "SOFTWARE\\Spinnaker Software\\News Clipper\\$VERSION";
  my $TempKey;

  # Return if we can't find the key in the registry.
  $main::HKEY_LOCAL_MACHINE->Open($key, $TempKey) || return;

  my ($class, $nSubKey, $nVals);
  $TempKey->QueryKey($class, $nSubKey, $nVals);

  # Return if there are no values for the key.
  return if $nVals <= 0;

  my ($value,$type);

  # Return if we can't find the value.
  $TempKey->QueryValueEx('InstallDir',$type,$value) || return;

  # Return if the value is there, but is the wrong type.
  return unless $type == 1;

  return $value;
}

# ------------------------------------------------------------------------------

# Needed by compiler
#perl2exe_include constant
#perl2exe_include jcode.pl
#perl2exe_include NewsClipper/AcquisitionFunctions
#perl2exe_include NewsClipper/Cache
#perl2exe_include NewsClipper/HTMLTools
#perl2exe_include NewsClipper/Handler
#perl2exe_include NewsClipper/HandlerFactory
#perl2exe_include NewsClipper/Interpreter
#perl2exe_include NewsClipper/Parser
#perl2exe_include NewsClipper/Types
#perl2exe_include Time/CTime
#perl2exe_include Date/Format
#perl2exe_include Net/NNTP

#------------------------------------------------------------------------------

sub _main()
{
  # Make unbuffered for easier debugging.
  $| = 1 if DEBUG;

  for (my $i=0;$i <= $#{$config{inputFiles}};$i++)
  {
    dprint "Now processing $config{inputFiles}[$i] => $config{outputFiles}[$i]";

    # Print a warning and skip if the file doesn't exist and isn't a text file.
    # However, don't do the checks if the file is STDIN.
    unless ($config{inputFiles}[$i] eq 'STDIN')
    {
      warn reformat "Input file $config{inputFiles}[$i] can't be found.\n"
        and next unless -e $config{inputFiles}[$i];
      warn reformat "Input file $config{inputFiles}[$i] is a directory.\n"
        and next if -d $config{inputFiles}[$i];
      warn reformat "Input file $config{inputFiles}[$i] is empty.\n"
        and next if -z $config{inputFiles}[$i];
    }

    # Figure out if we were called as a CGI program
    my $calledAsCgi = 0;
    $calledAsCgi = 1 if defined $ENV{'SCRIPT_NAME'};

    # We'll write to the file unless we were run as a CGI or if we're in DEBUG
    # mode.
    my $writeToFile = 1;
    $writeToFile = 0
      if DEBUG || $calledAsCgi || $config{outputFiles}[$i] eq 'STDOUT';

    $config{inputFiles}[$i] = *STDIN if $config{inputFiles}[$i] eq 'STDIN';

    # Print the content type if we're running as a CGI.
    print "Content-type: text/html\n\n" if $calledAsCgi;

    my $oldSTDOUT = new FileHandle;

    # Redirect STDOUT to a temp file.
    if ($writeToFile)
    {
      # Store the old STDOUT so we can replace it later.
      $oldSTDOUT->open(">&STDOUT");

      # If the user wants to see a copy of the output... (Doesn't work in
      # Windows or DOS)
      if ($opts{v} && ($^O ne 'MSWin32') && ($^O ne 'dos'))
      {
        # Make unbuffered
        $| = 1;
        open (STDOUT,"| tee $config{outputFiles}[$i].temp");
      }
      else
      {
        open (STDOUT,">$config{outputFiles}[$i].temp");
      }
    }

    require NewsClipper::Parser;

    # Okay, now do the magic. Parse the input file, calling the handlers
    # whenever a special tag is seen.

    my $p = new NewsClipper::Parser;
    $p->parse_file($config{inputFiles}[$i]);

    # Restore STDOUT to the way it was
    if ($writeToFile)
    {
      close (STDOUT);
      open(STDOUT, ">&".$oldSTDOUT->fileno()) or die "Can't restore STDOUT.\n";

      # Replace the output file with the temp file. Move it to .del for OSes
      # that have delayed deletes.
      rename ($config{outputFiles}[$i], "$config{outputFiles}[$i].del");
      unlink ("$config{outputFiles}[$i].del");
      rename ("$config{outputFiles}[$i].temp",$config{outputFiles}[$i]);
      chmod 0755, $config{outputFiles}[$i];
    }

    # Stop after the first file if we're being run as a CGI. (I guess...)
    last if $calledAsCgi;
  }
}

# ------------------------------ MAIN PROGRAM ---------------------------------

$commandLine = "$0 @ARGV";

# See if the user specified the input and output files on the command line.
getopt('ioc',\%opts);

SetupConfig();

if (DEBUG)
{
  dprint "Options are:";
  while (my ($k,$v) = each %opts)
  {
    dprint "  $k: $v";
  }

  dprint "INC is:";
  foreach my $i (@INC)
  {
    dprint "  $i";
  }

  dprint "Home directory:\n  $home";
  
  use Cwd;
  dprint "Current directory:\n  ",cwd,"\n";
}

print_usage and exit(0) if $opts{h};

HandleProxyPassword();

# Do timers if we aren't in debug mode and not on the broken Windows platform
if (DEBUG || ($^O eq 'MSWin32') || ($^O eq 'dos'))
{
  _main;
}
else
{
  $SIG{ALRM} = sub { die "timeout" };

  eval
  {
    alarm($config{scriptTimeout});
    _main;
    alarm(0);
  };

  if ($@)
  {
    # See if it was our timeout
    if ($@ =~ /timeout/)
    {
      die "News Clipper script timeout has expired. News Clipper killed.\n";
    }
    else
    {
      # The eval got aborted, so we need to stop the alarm
      alarm (0);
      # and print the error. (I'm not simply die'ing here because I don't like
      # the annoying ...propagated message. I don't know if this is the right
      # way to do this, but it works.)
      print $@;
      exit 1;
    }
  }
  exit 0;
}

#-------------------------------------------------------------------------------

END
{
  if (DEBUG)
  {
    dprint "Here are all the modules used during this run, and their locations:";
    foreach my $key (sort keys %INC)
    {
      dprint "  $key =>\n    $INC{$key}";
    }
  }
}

#-------------------------------------------------------------------------------

=head1 NAME

News Clipper - downloads and integrates dynamic information into your webpage

=head1 SYNOPSIS

NewsClipper.pl [B<-anrv>] [B<-i> inputfile] [B<-o> outputfile]
  [B<-c> configfile]

=head1 DESCRIPTION

I<News Clipper> grabs dynamic information from the internet and integrates it
into your webpage. Features include modular extensibility, timeouts to handle
dead servers without hanging the script, user-defined update times, automatic
installation of modules, and compatibility with cgi-wrap. 

News Clipper takes an input HTML file, which includes special tags of the
form:

  <!--newsclipper
    <input name=X>
    <filter name=Y>
    <output name=Z>
  -->

where I<X> represents a data source, such as "apnews", "slashdot", etc. When
such a tag is encountered, News Clipper attempts to load and execute the
handler to acquire the data. Then the data is sent to the filter named by
I<Y>, and then on to the output handler named by I<Z>.  If the handler can not
be found, the script asks for permission to attempt to download it from the
central repository.

=head1 HANDLERS

News Clipper has a modular architecture, in which I<handlers> implement the
acquisition and output of data gathered from the internet. To use new data
sources, first locate an interesting one at
http://www.newsclipper.com/handlers.html, then place
the News Clipper tag in your input file. Then run News Clipper once manually,
and it will prompt you for permission to download and install the handler.

You can control, at a high level, the format of the output data by using the
built-in filters and handlers described on the handlers web page. For more
control over the style of output data, you can write your own handlers in
Perl. 

To help handler developers, a utility called I<MakeHandler.pl> is included with
the News Clipper distribution. It is a generator that asks several questions,
and then creates a basic handler.  Handler development is supported by two
APIs, I<AcquisitionFunctions> and I<HTMLTools>. For a complete description of
these APIs, as well as suggestions on how to write handlers, visit
http://www.newsclipper.com/handlers.html.


=head1 OPTIONS AND ARGUMENTS

=over 4

=item B<-i>

Override the input file specified in the configuration file.

=item B<-o>

Override the output file specified in the configuration file.

=item B<-c>

Use the specified file as the configuration file, instead of NewsClipper.cfg.

=item B<-a>

Automatically download all handlers that are not installed locally.

=item B<-n>

Check for new versions of handlers while processing input file.

=item B<-r>

Reload the content from the proxy server even on a cache hit. This prevents
News Clipper from using stale data when constructing the output file.

=item B<-d>

Enable debug mode, which prints extra information about the execution of News
Clipper. Output is sent to the screen instead of the output file.

=item B<-v>

Verbose output. Output a copy of the information sent to the output file to
standard output. Does not work on Windows or DOS.

=back

=head1 Configuration

The file NewsClipper.cfg contains the configuration. News Clipper will first
look for this file in the system-wide location specified by the NEWSCLIPPER
environment variable. News Clipper will then load the user's NewsClipper.cfg
from $home/.NewsClipper. Options that appear in the personal configuration
file override those in the system-wide configuration file. In this file you
can specify the following:

=over 2

=item *

Multiple input and output files.

=item *

The timeout value for the script. This puts a limit on the total time the
script can execute, which prevents it from hanging.

=item *

The timeout value for socket connections. This allows the script to recover
from unresponsive servers.

=item *

Your proxy host. For example, "http://proxy.host.com:8080/"

=item *

The locations of handlers. For example, ['dir1','dir2'] would look for handlers
in dir1/NewsClipper/Handler/ and dir2/NewsClipper/Handler/. Note that while
installing handlers, the first directory is used.

=item *

The size and location of the HTML cache News Clipper uses to store data in
between the update times specified by the handlers.

=item *

The location of News Clipper's modules, in case the aren't in the standard
Perl module path. (Set during installation.)

=item *

The maximum age and location of images stored locally by the I<cacheimages>
filter.

=item *

DOS/Windows users can specify their time zone. (Set during installation.)

=back

See the file NewsClipper.cfg for examples.


=head1 RUNNING

You can run NewsClipper.pl from the command line, but a better
way is to run the script as a cron job. To do this, create a .crontab file
with something similar to the following:

=over 4

0 7,10,13,16,19,22 * * * /path/NewsClipper.pl

=back

You can also have cgiwrap call your startup page, but this would mean having to
wait for the script to execute (2 to 30 seconds, depending on the staleness of
the information). To do this, place NewsClipper.pl and NewsClipper.cfg in your
public_html/cgi-bin directory, and use a URL similar to the following:

=over 4

http://www.server.com/cgi-bin/cgiwrap?user=USER&script=NewsClipper.pl

=back

=head1 PREREQUISITES

This script requires the C<Time::CTime>, C<Time::ParseDate>, C<LWP::UserAgent>
(part of libwww), C<URI>, C<HTML-Tree>, and C<HTML::Parser> modules, in
addition to others that are included in the standard Perl distribution.
See the News Clipper distribution's README file for more information.

Handlers that you download may require additional modules.

=head1 AUTHOR

Spinnaker Software, Inc.
David Coppit, <david@coppit.org>, http://coppit.org/

=begin CPAN

=pod COREQUISITES

none

=pod OSNAMES

any

=pod SCRIPT
