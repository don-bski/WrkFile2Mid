#!/usr/bin/perl
# ==============================================================================
# FILE: WrkFile2Mid.pm                                                4-29-2026
#
# SERVICES: Support code for WrkFile2Mid.pl.  
#
# DESCRIPTION:
#   This program contains support code used by WrkFile2Mid.pl. Refer to the
#   main program for details. Subroutines herein extract data from the various
#   Calewalk WRK file chunks. Also included are subroutines for sysex related
#   processing and transmission.
# ==============================================================================
# -----------------------------------------------------------------------------
# Package Declaration
# -----------------------------------------------------------------------------
package WrkFile2Mid;
require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw(
   ColorMessage
   DisplayDebug
   ReadFile
   WriteFile
   ReadData
   WriteData
   MemRegionChunk
   MarkersChunk
   VarsChunk
   StringTableChunk
   VariableChunk
   ThruChunk
   TempoChunk
   MeterChunk
   SysexChunk
   TrkMiscChunks
   TrackChunk
   StreamChunk
   TimeFmtChunk
   TimebaseChunk
   ShowMidiDevices
   SendSyx
   SxdAutoSend
   ProcessSxdFile
   ShowExtractedData
   CheckMidiFile
);

use Time::HiRes qw(sleep);
use Term::ANSIColor;
require Win32::Console::ANSI if ($^O =~ m/Win/i);

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
# FUNCTION:  DisplayDebug
#
# DESCRIPTION:
#    Displays a debug message to the user if the current program debug level 
#    is >= to the message debug level. Debug level colors message unless it
#    includes 'm' for monochrome output. 
#
# CALLING SYNTAX:
#    $result = &DisplayDebug($Level, $Message);
#
# ARGUMENTS:
#    $Level                Message debug level.
#    $Message              Message to be output.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    $main::cliOpts{d}
# =============================================================================
sub DisplayDebug {
   my($MsgLevel, $Message) = @_;
   
   if (defined( $main::cliOpts{d} )) {
      my ($runLevel, $mono) = $main::cliOpts{d} =~ /^(\d)([m]*)$/; 
      if ($runLevel >= $MsgLevel) {
         my $color = '';
         if ($MsgLevel == 1) {
            $color = 'BRIGHT_CYAN' unless ($mono eq 'm');
         }            
         elsif ($MsgLevel == 2) {
            $color = 'BRIGHT_MAGENTA' unless ($mono eq 'm');
         }            
         elsif ($MsgLevel == 3) {
            $color = 'BRIGHT_GREEN' unless ($mono eq 'm');
         }            
         &ColorMessage($Message, $color, '');
      }
   }
   return 0;
}

# =============================================================================
# FUNCTION:  ReadFile
#
# DESCRIPTION:
#    This routine reads the specified file into the specified array.
#
# CALLING SYNTAX:
#    $result = &ReadFile($InputFile, \@Array, $Option);
#
# ARGUMENTS:
#    $InputFile      File to read.
#    \@Array         Pointer to array for the read records.
#    $Option         'trim' input records.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub ReadFile {
   my($InputFile, $ArrayPointer, $Option) = @_;
   my($fileHandle);

   unless (-e $InputFile) {
      &ColorMessage("File not found: $InputFile", "BRIGHT_RED", '');
      return 1;
   }
   unless (open($fileHandle, '<', $InputFile)) {
      &ColorMessage("Error: opening file for read: $InputFile - $!",
                    "BRIGHT_RED", '');
      return 1;
   }
   @$ArrayPointer = <$fileHandle>;
   close($fileHandle);
   if ($Option =~ m/trim/i) {
      foreach my $line (@$ArrayPointer) {
         chomp($line);
         $line =~ s/^\s+|\s+$//g;
      }   
   }
   return 0;
}

# =============================================================================
# FUNCTION:  WriteFile
#
# DESCRIPTION:
#    This routine writes the specified array to the specified file. If the file
#    already exists, it is deleted.
#
# CALLING SYNTAX:
#    $result = &WriteFile($OutputFile, \@Array, $Option);
#
# ARGUMENTS:
#    $OutputFile     File to write.
#    $Array          Pointer to array of records to write.
#    $Option         'trim' records before writing to file.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub WriteFile {
   my($OutputFile, $OutputArrayPointer, $Option) = @_;
   my($fileHandle);
   
   unlink ($OutputFile) if (-e $OutputFile);

   unless (open($fileHandle, '>', $OutputFile)) {
      &ColorMessage("Error: opening file for write: $OutputFile - $!",
                    "BRIGHT_RED", '');
      return 1;
   }
   foreach my $line (@$OutputArrayPointer) {
      if ($Option =~ m/trim/i) {
         chomp($line);
         $line =~ s/^\s+|\s+$//g;
      }
      unless (print $fileHandle $line, "\n") {
         &ColorMessage("Error: writing file: $OutputFile - $!", "BRIGHT_RED", '');
         close($fileHandle);
         return 1;
      }
   }
   close($fileHandle);
   return 0;
}

# =============================================================================
# FUNCTION:  ReadData
#
# DESCRIPTION:
#    This routine reads the specified file into the specified array. The opened
#    fileHandle is set for binary (raw bytes) reading using binmode.
#
# CALLING SYNTAX:
#    $result = &ReadData($Filename, \$Data, $MaxSize);
#
# ARGUMENTS:
#    $Filename       File to read.
#    $Data           Pointer to output scalar.
#    $MaxSize        Maximim number of bytes to read.
#
# RETURNED VALUES:
#    <byte count read> = Success,  -1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub ReadData {
   my($Filename, $Data , $MaxSize) = @_;
   my($fileHandle);
   
   &DisplayDebug(1,"ReadData Filename: $Filename   MaxSize: $MaxSize");
   unless (-e $Filename) {
      &ColorMessage("File not found: $Filename", "BRIGHT_RED", '');
      return -1;
   }
   unless (open($fileHandle, '<', $Filename)) {
      &ColorMessage("Error: opening file for read: $Filename - $!",
                    "BRIGHT_RED", '');
      return -1;
   }
   binmode($fileHandle);
   my $cnt = read($fileHandle, $$Data , $MaxSize);
   close($fileHandle);
   
   return $cnt;
}

# =============================================================================
# FUNCTION:  WriteData
#
# DESCRIPTION:
#    This routine writes the MIDI data specified by the array pointer to a 
#    new file. The specified path/file is overwritten if it already exists.
#    The opened fileHandle is set for binary (raw bytes) using binmode.
#
#    The MIDI data is expected to be an array of hexidecimal character bytes.
#    Each byte's digit pair is packed to 8 bit raw binary as part of the 
#    write. Example @array: 4D 54 72 6B 00 00 09 94 ...
#
# CALLING SYNTAX:
#    $result = &WriteData($Filename, $ArrayPtr);
#
# ARGUMENTS:
#    $Filename       File to write.
#    $ArrayPtr       Pointer to array of MIDI data bytes.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub WriteData {
   my($Filename, $ArrayPtr) = @_;
   my($fileHandle);
   my $dataLen = scalar @$ArrayPtr;

   &DisplayDebug(1,"WriteData Filename: $Filename");
   unlink $Filename if (-e $Filename);
   
   if (open($fileHandle, ">", $Filename)) {
      binmode($fileHandle);
      unless (print $fileHandle pack("(H2)*", @$ArrayPtr)) {
         &ColorMessage("Error writing file: $Filename - $!", "BRIGHT_RED", '');
         return 1;
      }
      close($fileHandle);
      &DisplayDebug(1,"WriteData $dataLen bytes written to file.");
   }
   else {
      &ColorMessage("Error opening file for write: $Filename - $!", "BRIGHT_RED", '');
      return 1;
   }
   return 0;
} 

# =============================================================================
# FUNCTION:  MemRegionChunk
#
# DESCRIPTION:
#    Called to process the MEMRGN_CHUNK. The retrieved values are stored in
#    the %WrkMemRegion hash. Unsure of the chunk formatting. All of my WRK
#    files that use it have 10 records. The initial byte looks to be an Id
#    value (could be more than one byte) followed by 41 bytes of 00. 
#
#    MEMRGN_CHUNK (07)
#       id: int8              <- one byte ?
#       unknown: int8         <- fourty-one bytes ?
#
#       00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 
#          00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#       01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#          00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#       ...
#       09 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#          00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#
# CALLING SYNTAX:
#    $result = &MemRegionChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub MemRegionChunk {
   my($WrkData, $Id) = @_;
   my $wrkMemRgn = $$WrkData{$Id}{'result'};
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   &DisplayDebug(2,"MemRegionChunk Id: $Id   data: @wrkBytes");

   my $key = splice(@wrkBytes, 0, 1);
   @{ $$wrkMemRgn{$key} } = @wrkBytes;

   return 0;
}

# =============================================================================
# FUNCTION:  MarkersChunk
#
# DESCRIPTION:
#    Called to process the MARKERS_CHUNK. The retrieved values are stored in
#    the %WrkMarkers hash. These markers are user entered offset points; e.g. 
#    intro, verse 1, etc. Used by the Calewalk GUI. 
#
#    MARKERS_CHUNK (15)
#       count: int32          <- four bytes little endian
#          smpte: int8        <- one byte
#          gap: int8          <- one byte
#          time: int24        <- three bytes little endian
#          gap: int8          <- five bytes
#          strLen: int8       <- one byte
#          string: text       <- strLen bytes
#          ...
#
# CALLING SYNTAX:
#    $result = &MarkersChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub MarkersChunk {
   my($WrkData, $Id) = @_;
   my $wrkMarkers = $$WrkData{$Id}{'result'};
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   &DisplayDebug(2,"MarkersChunk Id: $Id   data: @wrkBytes");

   my @data = splice(@wrkBytes, 0, 4);
   my $count = hex($data[3])*16777216 + hex($data[2])*65536 +
               hex($data[1])*256 + hex($data[0]);
   for (my $x = 0; $x < $count; $x++) {
      my $cnt = scalar keys(%$wrkMarkers) +1;          # Get next hash index.
      my $smpte = hex( splice(@wrkBytes, 0, 1) );
      @data = splice(@wrkBytes, 0, 1);
      @data = splice(@wrkBytes, 0, 3);  
      my $time = hex($data[2])*65536 + hex($data[1])*256 + hex($data[0]);
      @data = splice(@wrkBytes, 0, 5);
      my $strLen = hex( splice(@wrkBytes, 0, 1) );    
      my $string = pack("(H2)*", splice(@wrkBytes, 0, $strLen));
      $$wrkMarkers{$cnt} = join(':', $time, $smpte, $string);  
   }
   return 0;
}

# =============================================================================
# FUNCTION:  VarsChunk
#
# DESCRIPTION:
#    Called to process the VARS_CHUNK and SOFTVER_CHUNK. These values are used 
#    primatily by the Cakewalk program. 
#
#    VARS_CHUNK (03)
#       now: int32            <- four bytes little endian
#       from: int32           <- four bytes little endian
#       thru: int32           <- four bytes little endian
#       keysig: int8          <- one byte
#       clock: int8           <- one byte
#       auto_save: int8       <- one byte
#       play_delay: int8      <- one byte
#       gap: int8             <- one byte
#       zero_ctrls: bool      <- one byte
#       send_ssp: bool        <- one byte
#       send_cont: bool       <- one byte
#       patch_srch: bool      <- one byte
#       auto_stop: bool       <- one byte
#       stop_time: int32      <- four bytes little endian
#       auto_rewind: bool     <- one byte
#       rewind_time: int32    <- four bytes little endian
#       metro_play: bool      <- one byte
#       metro_record: bool    <- one byte
#       metro_accent: bool    <- one byte
#       count_in: int8        <- one byte
#       gap: int8             <- two bytes
#       thru_on: bool         <- one byte
#       gap: int8             <- nineteen bytes
#       auto_restart: bool    <- one byte
#       cur_tempo_ofs: int8   <- one byte
#       tempo_ofs1: int8      <- one byte
#       tempo_ofs2: int8      <- one byte
#       tempo_ofs3: int8      <- one byte
#       gap: int8             <- two bytes
#       punch_enable: bool    <- one byte
#       punch_in_time: int32  <- four bytes little endian
#       punch_out_time: int32 <- four bytes little endian
#       end_all_time: int32   <- four bytes little endian
#
#    VARS_CHUNK (4E)
#       strLen: int8          <- one byte
#       string: text          <- strLen bytes
#
# CALLING SYNTAX:
#    $result = &VarsChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub VarsChunk {
   my($WrkData, $Id) = @_;
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   
   if ($Id eq '4E') {
      my $wrkGlobal = $$WrkData{$Id}{'result'};
      &DisplayDebug(2,"SoftverChunk data: @wrkBytes");
      my $strLen = hex( splice(@wrkBytes, 0, 1) );    
      $$wrkGlobal{'softver'} = pack("(H2)*", splice(@wrkBytes, 0, $strLen));
      return 0;
   }
   
   &DisplayDebug(2,"VarsChunk Id: $Id   data: @wrkBytes");
   my $cakeVars = $$WrkData{$Id}{'result'};
   my @data = splice(@wrkBytes, 0, 4);
   $$cakeVars{'now'} = hex($data[3])*16777216 + hex($data[2])*65536 +
                       hex($data[1])*256 + hex($data[0]);
   @data = splice(@wrkBytes, 0, 4);
   $$cakeVars{'from'} = hex($data[3])*16777216 + hex($data[2])*65536 +
                        hex($data[1])*256 + hex($data[0]);
   @data = splice(@wrkBytes, 0, 4);
   $$cakeVars{'thru'} = hex($data[3])*16777216 + hex($data[2])*65536 +
                        hex($data[1])*256 + hex($data[0]);
   $$cakeVars{'keysig'} = hex( splice(@wrkBytes, 0, 1) );
   $$cakeVars{'clock'} = hex( splice(@wrkBytes, 0, 1) );
   $$cakeVars{'auto_save'} = hex( splice(@wrkBytes, 0, 1) );
   $$cakeVars{'play_delay'} = hex( splice(@wrkBytes, 0, 1) );
   $$cakeVars{'zero_ctrls'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   $$cakeVars{'send_ssp'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   $$cakeVars{'send_cont'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   $$cakeVars{'patch_srch'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   $$cakeVars{'auto_stop'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   @data = splice(@wrkBytes, 0, 4);
   $$cakeVars{'stop_time'} = hex($data[3])*16777216 + hex($data[2])*65536 +
                             hex($data[1])*256 + hex($data[0]);
   $$cakeVars{'auto_rewind'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   @data = splice(@wrkBytes, 0, 4);
   $$cakeVars{'rewind_time'} = hex($data[3])*16777216 + hex($data[2])*65536 +
                               hex($data[1])*256 + hex($data[0]);
   $$cakeVars{'metro_play'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   $$cakeVars{'metro_record'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   $$cakeVars{'metro_accent'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   $$cakeVars{'count_in'} = hex( splice(@wrkBytes, 0, 1) );
   @data = splice(@wrkBytes, 0, 2);
   $$cakeVars{'thru_on'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   @data = splice(@wrkBytes, 0, 19);
   $$cakeVars{'auto_restart'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   $$cakeVars{'cur_tempo_ofs'} = hex( splice(@wrkBytes, 0, 1) );
   $$cakeVars{'tempo_ofs1'} = hex( splice(@wrkBytes, 0, 1) );
   $$cakeVars{'tempo_ofs2'} = hex( splice(@wrkBytes, 0, 1) );
   $$cakeVars{'tempo_ofs3'} = hex( splice(@wrkBytes, 0, 1) );
   @data = splice(@wrkBytes, 0, 2);
   $$cakeVars{'punch_enable'} = hex( splice(@wrkBytes, 0, 1) ) & 0x01 ? 'true' : 'false';
   @data = splice(@wrkBytes, 0, 4);
   $$cakeVars{'punch_in_time'} = hex($data[3])*16777216 + hex($data[2])*65536 +
                                 hex($data[1])*256 + hex($data[0]);
   @data = splice(@wrkBytes, 0, 4);
   $$cakeVars{'punch_out_time'} = hex($data[3])*16777216 + hex($data[2])*65536 +
                                  hex($data[1])*256 + hex($data[0]);
   @data = splice(@wrkBytes, 0, 4);
   $$cakeVars{'end_all_time'} = hex($data[3])*16777216 + hex($data[2])*65536 +
                                hex($data[1])*256 + hex($data[0]);
   return 0;
}

# =============================================================================
# FUNCTION:  StringTableChunk
#
# DESCRIPTION:
#    Called to process the STRTAB_CHUNK chunk. The retrieved data is stored in 
#    %WrkStringTable hash. Each string table entry has an index which is used
#    as the hash key. The hash value is the associated text string.
#
#    STRTAB_CHUNK (16)
#       row_count: int16      <- two bytes little endian
#          strLen: int8       <- one byte
#          string: text       <- strLen bytes
#          index: int8        <- one byte
#          ...
#
# CALLING SYNTAX:
#    $result = &StringTableChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub StringTableChunk {
   my($WrkData, $Id) = @_;
   my $wrkStrTbl = $$WrkData{$Id}{'result'};
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };

   &DisplayDebug(2,"StringTableChunk Id: $Id   data: @wrkBytes");
   my @data = splice(@wrkBytes, 0, 2);
   my $count = hex($data[1])*256 + hex($data[0]);
   for (my $x = 0; $x < $count; $x++) {
      my $strLen = hex( splice(@wrkBytes, 0, 1) );    
      my $string = pack("(H2)*", splice(@wrkBytes, 0, $strLen));
      my $index = hex( splice(@wrkBytes, 0, 1) );  
      $$wrkStrTbl{$index} = $string;  
      &DisplayDebug(2,"StringTableChunk: $index: $$wrkStrTbl{$index}");
   }
   return 0;
}

# =============================================================================
# FUNCTION:  VariableChunk
#
# DESCRIPTION:
#    Called to process the VARIABLE_CHUNK and COMMENTS_CHUNK chunks. The retrieved
#    data is stored in %WrkVariables. Each processed chunk produces a new hash key.
#
#    COMMENTS_CHUNK (08)
#       count: int16          <- two bytes little endian
#       string: text          <- length bytes
#
#    VARIABLE_CHUNK (1A)
#       string: text        <- bytes of string
#
# CALLING SYNTAX:
#    $result = &VariableChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub VariableChunk {
   my($WrkData, $Id) = @_;
   my $wrkVariables = $$WrkData{$Id}{'result'};
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   my $text;

   &DisplayDebug(2,"VariableChunk: Id: 0x$Id  data: @wrkBytes");
   my $cnt = scalar keys(%$wrkVariables) +1;          # Get next hash index.
   if ($Id eq '08') {
      my @data = splice(@wrkBytes, 0, 2);
      my $byteCnt = hex($data[1])*256 + hex($data[0]);
      $$wrkVariables{$cnt} = pack("(H2)*", splice(@wrkBytes, 0, $byteCnt));
   }
   elsif ($Id eq '1A') {
      $$wrkVariables{$cnt} = pack("(H2)*", @wrkBytes);
   }
   return 0;
}

# =============================================================================
# FUNCTION:  ThruChunk
#
# DESCRIPTION:
#    Called to process the THRU_CHUNK. The retrieved value is stored in
#    %WrkGlobal{'thru'}.
#
#    THRU_CHUNK (10)
#       gap: int8          <- two bytes
#       port: int8         <- one byte  0->127
#       channel: int8      <- one byte  -1, 0->15
#       keyPlus: int8      <- one byte  0->127
#       velPlus: int8      <- one byte  0->127
#       local_port: int8   <- one byte
#       mode: int8         <- one byte
#
# CALLING SYNTAX:
#    $result = &ThruChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub ThruChunk {
   my($WrkData, $Id) = @_;
   my $wrkGlobal = $$WrkData{$Id}{'result'};
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   &DisplayDebug(2,"ThruChunk Id: $Id   data: @wrkBytes");

   my @data = splice(@wrkBytes, 0, 2);
   my $port = hex( splice(@wrkBytes, 0, 1) );
   my $channel = hex( splice(@wrkBytes, 0, 1) );
   my $keyPlus = hex( splice(@wrkBytes, 0, 1) );
   my $velPlus = hex( splice(@wrkBytes, 0, 1) );
   my $local_port = hex( splice(@wrkBytes, 0, 1) );
   my $mode = hex( splice(@wrkBytes, 0, 1) );
   $$wrkGlobal{'thru'} = join(':', $mode, $port, $channel, $keyPlus, $velPlus,
                                   $local_port);
   return 0;
}

# =============================================================================
# FUNCTION:  TempoChunk
#
# DESCRIPTION:
#    Called to process the TEMPO_CHUNK and NTEMPO_CHUNK chunks. The retrieved 
#    values are stored in %WrkGlobal{'tempo'}. The bpm tempo is expressed as a
#    decimal float xxx.yy value. E.g. 16000 = 160.00 bpm, 12325 = 123.25 bpm.
#
#    The TEMPO_CHUNK record tempo value does not include the fractional bpm 
#    component. The value is multiplied by 100 to normalize for downstream 
#    processing.
#
#    TEMPO_CHUNK (04) or NTEMPO_CHUNK (0F)
#       count: int16           <- two bytes little endian
#          tempoTime: int32    <- four bytes
#          reserved: int8      <- four bytes
#          tempo: int16        <- two bytes little endian
#          reserved: int8      <- eight bytes
#
# CALLING SYNTAX:
#    $result = &TempoChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub TempoChunk {
   my ($WrkData, $Id) = @_;

   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   my $tempoData = $$WrkData{$Id}{'result'};
   &DisplayDebug(2,"TempoChunk Id: $Id   data: @wrkBytes");
   
   my @data = splice(@wrkBytes, 0, 2);
   my $count = hex($data[1])*256 + hex($data[0]);
   
   for (my $x = 0; $x < $count; $x++) {
      my @data = splice(@wrkBytes, 0, 4);
      $tempoTime = hex($data[3])*16777216 + hex($data[2])*65536 +
                   hex($data[1])*256 + hex($data[0]);
      @data = splice(@wrkBytes, 0, 4);
      @data = splice(@wrkBytes, 0, 2);
      my $tempo = hex($data[1])*256 + hex($data[0]);
      $tempo = $tempo * 100 if ($Id eq '04');     # scale TEMPO_CHUNK value.
      @data = splice(@wrkBytes, 0, 8);
      &DisplayDebug(2,"TempoChunk entry: $tempoTime - " . 
                      sprintf("%.2f bpm", ($tempo/100)));
      $tempoData->{$tempoTime} = $tempo;
   }
   return 0;
}

# =============================================================================
# FUNCTION:  MeterChunk
#
# DESCRIPTION:
#    Called to process the METER_CHUNK and METERKEY_CHUNK chunks. Each entry 
#    contains the effective measure:numerator:denominator. There may be more
#    than one per WRK file. The retrieved values are stored in the arrays.
#
#    @{$$WrkGlobal{'meter'}}  'measure:sig_numerator:sig_demonimator'
#    @{$$WrkGlobal{'meterKey'}} 'measure:sig_numerator:sig_demonimator:keySig'  
#
#    METER_CHUNK (05)
#       count: int16           <- two bytes little endian
#          reserved: int8      <- four bytes
#          measure: int16      <- two bytes little endian
#          numerator: int8     <- one byte
#          denominator: int8   <- one byte,  2.0 ** byte
#          reserved: int8      <- four bytes
#
#    METERKEY_CHUNK (17)
#       count: int16           <- two bytes little endian
#          measure: int16      <- two bytes little endian
#          numerator: int8     <- one byte
#          denominator: int8   <- one byte,  2.0 ** byte
#          key_sig: int8       <- one byte
#
#    key_sig is an integer value between -7 and 7 inclusive. 
#       -7: 'Cb', -6: 'Gb', -5: 'Db', -4: 'Ab', 
#       -3: 'Eb', -2: 'Bb', -1: 'F',   0: 'C',
#        1: 'G',   2: 'D',   3: 'A',   4: 'E',
#        5: 'B',   6: 'F#',  7: 'C#');
#
# CALLING SYNTAX:
#    $result = &MeterChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub MeterChunk {
   my ($WrkData, $Id) = @_;
   my ($measure, $numerator, $denominator, $key);
    
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   my $meterData = $$WrkData{$Id}{'result'};
   &DisplayDebug(2,"MeterChunk Id: $Id   data: @wrkBytes");
   
   my @data = splice(@wrkBytes, 0, 2);
   my $count = hex($data[1])*256 + hex($data[0]);

   for (my $x = 0; $x < $count; $x++) {
      if ($Id eq '05') {                     # METER_CHUNK?
         @data = splice(@wrkBytes, 0, 4);    # Discard gap bytes
         @data = splice(@wrkBytes, 0, 2);    # measure bytes
         $measure = hex($data[1])*256 + hex($data[0]);
         $numerator = hex( splice(@wrkBytes, 0, 1) );
         $denominator = 2 ** hex( splice(@wrkBytes, 0, 1) );
         $key = 0;
         @data = splice(@wrkBytes, 0, 4);    # Discard gap bytes
      }
      else {                                 # METERKEY_CHUNK
         @data = splice(@wrkBytes, 0, 2);    # measure bytes
         $measure = hex($data[1])*256 + hex($data[0]);
         $numerator = hex( splice(@wrkBytes, 0, 1) );
         $denominator = 2 ** hex( splice(@wrkBytes, 0, 1) );
         $key = hex( splice(@wrkBytes, 0, 1) );
      }
      $meterData->{$measure} = join(':', $numerator, $denominator, $key);
      &DisplayDebug(1,"MeterChunk: measure: $measure   numerator: $numerator   " .
                      "denominator: $denominator   key: $key");
   }
   return 0;
}

# =============================================================================
# FUNCTION:  SysexChunk
#
# DESCRIPTION:
#    Called to process the sysex chunks. The data for each chunk type is 
#    detailed below. The $Id input is used to differentiate the processing. 
#    Note that sysex_length is not currently used because the sysex_data is
#    the remaining bytes that follow the bank_name.
#   
#    The retrieved values are stored in referenced hash $WrkData{$Id}{'result'}. 
#    The structure of this hash is as follows.
#
#    bankNum => {'name' => text, 'auto' => bool, 'port' => int, 'sysex' => []}
#
#    SYSEX_CHUNK (06)
#       bank_number: int8   <- one byte
#       sysex_length: int16 <- two bytes little endian
#       autosend: bool      <- one byte
#       name_length: int8   <- one byte
#       bank_name: ascii    <- name bytes
#       sysex_data:         <- sysex length bytes
#
#    SYSEX2_CHUNK (14)
#       bank_number: int16  <- two bytes little endian
#       sysex_length: int32 <- four bytes little endian
#       midi_port: int8     <- one byte (upper nibble, shift to lower)
#       autosend: bool      <- midi port byte lower nibble
#       name_length: int8   <- one byte
#       bank_name: ascii    <- name bytes
#       sysex_data:         <- sysex length bytes
#
#    NSYSEX_CHUNK (2C)
#       bank_number: int16  <- two bytes little endian
#       sysex_length: int32 <- four bytes little endian
#       midi_port: int16    <- two bytes little endian
#       autosend: bool      <- one byte
#       name_length: int8   <- one byte
#       bank_name: ascii    <- name bytes
#       sysex_data:         <- sysex length bytes
#
# CALLING SYNTAX:
#    $result = &SysexChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub SysexChunk {
   my ($WrkData, $Id) = @_;
   my ($bankNum, $sysexLen);
   my $sysexBank = $$WrkData{$Id}{'result'};
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };

   &DisplayDebug(2,"SysexChunk Id: $Id   data: @wrkBytes");
   if ($Id eq '06') {           # One byte bank number and 16 bit length?
      $bankNum = hex( splice(@wrkBytes, 0, 1) );
      my @data = splice(@wrkBytes, 0, 2);
      $sysexLen = hex($data[1])*256 + hex($data[0]);
   }
   else {
      my @data = splice(@wrkBytes, 0, 2);
      $bankNum = hex($data[1])*256 + hex($data[0]);
      @data = splice(@wrkBytes, 0, 4);
      $sysexLen = hex($data[3])*16777216 + hex($data[2])*65536 +
                  hex($data[1])*256 + hex($data[0]);
   }

   if ($Id eq '06') {          # autosend and no midi_port?
      $sysexBank->{$bankNum}{'port'} = 0;
      $sysexBank->{$bankNum}{'auto'} = hex( splice(@wrkBytes, 0, 1) );
   }
   elsif ($Id eq '14') {       # combined autosend and midi_port?
      my $portAutosend = hex( splice(@wrkBytes, 0, 1) );
      $sysexBank->{$bankNum}{'port'} = $portAutosend >> 4;
      $sysexBank->{$bankNum}{'auto'} = $portAutosend & 0x0f;
   }
   else {
      my @data = splice(@wrkBytes, 0, 2);
      $sysexBank->{$bankNum}{'port'} = hex($data[1])*256 + hex($data[0]);
      $sysexBank->{$bankNum}{'auto'} = hex( splice(@wrkBytes, 0, 1) );
   }
   my $nameLen = hex( splice(@wrkBytes, 0, 1) );    
   $sysexBank->{$bankNum}{'name'} = pack("(H2)*", splice(@wrkBytes, 0, $nameLen));
   push (@{ $sysexBank->{$bankNum}{'sysex'} }, @wrkBytes);
   return 0;
}

# =============================================================================
# FUNCTION:  TrkMiscChunks
#
# DESCRIPTION:
#    Called to process the TRKNAME_CHUNK, TRKBANK_CHUNK, NTRKOFS_CHUNK, 
#    TRKVOL_CHUNK, TRKPATCH_CHUNK, TRKREPS_CHUNK, TRKOFFS_CHUNK chunks. Some
#    of these chunks specify data parts of TRACK_CHUNK and NTRACK_CHUNK. The
#    $Id input is used to differentiate the processing. The retrieved data is
#    used to establish track prefix global values. These values are stored
#    in the referenced hash.
#
#    trackNum => {'name' => text, 'channel' => int, 'pitch' => int, 
#                 'velocity' => int, 'port' => int, 'selected' => bool, 
#                 'muted' => bool, 'loop' => bool, 'bank' => int,
#                 'patch' => int, 'volume' => int, 'pan' => int,
#                 'offset' => int, 'repeat' => int, 'events' => []}
#
#    TRKOFFS_CHUNK (09)
#       track_number: int16 <- two bytes little endian
#       track_offset: int16 <- two bytes little endian
#
#    TRKREPS_CHUNK (0C)
#       track_number: int16 <- two bytes little endian
#       track_repeat: int16 <- two bytes little endian
#
#    TRKPATCH_CHUNK (0E)
#       track_number: int16 <- two bytes little endian
#       patch: int8         <- one byte
#
#    TRKNAME_CHUNK (18)
#       track_number: int16 <- two bytes little endian
#       name_length: int8   <- one byte
#       track_name: ascii   <- name bytes
#
#    TRKVOL_CHUNK (13)
#       track_number: int16 <- two bytes little endian
#       track_volume: int16 <- two bytes little endian
#
#    NTRKOFS_CHUNK (1B)
#       track_number: int16 <- two bytes little endian
#       track_offset: int32 <- four bytes little endian
#
#    TRKBANK_CHUNK (1E)
#       track_number: int16 <- two bytes little endian
#       track_bank: int16   <- two bytes little endian
#
# CALLING SYNTAX:
#    $result = &TrkMiscChunks($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub TrkMiscChunks {
   my ($WrkData, $Id) = @_;
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   my $trackData = $$WrkData{$Id}{'result'};
   
   &DisplayDebug(2,"TrkMiscChunks Id: $Id   data: @wrkBytes");
   my @data = splice(@wrkBytes, 0, 2);
   my $trackNum = (hex($data[1])*256 + hex($data[0])) +1;  # Make tracks start at 1.

   if ($Id eq '09') {             # TRKOFFS_CHUNK
      @data = splice(@wrkBytes, 0, 2);
      $trackData->{$trackNum}{'offset'} = hex($data[1])*256 + hex($data[0]);
   }
   elsif ($Id eq '0C') {          # TRKREPS_CHUNK
      @data = splice(@wrkBytes, 0, 2);
      $trackData->{$trackNum}{'repeat'} = hex($data[1])*256 + hex($data[0]);
   }
   elsif ($Id eq '0E') {          # TRKPATCH_CHUNK
      $trackData->{$trackNum}{'patch'} = hex( splice(@wrkBytes, 0, 1) );
   }
   elsif ($Id eq '18') {          # TRKNAME_CHUNK
      my $nameLen = hex( splice(@wrkBytes, 0, 1) );    
      $trackData->{$trackNum}{'name'} = pack("(H2)*", splice(@wrkBytes, 0, $nameLen));
   }
   elsif ($Id eq '13') {          # TRKVOL_CHUNK
      @data = splice(@wrkBytes, 0, 2);
      $trackData->{$trackNum}{'volume'} = hex($data[1])*256 + hex($data[0]);
   }
   elsif ($Id eq '1B') {          # NTRKOFS_CHUNK
      @data = splice(@wrkBytes, 0, 4);
      $trackData->{$trackNum}{'offset'} = hex($data[3])*16777216 + 
         hex($data[2])*65536 + hex($data[1])*256 + hex($data[0]);
   }
   elsif ($Id eq '1E') {          # TRKBANK_CHUNK
      @data = splice(@wrkBytes, 0, 2);
      $trackData->{$trackNum}{'bank'} = hex($data[1])*256 + hex($data[0]);
   }
   return 0;
}

# =============================================================================
# FUNCTION:  TrackChunk
#
# DESCRIPTION:
#    Called to process the TRACK_CHUNK, and NTRACK_CHUNK chunks. The $Id 
#    input is used to differentiate the processing. The retrieved data is used
#    to establish track prefix global values. These values are stored in the 
#    referenced hash.
#
#    trackNum => {'name' => text, 'channel' => int, 'pitch' => int, 
#                 'velocity' => int, 'port' => int, 'selected' => bool, 
#                 'muted' => bool, 'loop' => bool, 'bank' => int,
#                 'patch' => int, 'volume' => int, 'pan' => int,
#                 'offset' => int, 'repeat' => int, 'events' => []}
#
#    TRACK_CHUNK (01)
#       track_number: int16 <- two bytes little endian
#       name_length1: int8  <- one byte
#       track_name1: ascii  <- name bytes  if non-zero length1
#       name_length2: int8  <- one byte
#       track_name2: ascii  <- name bytes  if non-zero length2
#       midi_channel: int8  <- one byte
#       pitch: int8         <- one byte
#       velocity: int8      <- one byte
#       midi_port: int8     <- one byte
#       flags: bool         <- one byte; selected(bit0), muted(bit1), loop(bit2)
#
#    NTRACK_CHUNK (24)
#       track_number: int16 <- two bytes little endian
#       name_length: int8   <- one byte
#       track_name: ascii   <- name bytes  if non-zero length
#       track_bank: int16   <- two bytes little endian
#       track_patch: int16  <- two bytes little endian
#       track_volume: int16 <- two bytes little endian
#       track_pan: int16    <- two bytes little endian
#       pitch: int8         <- one byte
#       velocity: int8      <- one byte
#       reserved: int8      <- seven bytes
#       midi_port: int8     <- one byte
#       midi_channel: int8  <- one byte
#       flags: bool         <- one byte; selected(bit0), muted(bit1), loop(bit2)
#
# CALLING SYNTAX:
#    $result = &TrackChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub TrackChunk {
   my ($WrkData, $Id) = @_;
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   my $trackData = $$WrkData{$Id}{'result'};
 
   &DisplayDebug(2,"TrackChunk Id: $Id   data: @wrkBytes");
   my @data = splice(@wrkBytes, 0, 2);
   my $trackNum = (hex($data[1])*256 + hex($data[0])) +1;  # Make tracks start at 1.
   my $nameLen = hex( splice(@wrkBytes, 0, 1) );    
   $trackData->{$trackNum}{'name'} = pack("(H2)*", splice(@wrkBytes, 0, $nameLen));
      
   if ($Id eq '01') {          # TRACK_CHUNK ?
      $nameLen = hex( splice(@wrkBytes, 0, 1) );    # 2nd part of name if non-zero
      $trackData->{$trackNum}{'name'} = join('', $trackData->{$trackNum}{'name'},
         pack("(H2)*", splice(@wrkBytes, 0, $nameLen)));
      $trackData->{$trackNum}{'channel'} = hex( splice(@wrkBytes, 0, 1) );
      $trackData->{$trackNum}{'pitch'} = hex( splice(@wrkBytes, 0, 1) );
      $trackData->{$trackNum}{'velocity'} = hex( splice(@wrkBytes, 0, 1) );
      $trackData->{$trackNum}{'port'} = hex( splice(@wrkBytes, 0, 1) );
   }
   else {
      my @data = splice(@wrkBytes, 0, 2);
      $trackData->{$trackNum}{'bank'} = hex($data[1])*256 + hex($data[0]);
      @data = splice(@wrkBytes, 0, 2);
      $trackData->{$trackNum}{'patch'} = hex($data[1])*256 + hex($data[0]);
      @data = splice(@wrkBytes, 0, 2);
      $trackData->{$trackNum}{'volume'} = hex($data[1])*256 + hex($data[0]);
      @data = splice(@wrkBytes, 0, 2);
      $trackData->{$trackNum}{'pan'} = hex($data[1])*256 + hex($data[0]);
      $trackData->{$trackNum}{'pitch'} = hex( splice(@wrkBytes, 0, 1) );
      $trackData->{$trackNum}{'velocity'} = hex( splice(@wrkBytes, 0, 1) );
      @data = splice(@wrkBytes, 0, 7);    # Reserved bytes.
      $trackData->{$trackNum}{'port'} = hex( splice(@wrkBytes, 0, 1) );
      $trackData->{$trackNum}{'channel'} = hex( splice(@wrkBytes, 0, 1) );
   }
   my $flags = hex( splice(@wrkBytes, 0, 1) );
   $trackData->{$trackNum}{'selected'} = $flags & 0x01 ? 'true' : 'false';
   $trackData->{$trackNum}{'muted'} = (($flags >> 1) & 0x01) ? 'true' : 'false';
   $trackData->{$trackNum}{'loop'} = (($flags >> 2) & 0x01) ? 'true' : 'false';

   return 0;
}

# =============================================================================
# FUNCTION:  StreamChunk
#
# DESCRIPTION:
#    Called to process the WRK file chunks listed below. The data retrieved are
#    the events for the track. This data is stored in the referenced location 
#    %TrackData{$trackNum}{'events'}. This data is normalized for each chunk
#    type as follows and appended to any existing data for the track. This data
#    is processed by &ProcessEvents during MIDI file creation.
#
#    %TrackData{$trackNum}{'eventCnt'} += events_count
#       events_count: int16 <- two bytes little endian
#
#    push %TrackData{$trackNum}{'events'}
#       time: int24         <- three byte little endian
#       status: int8        <- one byte   type = 0xf0   channel = 0x0f
#       data1: int8         <- one byte   e.g. note value
#       data2: int8         <- one byte   e.g. note velocity
#       duration: int16     <- two bytes little endian
#    
#    STREAM_CHUNK (02)
#       track_number: int16 <- two bytes little endian
#       events_count: int16 <- two bytes little endian
#       time: int24         <- three byte little endian
#       status: int8        <- one byte   type = 0xf0   channel = 0x0f
#       data1: int8         <- one byte   e.g. note value
#       data2: int8         <- one byte   e.g. note velocity
#       duration: int16     <- two bytes little endian
#       ...
#
#    LYRICS_CHUNK (12)
#       track_number: int16 <- two bytes little endian
#       events_count: int32 <- four bytes little endian
#       time: int24         <- three byte little endian
#       status: int8        <- one byte   type = 0xf0   channel = 0x0f
#       data1: int8         <- one byte   e.g. note value
#       data2: int8         <- one byte   e.g. note velocity
#       duration: int16     <- two bytes little endian
#       ...
#
#    NSTREAM_CHUNK (2D)
#       track_number: int16 <- two bytes little endian
#       string_len: int8    <- one byte
#       string: text        <- bytes if string_len not zero
#       events_count: int32 <- four bytes little endian
#       time: int24         <- three byte little endian
#       status: int8        <- one byte   type = 0xf0   channel = 0x0f
#       data1: int8         <- one byte   e.g. note value
#       data2: int8         <- one byte   e.g. note velocity
#       duration: int16     <- two bytes little endian
#       ...
#    
#    SGMNT_CHUNK (31)
#       track_number: int16 <- two bytes little endian
#       offset: int32       <- four bytes little endian
#       reserved: int8      <- eight bytes
#       string_len: int8    <- one byte
#       string: text        <- bytes if string_len not zero
#       reserved: int8      <- twenty bytes
#       string_len: int8    <- one byte
#       string: text        <- bytes if string_len not zero
#       events_count: int32 <- four bytes little endian
#       time: int24         <- three byte little endian
#       status: int8        <- one byte   type = 0xf0   channel = 0x0f
#       data1: int8         <- one byte   e.g. note value
#       data2: int8         <- one byte   e.g. note velocity
#       duration: int16     <- two bytes little endian
#       ...
#
# CALLING SYNTAX:
#    $result = &StreamChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub StreamChunk {
   my ($WrkData, $Id) = @_;
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   my $trackData = $$WrkData{$Id}{'result'};
   
   &DisplayDebug(2,"StreamChunk Id: $Id   data: @wrkBytes");
   my @data = splice(@wrkBytes, 0, 2);
   my $trackNum = (hex($data[1])*256 + hex($data[0])) +1;  # Make tracks start at 1.

   if ($Id eq '31') {                  # if SGMNT_CHUNK
      @data = splice(@wrkBytes, 0, 4);
      my $offset = hex($data[3])*16777216 + hex($data[2])*65536 + 
                   hex($data[1])*256 + hex($data[0]);
      @data = splice(@wrkBytes, 0, 8);
      my $stringLen = hex( splice(@wrkBytes, 0, 1) );    
      @data = splice(@wrkBytes, 0, $stringLen);
      @data = splice(@wrkBytes, 0, 20);
   }
   
   if ($Id eq '2D' or $Id eq '31') {   # if NSTREAM_CHUNK or SGMNT_CHUNK
      my $stringLen = hex( splice(@wrkBytes, 0, 1) );    
      @data = splice(@wrkBytes, 0, $stringLen);
   }

   unless (exists($trackData->{$trackNum}{'eventCnt'})) {
      $trackData->{$trackNum}{'eventCnt'} = 0;  # Initialize to 0 if not exists.
   }
   if ($Id eq '02') {
      @data = splice(@wrkBytes, 0, 2);
      my $eventCnt = hex($data[1])*256 + hex($data[0]);
      $trackData->{$trackNum}{'eventCnt'} += $eventCnt;          
   } 
   else {
      @data = splice(@wrkBytes, 0, 4);
      my $eventCnt = hex($data[3])*16777216 + hex($data[2])*65536 + 
                     hex($data[1])*256 + hex($data[0]);
      $trackData->{$trackNum}{'eventCnt'} += $eventCnt;          
   }
   push (@{ $trackData->{$trackNum}{'events'} }, @wrkBytes);
   
   # Mark track as lyrics if Id = '12'.
   $trackData->{$trackNum}{'lyric'} = 1 if ($Id eq '12');

   return 0;
}

# =============================================================================
# FUNCTION:  TimeFmtChunk
#
# DESCRIPTION:
#    Called to process the TIMEFMT_CHUNK. The retrieved value is stored in
#    %WrkGlobal{'smpte'}. Format is one of the standard SMPTE MIDI timecode 
#    formats: 24, 25, 29, or 30. The offset value corresponds to the SMPTE
#    offset; used in the SMPTE Offset meta-event (FF 54 05 hr mn se fr ff).
#
#    TIMEFMT_CHUNK (0B)
#       format: int16    <- two bytes little endian
#       offset: int32    <- four bytes little endian
#
# CALLING SYNTAX:
#    $result = &TimeFmtChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub TimeFmtChunk {
   my ($WrkData, $Id) = @_;
   my $wrkGlobal = $$WrkData{$Id}{'result'};
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   &DisplayDebug(2,"TimeFmtChunk Id: $Id   @wrkBytes");
   
   my @data = splice(@wrkBytes, 0, 2);
   my $format = hex($data[1])*256 + hex($data[0]);
   @data = splice(@wrkBytes, 0, 4);
   my $offset = hex($data[3])*16777216 + hex($data[2])*65536 + 
                hex($data[1])*256 + hex($data[0]);
   $$wrkGlobal{'smpte'} = join(':', $format, $offset);            
   &DisplayDebug(2,"TimeFmtChunk: format: $format   offset: $offset");

   return 0;
}

# =============================================================================
# FUNCTION:  TimebaseChunk
#
# DESCRIPTION:
#    Called to process the TIMEBASE_CHUNK. The retrieved value overwrites the 
#    default value (120) in %WrkGlobal{'timebase'}. The value is the number of
#    ticks per quarter note.
#
# CALLING SYNTAX:
#    $result = &TimebaseChunk($WrkData, $Id);
#
# ARGUMENTS:
#    $WrkData        Pointer to WrkFile data hash.
#    $Id             ChunkId identifer. %WrkData primary key.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub TimebaseChunk {
   my ($WrkData, $Id) = @_;
   my $wrkGlobal = $$WrkData{$Id}{'result'};
   my @wrkBytes = @{ $$WrkData{'00'}{'chunkbytes'} };
   &DisplayDebug(2,"TimebaseChunk Id: $Id   @wrkBytes");
   
   my @data = splice(@wrkBytes, 0, 2);
   $$wrkGlobal{'timebase'} = hex($data[1])*256 + hex($data[0]);
   &DisplayDebug(2,"TimebaseChunk: $$wrkGlobal{'timebase'} ticks per quarter note.");
   
   return 0;
}

# =============================================================================
# FUNCTION:  ShowMidiDevices
#
# DESCRIPTION:
#    Called to show the available MIDI devices. Referenced hash expected format.
#    $port is a numeric value; 0, 1, etc.
#
#    $$Devices{'raw'}->{$port}{'dir'}
#    $$Devices{'raw'}->{$port}{'dev'}
#    $$Devices{'raw'}->{$port}{'name'}
#    $$Devices{'seq'}->{$port}{'dev'}
#    $$Devices{'seq'}->{$port}{'name'}
#
# CALLING SYNTAX:
#    $result = &ShowMidiDevices($Devices);
#
# ARGUMENTS:
#    $Devices          Pointer to %Devices hash.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub ShowMidiDevices {
   my($Devices) = @_;

   if (scalar keys(%$Devices) == 0) {
      &ColorMessage("No MIDI devices found.", "BRIGHT_YELLOW", '');
   }
   else {
      &ColorMessage("\n" . '-' x 55, "WHITE", '');
      &ColorMessage("Available sysex rawmidi devices:", "WHITE", '');
      &ColorMessage("\n  Port  Device       Name", "WHITE", '');
      my $rawDevRef = $$Devices{'raw'};
      foreach my $port (sort {$a <=> $b} keys %{$rawDevRef}) {
         my $rawDev = $rawDevRef->{$port}{'dev'};
         my $name = $rawDevRef->{$port}{'name'};
         $dir = ' ' x 2 . $dir . ' ' x (6 - length($dir));
         $rawDev = ' ' x 4 . $rawDev . ' ' x (13 - length($rawDev));
         &ColorMessage("   $port$rawDev$name", "WHITE", '');
      }
      &ColorMessage("\nAvailable sequencer midi devices:", "WHITE", '');
      &ColorMessage("\n  Port  Device       Name", "WHITE", '');
      my $seqDevRef = $$Devices{'seq'};
      foreach my $port (sort {$a <=> $b} keys %{$seqDevRef}) {
         my $dev = $seqDevRef->{$port}{'dev'};
         my $name = $seqDevRef->{$port}{'name'};
         $dev = ' ' x 4 . $dev . ' ' x (13 - length($dev));
         &ColorMessage("   $port$dev$name", "WHITE", '');
      }
      &ColorMessage("" . '-' x 55, "WHITE", '');
   }
   return 0;
}

# =============================================================================
# FUNCTION:  SendSyx
#
# DESCRIPTION:
#    This routine is called to send the specified sysex to the specified MIDI 
#    port. The sysex is sent using multiple transmissions if it contains F0..F7
#    pairs to help minimize MIDI device overload with older equipment.
#
# CALLING SYNTAX:
#    $result = &SendSyx($Devices, $Port, $Bank, $Name, $Sysex, $XmitDelay,
#                       $Syxmidi);
#
# ARGUMENTS:
#    $Devices          Pointer to %Devices hash.
#    $Port             Devices hash index for port to use.
#    $Bank             Sysex bank index.
#    $Name             Sysex name string.
#    $Sysex            Pointer to array of sysex bytes; F0 ... F7
#    $XmitDelay        Transmission throttle values.
#    $Syxmidi          Syxmidi executable.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub SendSyx {
   my($Devices, $Port, $Bank, $Name, $Sysex, $XmitDelay, $Syxmidi) = @_;
   my ($msDelay, $size, $eoxDelay) = split(':', $XmitDelay);
   &DisplayDebug(1,"sendSyx: Port: $Port   Bank: $Bank   Name: $Name   " .
                   "XmitDelay: $XmitDelay   Sysex length: " . scalar @$Sysex);

   # Use syxmidi to send this sysex using the -S option. The -t option sets the
   # delay interval (microseconds) between the sysex bytes.
   my $rawDevRef = $$Devices{'raw'};
   my $syxmidiCmd = "$Syxmidi -q -d $rawDevRef->{$Port}{'dev'}";
   $syxmidiCmd = join(' ', $syxmidiCmd, "-t $XmitDelay") if ($XmitDelay > 0);
   $syxmidiCmd = join(' ', $syxmidiCmd, qq(-S "@$Sysex"));
   &DisplayDebug(1,"sendSyx: sysmidiCmd: $syxmidiCmd");
   my $result = `$syxmidiCmd`;
   &ColorMessage("   Sysex bank $Bank ($Name) ", "WHITE", 'nocr'); 
   &ColorMessage("-->", "BRIGHT_CYAN", 'nocr'); 
   &ColorMessage(" $rawDevRef->{$Port}{'name'}", "WHITE", '');
   return ($? >> 8) & 0xFF;
}

# =============================================================================
# FUNCTION:  SxdAutoSend
#
# DESCRIPTION:
#    This routine is called when the user requests auto-send of the .sxd file
#    content. Sysex banks with Auto set to 'yes' are processed. The Port value
#    is used to direct the transmission to the MIDI device.
#
#    This routine is also called when the user specifies a device port. In this
#    case, the specified port overrides the SxdFileData specified port. 
#
# CALLING SYNTAX:
#    $result = &SxdAutoSend($Devices, $SxdFileData, $XmitDelay, $Syxmidi);
#
# ARGUMENTS:
#    $Devices          Pointer to %Devices hash.
#    $SxdFileData      Pointer to %SxdFileData data.
#    $XmitDelay        $cliOpts{z} specified throttle.
#    $Syxmidi          Syxmidi executable.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub SxdAutoSend {
   my ($Devices, $SxdFileData, $XmitDelay, $Syxmidi, $Port) = @_;
   &DisplayDebug(1,"SxdAutoSend ...");
   my $rawDevRef = $$Devices{'raw'};
   
   foreach my $bank (sort {$a <=> $b} keys(%$SxdFileData)) {
      if ($$SxdFileData{$bank}{'auto'} =~ m/^y/i) {
         my $bankName = $$SxdFileData{$bank}{'name'};
         my @sysex = @{ $$SxdFileData{$bank}{'sysx'} };
         if (exists($$SxdFileData{$bank}{'port'})) {
            my $port = $$SxdFileData{$bank}{'port'};      # SxdFle specified port.
            $port = $Port if ($Port >= 0);                # User specified port.
            unless (exists($rawDevRef->{$port})) {
               &ColorMessage("   Sysex bank $bank ($bankName) skipped. MIDI device " .
                             "port $port is unavailable.", "BRIGHT_YELLOW", ''); 
               next;
            }
            &DisplayDebug(1,"SxdAutoSend: portName: $portName   bankName: $bankName");
            return 1 if (&SendSyx($Devices, $port, $bank, $bankName, \@sysex, $XmitDelay,
                                  $Syxmidi));
         }
         else {
            &ColorMessage("   Sysex bank $bank ($bankName) skipped. No auto port.",
                          "BRIGHT_YELLOW", ''); 
         }
      }
   }
   return 0;
}

# =============================================================================
# FUNCTION: ProcessSxdFile
#
# DESCRIPTION:
#    This routine is called to process the specified sysex data file (.sxd).
#    Processing is automatic if the -p option was also specified on the CLI.
#    Otherwise, the user is interactively prompted for input. 
#
# CALLING SYNTAX:
#    $result = &ProcessSxdFile($SxdFileData, \%Devices, $PortOpt, $XmitDelay,
#                              $Syxmidi);
#
# ARGUMENTS:
#    $SxdFileData      Pointer to %SxdFileData data.
#    $Devices          Pointer to port/device hash.
#    $PortOpt          $cliOpts{p} value or ''.
#    $XmitDelay        $cliOpts{z} specified throttle.
#    $Syxmidi          Syxmidi executable.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None.
# =============================================================================
sub ProcessSxdFile {
   my ($SxdFileData, $Devices, $PortOpt, $XmitDelay, $Syxmidi) = @_;
   my ($port, $portName, @sysex);
   my $syxCnt = scalar keys (%$SxdFileData);
   &DisplayDebug(1,"ProcessSxdFile: $syxCnt entries   PortOpt: '$PortOpt'   " .
                   "XmitDelay: $XmitDelay ...");   
   # ----------
   # Auto port specified.
   if ($PortOpt =~ m/auto/i) {        # Perform -p specified auto send.
      return &SxdAutoSend($Devices, $SxdFileData, $XmitDelay, $Syxmidi, -1);
   }
   
   # ----------
   # Numeric port specified.
   elsif ($PortOpt =~ m/^(\d+)$/) {   # Verify -p port and send.
      $port = $1;
      my $rawDevRef = $$Devices{'raw'};
      unless (exists($rawDevRef->{$port})) {
         &ColorMessage("Unavailable -p specified port: $port", "BRIGHT_RED", '');
         return 1;
      }
      return &SxdAutoSend($Devices, $SxdFileData, $XmitDelay, $Syxmidi, $port);
   }
   
   # ----------
   # Interactive mode.
   else {
      my ($iActive, $portRun, $bankRun);
      my $rawDevRef = $$Devices{'raw'};
      $iActive = 1;
      my %deviceNames = ();
      while ($iActive == 1) {            # Port input loop.
         return 1 if(&ShowMidiDevices($Devices));
         $portRun = 1;
         while ($portRun == 1) {         # Port selection loop.
            &ColorMessage("Enter port number or q to quit. -> ", "WHITE", 'nocr');
            $port = <STDIN>;
            chomp($port);
            next if ($port eq '');
            if ($port =~ m/^q/i or $port =~ m/^e/i) {   # Accept quit or exit.
               ($iActive, $portRun) = (0,0);
               last;
            }
            unless (exists($rawDevRef->{$port})) {
               &ColorMessage("Unavailable port: $port", "BRIGHT_YELLOW", '');
               next;
            }
            $portName = $rawDevRef->{$port}{'name'};
               
            # Get the sysex bank to send.
            &ColorMessage("\n" . '-' x 55, "WHITE", '');
            &ColorMessage("Port $port  '$portName' selected.", "WHITE", '');
            &ColorMessage("Sysex throttle: $XmitDelay usec per sysex byte", "WHITE", '');
            &ColorMessage("  Enter bank(s): ", "WHITE", 'nocr');
            &ColorMessage("<n>", "BRIGHT_CYAN", 'nocr');
            &ColorMessage(" or ", "WHITE", 'nocr');
            &ColorMessage("<n>,<n>", "BRIGHT_CYAN", 'nocr');
            &ColorMessage(" or ", "WHITE", 'nocr');
            &ColorMessage("<n>-<n>", "BRIGHT_CYAN", '');
            &ColorMessage("  p<n>", "BRIGHT_CYAN", 'nocr');
            &ColorMessage(" - send 'Port' <n> banks to selected port.", "WHITE", '');
            &ColorMessage("  s", "BRIGHT_CYAN", 'nocr');
            &ColorMessage(" - send 'Auto' yes banks to .sxd 'Port' port.", "WHITE", '');
            &ColorMessage("  c", "BRIGHT_CYAN", 'nocr');
            &ColorMessage(" - to change port selection.", "WHITE", '');
            &ColorMessage("\nAvailable Sysex Banks:", "WHITE", '');
            &ColorMessage("\n  Bank\tAuto\tPort\tLength\tName", "WHITE", '');
            foreach my $key (sort {$a <=> $b} keys(%$SxdFileData)) {
               &ColorMessage("   $key\t$$SxdFileData{$key}{'auto'}\t " .
                  "$$SxdFileData{$key}{'port'}\t" . scalar @{ $$SxdFileData{$key}{'sysx'} } .
                  "\t$$SxdFileData{$key}{'name'}", "WHITE", '');
            }
            &ColorMessage('-' x 55, "WHITE", '');
            $bankRun = 1;
            while ($bankRun == 1) {      # Bank selection loop.
               &ColorMessage("Enter bank(s) or q to quit. -> ", "WHITE", 'nocr');
               $bankSel = <STDIN>;
               chomp($bankSel);
               next if ($bankSel eq '');
               if ($bankSel =~ m/^q/i or $bankSel =~ m/^e/i) { # Accept quit or exit.
                  ($iActive, $portRun, $bankRun) = (0,0,0);
                  last;
               }
               if ($bankSel =~ m/^c$/i) {   # For c, exit bankRun loop back to port loop.
                  ($portRun, $bankRun) = (0,0);
                  last;
               }
   
               # Parse user input.
               my @banks = ();
               if ($bankSel =~ m/^s$/i) {
                  foreach my $key (sort {$a <=> $b} keys(%$SxdFileData)) {
                     push (@banks, $key) if ($$SxdFileData{$key}{'auto'} =~ m/^y/);
                  }
                  if ($#banks > 0) {
                     if (&SxdAutoSend($Devices, $SxdFileData, $XmitDelay, $Syxmidi, -1)) {
                        ($iActive, $portRun, $bankRun) = (0,0,0);
                        last;
                     }
                  }
                  else {
                     &ColorMessage("No Auto yes banks found.", "BRIGHT_YELLOW", '');
                  }
                  next;
               }
               elsif ($bankSel =~ m/,/) {                 # <n>,<n>
                  @banks = split(',', $bankSel);
               }
               elsif($bankSel =~ m/^(\d+)-(\d+)$/) {      # <n>-<n>
                  push (@banks, $1..$2);
               }
               elsif ($bankSel =~ m/^p(\d+)$/i) {         # p<n>
                  my $portNum = $1;
                  foreach my $key (sort {$a <=> $b} keys(%$SxdFileData)) {
                     push (@banks, $key) if ($$SxdFileData{$key}{'port'} == $portNum);
                  }
               }
               elsif ($bankSel =~ m/^(\d+)$/) {           # <n>
                  $banks[0] = $1;
               }
               else {
                  &ColorMessage("Invalid input: $bankSel.", "BRIGHT_YELLOW", '');
                  next;
               }
               &ColorMessage("No banks selected.", "BRIGHT_YELLOW", '') if ($#banks < 0);
                  
               # Send the specified sysex bank(s).
               foreach my $bank (@banks) {
                  if (exists($$SxdFileData{$bank})) {
                     $bankName = $$SxdFileData{$bank}{'name'};
                     @sysex = @{ $$SxdFileData{$bank}{'sysx'} };
                     return 1 if (&SendSyx($Devices, $port, $bank, $bankName, 
                                           \@sysex, $XmitDelay, $Syxmidi));
                  }
                  else {
                     &ColorMessage("Unavailable bank: $bank", "BRIGHT_YELLOW", '');
                  }
               }
            }
         }
      }
   }
   return 0;
}

# =============================================================================
# FUNCTION: ShowExtractedData
#
# DESCRIPTION:
#    This routine is called to show the extracted WRK file data.
#
# CALLING SYNTAX:
#    $result = &ShowExtractedData($File, $WrkGlobal, $CakeVars, $WrkVariables, 
#       $WrkStringTable, $WrkMarkers, $MemRegionData, $SysexBank, $TrackData,
#       $TempoData, $MeterData);
#
# ARGUMENTS:
#    $File             File being processed.
#    $WrkGlobal        Pointer to %WrkGlobal hash.
#    $CakeVars         Pointer to %CakeVars hash.
#    $WrkVariables     Pointer to %WrkVariables hash.
#    $WrkStringTable   Pointer to %WrkStringTable hash.
#    $WrkMarkers       Pointer to %WrkMarkers hash.
#    $MemRegionData    Pointer to %MemRegionData hash.
#    $KeySig           Pointer to %KeySig hash.
#    $SysexBank        Pointer to %SysexBank hash.
#    $TrackData        Pointer to %TrackData hash.
#    $TempoData        Pointer to %TempoData hash.
#    $MeterData        Pointer to %MeterData hash.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub ShowExtractedData {
   my ($File, $WrkGlobal, $CakeVars, $WrkVariables, $WrkStringTable, $WrkMarkers, 
       $MemRegionData, $KeySig, $SysexBank, $TrackData, $TempoData, $MeterData) = @_;
   
   # WRK file version, timebase, meter, key signature, and tempo.
   &ColorMessage("\n" . '=' x 60, "WHITE", '');
   &ColorMessage("$File  cakewalk file version: $$WrkGlobal{'version'}", "WHITE",'');
   if (exists($$WrkGlobal{'softver'})) {
      &ColorMessage("Software version that saved this file: " .
                    "$$WrkGlobal{'softver'}", "WHITE", '');
   }
   &ColorMessage("Timebase: $$WrkGlobal{'timebase'} ticks per quarter note.",
                 "WHITE", '');
   if (exists($$WrkGlobal{'smpte'})) {
      &ColorMessage("SMPTE format: $$WrkGlobal{'smpte'}", "WHITE", '');
   }
   if (exists($$WrkGlobal{'thru'})) {
      my ($mode, $port, $channel, $keyPlus, $velPlus, $local_port) = split(':', 
          $$WrkGlobal{'thru'});
      &ColorMessage("Extended thru parameters: mode: $mode   port: $port   " .
         "channel: $channel   keyPlus: $keyPlus   velPlus: $velPlus   " .
         "local_port: $local_port", "WHITE", '');
   }
   if (scalar keys(%$MeterData) > 0) {
      &ColorMessage("Meter(s): ", "WHITE", 'nocr');
      foreach my $measure (sort {$a <=> $b} keys(%$MeterData)) {
         my ($numer, $denom, $keySig) = split(':', $$MeterData{$measure});
         &ColorMessage("Measure: $measure -> TimeSig: $numer/$denom  ", "WHITE", 'nocr');
         $keySig = $keySig - 256 if ($keySig > 127);    # make negative.
         &ColorMessage("Key: $$KeySig{$keySig}  ", "WHITE", 'nocr');
      }
      &ColorMessage("", "WHITE", '');
   }
   if (scalar keys(%$TempoData) > 0) {
      &ColorMessage("Tempo Map(s): ", "WHITE", '');
      foreach my $tempoTime (sort {$a <=> $b} keys(%$TempoData)) {
         my $tempo = $$TempoData{$tempoTime};
         &ColorMessage("   Time: $tempoTime -> Tempo: $tempo (" .
            sprintf("%.2f bpm", ($tempo/100)) . ")" , "WHITE", '');
      }
   }
   &ColorMessage("", "WHITE", '');
   
   # CakeVars hash.
   &ColorMessage("CakeVars: ", "WHITE", 'nocr');
   my $cnt = 1;
   foreach my $key (sort keys(%$CakeVars)) {
      if ($cnt > 5) {
         &ColorMessage("${key}: $$CakeVars{$key}   ", "WHITE", '');
         $cnt = 1;
      }
      else {
         &ColorMessage("${key}: $$CakeVars{$key}   ", "WHITE", 'nocr');
         $cnt++;
      }
   }
   &ColorMessage("\n", "WHITE", '');

   # WrkVariables hash.
   if (scalar keys %$WrkVariables > 0) {
      foreach my $key (sort {$a <=> $b} keys(%$WrkVariables)) {
         my $text = $$WrkVariables{$key};
         $text =~ s/[^\x20-\x7e]/\./g;
         &ColorMessage("WrkVariables: $key - $text", "WHITE", '');
      }
   }
   else {
      &ColorMessage("WrkVariables: none", "WHITE", '');
   }
   &ColorMessage("", "WHITE", '');

   # WrkStringTable hash.
   if (scalar keys %$WrkStringTable > 0) {
      foreach my $key (sort {$a <=> $b} keys(%$WrkStringTable)) {
         my $text = $$WrkStringTable{$key};
         $text =~ s/[^\x20-\x7e]/\./g;
         &ColorMessage("WrkStringTable: $key - $text", "WHITE", '');
      }
   }
   else {
      &ColorMessage("WrkStringTable: none", "WHITE", '');
   }
   &ColorMessage("", "WHITE", '');
   
   # WrkMarkers hash.
   if (scalar keys %$WrkMarkers > 0) {
      foreach my $key (sort {$a <=> $b} keys(%$WrkMarkers)) {
         my ($offset, $smpte, $text) = split(':', $$WrkMarkers{$key});
         &ColorMessage("WrkMarkers: $key  offset: $offset  smpte: $smpte  " .
                       "text: $text", "WHITE", '');
      }
   }
   else {
      &ColorMessage("WrkMarkers: none", "WHITE", '');
   }
   &ColorMessage("", "WHITE", '');
   
   # MemRegionData hash.
   if (scalar keys %$MemRegionData > 0) {
      foreach my $key (sort {$a <=> $b} keys(%$MemRegionData)) {
         &ColorMessage("MemRegionData: $key: @{ $$MemRegionData{$key} }", "WHITE", '');
      }
   }
   else {
      &ColorMessage("MemRegionData: none", "WHITE", '');
   }
   &ColorMessage("", "WHITE", '');

   # Sysex data.
   foreach my $key (sort {$a <=> $b} keys(%$SysexBank)) {
      &ColorMessage("Sysex bank: $key   name: $$SysexBank{$key}{'name'}   auto: " .
         "$$SysexBank{$key}{'auto'}   port: $$SysexBank{$key}{'port'}", "WHITE", '');
      &ColorMessage("Sysex: @{ $$SysexBank{$key}{'sysex'} } \n", "WHITE", '');
   }

   # TrackData hash.
   foreach my $key (sort {$a <=> $b} keys(%$TrackData)) {
      &ColorMessage("Track: $key  name: $$TrackData{$key}{'name'}  " .
         "port: $$TrackData{$key}{'port'}  channel: $$TrackData{$key}{'channel'}  " .
         "pitch: $$TrackData{$key}{'pitch'}  velocity: $$TrackData{$key}{'velocity'}  " .
         "volume: $$TrackData{$key}{'volume'}  bank: $$TrackData{$key}{'bank'}  " .
         "patch: $$TrackData{$key}{'patch'}  pan: $$TrackData{$key}{'pan'}  " .
         "selected: $$TrackData{$key}{'selected'}  muted: $$TrackData{$key}{'muted'}  " .
         "loop: $$TrackData{$key}{'loop'}", "WHITE", '');
      if (exists($$TrackData{$key}{'eventCnt'})) {   
         &ColorMessage("Event count: $$TrackData{$key}{'eventCnt'}", "WHITE", '');
      }
      else {
         &ColorMessage("Event count: 0", "WHITE", '');
      }
      if (exists($$TrackData{$key}{'events'})) {   
         &ColorMessage("Events: @{ $$TrackData{$key}{'events'} } \n", "WHITE", '');
      }
      else {
         &ColorMessage("No event data.\n", "WHITE", '');
      }
   }
   return 0;
}

# =============================================================================
# FUNCTION: CheckMidiFile
#
# DESCRIPTION:
#    This routine walks the specified MIDI file to verify its general track
#    chunk integrity. Some selected data is displayed.
#
# CALLING SYNTAX:
#    $result = &CheckMidiFile($MidiFile, \%KeySig);
#
# ARGUMENTS:
#    $MidiFile         File to check.
#    $KeySig           Pointer to KeySig hash.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None.
# =============================================================================
sub CheckMidiFile {
   my ($MidiFile, $KeySig) = @_;
   my $fileHandle;  my $midiFileData;  my @midiBytes = ();  my $offset = 0;

   if (open($fileHandle, '<', $MidiFile)) {
      binmode($fileHandle);
      my $dataSize = read($fileHandle, $midiFileData, 10000000);
      close($fileHandle);
      &ColorMessage("\nRead $dataSize bytes from; $MidiFile", "WHITE", '');
      push (@midiBytes, sprintf("%02X", ord $_)) foreach (split //, $midiFileData);
      
      # MIDI header record.
      my @hdr = splice(@midiBytes, 0, 14);
      if ($hdr[0] eq '4D' and $hdr[1] eq '54' and $hdr[2] eq '68' and $hdr[3] eq '64') {
         &ColorMessage("header at 0x$offset: @hdr   " . pack("(H2)4", @hdr),"WHITE",'');
         $offset += scalar @hdr;
      }
      else {
         &ColorMessage("Unknown header at offset: $offset   @hdr   " . 
                       pack("(H2)*", @hdr), "BRIGHT_RED", '');
         return 1;
      }
      
      # MIDI track records.
      while (scalar @midiBytes > 0) {
         my @trk = splice(@midiBytes, 0, 4);
         if ($trk[0] eq '4D' and $trk[1] eq '54' and $trk[2] eq '72' and 
             $trk[3] eq '6B') {
            &ColorMessage("track  at offset: " . sprintf("0x%02X", $offset) . ": @trk",
                          "WHITE", 'nocr');
            $offset += scalar @trk;             
            my @len = splice(@midiBytes, 0, 4);
            my $trkLen = hex($len[0])*16777216 + hex($len[1])*65536 + 
                         hex($len[2])*256 + hex($len[3]);
            &ColorMessage("  length: " . sprintf("0x%02X", $trkLen), "WHITE", 'nocr');
            $offset += scalar @len;
            my $nextTrk = $offset + $trkLen;
            &ColorMessage("  next track or end at: " . sprintf("0x%02X", $nextTrk), 
                          "WHITE", '');
            if ($nextTrk > $dataSize) {
               &ColorMessage("Invalid track length. Points to: " .
                  sprintf("0x%02X", $nextTrk), "BRIGHT_RED", '');
               return 1;
            }
            my @tData = splice(@midiBytes, 0, $trkLen);
            for (my $x = 0; $x <= $#tData; $x++) {
               # Meta-data
               if ($tData[$x] eq 'FF') {
                  my $meta = $tData[$x+1];
                  my $len = hex($tData[$x+2]);
                  if ($meta eq '2F') {
                     &ColorMessage("   End-of-Track", "WHITE", '');
                  }
                  elsif ($meta eq '58') {
                     my $num = hex($tData[$x+3]);
                     my $dem = 2 ** (hex($tData[$x+4]));
                     &ColorMessage("   Time signature: $num/$dem", "WHITE", '');
                  }
                  elsif ($meta eq '59') {
                     my $key = hex($tData[$x+3]);
                     my $mi = 'major';
                     $mi = 'minor' if (hex($tData[$x+4]) == 1);
                     &ColorMessage("   Key signature: $$KeySig{$key} $mi", "WHITE", '');
                  }
                  elsif ($meta eq '51') {
                     my $tempo = hex($tData[$x+3])*65536 + hex($tData[$x+4])*256 + 
                                 hex($tData[$x+5]);
                     my $bpm = 60000000 / $tempo;            
                     &ColorMessage("   Tempo: $tempo uSec per quarter note - $bpm BPM",
                                   "WHITE", '');
                  }
                  elsif ($meta eq '20') {
                     &ColorMessage("   MIDI channel: " . hex($tData[$x+3]), "WHITE", '');
                  }
                  elsif ($meta eq '21') {
                     &ColorMessage("   MIDI port: " . hex($tData[$x+2]), "WHITE", '');
                  }
                  elsif ($meta eq '09' or $meta eq '03') {
                     my $nameStr = "''";
                     if ($len > 0) {
                        my @name = ();
                        for (my $y = $x+3; $y <= $x+3+$len-1; $y++) {
                           push (@name, $tData[$y]);
                        }
                        $nameStr = pack("(H2)*", @name);
                     }
                     if ($meta eq '09') {
                        &ColorMessage("   MIDI port name: ", "WHITE", 'nocr');
                     }
                     else {
                        &ColorMessage("   Name: ", "WHITE", 'nocr');
                     }
                     &ColorMessage("$nameStr", "WHITE", '');
                  }
                  $x += $len +2;
               }
               
               # Patch
               elsif ($tData[$x] eq 'C0') {
                  &ColorMessage("   Patch: " . hex($tData[$x+1]), "WHITE", '');
               }
               # Control
               elsif ($tData[$x] eq 'B0') {
                  if ($tData[$x+1] eq '07' or $tData[$x+1] eq '27') {
                     &ColorMessage("   Volume: " . hex($tData[$x+2]), "WHITE", '');
                  }
                  elsif ($tData[$x+1] eq '0A' or $tData[$x+1] eq '2A') {
                     &ColorMessage("   Pan: " . hex($tData[$x+2]), "WHITE", '');
                  }
               }
               # Sysex
               elsif ($tData[$x] eq 'F0') {
                  # Get the sysex length and offset;
                  my $ofs = 0;   my $len = 0;
                  for (my $y = 1; $y < 4; $y++) {
                     $ofs = $x + $y;
                     $len = $len | hex($tData[$ofs]) & 0x7F;
                     last if (hex($tData[$ofs]) < 128);
                     $len = $len << 7; 
                  }
                  # Get the sysex bytes.
                  my @syx = ('F0');   my $max = 24;
                  for (my $y = $ofs+1; $y <= $ofs+$len; $y++) {
                     if (scalar @syx >= $max) {
                        push (@syx, '...');
                        last;
                     }
                     else {
                        push (@syx, $tData[$y]);
                     }
                  }
                  &ColorMessage("   Sysex length $len: @syx", "WHITE", '');
               }
            }
            $offset += scalar @tData;
         }
         else {
            &ColorMessage("Expected track at offset: $offset   @trk", "BRIGHT_RED", '');
            return 1;
         }
      }
      if ($offset == $dataSize) {
         &ColorMessage("End of file.", "WHITE", '');
      }
      else {
         &ColorMessage("Unexpected EOF result. offset: $offset  dataSize: $dataSize",
                       "BRIGHT_RED", '');
         return 1;
      }
   }
   else {
      &ColorMessage("File not found: $MidiFile", "BRIGHT_RED", '');
      return 1;
   }
   return 0;
}
1;
