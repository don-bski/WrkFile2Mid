#!/usr/bin/perl
# ==============================================================================
# FILE: playWrk.pl                                                    4-29-2026
#
# SERVICES: MIDI Play Wrapper for WrkFile2Mid  
#
# DESCRIPTION:
#   This program is a wrapper for WrlFile2Midi.pl. It provides an interactive 
#   user interface for WRK file selection. The user selected file is processed
#   by WrkFile2Mid.pl to create sysex (.sxd) and MIDI (.mid) file output. The 
#   .sxd sysex data is then sent to the currently available MIDI devices using
#   syxmidi. Playback of the .mid file is then initiated using the pmidi program.
#   Upon completion of playback, the user is prompted to select another WRK file.
#
#   The -e option is used to specifiy the location of WrkFile2Mid.pl and syxmidi 
#   if not in the current working directory. WRK files specified on the startup
#   CLI will suppress user interactive prompting and may include directory path.
#
#   Revision History:
#   v0.1  Initial release.
#   v0.2  -q option and logic for best effort processing.
# ==============================================================================
use strict;
use warnings;
use Cwd qw( abs_path getcwd);
use File::Glob qw(:globally :nocase);
use Getopt::Std;
use Term::ANSIColor;
require Win32::Console::ANSI if ($^O =~ m/Win/i);

# ==============================================================================
# Global Variables
our %cliOpts = ();                                # CLI options working hash
getopts('he:w:', \%cliOpts);                      # Load CLI options hash

our ($ExecutableName) = ($0 =~ /([^\/\\]*)$/);    # Program name.
our $WorkingDir;                                  # Working directory.
if ($0 =~ m#^(.+)$ExecutableName$#) {
   $WorkingDir = $1;
}
else {
   $WorkingDir = getcwd;
}
our $Version = 'v0.2';                            # Program version string.

our $UsageText = (qq(
===== Help for $ExecutableName =====================================================

GENERAL DESCRIPTION
   This program is a wrapper for WrlFile2Midi.pl. It provides an interactive 
   user interface for WRK file selection. The user selected file is processed
   by WrkFile2Mid.pl to create sysex (.sxd) and MIDI (.mid) file output. The 
   .sxd sysex data is then sent to the currently available MIDI devices using
   syxmidi. Playback of the .mid file is then initiated using the pmidi program.
   Upon completion of playback, the user is prompted to select another WRK file.

   The -e option specifies the location of WrkFile2Mid.pl and syxmidi if not in
   the current working directory or $ExecutableName startup directory.

   The -w option specifies the location of the WRK files if not in the current
   working directory.
   
   WRK files specified on the startup CLI suppress user interactive prompting 
   and may include a directory path. Linux piped input is also supported.

USAGE:
   $ExecutableName  [-h] [-e <dir>] [-w <dir>] [[<path>/]<file>, ...]

   -h            Displays program usage text.
   -e <dir>      Specifies support tool directory. 
   -w <dir>      Specifies WRK file directory. 
                 
EXAMPLES:
   $ExecutableName
      Interactive processing of WRK files in the current working directory.

   $ExecutableName -e /home/don/perl -w ./midi
      Interactive processing of WRK files located in the ./midi directory.
      Support tools are located in the /home/don/perl directory.

   $ExecutableName -e /home/don/perl ./midi/piano.wrk ./midi/ditty.wrk
      Non-interactive processing of the specified WRK files. Support tools
      are located in the /home/don/perl directory.

VERSION: 
   $ExecutableName $Version
===============================================================================
));

# =============================================================================
# FUNCTION:  ColorMessage
#
# DESCRIPTION:
#    Displays a message to the user. If specified, an input parameter provides
#    coloring the message text. Specify 'use Term::ANSIColor' in the perl script
#    to define the ANSIcolor constants.
#
#    Color constants defined by Term::ANSIColor include:
#
#    CLEAR            RESET              BOLD             DARK
#    FAINT            ITALIC             UNDERLINE        UNDERSCORE
#    BLINK            REVERSE            CONCEALED
#  
#    BLACK            RED                GREEN            YELLOW
#    BLUE             MAGENTA            CYAN             WHITE
#    BRIGHT_BLACK     BRIGHT_RED         BRIGHT_GREEN     BRIGHT_YELLOW
#    BRIGHT_BLUE      BRIGHT_MAGENTA     BRIGHT_CYAN      BRIGHT_WHITE
#  
#    ON_BLACK         ON_RED             ON_GREEN         ON_YELLOW
#    ON_BLUE          ON_MAGENTA         ON_CYAN          ON_WHITE
#    ON_BRIGHT_BLACK  ON_BRIGHT_RED      ON_BRIGHT_GREEN  ON_BRIGHT_YELLOW
#    ON_BRIGHT_BLUE   ON_BRIGHT_MAGENTA  ON_BRIGHT_CYAN   ON_BRIGHT_WHITE
#
#    Space separate multiple constants. e.g. BOLD BLUE ON_WHITE
#  
# CALLING SYNTAX:
#    $result = &ColorMessage($Message, $Color, $Nocr);
#
# ARGUMENTS:
#    $Message         Message to be output.
#    $Color           Optional color attributes to apply.
#    $Nocr            Suppress message newline if set. 
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub ColorMessage {
   my($Message, $Color, $Nocr) = @_;
   my($cr) = "\n";
   
   $cr = '' if ($Nocr ne '');
   if ($Color ne '') {
      if ($^O =~ m/Win/i) {            # Windows environment?
         print STDOUT color("$Color"), $Message, color("reset"), "$cr";
      }
      else {
         print STDOUT colored($Message . "$cr", $Color);
      }
   }
   else {
      print STDOUT $Message, "$cr";
   }
   return 0;
}

# =============================================================================
# FUNCTION:  InteractiveHeader
#
# DESCRIPTION:
#    This routine is called by InteractiveMode to display the heading text.
#    Called during startup of interactive mode and in response to user entry
#    to redisplay the header.
#
# CALLING SYNTAX:
#    $result = &InteractiveHeader(\%WrkFiles, $RawPorts, $SeqPorts);
#
# ARGUMENTS:
#    $Dir                 Directory holding WRK files.
#    $WrkFiles            Pointer to WrkFiles hash.
#    $RawPorts            List of ; separated rawmidi ports.
#    $SeqPorts            List of , separated seqmidi ports.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None.
# =============================================================================
sub InteractiveHeader {
   my($Dir, $WrkFiles, $RawPorts, $SeqPorts) = @_;
   my (@ports);
   my $line = '=' x 80;
   my $col = 0;   my $cols = 2;
   
   &ColorMessage("\n$line", "WHITE", '');
   @ports = ('none');
   @ports = split(';', $RawPorts) if ($RawPorts ne '');
   &ColorMessage("Rawmidi devices: ", "WHITE", 'nocr');
   &ColorMessage("@ports", "BRIGHT_CYAN", '');
   @ports = ('none');
   @ports = split(',', $SeqPorts) if ($SeqPorts ne '');
   &ColorMessage("Seqmidi devices: ", "WHITE", 'nocr');
   &ColorMessage("@ports", "BRIGHT_CYAN", '');
   &ColorMessage("\nAvailable WRK files in $Dir", "WHITE", '');
   &ColorMessage("", "WHITE", '') if (scalar keys(%$WrkFiles) > 0);
   foreach my $id (sort {$a <=> $b} keys(%$WrkFiles)) {
      &ColorMessage('  ' . substr("  $id", -3) . " ", "BRIGHT_CYAN", 'nocr');
      my $name = substr($$WrkFiles{$id}, rindex($$WrkFiles{$id}, '/')+1);
      &ColorMessage(substr(($name . ' ' x 36), 0, 36), "WHITE", 'nocr');
      $col++;
      if ($col == $cols) {
         &ColorMessage("", "WHITE", '');
         $col = 0;
      }
   }
   &ColorMessage("", "WHITE", '') if ($col != 0);
   &ColorMessage("\nSeparate multiple Ids with space or comma.", "WHITE", '');
   &ColorMessage("$line", "WHITE", '');
   return 0;
}

# =============================================================================
# FUNCTION:  InteractiveMode
#
# DESCRIPTION:
#    This routine displays the WRK files in the specified directory and then
#    prompts for selection. Once selection(s) are input, &ProcessWrkFile is
#    called with file list.
#
#    User entered WRK Id values, redisplay header (r), or termination command
#    (q or e) are processed by this subroutine.
#
# CALLING SYNTAX:
#    $result = &InteractiveMode($Dir, $Wrk2Mid, $Pmidi, $RawPorts, $SeqPorts);
#
# ARGUMENTS:
#    $Dir              Directory holding WRK files.
#    $Wrk2Mid          WrkFile2Mid perl program.
#    $Pmidi            pmidi player executable.
#    $RawPorts         Ordered rawmidi ports.
#    $SeqPorts         Ordered seqmidi ports.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None.
# =============================================================================
sub InteractiveMode {
   my($Dir, $Wrk2Mid, $Pmidi, $RawPorts, $SeqPorts) = @_;
   my(@resp) = ();   my(%wrkFiles) = ();

   # Get the WRK files in the specified directory.
   my @files = sort glob "$Dir/*.wrk";
   if (scalar @files < 0) {
      &ColorMessage("\nNo WRK files found in $Dir", "BRIGHT_YELLOW", '');
      return 0;
   }
   else {
      my $id = 1;
      foreach my $file (@files) {
         $wrkFiles{$id++} = $file;
      }
   }

   # Display available WRK files.
   return 1 if (&InteractiveHeader($Dir, \%wrkFiles, $RawPorts, $SeqPorts));

   # Get user input and process.
   while (1) {
      &ColorMessage("Enter file Id(s), ", "WHITE", 'nocr');
      &ColorMessage("r ", "BRIGHT_CYAN", 'nocr');
      &ColorMessage("to relist, or ", "WHITE", 'nocr');
      &ColorMessage("q ", "BRIGHT_CYAN", 'nocr');
      &ColorMessage("to quit. -> ", "WHITE", 'nocr');
      my $id = <STDIN>;
      chomp($id);
      $id =~ s/^\s+|\s+$//g;
      next if ($id eq '');
      last if ($id =~ m/^q/i or $id =~ m/^e/i);      # Accept quit or exit.
      if ($id =~ m/^r/i) {
         return 1 if (&InteractiveHeader($Dir, \%wrkFiles, $RawPorts, $SeqPorts));
         next;
      }
      
      # ==========
      my @idList = ();
      if ($id =~ m/^\d+$/) {              # Single id.
         push (@idList, $id);
      }
      elsif ($id =~ m/^\d+ /) {           # Multi space separated.
         push (@idList, split(' ', $id));
      }
      elsif ($id =~ m/^\d+,/) {           # Multi comma separated.
         push (@idList, split(',', $id));
      }
      else {
         &ColorMessage("Invalid input: $id", "BRIGHT_YELLOW", '');
         next;
      }
      foreach my $id (@idList) {
         if (exists($wrkFiles{$id})) {
            return 1 if(&ProcessWrkFile($wrkFiles{$id}, $Wrk2Mid, $Pmidi, 
                                        $RawPorts, $SeqPorts));
         }
         else {
            &ColorMessage("Invalid Id: $id", "BRIGHT_YELLOW", '');
         }
      }
   }
   &ColorMessage("", "WHITE", '');
   return 0;
}

# =============================================================================
# FUNCTION: ProcessWrkFile
#
# DESCRIPTION:
#    This routine processes and plays the specified WrkFile.
#
# CALLING SYNTAX:
#    $result = &ProcessWrkFile($WrkFile, $Wrk2Mid, $Pmidi, $RawPorts, $SeqPorts);
#
# ARGUMENTS:
#    $WrkFile          WRK file to process.
#    $Wrk2Mid          WrkFile2Mid perl program.
#    $Pmidi            pmidi player executable.
#    $RawPorts         Ordered rawmidi ports.
#    $SeqPorts         Ordered seqmidi ports.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None.
# =============================================================================
sub ProcessWrkFile {
   my ($WrkFile, $Wrk2Mid, $Pmidi, $RawPorts, $SeqPorts) = @_;
   
   if (-e $WrkFile and $Wrk2Mid ne '') {                    # Process the WRK file.
      &ColorMessage("\nLaunch WrkFile2Mid.pl ...", "BRIGHT_CYAN", '');
      system("perl $Wrk2Mid -f $WrkFile");
      return 1 if (($? >> 8) > 0);
   }
   
   $WrkFile =~ s/\.wrk$/\.sxd/i;
   if (-e $WrkFile and $Wrk2Mid ne '' and $RawPorts ne '') {  # Send the sysex data.
      &ColorMessage("\nLaunch WrkFile2Mid.pl to send sysex ...", "BRIGHT_CYAN", '');
      system("perl $Wrk2Mid -M '$RawPorts' -p auto -s $WrkFile");
      return 1 if (($? >> 8) > 0);
   }
   
   $WrkFile =~ s/\.sxd$/\.mid/i;
   if (-e $WrkFile and $Pmidi ne '' and $SeqPorts ne '') {    # Play the mid file.
      &ColorMessage("\nLaunch pmidi to play $WrkFile ...", "BRIGHT_CYAN", '');
      system("$Pmidi -p $SeqPorts $WrkFile");  
      &ColorMessage("", "WHITE", '');
      return 1 if (($? >> 8) > 0);
   }
   &ColorMessage("Processing complete for: ", "BRIGHT_CYAN", 'nocr');   
   &ColorMessage("$WrkFile\n", "WHITE", '');
   return 0;
}

# =============================================================================
# MAIN PROGRAM
# =============================================================================

# ==========
# Display program help if -h specified.
if (defined( $cliOpts{h} )) {
   &ColorMessage("$UsageText", "WHITE", '');
   exit(0);  
}

# ==========
# Set tool path and process -e if specified.
my $toolPath = $WorkingDir;
if (defined( $cliOpts{e} )) {
   $toolPath = $cliOpts{e};
   chomp($toolPath);
   $toolPath =~ s/^\s+|\s+$//g;
   unless (-d $toolPath) {
      &ColorMessage("Invalid directory: $cliOpts{e}", "BRIGHT_RED", '');
      exit(1);
   }
}

# ==========
# Verify required tools are available.
my $wrk2Mid = join('/', $toolPath, 'WrkFile2Mid.pl');
unless (-e $wrk2Mid) {
   &ColorMessage("WrkFile2Mid.pl not found. WRK files won't be processed.", 
                 "BRIGHT_YELLOW", '');
   &ColorMessage("Use -e to specify location.", "BRIGHT_YELLOW", '');
   $wrk2Mid = '';
}
my $syxmidi = join('/', $toolPath, 'syxmidi');
unless (-e $syxmidi) {
   &ColorMessage("syxmidi not found. Sysex data won't be processed.", 
                 "BRIGHT_YELLOW", '');
   &ColorMessage("Use -e to specify location.", "BRIGHT_YELLOW", '');
   $syxmidi = '';
}
my $pMidi = '/usr/bin/pmidi';
my $result = '';
$result = `which $pMidi` unless ($^O =~ m/Win/i);
chomp($result);
unless ($pMidi eq $result) {
   &ColorMessage("pmidi not installed. Mid files won't be played.",
                 "BRIGHT_YELLOW", '');
   &ColorMessage("Install using linux package manager.", "BRIGHT_YELLOW", '');
   $pMidi = '';              
}


# ==========
# Get the available rawmidi and seqmidi ports. Each is ordered by port number.
# e.g. rawmidi: hw:2,0,0 hw:2,0,1   seqmidi: 24:0 24:1
my ($rawPorts, $seqPorts) = ('', '');
if ($syxmidi ne '') {
   my @rawmidi = ();
   my @midiDevs = `$syxmidi -l`;      # Get available ALSA RawMidi devices
   splice(@midiDevs, 0, 1);           # Discard headline.
   if (scalar @midiDevs > 0) {
      foreach my $midiDevRec (@midiDevs) {
         chomp($midiDevRec);
         my ($dir, $dev, $name) = $midiDevRec =~ m/^(\S+)\s+(\S+)\s+(.+)$/;
         push (@rawmidi, $dev);
      }
      @rawmidi = sort @rawmidi;
   }
   if (scalar @rawmidi == 0) {
      &ColorMessage("No rawmidi devices found.", "BRIGHT_YELLOW", '');
   }
   else {
      $rawPorts = join(';', @rawmidi);
   }
   
   my @seqmidi = ();
   @midiDevs = `$syxmidi -L`;         # Get available ALSA sequencer devices
   splice(@midiDevs, 0, 1);           # Discard headline.
   if (scalar @midiDevs > 0) {
      foreach my $midiDevRec (@midiDevs) {
         chomp($midiDevRec);
         $midiDevRec =~ s/^\s+//;
         my ($dev, $name) = $midiDevRec =~ m/^(\S+)\s+(.+)$/;
         next if ($name =~ m/Midi Through/);  # Skip MIDI Through device.
         push (@seqmidi, $dev);
      }
      @seqmidi = sort @seqmidi;
   }
   if (scalar @seqmidi == 0) {
      &ColorMessage("No seqmidi devices found.", "BRIGHT_YELLOW", '');
   }
   else {
      $seqPorts = join(',', @seqmidi);
   }
}

# ==========
# Handle piped input.
unless (-t STDIN) {      # STDIN not connected to terminal? 
   while (<STDIN>) {
      chomp($_);
      $_ =~ s/^\s+|\s+$//g;
      next if ($_ eq '' or $_ =~ m/^#/);
      push (@ARGV, $_);  # Add to end of @ARGV.
   }
}

# ==========
# Check for -w specifying the WRK file directory path. This path is used
# when a WRK file does not already have a path portion.
my $wrkPath = '';
if (defined( $cliOpts{w} )) {
   if (-d $cliOpts{w}) {
      $wrkPath = $cliOpts{w};
      chomp($wrkPath);
      $wrkPath =~ s/^\s+|\s+$//g;
   }
   else {
      &ColorMessage("Invalid -w directory: $cliOpts{w}", "BRIGHT_RED", '');
      exit(1);
   }
}

# ==========
# Get CLI specified WRK files. If none, enter interactive mode.
if (scalar @ARGV > 0) {
   foreach my $wrk (@ARGV) {
      if ($wrk =~ m/\.wrk$/i) {
         unless ($wrk =~ m#/# or $wrkPath eq '') {
            $wrk = join('/', $wrkPath, $wrk);
         }
         if (-e $wrk) {
            exit(1) if (&ProcessWrkFile($wrk, $wrk2Mid, $pMidi, $rawPorts, 
                        $seqPorts));
         }
         else {
            &ColorMessage("File not found: $wrk", "BRIGHT_YELLOW", '');
         }
      }
      else {
        &ColorMessage("Not a WRK file: $wrk", "BRIGHT_YELLOW", '');
      } 
   }
}
else {
   my $dir = getcwd;
   $dir = $wrkPath if ($wrkPath ne '');
   exit(1) if (&InteractiveMode($dir, $wrk2Mid, $pMidi, $rawPorts, $seqPorts));
}

exit(0);
