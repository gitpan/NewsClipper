#!/usr/bin/perl
# use perl                                  -*- mode: Perl; -*-

use strict;
use ExtUtils::MakeMaker;

require 5.004;

# The names of the programs
my @programs = qw( NewsClipper MakeHandler ConvertConfig ConvertHandler );

# Used by Get_Version()
my $SOURCE_DIR = '.';

# Computed in Setup_Install() based on the architecture type. Used by
# postamble (which doesn't take arguments, so this has to be a global).
my $newsclipper_cfg_path;

# Computed by Setup_Install_Unix(). Used by postamble (which doesn't take
# arguments, so this has to be a global).
my $install_type;

# Computed in Setup_Install() based on the architecture type. Used by
# postamble (which doesn't take arguments, so this has to be a global).
my $timezone;

# The distribution version. Extended by a suffix when doing "make dist" which
# describes the type of distribution.
my $VERSION = GetVersion();

if ($ARGV[0] eq "opensource" || $ARGV[0] eq "unix" || $ARGV[0] eq "perl")
{
  Setup_Dist();
}
else
{
  Setup_Install($VERSION);
}

my %makefile_attributes = Compute_Makefile_Attributes($VERSION,@programs);

WriteMakefile(%makefile_attributes);

# --------------------------------------------------------------------------

# We get the version ourselves because we want to augment it with the
# distribution type. (That's why we can't use VERSION_FROM from MakeMaker.)

sub GetVersion
{
  open NC, "$SOURCE_DIR/NewsClipper.pl";
  my $newsclipper_code = join '',<NC>;
  close NC;

  my $VERSION;

  my ($version_code) = $newsclipper_code =~ /(\$VERSION =.*?)\n/s;

  eval $version_code;

  return $VERSION;
}

# --------------------------------------------------------------------------

sub Setup_Dist
{
  $VERSION .= '-os' if $ARGV[0] eq 'opensource';
  $VERSION .= '-pl' if $ARGV[0] eq 'perl';
  $VERSION .= '-un' if $ARGV[0] eq 'unix';
}

# --------------------------------------------------------------------------

# Performs either the Windows or Unix installation

sub Setup_Install
{
  my $VERSION = shift;

  my ($install_dir,$install_man_dir);

  if (($^O eq 'dos') || ($^O eq 'MSWin32'))
  {
    ($timezone,$newsclipper_cfg_path,$install_dir,$install_man_dir) =
      Setup_Install_Windows();
    $install_type = undef;
  }
  else
  {
    ($newsclipper_cfg_path,$install_type,$install_dir,$install_man_dir) =
      Setup_Install_Unix();
    $timezone = undef;
  }

  unless (defined $install_type && $install_type eq 'system')
  {
    push @ARGV,'INSTALLDIRS=perl';
    push @ARGV,"PREFIX=$install_dir";
    push @ARGV,"INSTALLMAN1DIR=$install_man_dir";
  }

  print<<EOF;

If you are upgrading from a previous version of News Clipper, you need to:
- run ConvertHandler.pl on any handlers you wrote yourself. (i.e.,
  which aren't in the handler database already.)
- delete any other handlers for the old version of News Clipper.

EOF
}

# --------------------------------------------------------------------------

sub Setup_Install_Windows
{
  my ($timezone,$install_dir) = Get_Windows_Install_Info();

  # Put the installation directory in the registry
  WriteRegistry($install_dir,$VERSION);

  # Figure out if there is already a NewsClipper.cfg
  my $newsclipper_cfg_path = Find_NewsClipper_cfg($install_dir);

  return ($timezone,$newsclipper_cfg_path,$install_dir,
    "$install_dir/man/man1");
}

# --------------------------------------------------------------------------

# Finds the path to the existing NewsClipper.cfg, or the path to where the new
# one should be copied. Unix installations should call this function with a
# second argument telling whether the installation type is "system" or "user".

sub Find_NewsClipper_cfg
{
  my $install_dir = shift;
  my $install_type = shift;

  my $config_dir;

  # Figure out directory for NewsClipper.cfg
  if (($^O eq 'dos') || ($^O eq 'MSWin32'))
  {
    $config_dir = "$install_dir/.NewsClipper";
    $config_dir =~ s#\\#/#g;
  }
  else
  {
    print "\nWhere would you like to install the system-wide configuration file\n"
      if $install_type eq 'system';
    print "\nWhere would you like to install the default configuration file\n"
      if $install_type eq 'user';

    print "NewsClipper.cfg?\n";

    $config_dir = "$install_dir/etc";
    print "=> [$config_dir] ";

    my $input = <STDIN>;
    chomp $input;

    $config_dir = $input if $input ne '';
    $config_dir =~ s#\\#/#g;
  }

  my $config_exists = -e "$config_dir/NewsClipper.cfg";

  if ($config_exists)
  {
    print <<EOF;

News Clipper has found a configuration file (NewsClipper.cfg) in
$config_dir. This configuration file will be
automatically converted during installation. Use the ConvertConfig program to
convert any other NewsClipper.cfg files you may have.
EOF
  }
  else
  {
    print <<EOF;

News Clipper could not find an existing configuration file (NewsClipper.cfg).
This probably means that this is the first time you have installed News
Clipper. If you do have a NewsClipper.cfg from a previous installation of News
Clipper, please use the ConvertConfig program to convert it.
EOF
  }

  return $config_dir;
}

# --------------------------------------------------------------------------

sub Get_Windows_Install_Info
{
  my ($timezone,$install_dir);

  # Get the time zone
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


  # Get the installation directory
  print "\n","-"x78,"\n";
  print<<EOF;
Where would you like to install News Clipper? Use / instead of \\, and don't
use spaces.
EOF
  print "=> [C:/Program Files/NewsClipper] ";
  $install_dir = <STDIN>;
  chomp $install_dir;
  $install_dir = "C:/Program Files/NewsClipper" if $install_dir eq '';
  
  $install_dir = Win32::GetShortPathName $install_dir;
  $install_dir =~ s/\0.*//;

  print "\n","-"x78,"\n";

  return ($timezone,$install_dir);
}

# --------------------------------------------------------------------------

sub Setup_Install_Unix
{
  my ($install_dir,$install_man_dir,$install_type) = Get_Unix_Install_Info();

  # Figure out if there is already a NewsClipper.cfg
  my $newsclipper_cfg_path = Find_NewsClipper_cfg($install_dir,$install_type);

  return ($newsclipper_cfg_path,$install_type,$install_dir,$install_man_dir);
}

# --------------------------------------------------------------------------

sub Get_Unix_Install_Info
{
  my ($install_dir,$install_type,$install_man_dir);

  print <<EOF;
Are you installing News Clipper as a [1] single user or [2] system-wide?
EOF

  my $home = Get_Home_Directory();

  print "=> [1] ";
  my $response = <STDIN>;
  chomp $response;

  if ($response eq '' || $response eq '1')
  {
    $install_type = 'user';

    print "\n","-"x78,"\n";
    print "Where would you like to install News Clipper?\n" .
      " (Subdirectories will be created for the binaries, documentation, etc.)\n";
    print "=> [$home/NewsClipper] ";
    $install_dir = <STDIN>;
    chomp $install_dir;
    $install_dir = "$home/NewsClipper" if $install_dir eq '';

    print "\n","-"x78,"\n";
    print "Where would you like to install the man pages?\n";
    print "=> [$install_dir/man/man1] ";
    $install_man_dir = <STDIN>;
    chomp $install_man_dir;
    $install_man_dir = "$install_dir/man/man1" if $install_man_dir eq '';

    # Skip modulepath with compiled versions
    unless (-d 'bin')
    {
      print "\n","-"x78,"\n";
      print<<EOF;

Since you're doing a single-user installation, I'm going to set modulepath in
NewsClipper's configuration file to point to \$INSTALLPRIVLIB (typically
something like $install_dir/lib/perl5/5.00502.)
This is so that you don't have to change your PERL5LIB variable, or run News
Clipper using "perl -I".
EOF
    }
  }
  else
  {
    $install_type = 'system';
    require Config;
  }

  return ($install_dir,$install_man_dir,$install_type);
}

# --------------------------------------------------------------------------

# Figures out the user's home directory in Unix

sub Get_Home_Directory()
{
  # Get the user's home directory. First try the password info, then the
  # registry (if it's a Windows machine), then any HOME environment variable.
  my $home = eval { (getpwuid($>))[7] } || $ENV{HOME};

  die <<"  EOF"
News Clipper could not determine your home directory. I tried to get your
home directory using both getpwuid and your HOME environment variable.
  EOF
    unless defined $home;

  return $home;
}

# --------------------------------------------------------------------------

# Writes the user's installation directory into the Windows registry

sub WriteRegistry
{
  my $install_dir = shift;
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
  $TempKey->SetValueEx("install_dir", $junk, 1, $install_dir);

  print "Done.\n";
}

# --------------------------------------------------------------------------

sub Compute_Makefile_Attributes
{
  my $VERSION = shift;
  my @programs = @_;

  my %makefile_attributes;

  # Unix version has binaries
  if (-d 'bin')
  {
    @programs = grep { s/^/bin\// } @programs;

    %makefile_attributes = (
      'NAME'  => 'NewsClipper',
      'VERSION' => $VERSION,

      # Prevent recursion into src directory
      'DIR' => [],
      # Get man pages from .pl files in src directory
      'MAN1PODS' => { 'src/NewsClipper.pl' => 'blib/man1/NewsClipper.1',
                      'src/MakeHandler.pl' => 'blib/man1/MakeHandler.1',
                    },
      'dist'  => { COMPRESS => 'gzip -9', SUFFIX => 'gz' },
      # Gotta do this to prevent MakeMaker from thinking the .pl files are
      # library modules
      'PM' => { },
      'EXE_FILES' => \@programs,
      'PREREQ_PM' => { },
    );
  }
  else
  {
    @programs = grep { s/$/.pl/ } @programs;

    %makefile_attributes = (
      'NAME'  => 'NewsClipper',
      'VERSION' => $VERSION,

      'dist'  => { COMPRESS => 'gzip -9', SUFFIX => 'gz' },
      # Gotta do this to prevent MakeMaker from thinking the .pl files are
      # library modules
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
        'NewsClipper/TagParser.pm' =>
            '$(INST_LIBDIR)/NewsClipper/TagParser.pm',
      },
      'EXE_FILES' => \@programs,
      'PREREQ_PM' => { 'HTML::Parser' => 2.06, 'HTML::FormatText' => 0,
                       'Time::ParseDate' => 0,
                       'Time::CTime' => 0,
                       'File::Cache' => 0.09,
                       'HTML::TreeBuilder' => 0, 'URI' => 1.0, 'LWP' => 5.15,
                       'Storable' => 0},
    );
  }

  return %makefile_attributes
}

# --------------------------------------------------------------------------

# Uses globals: $install_type, $newsclipper_cfg_path, $^O

sub MY::install
{
  # Return nothing if we are building a makefile for building the .tar.gz
  # distribution
  return ''
    if ($ARGV[0] eq "opensource" || $ARGV[0] eq "unix" || $ARGV[0] eq "perl");

  package MY; # so that "SUPER" works right
  my $inherited = shift->SUPER::install(@_);
  $inherited =~ s/(install :: .*)$/$1 NewsClipper_Cleanup/m;
  return $inherited;
}

sub MY::postamble
{
  my $returnText = "NewsClipper_Cleanup:\n";

  # Return nothing if we are building a makefile for building the .tar.gz
  # distribution
  return ''
    if ($ARGV[0] eq "opensource" || $ARGV[0] eq "unix" || $ARGV[0] eq "perl");

  my $cfg_file = "$newsclipper_cfg_path/NewsClipper.cfg";

    $returnText .=<<"    EOF";
	\@echo '  -------------------------------------------------------------'; \\
	echo 'DOING FINAL NEWS CLIPPER CONFIGURATION CHANGES'; \\
    EOF

  my $convert_config = 'ConvertConfig';

  # Unix version has binaries
  $convert_config .= '.pl' unless -d 'bin';

  # Look for an old NewsClipper.cfg in ~/.NewsClipper
  my $home = Get_Home_Directory();
  if (-e "$home/.NewsClipper/NewsClipper.cfg")
  {
    $returnText .=<<"    EOF";
	echo '  Updating $home/.NewsClipper/NewsClipper.cfg ...'; \\
	\$(INSTALLSCRIPT)/$convert_config "$home/.NewsClipper/NewsClipper.cfg"; \\
    EOF
  }

  # If the NewsClipper.cfg exists, we need to update it instead of copying it.
  if (-e $cfg_file)
  {
    $returnText .=<<"    EOF";
	echo '  Updating $cfg_file ...'; \\
	\$(INSTALLSCRIPT)/$convert_config "$cfg_file"; \\
    EOF
  }
  else
  {
    $returnText .=<<"    EOF";
	echo '  Copying NewsClipper.cfg to $newsclipper_cfg_path ...'; \\
	perl -MExtUtils::Command -e mkpath "$newsclipper_cfg_path"; \\
	perl -MExtUtils::Command -e cp NewsClipper.cfg "$newsclipper_cfg_path"; \\
    EOF
  }

  $returnText .=<<"  EOF";
	echo '  Making $cfg_file writeable ...'; \\
	perl -MExtUtils::Command -e "chmod(0666,'$cfg_file')"; \\
  EOF

  # If we are installing system-wide on Unix, or it's the Unix compile
  # version, we don't need to set the modulepath
  unless ((!(($^O eq 'dos') || ($^O eq 'MSWin32')) && ($install_type eq 'system'))
      || (-d 'bin'))
  {
    $returnText .=<<"    EOF";
	echo '  Setting modulepath in $cfg_file...'; \\
	perl -ibak -pe "s|'modulepath' => '.*'|'modulepath' => '\$(INSTALLPRIVLIB)'|" "$cfg_file"; \\
	perl -MExtUtils::Command -e "rm_f('${cfg_file}bak')"; \\
    EOF

    if (-e "$home/.NewsClipper/NewsClipper.cfg")
    {
      $returnText .=<<"      EOF";
	echo '  Setting modulepath in $home/.NewsClipper/NewsClipper.cfg...'; \\
	perl -ibak -pe "s|'modulepath' => '.*'|'modulepath' => '\$(INSTALLPRIVLIB)'|" "$home/.NewsClipper/NewsClipper.cfg"; \\
	perl -MExtUtils::Command -e "rm_f('$home/.NewsClipper/NewsClipper.cfgbak')"; \\
      EOF
    }
  }

  return $returnText;
}
