#!/usr/bin/perl
# use perl                                  -*- mode: Perl; -*-

use strict;

sub WriteRegistry
{
  my $home = shift;
  my $VERSION = shift;

  print "Writing Installation directory information to Windows registry...\n";

  require Win32::Registry;

  my $key = "SOFTWARE\\Spinnaker Software\\News Clipper\\$VERSION";
  my $TempKey;

  $main::HKEY_LOCAL_MACHINE->Create($key, $TempKey) ||
    die "Can't create key $key in registry.\n";
  
  $main::HKEY_LOCAL_MACHINE->Open($key, $TempKey) ||
    die "Can't find key $key in registry.\n";
  
  my ($class, $nSubKey, $nVals, $junk);
  $TempKey->SetValueEx("InstallDir", $junk, 1, $home);

  print "Done.\n";
}

# --------------------------------------------------------------------------

# Get the version number from the NewsClipper.pl script
sub GetVersion
{
  open NC, "NewsClipper.pl";
  my $nccode = join '',<NC>;
  close NC;

  my $VERSION;

  my ($versionCode) = $nccode =~ /(\$VERSION =.*?)\n/s;

  eval $versionCode;

  return $VERSION;
}

# --------------------------------------------------------------------------

sub GetInstallInfo
{
  my ($home,$timezone,$prefix,$installtype);

  if (($^O eq 'dos') || ($^O eq 'MSWin32'))
  {
    print<<EOF;

Also, you need to tell me what time zone you are in, because News Clipper
won't be able to figure it out from your operating system.  In the US,
they are of the form PST, CST, EST. See "perldoc Date::Manip" for a complete 
list, if you have Date::Manip installed.
EOF

    print "=> [PST] ";
    $timezone = <STDIN>;
    $timezone = "PST\n" if $timezone eq "\n";
    chomp $timezone;

    # ----------------------------------------------------------------------

    $installtype = 'user';

    print "\n","-"x78,"\n";
    print<<EOF;
Where would you like to install News Clipper? Use / instead of \\, and don't
use spaces.
EOF
    print "=> [C:/PROGRA~1/NewsClipper] ";
    $home = <STDIN>;
    chomp $home;
    $home = "C:/PROGRA~1/NewsClipper" if $home eq '';

    print "\n","-"x78,"\n";

    push @ARGV,'INSTALLDIRS=perl';
    push @ARGV,"PREFIX=$home";

    $prefix=$home;
  }
  else
  {
    print <<EOF;
Are you installing News Clipper as a [1] single user or [2] system-wide?
EOF

    print "=> [1] ";
    my $response = <STDIN>;
    chomp $response;

    if ($response eq '' || $response eq '1')
    {
      $installtype = 'user';

      print "\n","-"x78,"\n";
      print "Where would you like to install News Clipper?\n=> ";
      my $installdir = <STDIN>;
      chomp $installdir;

      print "\n","-"x78,"\n";
      print "Where would you like to install the man pages?\n";
      print "=> [$installdir/man/man1] ";
      my $installmandir = <STDIN>;
      chomp $installmandir;
      $installmandir = "$installdir/man/man1" if $installmandir eq '';

      push @ARGV,'INSTALLDIRS=perl';
      push @ARGV,"PREFIX=$installdir";
      push @ARGV,"INSTALLMAN1DIR=$installmandir";

      print "\n","-"x78,"\n";
      print<<EOF;

Since you're doing a single-user installation, I'm going to set modulepath in
NewsClipper's configuration file to point to \$INSTALLPRIVLIB (typically
something like $installdir/lib/perl5/5.00502.)
This is so that you don't have to change your PERL5LIB variable, or run News
Clipper using "perl -I".
EOF
      $prefix=$installdir;
    }
    else
    {
      $installtype = 'system';
      require Config;
      $prefix = $Config::Config{'prefix'};
    }
  }

  return ($home,$timezone,$prefix,$installtype);
}

# --------------------------------------------------------------------------

my ($home,$timezone);
my $prefix = undef;
my $installtype;
my $sysconfigdir;

my $VERSION = GetVersion;

if ($ARGV[0] eq "dist")
{
  print<<EOF;
Which version are you distributing? [1] Open Source [2] Perl [3] Linux/Solaris
EOF

  print "=> [1] ";
  my $response = <STDIN>;
  chomp $response;

  $VERSION .= '-os' if $response eq '1' || $response eq '';
  $VERSION .= '-pl' if $response eq '2';
  $VERSION .= '-ls' if $response eq '3';
}
else
{
  ($home,$timezone,$prefix,$installtype) = GetInstallInfo;

  # ----------------------------------------------------------------------------

  # The home directory is the global system configuration directory in Windows.
  if (($^O eq 'dos') || ($^O eq 'MSWin32'))
  {
    WriteRegistry($home,$VERSION);
    $sysconfigdir = "$home/.NewsClipper";
    $sysconfigdir =~ s#\\#/#g;
  }
  else
  {
    print "\n","-"x78,"\n";

    print "Where would you like to install the system-wide configuration file\n"
      if $installtype eq 'system';
    print "Where would you like to install the default configuration file\n"
      if $installtype eq 'user';

    print "NewsClipper.cfg?\n";

    $sysconfigdir = "$prefix/etc";
    print "=> [$sysconfigdir] ";
    my $input = <STDIN>;
    chomp $input;
    $sysconfigdir = $input if $input ne '';
    $sysconfigdir =~ s#\\#/#g;
  }
}

# ------------------------------------------------------------------------------

use ExtUtils::MakeMaker;

require 5.004;

WriteMakefile(
  # For debugging
  #'NOECHO' => '',
  'NAME'  => 'NewsClipper',
  # finds $VERSION
  #'VERSION_FROM' => 'NewsClipper.pl',
  'VERSION' => $VERSION,

  'dist'  => { COMPRESS => 'gzip -9', SUFFIX => 'gz' },
  # Gotta do this to prevent MakeMaker from thinking the .pl files are library
  # modules
  'PM' => {
    'NewsClipper/AcquisitionFunctions.pm' =>
        '$(INST_LIBDIR)/NewsClipper/AcquisitionFunctions.pm',
    'NewsClipper/Globals.pm' =>
        '$(INST_LIBDIR)/NewsClipper/Globals.pm',
    'NewsClipper/Handler.pm' =>
        '$(INST_LIBDIR)/NewsClipper/Handler.pm',
    'NewsClipper/HTMLTools.pm' =>
        '$(INST_LIBDIR)/NewsClipper/HTMLTools.pm',
    'NewsClipper/HandlerFactory.pm' =>
        '$(INST_LIBDIR)/NewsClipper/HandlerFactory.pm',
    'NewsClipper/Interpreter.pm' =>
        '$(INST_LIBDIR)/NewsClipper/Interpreter.pm',
    'NewsClipper/Cache.pm' =>
        '$(INST_LIBDIR)/NewsClipper/Cache.pm',
    'NewsClipper/Types.pm' =>
        '$(INST_LIBDIR)/NewsClipper/Types.pm',
    'NewsClipper/Parser.pm' =>
        '$(INST_LIBDIR)/NewsClipper/Parser.pm',
  },
  'EXE_FILES' => [ 'NewsClipper.pl', 'MakeHandler.pl', ],
  'PREREQ_PM' => { 'HTML::Parser' => 2.06, 'HTML::FormatText' => 0,
                   'Time::ParseDate' => 0,
                   'Time::CTime' => 0,
                   'HTML::TreeBuilder' => 0, 'URI' => 1.0, 'LWP' => 5.15},
);

# Create new targets to do the permissions and cleanup installation
sub MY::postamble
{
my $returnText =<<EOF;
NewsClipper_Cleanup:
	\@echo 'Finishing up:'
	\@echo '  Making NewsClipper.pl and MakeHandler.pl executable...'
	\@perl -MExtUtils::Command -e "chmod(0755,'\$(INSTALLSCRIPT)/NewsClipper.pl')"
	\@perl -MExtUtils::Command -e "chmod(0755,'\$(INSTALLSCRIPT)/MakeHandler.pl')"
EOF

# I don't know why the backslash matters on Windows, but it does...
if (($^O eq 'dos') || ($^O eq 'MSWin32'))
{
  $returnText .=<<EOF;
	\@echo '  Updating #! line in NewsClipper.pl and MakeHandler.pl...'
	\@perl -ibak -pe "BEGIN { (\$\$FP = '\$(FULLPERL)') =~ tr|\\\\\\\\|/| } s|^#!\\S*perl|#!\$\$FP|" \$(INSTALLSCRIPT)/NewsClipper.pl
	\@perl -e "unlink('\$(INSTALLSCRIPT)/NewsClipper.plbak')"
	\@perl -ibak -pe "BEGIN { (\$\$FP = '\$(FULLPERL)') =~ tr|\\\\\\\\|/| } s|^#!\\S*perl|#!\$\$FP|" \$(INSTALLSCRIPT)/MakeHandler.pl
	\@perl -e "unlink('\$(INSTALLSCRIPT)/MakeHandler.plbak')"
EOF
}
else
{
  $returnText .=<<EOF;
	\@echo '  Updating #! line in NewsClipper.pl and MakeHandler.pl...'
	\@perl -ibak -pe "BEGIN { (\\\$\$FP = '\$(FULLPERL)') =~ tr|\\\\\\\\|/| } s|^#!\\S*perl|#!\\\$\$FP|" \$(INSTALLSCRIPT)/NewsClipper.pl
	\@perl -e "unlink('\$(INSTALLSCRIPT)/NewsClipper.plbak')"
	\@perl -ibak -pe "BEGIN { (\\\$\$FP = '\$(FULLPERL)') =~ tr|\\\\\\\\|/| } s|^#!\\S*perl|#!\\\$\$FP|" \$(INSTALLSCRIPT)/MakeHandler.pl
	\@perl -e "unlink('\$(INSTALLSCRIPT)/MakeHandler.plbak')"
EOF
}

if ($sysconfigdir ne '')
{
  $returnText .=<<EOF;
	\@echo '  Copying NewsClipper.cfg to $sysconfigdir...'
	\@perl -MExtUtils::Command -e mkpath "$sysconfigdir"
	\@perl -MExtUtils::Command -e cp NewsClipper.cfg "$sysconfigdir"
	\@echo '  Making NewsClipper.cfg writeable...'
	\@perl -MExtUtils::Command -e "chmod(0666,'$sysconfigdir/NewsClipper.cfg')"
EOF
}

if ($installtype eq 'user' && ($^O ne 'dos') && ($^O ne 'MSWin32'))
{
  $returnText .=<<EOF;
	\@echo '  Setting modulepath in NewsClipper.cfg...'
	\@perl -ibak -pe "s|'modulepath' => '.*'|'modulepath' => '\$(INSTALLPRIVLIB)'|" "$sysconfigdir/NewsClipper.cfg"
	\@perl -e "unlink(\\"$sysconfigdir/NewsClipper.cfgbak\\")"
EOF
}

if (($^O eq 'dos') || ($^O eq 'MSWin32'))
{
  $returnText .=<<EOF;
	\@perl -e "unlink(\\"\$(INSTALLSCRIPT)/NewsClipper.plbak\\")"
	\@echo '  Setting \$\$ENV\{TZ\} in NewsClipper.cfg...'
	\@perl -ibak -pe "s|^\\\$\$ENV.TZ.*if |\\\$\$ENV\\173TZ\\175 = '$timezone' if |" "$sysconfigdir/NewsClipper.cfg"
	\@perl -e "unlink(\\"$sysconfigdir/NewsClipper.cfgbak\\")"
EOF
}

return $returnText;
}
